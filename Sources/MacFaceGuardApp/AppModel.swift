import SwiftUI
import AVFoundation
import LocalAuthentication
import ServiceManagement
import QuartzCore
import MacFaceGuardCore

@MainActor
final class AppModel: ObservableObject {
    @Published var hasEnrollment = false
    @Published var active = false
    @Published var busy = false
    @Published var consent = false
    @Published var status = "Pronto para o primeiro cadastro"
    @Published var guidance = "Seu rosto fica neste Mac. Você controla quando a câmera liga."
    @Published var sampleCount = 0
    @Published var captureHint = ""
    @Published var poseReady = false
    /// Guia visual do giro; não é prova de vida nem participa da decisão.
    @Published var ring = RotationRing()
    @Published var faceCount = 0
    @Published var quality: Float = 0
    @Published var similarity: Float?
    @Published var loginEnabled = false
    @Published var loginMessage = ""
    @Published var error: String?
    @Published var tab = "Cadastro"
    let camera = CameraPipeline()
    /// Painel no entalhe que mostra o anel de giro durante o cadastro.
    let island = NotchIsland()
    private let vault = TemplateVault()
    private var run: UUID?
    private var context: LAContext?
    private var mode = ""
    private var samples: [[Float]] = []
    private var reference: EnrollmentV2?
    private var extractor: EdgeFaceExtractor?
    private var lastCapture: TimeInterval = 0
    private var expiry: Task<Void, Never>?
    private var frames: CaptureFrameGate?
    private var activation = CaptureActivationGate()
    private var firstTurn: Double?
    private var neutralYaw: Double?
    private var neutralTurn: Double?
    private var neutralLift: Double?

    init() {
        hasEnrollment = vault.exists
        loginEnabled = SMAppService.mainApp.status == .enabled
        if hasEnrollment { status = "Cadastro local encontrado" }
    }

