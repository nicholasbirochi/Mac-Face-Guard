import Foundation
import CryptoKit

public enum EmbeddingError: Error, Equatable { case wrongDimension, nonFinite, zeroNorm, notNormalized }

public enum FaceEmbedding {
    /// Normaliza a saída bruta do modelo (L2). Recusa dimensão errada, NaN/infinito e vetor nulo.
    public static func normalized(_ raw: [Float], dimension: Int) throws -> [Float] {
        guard raw.count == dimension, dimension > 0 else { throw EmbeddingError.wrongDimension }
        guard raw.allSatisfy(\.isFinite) else { throw EmbeddingError.nonFinite }
        let norm = raw.reduce(0.0) { $0 + Double($1) * Double($1) }.squareRoot()
        guard norm.isFinite, norm > 1e-6 else { throw EmbeddingError.zeroNorm }
        return raw.map { Float(Double($0) / norm) }
    }

    public static func validate(_ vector: [Float], dimension: Int) throws {
        guard vector.count == dimension, dimension > 0 else { throw EmbeddingError.wrongDimension }
        guard vector.allSatisfy(\.isFinite) else { throw EmbeddingError.nonFinite }
        let norm = vector.reduce(0.0) { $0 + Double($1) * Double($1) }.squareRoot()
        guard abs(norm - 1) < 1e-3 else { throw EmbeddingError.notNormalized }
    }

    /// Similaridade do cosseno entre vetores já normalizados; é informativa, não decisão de identidade.
    public static func cosine(_ a: [Float], _ b: [Float], dimension: Int) throws -> Float {
        try validate(a, dimension: dimension)
        try validate(b, dimension: dimension)
        let value = zip(a, b).reduce(0.0) { $0 + Double($1.0) * Double($1.1) }
        return Float(max(-1, min(1, value)))
    }
}

/// Identifica o modelo e o pré-processamento que produziram um cadastro.
public struct FaceModelDescriptor: Equatable, Sendable {
    public let id: String
    public let packageSHA256: String
    public let dimension: Int
    public let preprocessing: String
    public let input: String
    public let output: String

    public init(id: String, packageSHA256: String, dimension: Int, preprocessing: String, input: String, output: String) {
        self.id = id
        self.packageSHA256 = packageSHA256
        self.dimension = dimension
        self.preprocessing = preprocessing
        self.input = input
        self.output = output
    }

    /// EdgeFace XS (γ=0,6), convertido localmente por scripts/convert-edgeface.py. Os pesos não estão no Git.
    public static let edgeFaceXS = FaceModelDescriptor(id: "edgeface-xs-gamma-0.6",
        packageSHA256: "036326e60212ab3773a6b3bb2d312655cc4a2707e738c0807bc2341d82f0edee",
        dimension: 512, preprocessing: FaceAlignment.preprocessingVersion, input: "face", output: "embedding")
}

public enum ModelIntegrityError: Error, Equatable { case missing, invalidLayout, tooLarge, hashMismatch }

public enum ModelIntegrity {
    public static let maximumBytes = 64 * 1024 * 1024
    public static let maximumFiles = 64

    /// Mesmo algoritmo de `package_digest` em scripts/convert-edgeface.py: arquivos regulares em ordem de
    /// componentes do caminho; para cada um, caminho relativo + 0x00 + SHA-256 do conteúdo. Links simbólicos são recusados.
    public static func packageDigest(at root: URL) throws -> String {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: root.path, isDirectory: &isDirectory) else { throw ModelIntegrityError.missing }
        let rootValues = try root.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard isDirectory.boolValue, rootValues.isSymbolicLink != true else { throw ModelIntegrityError.invalidLayout }
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let walker = manager.enumerator(at: root, includingPropertiesForKeys: keys) else {
            throw ModelIntegrityError.invalidLayout
        }
        let base = root.standardizedFileURL.pathComponents
        var files: [(parts: [String], url: URL)] = []
        var total = 0
        for case let url as URL in walker {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true { throw ModelIntegrityError.invalidLayout }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true else { throw ModelIntegrityError.invalidLayout }
            let parts = url.standardizedFileURL.pathComponents
            guard parts.count > base.count, Array(parts.prefix(base.count)) == base else { throw ModelIntegrityError.invalidLayout }
            total += values.fileSize ?? 0
            files.append((Array(parts.dropFirst(base.count)), url))
            guard files.count <= maximumFiles, total <= maximumBytes else { throw ModelIntegrityError.tooLarge }
        }
        guard !files.isEmpty else { throw ModelIntegrityError.invalidLayout }
        files.sort { lhs, rhs in
            for (l, r) in zip(lhs.parts, rhs.parts) where l != r { return Array(l.utf8).lexicographicallyPrecedes(Array(r.utf8)) }
            return lhs.parts.count < rhs.parts.count
        }
        var digest = SHA256()
        for file in files {
            let data = try Data(contentsOf: file.url)
            guard data.count <= maximumBytes else { throw ModelIntegrityError.tooLarge }
            digest.update(data: Data(file.parts.joined(separator: "/").utf8) + [0])
            digest.update(data: Data(SHA256.hash(data: data)))
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func verify(_ root: URL, expected: String) throws {
        guard try packageDigest(at: root) == expected.lowercased() else { throw ModelIntegrityError.hashMismatch }
    }
}
