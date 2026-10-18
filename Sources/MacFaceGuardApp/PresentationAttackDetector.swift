import Foundation
import CoreML
import CoreVideo
import MacFaceGuardCore

/// Carrega o MiniFASNet (PAD passivo) convertido localmente. Usado só na comparação experimental: sem ele, a
/// comparação não começa, e mesmo com ele nada é autorizado.
final class PresentationAttackDetector: @unchecked Sendable {
    static var defaultPackage: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/MacFaceGuard/minifasnet-build/MiniFASNetPAD.mlpackage", isDirectory: true)
    }

    let descriptor: PADModelDescriptor
    private let model: MLModel
    private let workspace: URL
    private let lock = NSLock()

    /// Copia o pacote para uma pasta privada, confere o hash na cópia e só então compila e carrega.
    init(package: URL = PresentationAttackDetector.defaultPackage, descriptor: PADModelDescriptor = .miniFASNet) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: package.path) else {
            throw GuardError.message("Modelo anti-fraude ausente. Converta o MiniFASNet localmente (scripts/convert-minifasnet.py); a comparação foi bloqueada.")
        }
        let workspace = manager.temporaryDirectory.appendingPathComponent("MacFaceGuard-pad-" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: workspace, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            let copy = workspace.appendingPathComponent("MiniFASNetPAD.mlpackage", isDirectory: true)
            try manager.copyItem(at: package, to: copy)
            do { try ModelIntegrity.verify(copy, expected: descriptor.packageSHA256) }
            catch { throw GuardError.message("O modelo anti-fraude não confere com o hash esperado. A comparação foi bloqueada.") }
            let compiled = workspace.appendingPathComponent("MiniFASNetPAD.mlmodelc", isDirectory: true)
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
            throw GuardError.message("Não foi possível carregar o modelo anti-fraude. A comparação foi bloqueada.")
        }
        self.workspace = workspace
        self.descriptor = descriptor
    }

    deinit { try? FileManager.default.removeItem(at: workspace) }

    private static func checkInterface(_ description: MLModelDescription, descriptor: PADModelDescriptor) throws {
        let inputsMatch = descriptor.crops.allSatisfy { crop in
            guard let image = description.inputDescriptionsByName[crop.input]?.imageConstraint else { return false }
            return image.pixelsWide == descriptor.inputSize && image.pixelsHigh == descriptor.inputSize
        }
        guard inputsMatch, description.inputDescriptionsByName.count == descriptor.crops.count,
              let array = description.outputDescriptionsByName[descriptor.output]?.multiArrayConstraint,
              array.shape.map(\.intValue).reduce(1, *) == descriptor.classes else {
            throw GuardError.message("A interface do modelo anti-fraude é diferente da esperada. A comparação foi bloqueada.")
        }
    }

    /// Recorta o quadro BGRA (ainda bloqueado pelo chamador) em torno da caixa do Vision e avalia os dois recortes.
    func assess(frame pixels: UnsafeRawBufferPointer, width: Int, height: Int, bytesPerRow: Int,
                visionBox: CGRect) throws -> PresentationAssessment {
        let face = try PresentationAttack.pixelRect(fromVision: visionBox, width: width, height: height)
        var inputs: [String: Any] = [:]
        for crop in descriptor.crops {
            let box = try PresentationAttack.cropBox(face: face, imageWidth: width, imageHeight: height, scale: crop.scale)
            let bytes = try PresentationAttack.resample(pixels, width: width, height: height, bytesPerRow: bytesPerRow,
                                                        box: box, size: descriptor.inputSize)
            inputs[crop.input] = MLFeatureValue(pixelBuffer: try Self.buffer(bytes, size: descriptor.inputSize))
        }
        return try assess(inputs)
    }

    private func assess(_ inputs: [String: Any]) throws -> PresentationAssessment {
        let features = try MLDictionaryFeatureProvider(dictionary: inputs)
        lock.lock()
        defer { lock.unlock() }
        let result = try model.prediction(from: features)
        guard let array = result.featureValue(for: descriptor.output)?.multiArrayValue,
              array.count == descriptor.classes else { throw PresentationAttackError.invalidProbabilities }
        return try PresentationAttack.assess(probabilities: (0..<array.count).map { array[$0].floatValue })
    }

    private static func buffer(_ bytes: [UInt8], size: Int) throws -> CVPixelBuffer {
        guard bytes.count == size * size * 4 else { throw PresentationAttackError.invalidImage }
        var created: CVPixelBuffer?
        let attributes = [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary
        guard CVPixelBufferCreate(nil, size, size, kCVPixelFormatType_32BGRA, attributes, &created) == kCVReturnSuccess,
              let buffer = created else { throw PresentationAttackError.invalidImage }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw PresentationAttackError.invalidImage }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        bytes.withUnsafeBytes { source in
            for row in 0..<size {
                (base + row * stride).copyMemory(from: source.baseAddress! + row * size * 4, byteCount: size * 4)
            }
        }
        return buffer
    }

    /// Diagnóstico sem dados faciais: confere o hash e roda imagens sintéticas. Não mede acurácia.
    static func selfCheck() throws -> String {
        let detector = try PresentationAttackDetector()
        let size = detector.descriptor.inputSize
        var pattern = [UInt8](repeating: 128, count: size * size * 4)
        for row in 0..<size { for column in 0..<size {
            let offset = (row * size + column) * 4
            if (row / 8 + column / 8) % 2 == 0 { pattern[offset] = 96; pattern[offset + 1] = 112; pattern[offset + 2] = 160 }
            pattern[offset + 3] = 255
        } }
        let image = MLFeatureValue(pixelBuffer: try buffer(pattern, size: size))
        let result = try detector.assess(Dictionary(uniqueKeysWithValues: detector.descriptor.crops.map { ($0.input, image as Any) }))
        return "PAD_VERIFIED \(detector.descriptor.id) sha256=\(detector.descriptor.packageSHA256) classes=\(detector.descriptor.classes) synthetic_label=\(result.label)"
    }
}
