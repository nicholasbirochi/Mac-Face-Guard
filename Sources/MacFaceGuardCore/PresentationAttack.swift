import Foundation
import CoreGraphics

public enum PresentationAttackError: Error, Equatable { case invalidBox, invalidImage, invalidProbabilities }

/// Recorte de entrada do detector de ataque de apresentação (PAD): nome da entrada Core ML e fator de ampliação.
public struct PADCrop: Equatable, Sendable {
    public let input: String
    public let scale: Double
}

/// Identifica o pacote PAD e o pré-processamento esperado. Os pesos não estão no Git.
public struct PADModelDescriptor: Equatable, Sendable {
    public let id: String
    public let packageSHA256: String
    public let inputSize: Int
    public let crops: [PADCrop]
    public let output: String
    public let classes: Int

    /// MiniFASNetV2 (recorte 2,7) + MiniFASNetV1SE (recorte 4,0) do Silent-Face-Anti-Spoofing (Apache-2.0),
    /// convertidos localmente por scripts/convert-minifasnet.py. Saída: média das softmax [falso 2D, real, falso 3D].
    public static let miniFASNet = PADModelDescriptor(id: "minifasnet-v2-v1se-80",
        packageSHA256: "ee53d0da53d02ba7771d850dde8748d6bf71800186a97c7c53c5cfbba52d78fa",
        inputSize: 80, crops: [PADCrop(input: "wide", scale: 2.7), PADCrop(input: "wider", scale: 4.0)],
        output: "probabilities", classes: 3)
}

/// Retângulo em pixels com origem no canto superior esquerdo e limites inclusivos, como `img[top:bottom+1, left:right+1]`.
public struct PixelBox: Equatable, Sendable {
    public let left: Int, top: Int, right: Int, bottom: Int
    public var width: Int { right - left + 1 }
    public var height: Int { bottom - top + 1 }
}

public enum PresentationLabel: Int, Equatable, Sendable { case fake2D = 0, real = 1, fake3D = 2 }

public struct PresentationAssessment: Equatable, Sendable {
    public let label: PresentationLabel
    public let realScore: Float
    /// Real é a classe mais provável e supera o limiar experimental.
    public let isLive: Bool
    public var spoofSuspected: Bool { label != .real }
}

/// Contagem de quadros consecutivos com PAD favorável. Qualquer quadro sem avaliação favorável zera a sequência.
public struct PresentationStreak: Equatable, Sendable {
    public let required: Int
    public private(set) var count = 0

    public init(required: Int = 3) { self.required = max(1, required) }

    public var passed: Bool { count >= required }

    public mutating func record(_ assessment: PresentationAssessment?) {
        count = assessment?.isLive == true ? count + 1 : 0
    }

    public mutating func reset() { count = 0 }
}

/// Pré-processamento e leitura do MiniFASNet. PAD passivo estima ataque de foto/tela/máscara; não é prova de vida
/// ativa nem reconhecimento, e o limiar abaixo não foi calibrado neste Mac.
public enum PresentationAttack {
    public static let preprocessingVersion = "minifasnet-crop-bgra-bilinear-v1"
    public static let experimentalThreshold: Float = 0.8

    /// Converte a caixa normalizada do Vision (origem inferior esquerda) em (x, y, largura, altura) em pixels,
    /// origem superior esquerda. A referência usa caixa do RetinaFace; a do Vision é uma aproximação.
    public static func pixelRect(fromVision box: CGRect, width: Int, height: Int) throws -> CGRect {
        guard width > 1, height > 1, box.minX.isFinite, box.minY.isFinite, box.width.isFinite, box.height.isFinite,
              box.width > 0, box.height > 0 else { throw PresentationAttackError.invalidBox }
        let w = Double(width), h = Double(height)
        return CGRect(x: box.minX * w, y: (1 - box.maxY) * h, width: box.width * w, height: box.height * h)
    }

