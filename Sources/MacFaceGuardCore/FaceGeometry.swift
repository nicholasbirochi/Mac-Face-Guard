import Foundation
import CoreGraphics

public enum FaceGeometry {
    /// Deslocamento do nariz em relação aos olhos; independe da posição e escala do rosto.
    public static func noseOffset(nose: Double, leftEye: Double, rightEye: Double) -> Double? {
        guard [nose, leftEye, rightEye].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
        let separation = abs(rightEye - leftEye)
        guard separation >= 0.05 else { return nil }
        let offset = (nose - (leftEye + rightEye) / 2) / separation
        return abs(offset) <= 1 ? offset : nil
    }

    /// Altura do nariz em relação à linha dos olhos (y para cima), na escala da distância entre os olhos.
    /// Cresce quando a pessoa olha para cima, porque a ponta do nariz fica à frente do plano dos olhos.
    public static func noseLift(nose: Double, leftEyeX: Double, leftEyeY: Double, rightEyeX: Double, rightEyeY: Double) -> Double? {
        guard [nose, leftEyeX, leftEyeY, rightEyeX, rightEyeY].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
        let separation = abs(rightEyeX - leftEyeX)
        guard separation >= 0.05 else { return nil }
        let lift = (nose - (leftEyeY + rightEyeY) / 2) / separation
        return abs(lift) <= 2 ? lift : nil
    }

    /// Só une caixas quase idênticas; rostos separados, parcialmente sobrepostos ou pequenos permanecem distintos.
    public static func uniqueFaceIndices(_ boxes: [CGRect]) -> [Int] {
        var kept: [Int] = []
        for index in boxes.indices {
            let box = boxes[index]
            let area = box.width * box.height
            guard area.isFinite, area > 0 else { kept.append(index); continue }
            let duplicate = kept.contains(where: { other in
                let candidate = boxes[other]
                let otherArea = candidate.width * candidate.height
                let intersection = box.intersection(candidate)
                guard !intersection.isNull, otherArea > 0 else { return false }
                let shared = intersection.width * intersection.height
                return shared / min(area, otherArea) >= 0.90 && shared / (area + otherArea - shared) >= 0.70
            })
            if !duplicate { kept.append(index) }
        }
        return kept
    }
}
