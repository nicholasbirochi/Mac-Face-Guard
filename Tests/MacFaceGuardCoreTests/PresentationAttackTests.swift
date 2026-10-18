import XCTest
import CoreGraphics
@testable import MacFaceGuardCore

final class PresentationAttackTests: XCTestCase {
    private func box(_ face: CGRect, scale: Double) throws -> PixelBox {
        try PresentationAttack.cropBox(face: face, imageWidth: 640, imageHeight: 480, scale: scale)
    }

    func testDescriptorMatchesConvertedPackage() {
        let d = PADModelDescriptor.miniFASNet
        XCTAssertEqual(d.packageSHA256.count, 64)
        XCTAssertEqual(d.inputSize, 80)
        XCTAssertEqual(d.crops, [PADCrop(input: "wide", scale: 2.7), PADCrop(input: "wider", scale: 4.0)])
        XCTAssertEqual(d.output, "probabilities")
        XCTAssertEqual(d.classes, 3)
    }

    func testVisionBoxBecomesTopLeftPixels() throws {
        let r = try PresentationAttack.pixelRect(fromVision: CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25), width: 640, height: 480)
        XCTAssertEqual(r, CGRect(x: 160, y: 120, width: 320, height: 120))
        XCTAssertThrowsError(try PresentationAttack.pixelRect(fromVision: CGRect(x: 0, y: 0, width: 0, height: 0.2), width: 640, height: 480))
    }

    func testCropBoxFollowsReference() throws {
        // Valores calculados com CropImage._get_new_box da referência.
        XCTAssertEqual(try box(CGRect(x: 270, y: 190, width: 100, height: 100), scale: 2.7),
                       PixelBox(left: 185, top: 105, right: 455, bottom: 375))
        // Bordas: desloca para dentro sem encolher.
        XCTAssertEqual(try box(CGRect(x: 10, y: 10, width: 100, height: 100), scale: 2.7),
                       PixelBox(left: 0, top: 0, right: 270, bottom: 270))
        XCTAssertEqual(try box(CGRect(x: 530, y: 370, width: 100, height: 100), scale: 2.7),
                       PixelBox(left: 369, top: 209, right: 639, bottom: 479))
        // Escala limitada pela altura: min(479/200, 639/200, 4).
        XCTAssertEqual(try box(CGRect(x: 220, y: 140, width: 200, height: 200), scale: 4),
                       PixelBox(left: 80, top: 0, right: 559, bottom: 479))
    }

    func testCropBoxRejectsInvalidInput() {
        for face in [CGRect(x: 0, y: 0, width: 0, height: 50), CGRect(x: CGFloat.nan, y: 0, width: 50, height: 50)] {
            XCTAssertThrowsError(try box(face, scale: 2.7)) { XCTAssertEqual($0 as? PresentationAttackError, .invalidBox) }
        }
        XCTAssertThrowsError(try box(CGRect(x: 0, y: 0, width: 50, height: 50), scale: .infinity))
    }

    private func image(width: Int, height: Int, bytesPerRow: Int, _ value: (Int, Int, Int) -> UInt8) -> [UInt8] {
        var pixels = [UInt8](repeating: 0xEE, count: bytesPerRow * height)
        for y in 0..<height { for x in 0..<width { for c in 0..<4 { pixels[y * bytesPerRow + x * 4 + c] = value(x, y, c) } } }
        return pixels
    }

    private func resample(_ pixels: [UInt8], width: Int, height: Int, bytesPerRow: Int, box: PixelBox, size: Int) throws -> [UInt8] {
        try pixels.withUnsafeBytes {
            try PresentationAttack.resample($0, width: width, height: height, bytesPerRow: bytesPerRow, box: box, size: size)
        }
    }

    func testResampleCopiesSameSizeCropAndSkipsRowPadding() throws {
        let pixels = image(width: 6, height: 4, bytesPerRow: 32) { x, y, c in UInt8(x * 40 + y * 7 + c) }
        let out = try resample(pixels, width: 6, height: 4, bytesPerRow: 32, box: PixelBox(left: 1, top: 1, right: 3, bottom: 3), size: 3)
        for v in 0..<3 { for u in 0..<3 { for c in 0..<4 {
            XCTAssertEqual(out[(v * 3 + u) * 4 + c], UInt8((u + 1) * 40 + (v + 1) * 7 + c))
        } } }
    }

    func testResampleHalvesLikeOpenCVLinear() throws {
        // Reduzir 4→2 com INTER_LINEAR faz a média de pares vizinhos em cada eixo.
        let pixels = image(width: 4, height: 4, bytesPerRow: 16) { x, y, _ in UInt8(x * 20 + y * 60) }
        let out = try resample(pixels, width: 4, height: 4, bytesPerRow: 16, box: PixelBox(left: 0, top: 0, right: 3, bottom: 3), size: 2)
        XCTAssertEqual(out[0], 40)            // média de x 0,1 e y 0,1: 10 + 30
        XCTAssertEqual(out[4], 80)            // x 2,3: 50 + 30
        XCTAssertEqual(out[(2 + 1) * 4], 200) // x 2,3, y 2,3: 50 + 150
    }

    func testResampleUniformImageStaysUniform() throws {
        let pixels = image(width: 640, height: 480, bytesPerRow: 2560) { _, _, c in [10, 20, 30, 255][c] }
        let crop = try PresentationAttack.cropBox(face: CGRect(x: 250, y: 150, width: 140, height: 160), imageWidth: 640, imageHeight: 480, scale: 4)
        let out = try resample(pixels, width: 640, height: 480, bytesPerRow: 2560, box: crop, size: 80)
        XCTAssertEqual(out.count, 80 * 80 * 4)
        for index in stride(from: 0, to: out.count, by: 4) { XCTAssertEqual(Array(out[index..<index + 4]), [10, 20, 30, 255]) }
    }

    func testResampleRejectsBoxOutsideImage() {
        let pixels = [UInt8](repeating: 0, count: 64)
        XCTAssertThrowsError(try resample(pixels, width: 4, height: 4, bytesPerRow: 16, box: PixelBox(left: 0, top: 0, right: 4, bottom: 3), size: 2))
        XCTAssertThrowsError(try resample(pixels, width: 4, height: 4, bytesPerRow: 32, box: PixelBox(left: 0, top: 0, right: 3, bottom: 3), size: 2))
    }

    func testAssessmentFailsClosed() throws {
        let live = try PresentationAttack.assess(probabilities: [0.1, 0.85, 0.05])
        XCTAssertEqual(live.label, .real)
        XCTAssertTrue(live.isLive)
        XCTAssertFalse(live.spoofSuspected)

        let unsure = try PresentationAttack.assess(probabilities: [0.2, 0.7, 0.1])
        XCTAssertFalse(unsure.isLive)
        XCTAssertFalse(unsure.spoofSuspected)

        let photo = try PresentationAttack.assess(probabilities: [0.6, 0.3, 0.1])
        XCTAssertEqual(photo.label, .fake2D)
        XCTAssertTrue(photo.spoofSuspected)
        XCTAssertFalse(photo.isLive)

        XCTAssertEqual(try PresentationAttack.assess(probabilities: [0.1, 0.3, 0.6]).label, .fake3D)
        // Empate nunca favorece "real".
        XCTAssertEqual(try PresentationAttack.assess(probabilities: [0.45, 0.45, 0.1]).label, .fake2D)

        for bad: [Float] in [[0.5, 0.5], [.nan, 0.5, 0.5], [0.2, 0.5, 0.2], [-0.5, 1, 0.5], [0, .infinity, 0]] {
            XCTAssertThrowsError(try PresentationAttack.assess(probabilities: bad)) {
                XCTAssertEqual($0 as? PresentationAttackError, .invalidProbabilities)
            }
        }
    }

    func testStreakRequiresConsecutiveLiveFrames() throws {
        let live = try PresentationAttack.assess(probabilities: [0.05, 0.9, 0.05])
        let spoof = try PresentationAttack.assess(probabilities: [0.7, 0.2, 0.1])
        var streak = PresentationStreak(required: 3)
        streak.record(live); streak.record(live)
        XCTAssertFalse(streak.passed)
        streak.record(spoof)
        XCTAssertEqual(streak.count, 0)
        streak.record(live); streak.record(live); streak.record(nil)
        XCTAssertFalse(streak.passed)
        streak.record(live); streak.record(live); streak.record(live)
        XCTAssertTrue(streak.passed)
        streak.reset()
        XCTAssertFalse(streak.passed)
    }
}
