import SwiftUI
import AVFoundation
import Vision
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
    @Published var faceCount = 0
    @Published var quality: Float = 0
    @Published var distance: Float?
    @Published var loginEnabled = false
    @Published var loginMessage = ""
    @Published var error: String?
    @Published var tab = "Cadastro"
    let camera = CameraPipeline()
    private let vault = TemplateVault()
    private var run: UUID?
    private var context: LAContext?
    private var mode = ""
    private var samples: [Data] = []
    private var reference: [VNFeaturePrintObservation] = []
    private var lastCapture: TimeInterval = 0
    private var expiry: Task<Void, Never>?
    private var startedAt: TimeInterval = 0
    private var activation = CaptureActivationGate()
    private var firstTurn: Double?
    private var neutralYaw: Double?

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
            if !enrolling {
                let record = try vault.load(context: auth)
                reference = try record.samples.map { data in
                    guard let feature = try NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data),
                          feature.requestRevision == record.revision else {
                        throw GuardError.message("Cadastro incompatível. Faça um novo cadastro.")
                    }
                    return feature
                }
            }
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
            distance = nil
            lastCapture = 0
            firstTurn = nil
            neutralYaw = nil
            captureHint = "Centralize o rosto na moldura."
            poseReady = false
            activation.prepare(operation)
            status = "Touch ID confirmado • aguardando a janela"
            guidance = enrolling ? "Olhe de frente para a câmera." : "Olhe de frente. A distância visual não confirma sua identidade."
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
        guard let run, consent, activation.consume(run, isForeground: NSApp.isActive) else { return }
        startedAt = CACurrentMediaTime()
        active = true
        busy = false
        status = mode == "enroll" ? "Cadastro em andamento" : "Comparação experimental"
        camera.start(run: run) { [weak self] frame in
            Task { @MainActor in self?.receive(frame) }
        }
    }

    private func receive(_ frame: FrameAnalysis) {
        guard active, run == frame.run, CACurrentMediaTime() - frame.capturedAt < 2,
              frame.capturedAt >= startedAt else { return }
        faceCount = frame.count
        quality = frame.quality
        if frame.count < 0 {
            stop(message: "Câmera indisponível")
            error = frame.message
            return
        }
        guard let print = frame.print, frame.count == 1 else {
            status = frame.message
            captureHint = frame.message
            poseReady = false
            distance = nil
            return
        }
        if mode == "enroll" {
            let pose = CapturePose.allCases[samples.count]
            let qualityEnough = frame.quality >= pose.minimumQuality
            let yaw = samples.isEmpty ? frame.yaw : frame.yaw - (neutralYaw ?? 0)
            poseReady = pose.accepts(quality: frame.quality, yaw: yaw, firstTurn: firstTurn)
            captureHint = !qualityEnough ? "Procure mais luz no rosto." : poseReady ? "Posição detectada. Segure um instante…" : samples.isEmpty ? "Olhe de frente e mantenha o rosto centralizado." : samples.count == 1 ? "Pode virar para qualquer lado, só um pouquinho." : "Passe pelo centro e vire um pouco para o outro lado."
            guard poseReady, frame.capturedAt - lastCapture > 1.2 else { return }
            do {
                samples.append(try NSKeyedArchiver.archivedData(withRootObject: print, requiringSecureCoding: true))
                if samples.count == 1 { neutralYaw = frame.yaw }
                if samples.count == 2 { firstTurn = yaw }
                sampleCount = samples.count
                lastCapture = frame.capturedAt
                NSSound(named: "Tink")?.play()
                poseReady = false
                if samples.count == 3 {
                    guard let context else { throw GuardError.message("A sessão de cadastro expirou.") }
                    try vault.save(Enrollment(revision: 2, samples: samples), context: context)
                    hasEnrollment = true
                    stop(message: "Seu cadastro foi criptografado neste Mac")
                    guidance = "Três amostras salvas. Nenhuma foto ou vídeo foi gravado."
                } else {
                    status = "Amostra \(samples.count) de 3 capturada"
                    guidance = samples.count == 1 ? "Vire um pouco para um dos lados" : "Agora, vire para o lado oposto"
                    captureHint = samples.count == 1 ? "Esquerda ou direita: você escolhe." : "Passe pelo centro e vire para o outro lado."
                }
            } catch {
                stop(message: "O cadastro não pôde ser salvo")
                self.error = (error as? GuardError)?.localizedDescription ?? "Falha na proteção do cadastro. Tente novamente."
            }
        } else {
            do {
                let values = try reference.map { observation -> Float in
                    var value: Float = 0
                    try print.computeDistance(&value, to: observation)
                    guard value.isFinite, value >= 0 else { throw GuardError.message("Distância visual inválida.") }
                    return value
                }
                guard let best = values.min() else { throw GuardError.message("Cadastro ausente.") }
                distance = best
                // shortcut: feature prints medem semelhança de imagem; substituir por modelo facial e PAD avaliados antes de autorizar.
                let decision = DecisionEngine().evaluate(DemoEvidence(cameraAuthorized: true,
                    enrollmentExists: true, singleFaceDetected: true, captureQualityApproved: true,
                    identityMatched: false, livenessPassed: false, framesConsistent: true,
                    sessionCurrent: true, spoofSuspected: false))
                if case .denied = decision { status = "Semelhança medida • autenticação bloqueada" }
            } catch {
                stop(message: "Comparação interrompida")
                self.error = "Não foi possível comparar o cadastro com segurança. Cadastre novamente se a versão do Vision mudou."
            }
        }
    }

    func stop(message: String = "Câmera desligada") {
        run = nil
        activation.cancel()
        expiry?.cancel()
        expiry = nil
        camera.stop()
        context?.invalidate()
        context = nil
        active = false
        busy = false
        faceCount = 0
        quality = 0
        poseReady = false
        firstTurn = nil
        neutralYaw = nil
        distance = nil
        samples.removeAll()
        reference.removeAll()
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
