import Foundation
import CoreML
import CoreVideo
import MacFaceGuardCore

/// Carrega o EdgeFace XS convertido localmente. O pacote fica fora do Git e do app; sem ele, nada é comparado.
final class EdgeFaceExtractor: @unchecked Sendable {
    static var defaultPackage: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/MacFaceGuard/edgeface-build/EdgeFaceXS.mlpackage", isDirectory: true)
    }

    let descriptor: FaceModelDescriptor
    private let model: MLModel
    private let workspace: URL
    private let lock = NSLock()

    /// Copia o pacote para uma pasta privada, confere o hash na cópia e só então compila e carrega.
    init(package: URL = EdgeFaceExtractor.defaultPackage, descriptor: FaceModelDescriptor = .edgeFaceXS) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: package.path) else {
            throw GuardError.message("Modelo facial ausente. Converta o EdgeFace XS localmente (scripts/convert-edgeface.py); nenhuma comparação será feita.")
        }
        let workspace = manager.temporaryDirectory.appendingPathComponent("MacFaceGuard-model-" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: workspace, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            let copy = workspace.appendingPathComponent("EdgeFaceXS.mlpackage", isDirectory: true)
            try manager.copyItem(at: package, to: copy)
            do { try ModelIntegrity.verify(copy, expected: descriptor.packageSHA256) }
            catch { throw GuardError.message("O modelo facial não confere com o hash esperado. A comparação foi bloqueada.") }
            let compiled = workspace.appendingPathComponent("EdgeFaceXS.mlmodelc", isDirectory: true)
            let temporary = try MLModel.compileModel(at: copy)
            try manager.moveItem(at: temporary, to: compiled)
            try manager.removeItem(at: copy)
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuOnly
            let model = try MLModel(contentsOf: compiled, configuration: configuration)
            try Self.checkInterface(model.modelDescription, descriptor: descriptor)
            self.model = model
        } catch {
            try? manager.removeItem(at: workspace)
            if error is GuardError { throw error }
            throw GuardError.message("Não foi possível carregar o modelo facial. A comparação foi bloqueada.")
        }
        self.workspace = workspace
        self.descriptor = descriptor
    }

    deinit { try? FileManager.default.removeItem(at: workspace) }

    private static func checkInterface(_ description: MLModelDescription, descriptor: FaceModelDescriptor) throws {
        guard let input = description.inputDescriptionsByName[descriptor.input],
              let image = input.imageConstraint,
              image.pixelsWide == FaceAlignment.outputSize, image.pixelsHigh == FaceAlignment.outputSize,
              let output = description.outputDescriptionsByName[descriptor.output],
              let array = output.multiArrayConstraint,
              array.shape.map(\.intValue).reduce(1, *) == descriptor.dimension else {
            throw GuardError.message("A interface do modelo facial é diferente da esperada. A comparação foi bloqueada.")
        }
    }

    /// Recebe o rosto alinhado 112×112 em BGRA e devolve o vetor normalizado (L2).
    func embedding(alignedBGRA bytes: [UInt8]) throws -> [Float] {
        let size = FaceAlignment.outputSize
        guard bytes.count == size * size * 4 else { throw AlignmentError.invalidImage }
        var created: CVPixelBuffer?
        let attributes = [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary
        guard CVPixelBufferCreate(nil, size, size, kCVPixelFormatType_32BGRA, attributes, &created) == kCVReturnSuccess,
              let buffer = created else { throw AlignmentError.invalidImage }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            bytes.withUnsafeBytes { source in
                for row in 0..<size {
                    (base + row * stride).copyMemory(from: source.baseAddress! + row * size * 4, byteCount: size * 4)
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        let features = try MLDictionaryFeatureProvider(dictionary: [descriptor.input: MLFeatureValue(pixelBuffer: buffer)])
        lock.lock()
        defer { lock.unlock() }
        let result = try model.prediction(from: features)
        guard let array = result.featureValue(for: descriptor.output)?.multiArrayValue,
              array.count == descriptor.dimension else { throw EmbeddingError.wrongDimension }
        let raw = (0..<array.count).map { array[$0].floatValue }
        return try FaceEmbedding.normalized(raw, dimension: descriptor.dimension)
    }

    /// Diagnóstico sem dados faciais: confere o hash e roda uma imagem cinza sintética.
    static func selfCheck() throws -> String {
        let extractor = try EdgeFaceExtractor()
        let size = FaceAlignment.outputSize
        var gray = [UInt8](repeating: 128, count: size * size * 4)
        for index in stride(from: 3, to: gray.count, by: 4) { gray[index] = 255 }
        for row in 0..<size { for column in 0..<size where (row / 8 + column / 8) % 2 == 0 {
            let offset = (row * size + column) * 4
            gray[offset] = 96; gray[offset + 1] = 112; gray[offset + 2] = 160
        } }
        let vector = try extractor.embedding(alignedBGRA: gray)
        return "MODEL_VERIFIED \(extractor.descriptor.id) sha256=\(extractor.descriptor.packageSHA256) dim=\(vector.count)"
    }
}