    func start(enrolling: Bool) async {
        guard !busy, !active, consent else { return }
        busy = true
        error = nil
        let operation = UUID()
        run = operation
        let auth = LAContext()
        context = auth
        auth.localizedCancelTitle = "Cancelar"
        auth.localizedFallbackTitle = ""
        do {
            var authError: NSError?
            guard auth.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
                throw GuardError.message("Ative o Touch ID no macOS antes de cadastrar, comparar ou excluir seu rosto.")
            }
            let reason = enrolling ? "Autorizar o cadastro facial local no MacFaceGuard" : "Acessar seu cadastro facial criptografado"
            guard try await auth.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) else {
                throw GuardError.message("Touch ID não confirmou a operação.")
            }
            guard run == operation else { return }
            // Sem modelo íntegro não há câmera nem comparação: hash, interface e dimensão são conferidos antes.
            let loaded = try await Task.detached(priority: .userInitiated) { try EdgeFaceExtractor() }.value
            guard run == operation else { return }
            extractor = loaded
            if enrolling { try vault.prepare(context: auth) }
            else { reference = try vault.load(context: auth, model: loaded.descriptor) }
            let authorized: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: authorized = true
            case .notDetermined: authorized = await AVCaptureDevice.requestAccess(for: .video)
            default: authorized = false
            }
            guard run == operation else { return }
            guard authorized else { throw GuardError.message("Autorize a câmera em Ajustes do Sistema → Privacidade e Segurança → Câmera.") }
            mode = enrolling ? "enroll" : "compare"
            samples = []
            sampleCount = 0
            similarity = nil
            lastCapture = 0
            firstTurn = nil
            neutralYaw = nil
            neutralTurn = nil
            neutralLift = nil
            ring.reset()
            captureHint = "Centralize o rosto no círculo."
            poseReady = false
            activation.prepare(operation)
            status = "Touch ID confirmado • aguardando a janela"
            guidance = enrolling ? "Olhe de frente para a câmera." : "Olhe de frente. A similaridade não confirma sua identidade."
            expiry = Task { [weak self] in
                try? await Task.sleep(for: .seconds(enrolling ? 90 : 45))
                guard !Task.isCancelled, let self, self.run == operation else { return }
                self.stop(message: "O tempo da sessão terminou. Inicie novamente quando quiser.")
            }
            foregrounded()
            if !active { NSApp.activate(ignoringOtherApps: true) }
        } catch {
            guard run == operation else { return }
            stop(message: "Operação interrompida")
            self.error = (error as? GuardError)?.localizedDescription ?? "Não foi possível concluir a operação com segurança. Nenhum acesso foi autorizado."
        }
    }

    func foregrounded() {
        guard let run, consent, let extractor, activation.consume(run, isForeground: NSApp.isActive) else { return }
        frames = CaptureFrameGate(startedAt: CACurrentMediaTime())
        active = true
        busy = false
        status = mode == "enroll" ? "Cadastro em andamento" : "Comparação experimental"
        camera.start(run: run, extractor: extractor) { [weak self] frame in
            Task { @MainActor in self?.receive(frame) }
        }
        if mode == "enroll" { island.show(model: self) }
    }

    private func receive(_ frame: FrameAnalysis) {
        guard active, run == frame.run,
              frames?.consume(capturedAt: frame.capturedAt, now: CACurrentMediaTime()) == true else { return }
        faceCount = frame.count
        quality = frame.quality
        if frame.count < 0 {
            stop(message: "Câmera indisponível")
            error = frame.message
            return
        }
        if mode == "enroll", frame.count == 1 { traceRing(frame) }
        guard let embedding = frame.embedding, frame.count == 1 else {
            status = frame.message
            captureHint = frame.message
            poseReady = false
            similarity = nil
            return
        }
        if mode == "enroll" {
            if samples.count < EnrollmentV2.sampleCount {
                let pose = CapturePose.allCases[samples.count]
                let qualityEnough = frame.quality >= pose.minimumQuality
                let yaw: Double
                if samples.isEmpty { yaw = frame.yaw }
                else if let neutralTurn {
                    guard let turn = frame.turn else {
                        poseReady = false
                        captureHint = "Gire menos: mantenha os dois olhos visíveis."
                        return
                    }
                    yaw = turn - neutralTurn
                } else { yaw = frame.yaw - (neutralYaw ?? 0) }
                // As amostras laterais saem com a cabeça na altura neutra, como no cadastro 0.1.6.
                let level = samples.isEmpty || abs((frame.lift ?? .nan) - (neutralLift ?? .nan)) < 0.2
                let geometry = !samples.isEmpty || (frame.turn != nil && frame.lift != nil)
                poseReady = level && geometry && pose.accepts(quality: frame.quality, yaw: yaw, firstTurn: firstTurn)
                if !qualityEnough { captureHint = "Procure mais luz no rosto." }
                else if samples.isEmpty { captureHint = poseReady ? "Posição detectada. Segure um instante…" : "Olhe de frente e mantenha o rosto no círculo." }
                if poseReady, frame.capturedAt - lastCapture > 1.2 {
                    samples.append(embedding)
                    if samples.count == 1 { neutralYaw = frame.yaw; neutralTurn = frame.turn; neutralLift = frame.lift }
                    if samples.count == 2 { firstTurn = yaw }
                    sampleCount = samples.count
                    lastCapture = frame.capturedAt
                    NSSound(named: "Tink")?.play()
                    poseReady = false
                }
            }
            guard !samples.isEmpty else { return }
            if samples.count < EnrollmentV2.sampleCount || !ring.isComplete {
                status = ring.isComplete ? "Anel completo • falta uma vista lateral" : "Gire a cabeça devagar em círculo"
                guidance = "Mova a cabeça devagar para completar o círculo"
                captureHint = ringPrompt()
                return
            }
            do {
                guard let context, let extractor else { throw GuardError.message("A sessão de cadastro expirou.") }
                try vault.save(EnrollmentV2(model: extractor.descriptor, embeddings: samples),
                               model: extractor.descriptor, context: context)
                hasEnrollment = true
                NSSound(named: "Glass")?.play()
                island.close(success: true)
                stop(message: "Seu cadastro foi criptografado neste Mac")
                guidance = "Três vetores faciais salvos. Nenhuma foto ou vídeo foi gravado."
            } catch {
                stop(message: "O cadastro não pôde ser salvo")
                self.error = (error as? GuardError)?.localizedDescription ?? "Falha na proteção do cadastro. Tente novamente."
            }
        } else {
            do {
                guard let reference else { throw GuardError.message("Cadastro ausente.") }
                similarity = try reference.bestSimilarity(to: embedding)
                // shortcut: sem PAD e sem limiar validado com dados locais, a similaridade não autoriza acesso.
                let decision = DecisionEngine().evaluate(DemoEvidence(cameraAuthorized: true,
                    enrollmentExists: true, singleFaceDetected: true, captureQualityApproved: true,
                    identityMatched: false, livenessPassed: false, framesConsistent: true,
                    sessionCurrent: true, spoofSuspected: false))
                if case .denied = decision { status = "Semelhança medida • autenticação bloqueada" }
            } catch {
                stop(message: "Comparação interrompida")
                self.error = "Não foi possível comparar o cadastro com segurança. Nenhum acesso foi autorizado."
            }
        }
    }

    /// Acende o anel pela direção da cabeça em relação à vista frontal; só orienta o movimento.
    private func traceRing(_ frame: FrameAnalysis) {
        guard !samples.isEmpty, let turn = frame.turn, let lift = frame.lift,
              let neutralTurn, let neutralLift else { return }
        // Na imagem espelhada, a direita da pessoa é a direita da tela.
        let dx = frame.mirrored ? turn - neutralTurn : neutralTurn - turn
        var next = ring
        if next.record(dx: dx, dy: lift - neutralLift) != nil, next != ring { ring = next }
    }

    private func ringPrompt() -> String {
        if !ring.isComplete {
            guard let gap = ring.largestGapCenter else { return "Mova a cabeça devagar, desenhando um círculo com o nariz." }
            let directions = ["para a direita", "para cima e à direita", "para cima", "para cima e à esquerda",
                              "para a esquerda", "para baixo e à esquerda", "para baixo", "para baixo e à direita"]
            let sector = Int((ring.angle(of: gap) / (2 * .pi) * 8).rounded()) % 8
            return "Vire a cabeça \(directions[sector])"
        }
        return samples.count == 1 ? "Quase lá: vire para um dos lados, olhando reto." : "Quase lá: vire para o outro lado, olhando reto."
    }

    func stop(message: String = "Câmera desligada") {
        run = nil
        frames = nil
        activation.cancel()
        expiry?.cancel()
        expiry = nil
        camera.stop()
        island.close(success: false)
        context?.invalidate()
        context = nil
        active = false
        busy = false
        faceCount = 0
        quality = 0
        poseReady = false
        firstTurn = nil
        neutralYaw = nil
        neutralTurn = nil
        neutralLift = nil
        ring.reset()
        similarity = nil
        samples.removeAll()
        reference = nil
        extractor = nil
        status = message
    }

    func backgrounded() {
        if active { stop(message: "Câmera desligada ao sair do app") }
    }

    func deleteEnrollment() async {
        guard !busy else { return }
        stop()
        busy = true
        let operation = UUID()
        run = operation
        let auth = LAContext()
        context = auth
        auth.localizedFallbackTitle = ""
        do {
            guard try await auth.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Excluir definitivamente o cadastro facial deste Mac") else {
                throw GuardError.message("A exclusão não foi autorizada pelo Touch ID.")
            }
            guard run == operation else { return }
            try vault.delete()
            hasEnrollment = false
            sampleCount = 0
            status = "Cadastro e chave excluídos"
            guidance = "Você pode fazer um novo cadastro quando quiser."
        } catch {
            guard run == operation else { return }
            self.error = (error as? GuardError)?.localizedDescription ?? "A exclusão não foi concluída. O cadastro não será utilizado nesta sessão."
        }
        context?.invalidate()
        context = nil
        run = nil
        busy = false
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            loginMessage = SMAppService.mainApp.status == .requiresApproval ? "Confirme em Ajustes do Sistema → Geral → Itens de Início." : ""
        } catch {
            loginEnabled = SMAppService.mainApp.status == .enabled
            loginMessage = "O macOS não confirmou a alteração. Confira os Itens de Início."
        }
    }
}
