import XCTest
import CoreGraphics
@testable import MacFaceGuardCore

final class FaceAlignmentTests: XCTestCase {
    private func points(_ list: [CGPoint]) -> FivePoints {
        FivePoints(leftEye: list[0], rightEye: list[1], nose: list[2], mouthLeft: list[3], mouthRight: list[4])
    }

    func testReferencePointsGiveIdentity() throws {
        let t = try FaceAlignment.transform(from: points(FaceAlignment.reference))
        XCTAssertEqual(t.a, 1, accuracy: 1e-9)
        XCTAssertEqual(t.b, 0, accuracy: 1e-9)
        XCTAssertEqual(t.tx, 0, accuracy: 1e-6)
        XCTAssertEqual(t.ty, 0, accuracy: 1e-6)
    }

    func testKnownSimilarityIsRecovered() throws {
        // Rosto na câmera = referência ampliada 2,5×, girada 10° e deslocada.
        let angle = 10.0 * .pi / 180, scale = 2.5
        let forward = SimilarityTransform(a: scale * cos(angle), b: scale * sin(angle), tx: 400, ty: 210)
        let camera = FaceAlignment.reference.map(forward.apply)
        let t = try FaceAlignment.transform(from: points(camera))
        let expected = forward.inverse
        XCTAssertEqual(t.a, expected.a, accuracy: 1e-9)
        XCTAssertEqual(t.b, expected.b, accuracy: 1e-9)
        XCTAssertEqual(t.tx, expected.tx, accuracy: 1e-6)
        XCTAssertEqual(t.ty, expected.ty, accuracy: 1e-6)
        for (p, q) in zip(camera, FaceAlignment.reference) {
            XCTAssertEqual(t.apply(p).x, q.x, accuracy: 1e-6)
            XCTAssertEqual(t.apply(p).y, q.y, accuracy: 1e-6)
        }
    }

    func testEyesAndMouthCornersAreOrderedByImagePosition() throws {
        let r = FaceAlignment.reference
        let swapped = try FivePoints(eyes: (r[1], r[0]), nose: r[2], lips: [r[4], CGPoint(x: 56, y: 95), r[3]])
        XCTAssertEqual(swapped, points(r))
        XCTAssertThrowsError(try FivePoints(eyes: (r[0], r[1]), nose: r[2], lips: [r[3]]))
    }

    func testInvalidGeometryFailsClosed() {
        let r = FaceAlignment.reference
        let cases: [([CGPoint], AlignmentError)] = [
            (Array(repeating: CGPoint(x: 10, y: 10), count: 5), .degenerate),
            ([CGPoint(x: CGFloat.nan, y: 1)] + r.dropFirst(), .invalidPoints),
            ([CGPoint(x: CGFloat.infinity, y: 1)] + r.dropFirst(), .invalidPoints),
            // Olhos e boca espelhados (esquerda/direita trocadas) exigiriam reflexão.
            ([r[1], r[0], r[2], r[4], r[3]], .reflected),
            // Rosto minúsculo (escala > 1,5 para chegar a 112 px) ou enorme.
            (r.map { CGPoint(x: $0.x * 0.3, y: $0.y * 0.3) }, .outOfRange),
            (r.map { CGPoint(x: $0.x * 20, y: $0.y * 20) }, .outOfRange),
            // Inclinação de 90°.
            (r.map { CGPoint(x: -$0.y, y: $0.x) }, .outOfRange),
        ]
        for (list, error) in cases {
            XCTAssertThrowsError(try FaceAlignment.transform(from: points(list))) {
                XCTAssertEqual($0 as? AlignmentError, error, "\(list)")
            }
        }
    }

    func testPoorlyFittingPointsAreRejected() {
        var r = FaceAlignment.reference.map { CGPoint(x: $0.x * 3, y: $0.y * 3) }
        r[2] = CGPoint(x: r[2].x, y: r[2].y + 150)
        XCTAssertThrowsError(try FaceAlignment.transform(from: points(r))) {
            XCTAssertEqual($0 as? AlignmentError, .poorFit)
        }
    }

    func testWarpSamplesBilinearlyAndPadsWithZero() throws {
        // Imagem 4×2 BGRA com bytes por linha maiores que a largura (como em CVPixelBuffer).
        let width = 4, height = 2, stride = 20
        var image = [UInt8](repeating: 9, count: stride * height)
        for y in 0..<height { for x in 0..<width {
            let o = y * stride + x * 4
            image[o] = UInt8(x * 10); image[o + 1] = UInt8(y * 100); image[o + 2] = 7; image[o + 3] = 255
        } }
        // Saída (u, v) lê a origem em (u/2, v/2): escala 2 da origem para a saída.
        let t = SimilarityTransform(a: 2, b: 0, tx: 0, ty: 0)
        let out = try image.withUnsafeBytes { try FaceAlignment.warp($0, width: width, height: height, bytesPerRow: stride, transform: t) }
        XCTAssertEqual(out.count, 112 * 112 * 4)
        func pixel(_ u: Int, _ v: Int) -> [UInt8] { Array(out[(v * 112 + u) * 4 ..< (v * 112 + u) * 4 + 4]) }
        XCTAssertEqual(pixel(0, 0), [0, 0, 7, 255])
        XCTAssertEqual(pixel(2, 0), [10, 0, 7, 255])
        XCTAssertEqual(pixel(1, 0), [5, 0, 7, 255])     // meio caminho entre x=0 e x=1
        XCTAssertEqual(pixel(1, 1), [5, 50, 7, 255])    // interpolação nos dois eixos
        XCTAssertEqual(pixel(6, 0), [30, 0, 7, 255])
        XCTAssertEqual(pixel(7, 0), [15, 0, 4, 128])    // metade fora da imagem: mistura com zero
        XCTAssertEqual(pixel(100, 100), [0, 0, 0, 0])   // fora da imagem
    }

    func testWarpRejectsShortOrInvalidBuffers() {
        let t = SimilarityTransform(a: 1, b: 0, tx: 0, ty: 0)
        let small = [UInt8](repeating: 0, count: 10)
        XCTAssertThrowsError(try small.withUnsafeBytes { try FaceAlignment.warp($0, width: 4, height: 4, bytesPerRow: 16, transform: t) })
        XCTAssertThrowsError(try small.withUnsafeBytes { try FaceAlignment.warp($0, width: 2, height: 1, bytesPerRow: 8, transform: t) })
        XCTAssertThrowsError(try small.withUnsafeBytes { try FaceAlignment.warp($0, width: 2, height: 2, bytesPerRow: 4, transform: t) })
    }
}
