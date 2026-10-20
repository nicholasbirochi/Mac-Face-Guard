import Foundation
import AppKit
import CoreGraphics
@preconcurrency import AVFoundation
import LocalAuthentication
import QuartzCore
import MacFaceGuardCore

/// Desbloqueio facial no estilo do Glance: ao bloquear ou despertar com a tela bloqueada, mostra a ilha no entalhe,
/// liga a câmera por até 15 s, compara o rosto e, só com semelhança e anti-fraude aprovados, digita a senha guardada
/// por Acessibilidade. Passar o cursor sobre a ilha tenta de novo. A senha digitada e o Touch ID continuam valendo
/// durante a procura: o primeiro método que responder vence e o rosto sai do caminho (`UnlockRace`).
@MainActor
final class UnlockCoordinator: ObservableObject {
    @Published private(set) var armed = false
    @Published private(set) var busy = false
    @Published private(set) var scanning = false
    @Published private(set) var hasPassword = false
    @Published private(set) var accessibility = false
    @Published var status = "Desarmado"
    @Published var error: String?
    @Published private(set) var lastSimilarity: Float?
    @Published var threshold: Float {
        didSet { UserDefaults.standard.set(threshold, forKey: Self.thresholdKey) }
    }

    /// Chamado antes de ligar a câmera, para encerrar a sessão do app que estiver aberta.
    var beforeScan: (() -> Void)?

    private static let thresholdKey = "unlockThreshold"
    /// Rostos recusados (outra pessoa ou fraude) por bloqueio; depois disso só a senha digitada.
    private static let failuresPerLock = 3
    private let vault = PasswordVault()
    private let templates = TemplateVault()
    private let monitor = LockMonitor()
    private let camera = CameraPipeline()
    private var reference: EnrollmentV2?
    private var extractor: EdgeFaceExtractor?
    private var detector: PresentationAttackDetector?
    private var gate: UnlockGate?
    private var race: UnlockRace?
    private var run: UUID?
    private var pending: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var autoRetry: Task<Void, Never>?
    private var keyWatch: Task<Void, Never>?
    private var lastWake: TimeInterval = 0
    private var failures = 0
    private var autoRetried = false
    private var typed = false
    private var overlay: NotchOverlayController { .shared }

    init() {
        let saved = UserDefaults.standard.object(forKey: Self.thresholdKey) as? Float
        threshold = saved ?? 0.5
        refresh()
        monitor.handler = { [weak self] event in self?.handle(event) }
    }

    func refresh() {
        hasPassword = vault.hasPassword
        accessibility = KeystrokeInjector.isTrusted
    }

