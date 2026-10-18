import Foundation
import CoreGraphics

public enum AlignmentError: Error, Equatable { case invalidPoints, degenerate, reflected, outOfRange, poorFit, invalidImage }

/// Cinco pontos em pixels, origem no canto superior esquerdo: olhos, ponta do nariz e cantos da boca.
public struct FivePoints: Equatable, Sendable {
    public let leftEye: CGPoint, rightEye: CGPoint, nose: CGPoint, mouthLeft: CGPoint, mouthRight: CGPoint

    public init(leftEye: CGPoint, rightEye: CGPoint, nose: CGPoint, mouthLeft: CGPoint, mouthRight: CGPoint) {
        self.leftEye = leftEye
        self.rightEye = rightEye
        self.nose = nose
        self.mouthLeft = mouthLeft
        self.mouthRight = mouthRight
    }

    public var all: [CGPoint] { [leftEye, rightEye, nose, mouthLeft, mouthRight] }

    /// Ordena olhos e cantos da boca pela posição na imagem, como na referência (esquerda da imagem primeiro).
    public init(eyes: (CGPoint, CGPoint), nose: CGPoint, lips: [CGPoint]) throws {
        guard lips.count >= 2, let left = lips.min(by: { $0.x < $1.x }), let right = lips.max(by: { $0.x < $1.x }) else {
            throw AlignmentError.invalidPoints
        }
        let ordered = eyes.0.x <= eyes.1.x ? eyes : (eyes.1, eyes.0)
        self.init(leftEye: ordered.0, rightEye: ordered.1, nose: nose, mouthLeft: left, mouthRight: right)
    }
}

/// Semelhança não refletida: (x, y) → (a·x − b·y + tx, b·x + a·y + ty).
public struct SimilarityTransform: Equatable, Sendable {
    public let a: Double, b: Double, tx: Double, ty: Double

    public var scale: Double { (a * a + b * b).squareRoot() }

    public func apply(_ p: CGPoint) -> CGPoint {
        CGPoint(x: a * p.x - b * p.y + tx, y: b * p.x + a * p.y + ty)
    }

    public var inverse: SimilarityTransform {
        let d = a * a + b * b
        let ia = a / d, ib = -b / d
        return SimilarityTransform(a: ia, b: ib, tx: -(ia * tx - ib * ty), ty: -(ib * tx + ia * ty))
    }
}

/// Reproduz `warp_and_crop_face` (mtcnn align_trans) usado pelos autores do EdgeFace: recorte quadrado
/// 112×112, pontos de referência ArcFace e semelhança por mínimos quadrados com escolha da solução refletida
/// quando ela se ajusta melhor. Aqui a solução refletida é recusada, pois indica pontos trocados.
public enum FaceAlignment {
    public static let outputSize = 112
    public static let preprocessingVersion = "arcface5-similarity-112-bgra-bilinear-v1"
    public static let reference = [CGPoint(x: 38.2946, y: 51.6963), CGPoint(x: 73.5318, y: 51.5014),
                                   CGPoint(x: 56.0252, y: 71.7366), CGPoint(x: 41.5493, y: 92.3655),
                                   CGPoint(x: 70.7299, y: 92.2041)]

    public static func transform(from points: FivePoints) throws -> SimilarityTransform {
        let source = points.all
        guard source.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { throw AlignmentError.invalidPoints }
        let direct = try fit(source, reference)
        let mirrored = try fit(source.map { CGPoint(x: -$0.x, y: $0.y) }, reference)
        guard residual(direct, source) <= residual(mirrored, source.map { CGPoint(x: -$0.x, y: $0.y) }) else {
            throw AlignmentError.reflected
        }
        // Distância entre olhos de ~25 a ~500 px na origem e inclinação até 45°.
        guard direct.scale > 0.07, direct.scale < 1.5, abs(atan2(direct.b, direct.a)) < .pi / 4 else {
            throw AlignmentError.outOfRange
        }
        let rms = (residual(direct, source) / Double(source.count)).squareRoot()
        guard rms < 8 else { throw AlignmentError.poorFit }
        return direct
    }

    /// Amostragem bilinear como `cv2.warpAffine` (centros de pixel inteiros, borda constante zero).
    /// Entrada e saída em 4 bytes por pixel, preservando a ordem dos canais.
    public static func warp(_ pixels: UnsafeRawBufferPointer, width: Int, height: Int, bytesPerRow: Int,
                            transform: SimilarityTransform) throws -> [UInt8] {
        guard width > 1, height > 1, bytesPerRow >= width * 4, pixels.count >= bytesPerRow * (height - 1) + width * 4 else {
            throw AlignmentError.invalidImage
        }
        let size = outputSize, back = transform.inverse
        var output = [UInt8](repeating: 0, count: size * size * 4)
        for v in 0..<size {
            for u in 0..<size {
                let source = back.apply(CGPoint(x: Double(u), y: Double(v)))
                let x0 = Int(floor(source.x)), y0 = Int(floor(source.y))
                let fx = source.x - Double(x0), fy = source.y - Double(y0)
                for channel in 0..<4 {
                    func sample(_ x: Int, _ y: Int) -> Double {
                        guard x >= 0, y >= 0, x < width, y < height else { return 0 }
                        return Double(pixels[y * bytesPerRow + x * 4 + channel])
                    }
                    let top = sample(x0, y0) * (1 - fx) + sample(x0 + 1, y0) * fx
                    let bottom = sample(x0, y0 + 1) * (1 - fx) + sample(x0 + 1, y0 + 1) * fx
                    let value = (top * (1 - fy) + bottom * fy).rounded()
                    output[(v * size + u) * 4 + channel] = UInt8(max(0, min(255, value)))
                }
            }
        }
        return output
    }

    private static func fit(_ source: [CGPoint], _ target: [CGPoint]) throws -> SimilarityTransform {
        let n = Double(source.count)
        let sx = source.reduce(0) { $0 + $1.x } / n, sy = source.reduce(0) { $0 + $1.y } / n
        let txm = target.reduce(0) { $0 + $1.x } / n, tym = target.reduce(0) { $0 + $1.y } / n
        var spread = 0.0, dotSum = 0.0, crossSum = 0.0
        for (p, q) in zip(source, target) {
            let x = p.x - sx, y = p.y - sy, u = q.x - txm, v = q.y - tym
            spread += x * x + y * y
            dotSum += x * u + y * v
            crossSum += x * v - y * u
        }
        guard spread.isFinite, spread > 1e-6 else { throw AlignmentError.degenerate }
        let a = dotSum / spread, b = crossSum / spread
        guard a.isFinite, b.isFinite, a * a + b * b > 1e-12 else { throw AlignmentError.degenerate }
        return SimilarityTransform(a: a, b: b, tx: txm - (a * sx - b * sy), ty: tym - (b * sx + a * sy))
    }

    private static func residual(_ t: SimilarityTransform, _ source: [CGPoint]) -> Double {
        zip(source, reference).reduce(0) { sum, pair in
            let p = t.apply(pair.0)
            return sum + (p.x - pair.1.x) * (p.x - pair.1.x) + (p.y - pair.1.y) * (p.y - pair.1.y)
        }
    }
}
