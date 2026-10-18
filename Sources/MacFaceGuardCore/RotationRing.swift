import Foundation

/// Anel de giro do cadastro: cada direção da cabeça acende os traços daquele ângulo.
/// É só um guia de movimento. Não é prova de vida nem PAD: um vídeo reproduzido também o preenche.
public struct RotationRing: Equatable, Sendable {
    public let segmentCount: Int
    /// Deslocamento mínimo (na escala da distância entre os olhos) para contar uma direção.
    public let threshold: Double
    /// Acima disso a leitura é tratada como ruído dos landmarks.
    public let limit: Double
    /// Traços vizinhos acesos de cada lado da direção medida.
    public let spread: Int
    /// Fração de traços que conclui o anel; os poucos restantes costumam ser jitter.
    public let requiredCoverage: Double
    public private(set) var covered: [Bool]

    public init(segmentCount: Int = 60, threshold: Double = 0.07, limit: Double = 1.2,
                spread: Int = 2, requiredCoverage: Double = 0.95) {
        precondition(segmentCount >= 8 && threshold > 0 && limit > threshold && spread >= 0
                     && (0.5...1).contains(requiredCoverage))
        self.segmentCount = segmentCount
        self.threshold = threshold
        self.limit = limit
        self.spread = min(spread, segmentCount / 4)
        self.requiredCoverage = requiredCoverage
        covered = Array(repeating: false, count: segmentCount)
    }

    /// `dx` positivo = direita na tela; `dy` positivo = para cima. O traço 0 fica à direita e a ordem é anti-horária.
    public func segment(dx: Double, dy: Double) -> Int? {
        guard dx.isFinite, dy.isFinite else { return nil }
        let magnitude = (dx * dx + dy * dy).squareRoot()
        guard magnitude >= threshold, magnitude <= limit else { return nil }
        var angle = atan2(dy, dx)
        if angle < 0 { angle += 2 * .pi }
        return Int((angle / (2 * .pi) * Double(segmentCount)).rounded()) % segmentCount
    }

    @discardableResult
    public mutating func record(dx: Double, dy: Double) -> Int? {
        guard let index = segment(dx: dx, dy: dy) else { return nil }
        for offset in -spread...spread {
            covered[(index + offset + segmentCount) % segmentCount] = true
        }
        return index
    }

    public var coveredCount: Int { covered.lazy.filter { $0 }.count }
    public var coverage: Double { Double(coveredCount) / Double(segmentCount) }
    public var isComplete: Bool { coverage >= requiredCoverage }

    /// Centro do maior trecho ainda apagado, para orientar o próximo movimento; `nil` se nada ou tudo estiver aceso.
    public var largestGapCenter: Int? {
        guard let start = covered.firstIndex(of: true), covered.contains(false) else { return nil }
        var best = (start: 0, length: 0)
        var run = (start: 0, length: 0)
        for step in 1...segmentCount {
            let index = (start + step) % segmentCount
            if covered[index] {
                if run.length > best.length { best = run }
                run.length = 0
            } else {
                if run.length == 0 { run.start = index }
                run.length += 1
            }
        }
        return (best.start + (best.length - 1) / 2) % segmentCount
    }

    /// Ângulo do traço em radianos, no mesmo sentido de `segment(dx:dy:)`.
    public func angle(of index: Int) -> Double { 2 * .pi * Double(index) / Double(segmentCount) }

    public mutating func reset() { covered = Array(repeating: false, count: segmentCount) }
}