    func requestAccessibility() {
        KeystrokeInjector.promptForAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Senha e armação

    /// Confere a senha no diretório local, guarda cifrada e já arma com o mesmo Touch ID.
    func storePassword(_ password: String) async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let context = try await authenticate("Guardar a senha do Mac para o desbloqueio facial")
            defer { context.invalidate() }
            let vault = self.vault
            // O contexto só é usado por esta tarefa enquanto aguardamos o resultado.
            nonisolated(unsafe) let shared = context
            try await Task.detached(priority: .userInitiated) { try vault.store(password, context: shared) }.value
            refresh()
            try await load(context: context)
        } catch {
            refresh()
            fail(error, fallback: "A senha não foi guardada.")
        }
    }

    func arm() async {
        guard !busy, !armed else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let context = try await authenticate("Armar o desbloqueio facial do MacFaceGuard")
            defer { context.invalidate() }
            try await load(context: context)
        } catch {
            disarm()
            fail(error, fallback: "O desbloqueio não foi armado.")
        }
    }

    private func load(context: LAContext) async throws {
        guard templates.hasV2 else { throw GuardError.message("Faça o cadastro facial antes de armar o desbloqueio.") }
        refresh()
        guard accessibility else { throw GuardError.message("Permita o MacFaceGuard em Acessibilidade para digitar a senha.") }
        let camera: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: camera = true
        case .notDetermined: camera = await AVCaptureDevice.requestAccess(for: .video)
        default: camera = false
        }
        guard camera else { throw GuardError.message("Autorize a câmera em Ajustes do Sistema → Privacidade e Segurança → Câmera.") }
        let models = try await Task.detached(priority: .userInitiated) {
            (try EdgeFaceExtractor(), try PresentationAttackDetector())
        }.value
        reference = try templates.load(context: context, model: models.0.descriptor)
        try vault.arm(context: context)
        extractor = models.0
        detector = models.1
        monitor.start()
        armed = true
        resetLock()
        status = "Armado • bloqueie o Mac para usar o rosto"
    }

    func disarm() {
        stopScan()
        autoRetry?.cancel()
        autoRetry = nil
        overlay.disarm()
        monitor.stop()
        vault.disarm()
        reference = nil
        extractor = nil
        detector = nil
        armed = false
        status = "Desarmado"
    }

    func deletePassword() {
        disarm()
        do { try vault.remove() } catch { fail(error, fallback: "A senha não foi apagada.") }
        refresh()
        if error == nil { status = "Senha apagada do Chaves" }
    }

    private func authenticate(_ reason: String) async throws -> LAContext {
        let context = LAContext()
        context.localizedFallbackTitle = ""
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
            throw GuardError.message("Ative o Touch ID no macOS para usar o desbloqueio facial.")
        }
        guard try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) else {
            throw GuardError.message("Touch ID não confirmou a operação.")
        }
        return context
    }

    private func fail(_ error: Error, fallback: String) {
        self.error = (error as? GuardError)?.localizedDescription ?? fallback
    }

    // MARK: Gatilhos (mesmo fluxo do FaceUnlockCoordinator do Glance)

    private func resetLock() {
        failures = 0
        autoRetried = false
        typed = false
    }

    private func handle(_ event: LockMonitor.Event) {
        switch event {
        case .locked:
            resetLock()
            schedule(after: .milliseconds(550))
        case .unlocked:
            stopScan()
            autoRetry?.cancel()
            overlay.disarm()
            resetLock()
            if armed { status = "Armado • Mac desbloqueado" }
        case .willSleep:
            stopScan()
            autoRetry?.cancel()
            overlay.dismissImmediately()
        case .wake:
            // Vários sinais chegam juntos ao abrir a tampa; só o primeiro de cada 2 s conta.
            let now = CACurrentMediaTime()
            guard now - lastWake >= 2 else { return }
            lastWake = now
            autoRetried = false
            schedule(after: .milliseconds(550))
        }
    }

    /// Espera o estado do WindowServer assentar, mostra a ilha fechada no entalhe e começa a procurar o rosto.
    private func schedule(after delay: Duration) {
        guard armed else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.armed, !self.monitor.isSleeping, LockMonitor.isScreenLocked else { return }
            self.overlay.arm { [weak self] in self?.beginScan() }
            self.beginScan()
        }
    }

    /// Chamado ao armar e sempre que o cursor passa sobre a ilha.
    private func beginScan() {
        guard armed, !scanning, !typed, failures < Self.failuresPerLock, LockMonitor.isScreenLocked,
              !monitor.isSleeping, let extractor, let detector, reference != nil else { return }
        beforeScan?()
        autoRetry?.cancel()
        autoRetry = nil
        let operation = UUID()
        run = operation
        let started = CACurrentMediaTime()
        gate = UnlockGate(threshold: threshold, started: started)
        race = UnlockRace(started: started)
        lastSimilarity = nil
        scanning = true
        status = "Tela bloqueada • procurando seu rosto"
        overlay.beginScanning()
        camera.start(run: operation, extractor: extractor, detector: detector) { [weak self] frame in
            Task { @MainActor in self?.receive(frame) }
        }
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(16))
            guard !Task.isCancelled, let self, self.run == operation else { return }
            self.stopScan(message: "Tempo esgotado • passe o cursor no entalhe para tentar de novo")
            Task { await self.overlay.collapse() }
        }
        // A tela de bloqueio usa entrada segura, então as teclas em si não são visíveis: só o tempo desde a última
        // tecla física (HID), que basta para saber que alguém começou a digitar a senha.
        keyWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled, let self, self.run == operation else { return }
                self.checkRace()
            }
        }
    }

    nonisolated private static func secondsSinceKey() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
    }

    /// Confere se a senha ou o Touch ID responderam antes do rosto. Devolve `true` se a procura pode continuar.
    @discardableResult
    private func checkRace() -> Bool {
        guard scanning, var race else { return false }
        let outcome = race.check(locked: LockMonitor.isScreenLocked, secondsSinceKey: Self.secondsSinceKey(),
                                 now: CACurrentMediaTime())
        self.race = race
        switch outcome {
        case .open, .faceWon: return true
        case .yielded(let reason): yield(reason); return false
        }
    }

    /// Outro método respondeu primeiro: câmera desligada, ilha recolhida e nenhuma nova tentativa automática neste
    /// bloqueio. Passar o cursor no entalhe ainda pode chamar o rosto de novo.
    private func yield(_ reason: UnlockRace.Yield) {
        autoRetry?.cancel()
        autoRetry = nil
        autoRetried = true
        switch reason {
        case .typing:
            stopScan(message: "Digitando a senha • rosto em espera")
            Task { await overlay.collapse() }
        case .unlocked:
            stopScan(message: "Armado • Mac desbloqueado")
            overlay.disarm()
        }
    }

    private func receive(_ frame: FrameAnalysis) {
        guard frame.run == run, scanning, checkRace(), var gate, let reference else { return }
        if frame.count < 0 {
            stopScan(message: "Câmera indisponível • digite a senha")
            Task { await overlay.collapse() }
            return
        }
        let similarity = frame.embedding.flatMap { try? reference.bestSimilarity(to: $0) }
        if let similarity { lastSimilarity = similarity }
        let step = gate.record(locked: LockMonitor.isScreenLocked, faceCount: frame.count, similarity: similarity,
                               presentation: frame.presentation, now: frame.capturedAt)
        self.gate = gate
        switch step {
        case .continue: return
        case .abort(.spoof): refuse("Possível fraude detectada")
        case .abort(.wrongFace): refuse("Rosto não reconhecido")
        case .abort(.timeout):
            stopScan(message: "Nenhum rosto detectado • passe o cursor no entalhe para tentar de novo")
            Task { await overlay.collapse() }
            scheduleAutoRetry(after: overlay.collapseAnimationDuration)
        case .abort(.notLocked):
            stopScan(message: "Armado • Mac desbloqueado")
            overlay.disarm()
        case .unlock:
            // O rosto só vence se ninguém digitou nem desbloqueou até este instante.
            guard var race else { return }
            let won = race.claimForFace(locked: LockMonitor.isScreenLocked, secondsSinceKey: Self.secondsSinceKey(),
                                        now: CACurrentMediaTime())
            self.race = race
            guard won else {
                if case .yielded(let reason) = race.outcome { yield(reason) }
                return
            }
            stopScan(message: "Rosto reconhecido • desbloqueando")
            typed = true
            overlay.finish(success: true)
            type(claimedAt: CACurrentMediaTime())
        }
    }

    private func refuse(_ reason: String) {
        failures += 1
        let left = Self.failuresPerLock - failures
        stopScan(message: left > 0 ? "\(reason) • passe o cursor no entalhe para tentar de novo" : "\(reason) • digite a senha")
        overlay.finish(success: false)
        if left > 0 { scheduleAutoRetry(after: overlay.failureHoldDuration) }
    }

    /// Como o "tentar de novo uma vez" do Glance: espera a animação terminar e só repete se a ilha já fechou.
    private func scheduleAutoRetry(after delay: Duration) {
        guard !autoRetried else { return }
        autoRetried = true
        autoRetry?.cancel()
        let scheduled = CACurrentMediaTime()
        autoRetry = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, LockMonitor.isScreenLocked, self.overlay.phase == .closed else { return }
            // Quem começou a digitar durante a espera não tem a câmera religada por cima.
            guard !UnlockRace.keyPressed(since: scheduled, secondsSinceKey: Self.secondsSinceKey(),
                                         now: CACurrentMediaTime()) else { return }
            self.beginScan()
        }
    }

    /// A senha só é lida aqui, digitada fora da thread principal e zerada em seguida. Antes de cada tecla, confere que
    /// a tela continua bloqueada; se o Touch ID ou a senha desbloquearem no meio, nada mais é enviado (nem o Return).
    private func type(claimedAt: TimeInterval) {
        let vault = self.vault
        Task.detached(priority: .userInitiated) { [weak self] in
            var message: String?
            do {
                var bytes = try vault.password()
                defer { bytes.resetBytes(in: 0..<bytes.count) }
                // Reconfere o bloqueio no último instante: nunca digitar a senha numa tela desbloqueada.
                guard LockMonitor.isScreenLocked else { throw GuardError.message("A tela já estava desbloqueada.") }
                // Alguém começou a digitar entre a vitória do rosto e a digitação: a vez é de quem digita.
                guard !UnlockRace.keyPressed(since: claimedAt, secondsSinceKey: Self.secondsSinceKey(),
                                             now: CACurrentMediaTime()) else {
                    throw GuardError.message("Digitação cancelada: você começou a digitar a senha.")
                }
                try KeystrokeInjector.typeAndReturn(bytes) { LockMonitor.isScreenLocked }
            } catch {
                message = (error as? GuardError)?.localizedDescription ?? "A digitação falhou."
            }
            await MainActor.run { [message] in
                guard let self else { return }
                if let message { self.error = message; self.status = "Desbloqueio não concluído" }
            }
        }
    }

    private func stopScan(message: String? = nil) {
        pending?.cancel()
        pending = nil
        watchdog?.cancel()
        watchdog = nil
        keyWatch?.cancel()
        keyWatch = nil
        race = nil
        if scanning || run != nil { camera.stop() }
        run = nil
        gate = nil
        scanning = false
        if let message { status = message }
    }
}