    /// Porta de `CropImage._get_new_box` (Silent-Face-Anti-Spoofing): amplia a caixa em torno do centro,
    /// limita a escala ao tamanho da imagem e desloca para dentro das bordas; `int()` trunca.
    public static func cropBox(face: CGRect, imageWidth: Int, imageHeight: Int, scale requested: Double) throws -> PixelBox {
        guard imageWidth > 1, imageHeight > 1, requested.isFinite, requested > 0,
              face.minX.isFinite, face.minY.isFinite, face.width.isFinite, face.height.isFinite,
              face.width >= 1, face.height >= 1 else { throw PresentationAttackError.invalidBox }
        let srcW = Double(imageWidth), srcH = Double(imageHeight)
        let boxW = Double(face.width), boxH = Double(face.height)
        let scale = min((srcH - 1) / boxH, min((srcW - 1) / boxW, requested))
        let newW = boxW * scale, newH = boxH * scale
        let centerX = boxW / 2 + Double(face.minX), centerY = boxH / 2 + Double(face.minY)
        var left = centerX - newW / 2, top = centerY - newH / 2
        var right = centerX + newW / 2, bottom = centerY + newH / 2
        if left < 0 { right -= left; left = 0 }
        if top < 0 { bottom -= top; top = 0 }
        if right > srcW - 1 { left -= right - srcW + 1; right = srcW - 1 }
        if bottom > srcH - 1 { top -= bottom - srcH + 1; bottom = srcH - 1 }
        // Pequenos negativos vêm só de arredondamento; truncar como int() do Python.
        let box = PixelBox(left: Int(max(0, left)), top: Int(max(0, top)), right: Int(right), bottom: Int(bottom))
        guard box.left >= 0, box.top >= 0, box.right < imageWidth, box.bottom < imageHeight,
              box.width >= 2, box.height >= 2 else { throw PresentationAttackError.invalidBox }
        return box
    }

    /// Recorta e redimensiona como `cv2.resize(..., INTER_LINEAR)`: centros de meio pixel, sem antisserrilhamento
    /// e coordenadas presas às bordas do recorte. Entrada e saída em 4 bytes por pixel, preservando os canais.
    public static func resample(_ pixels: UnsafeRawBufferPointer, width: Int, height: Int, bytesPerRow: Int,
                                box: PixelBox, size: Int) throws -> [UInt8] {
        guard width > 1, height > 1, size > 0, bytesPerRow >= width * 4,
              pixels.count >= bytesPerRow * (height - 1) + width * 4 else { throw PresentationAttackError.invalidImage }
        guard box.left >= 0, box.top >= 0, box.right < width, box.bottom < height,
              box.width >= 1, box.height >= 1 else { throw PresentationAttackError.invalidBox }
        let scaleX = Double(box.width) / Double(size), scaleY = Double(box.height) / Double(size)
        func axis(_ d: Int, _ scale: Double, _ count: Int) -> (Int, Int, Double) {
            var f = (Double(d) + 0.5) * scale - 0.5
            if f < 0 { f = 0 }
            var i = Int(floor(f)), t = f - Double(i)
            if i >= count - 1 { i = count - 1; t = 0 }
            return (i, min(i + 1, count - 1), t)
        }
        let xs = (0..<size).map { axis($0, scaleX, box.width) }
        let ys = (0..<size).map { axis($0, scaleY, box.height) }
        var output = [UInt8](repeating: 0, count: size * size * 4)
        for (v, (y0, y1, fy)) in ys.enumerated() {
            let row0 = (box.top + y0) * bytesPerRow, row1 = (box.top + y1) * bytesPerRow
            for (u, (x0, x1, fx)) in xs.enumerated() {
                let c0 = (box.left + x0) * 4, c1 = (box.left + x1) * 4
                for channel in 0..<4 {
                    let top = Double(pixels[row0 + c0 + channel]) * (1 - fx) + Double(pixels[row0 + c1 + channel]) * fx
                    let bottom = Double(pixels[row1 + c0 + channel]) * (1 - fx) + Double(pixels[row1 + c1 + channel]) * fx
                    let value = (top * (1 - fy) + bottom * fy).rounded()
                    output[(v * size + u) * 4 + channel] = UInt8(max(0, min(255, value)))
                }
            }
        }
        return output
    }

    /// Lê a saída [falso 2D, real, falso 3D]. Recusa tamanho errado, NaN/infinito e soma distante de 1.
    /// Empate escolhe a primeira classe, que nunca é "real".
    public static func assess(probabilities: [Float], threshold: Float = experimentalThreshold) throws -> PresentationAssessment {
        guard probabilities.count == 3, probabilities.allSatisfy({ $0.isFinite && $0 >= -1e-4 && $0 <= 1 + 1e-4 }),
              abs(probabilities.reduce(0, +) - 1) < 1e-3 else { throw PresentationAttackError.invalidProbabilities }
        var best = 0
        for index in 1..<3 where probabilities[index] > probabilities[best] { best = index }
        let label = PresentationLabel(rawValue: best)!
        let real = probabilities[PresentationLabel.real.rawValue]
        return PresentationAssessment(label: label, realScore: real, isLive: label == .real && real >= threshold)
    }
}
