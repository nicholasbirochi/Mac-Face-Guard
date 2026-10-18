import SwiftUI
import AVFoundation
import ServiceManagement
import MacFaceGuardCore

@main
struct MacFaceGuardApp: App {
    @StateObject private var model: AppModel
    @StateObject private var unlock: UnlockCoordinator
    @Environment(\.scenePhase) private var phase

    init() {
        if CommandLine.arguments.contains("--self-check-keychain") {
            do {
                try TemplateVault.verifyKeychainProtection()
                print("KEYCHAIN_PROTECTION_VERIFIED")
                exit(0)
            } catch {
                print(error.localizedDescription)
                exit(1)
            }
        }
        if CommandLine.arguments.contains("--self-check-model") {
            do {
                print(try EdgeFaceExtractor.selfCheck())
                print(try PresentationAttackDetector.selfCheck())
                exit(0)
            } catch {
                print((error as? GuardError)?.localizedDescription ?? "MODEL_CHECK_FAILED")
                exit(1)
            }
        }
        if CommandLine.arguments.contains("--register-login-item") {
            do {
                try SMAppService.mainApp.register()
                let status = SMAppService.mainApp.status
                print(status == .enabled ? "LOGIN_ITEM_ENABLED" : "LOGIN_ITEM_REQUIRES_APPROVAL")
                exit(status == .enabled ? 0 : 2)
            } catch {
                print("LOGIN_ITEM_REGISTRATION_FAILED")
                exit(1)
            }
        }
        let model = AppModel()
        let unlock = UnlockCoordinator()
        // A câmera tem um dono por vez: o desbloqueio encerra a sessão do app antes de ligá-la.
        unlock.beforeScan = { [weak model] in model?.stop(message: "Sessão encerrada para o desbloqueio facial") }
        _model = StateObject(wrappedValue: model)
        _unlock = StateObject(wrappedValue: unlock)
    }

    var body: some Scene {
        Window("MacFaceGuard", id: "main") {
            ContentView(model: model, unlock: unlock)
                .frame(minWidth: 1040, minHeight: 700)
                .preferredColorScheme(.dark)
                .onChange(of: phase) { _, phase in
                    if phase == .active { model.foregrounded() }
                    else { model.backgrounded() }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    model.foregrounded()
                }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in
                    model.stop(message: "Sessão encerrada ao suspender o Mac")
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.stop()
                    unlock.disarm()
                }
                .onDisappear { model.stop() }
                .task {
                    if CommandLine.arguments.contains("--enable-login-item") { model.setLogin(true) }
                }
                .alert("MacFaceGuard", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                    Button("Entendi", role: .cancel) { model.error = nil }
                } message: { Text(model.error ?? "") }
        }
        .defaultSize(width: 1140, height: 780)
        .windowResizability(.contentMinSize)
        MenuBarExtra("MacFaceGuard", systemImage: "faceid") {
            GuardMenu(model: model, unlock: unlock)
        }
    }
}

private struct GuardMenu: View {
    @ObservedObject var model: AppModel
    @ObservedObject var unlock: UnlockCoordinator
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Abrir MacFaceGuard") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        if model.active { Button("Desligar câmera") { model.stop() } }
        Divider()
        if unlock.armed {
            Button("Desarmar desbloqueio facial") { unlock.disarm() }
        } else if unlock.hasPassword {
            Button("Armar desbloqueio facial") { Task { await unlock.arm() } }.disabled(unlock.busy)
        }
        Text(unlock.armed ? "Desbloqueio facial armado" : "Desbloqueio facial desarmado")
        Button("Sair") { model.stop(); unlock.disarm(); NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

let ink = Color(red: 0.055, green: 0.071, blue: 0.105)
let panel = Color(red: 0.09, green: 0.11, blue: 0.15)
let accent = Color(red: 0.40, green: 0.88, blue: 0.74)
/// Verde do anel de giro, no tom do cadastro de rosto dos iPhones recentes.
let ringGreen = Color(red: 0.20, green: 0.84, blue: 0.40)

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var unlock: UnlockCoordinator
    @State private var confirmDelete = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Label("ESPAÇO PESSOAL", systemImage: "laptopcomputer")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                        Spacer()
                        Label("100% local", systemImage: "lock.shield.fill").font(.system(size: 12)).foregroundStyle(accent)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.tab == "Privacidade" ? "Seu rosto. Seu controle." : model.tab == "Desbloqueio" ? "Olhe e entre." : "Um rosto. Só neste Mac.")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                        Text(model.tab == "Privacidade" ? "Veja o que é salvo e escolha o que permanece."
                             : model.tab == "Desbloqueio" ? "Ao despertar o Mac bloqueado, o MacFaceGuard reconhece seu rosto e digita sua senha."
                             : "Cadastre seu rosto para explorar a comparação visual com privacidade.")
                            .font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        metric("CADASTRO", value: model.hasEnrollment ? "Protegido" : "Não cadastrado", icon: "person.crop.circle")
                        metric("ARMAZENAMENTO", value: "AES-256-GCM", icon: "lock.fill")
                        metric("CÂMERA", value: model.active || unlock.scanning ? "Ligada" : "Desligada", icon: "camera")
                    }
                    if model.tab == "Privacidade" { privacy }
                    else if model.tab == "Desbloqueio" { UnlockPanel(unlock: unlock, hasEnrollment: model.hasEnrollment) }
                    else { capture }
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "flask.fill").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Protótipo experimental").font(.system(size: 13, weight: .semibold))
                            Text("A webcam 2D é mais fraca que o Face ID: o limiar de identidade e o anti-fraude MiniFASNet ainda não foram calibrados, e uma foto ou vídeo pode enganá-los. O desbloqueio facial só funciona se você armá-lo; desarmado, nada é digitado.")
                                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                }.padding(30)
            }.background(ink)
        }
        .tint(accent)
        .confirmationDialog("Excluir o cadastro facial e a chave deste Mac?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Excluir definitivamente", role: .destructive) { Task { await model.deleteEnrollment() } }
        } message: { Text("O Touch ID confirma a exclusão. Essa ação não pode ser desfeita.") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 10) {
                Image(systemName: "faceid").font(.system(size: 30, weight: .light)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("MacFaceGuard").font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text("PERSONAL FACE LAB").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1.5).foregroundStyle(.secondary)
                }
            }.padding(.top, 14)
            VStack(spacing: 6) {
                nav("Cadastro", icon: "person.crop.rectangle.badge.plus")
                nav("Comparação", icon: "viewfinder")
                nav("Desbloqueio", icon: "lock.open")
                nav("Privacidade", icon: "hand.raised")
            }
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Label("A chave fica no Chaves", systemImage: "key.fill").font(.system(size: 12, weight: .medium)).foregroundStyle(accent)
                Text("Sem conta, sem nuvem e sem gravação de fotos ou vídeos.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(14).background(ink, in: RoundedRectangle(cornerRadius: 12))
            Text("v0.2.0 • Protótipo experimental").font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(20).frame(width: 230).frame(maxHeight: .infinity)
            .background(panel)
    }

    private func nav(_ title: String, icon: String) -> some View {
        Button {
            if model.active || model.busy { model.stop() }
            model.tab = title
        } label: {
            HStack(spacing: 11) {
                Image(systemName: icon).frame(width: 20)
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer()
                if model.tab == title { Circle().fill(accent).frame(width: 5, height: 5) }
            }.padding(12).foregroundStyle(model.tab == title ? accent : .secondary)
                .background(model.tab == title ? accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }

    /// O anel de giro aparece na ilha, no entalhe; a janela só aponta para lá.
    private var enrollPointer: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.up").font(.system(size: 30, weight: .semibold)).foregroundStyle(ringGreen)
            Text("Siga o anel na ilha, no topo da tela").font(.system(size: 17, weight: .semibold, design: .rounded))
            Text(model.sampleCount == 0 ? model.guidance : "Anel \(Int(model.ring.coverage * 100))% • amostra \(model.sampleCount) de 3")
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
        }.multilineTextAlignment(.center).padding(.horizontal, 24)
            .accessibilityElement(children: .combine)
    }

    private func metric(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(accent)
            }
            Text(value).font(.system(size: 14, weight: .semibold))
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(panel, in: RoundedRectangle(cornerRadius: 13))
    }

    private var capture: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 0) {
                ZStack {
                    Color.black.opacity(0.35)
                    if model.active && model.tab == "Cadastro" {
                        Color.black
                        enrollPointer
                    } else if model.active {
                        CameraPreview(session: model.camera.session)
                    } else {
                        VStack(spacing: 18) {
                            Image(systemName: "faceid").font(.system(size: 68, weight: .ultraLight)).foregroundStyle(accent.opacity(0.75))
                            Text("A câmera está desligada").font(.system(size: 15, weight: .medium))
                            Text("Ela só liga quando você inicia uma sessão.")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                    VStack {
                        HStack {
                            Label(model.active ? "CÂMERA ATIVA" : "MODO PRIVADO", systemImage: model.active ? "circle.fill" : "lock.fill")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(model.active ? accent : .secondary)
                            Spacer()
                            if model.active && model.tab == "Cadastro" {
                                HStack(spacing: 6) {
                                    ForEach(0..<3) { step in
                                        Circle().fill(step < model.sampleCount ? ringGreen : .white.opacity(0.22))
                                            .frame(width: 8, height: 8)
                                    }
                                }.accessibilityHidden(true)
                            }
                        }
                        Spacer()
                    }.padding(16)
                }.frame(height: 380).clipShape(UnevenRoundedRectangle(topLeadingRadius: 15, topTrailingRadius: 15))
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.status).font(.system(size: 12, weight: .medium)).lineLimit(2)
                    if let similarity = model.similarity {
                        Text("Similaridade: \(similarity, specifier: "%.3f") • informativa, não autentica")
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(accent)
                        if let presentation = model.presentation {
                            Text("Anti-fraude: \(presentationLabel(presentation.label)) • real \(presentation.realScore, specifier: "%.2f") • informativo")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(presentation.spoofSuspected ? Color.orange : Color.secondary)
                        }
                    } else {
                        Text(model.active ? "\(model.faceCount) rosto(s) • qualidade: \(Int(model.quality * 100))%" : "Nenhum quadro é enviado à internet.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(panel)
            }.clipShape(RoundedRectangle(cornerRadius: 15)).frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 19) {
                Text(model.tab == "Comparação" ? "Comparação experimental" : "Cadastre seu rosto")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                if model.tab == "Cadastro" {
                    step(1, title: "Confirme com Touch ID", text: "Só você autoriza o cadastro.")
                    step(2, title: "Complete o anel de giro", text: "Olhe de frente e depois mova a cabeça em círculo, devagar.")
                    step(3, title: "Guarde neste Mac", text: "Vetores faciais criptografados, sem fotos.")
                } else {
                    Text("O EdgeFace XS gera um vetor do rosto alinhado e mede a similaridade do cosseno com suas três amostras. O MiniFASNet estima se o quadro parece foto, tela ou máscara, com limiar ainda não calibrado. Não é prova de vida e, sem limiar de identidade validado, nada é autorizado.")
                        .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if model.active {
                    Text(model.tab == "Cadastro" ? "O anel só guia o movimento: não é prova de vida." : model.guidance)
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(accent).fixedSize(horizontal: false, vertical: true)
                    Button("Encerrar sessão") { model.stop() }.buttonStyle(.bordered).controlSize(.large)
                } else {
                    Toggle(isOn: $model.consent) {
                        Text("Autorizo o uso local da câmera e dos vetores faciais do meu rosto.")
                            .font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                    }.toggleStyle(.checkbox).disabled(model.busy)
                    Button {
                        Task { await model.start(enrolling: model.tab == "Cadastro") }
                    } label: {
                        HStack {
                            if model.busy { ProgressView().controlSize(.small) }
                            Text(model.tab == "Cadastro" ? (model.hasEnrollment ? "Refazer cadastro" : "Cadastrar meu rosto") : "Iniciar comparação")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }.padding(.vertical, 5)
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(!model.consent || model.busy || (model.tab == "Comparação" && !model.hasEnrollment))
                }
                Text("Requer Touch ID. Cadastro: até 90 segundos. Comparação: até 45 segundos. A câmera para ao sair do app.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(20).frame(width: 250, alignment: .leading)
                .background(panel, in: RoundedRectangle(cornerRadius: 15))
        }
    }

    private func presentationLabel(_ label: PresentationLabel) -> String {
        switch label {
        case .real: "parece real"
        case .fake2D: "possível foto ou tela"
        case .fake3D: "possível máscara"
        }
    }

    private func step(_ number: Int, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Text("\(number)").font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(accent).frame(width: 24, height: 24).background(accent.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(text).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 22) {
            Label("O que fica no seu Mac", systemImage: "internaldrive").font(.headline)
            Text("Três vetores faciais de 512 números, o identificador e o hash do modelo e a versão do alinhamento. O modelo fica em ~/Library/Caches/MacFaceGuard, fora do app e do Git. O arquivo é protegido com AES-256-GCM em ~/Library/Application Support/MacFaceGuard/private. A chave fica no Chaves, sem sincronização, com proteção pelo conjunto atual de biometrias.")
                .font(.system(size: 13)).foregroundStyle(.secondary).textSelection(.enabled)
            Text("O diretório privado fica fora do OneDrive, do Git e da pasta do aplicativo. Ele é marcado para exclusão de backup; ferramentas que ignoram essa marcação ainda podem copiá-lo. Nunca mova o cadastro ou a chave para o repositório.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Divider()
            Toggle("Abrir MacFaceGuard ao entrar no macOS", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                .toggleStyle(.switch)
            Text("A câmera permanece desligada na inicialização.").font(.caption).foregroundStyle(.secondary)
            if !model.loginMessage.isEmpty {
                Text(model.loginMessage).font(.caption).foregroundStyle(.orange)
                Button("Abrir Itens de Início") { SMAppService.openSystemSettingsLoginItems() }
            }
            Divider()
            HStack {
                Button("Ajustar permissão da câmera") {
                    model.stop()
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") { NSWorkspace.shared.open(url) }
                }
                Spacer()
                Button("Excluir cadastro", role: .destructive) { confirmDelete = true }
                    .disabled(!model.hasEnrollment || model.busy)
            }
        }.padding(24).background(panel, in: RoundedRectangle(cornerRadius: 15))
    }
}

/// Traços radiais do anel: cinza até a direção ser percorrida, verde depois. O traço 0 fica à direita, em sentido anti-horário.
struct RingTicks: View {
    let ring: RotationRing
    let diameter: CGFloat
    /// Acende todos os traços, como no fim do cadastro do iPhone.
    var allLit = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(0..<ring.segmentCount, id: \.self) { index in
                let lit = allLit || ring.covered[index]
                Capsule()
                    .fill(lit ? ringGreen : .white.opacity(0.25))
                    .frame(width: lit ? 20 : 13, height: 3)
                    .offset(x: diameter / 2 - (lit ? 10 : 6.5))
                    // A tela tem y para baixo; o anel conta ângulos com y para cima.
                    .rotationEffect(.radians(-ring.angle(of: index)))
            }
        }.frame(width: diameter, height: diameter)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: ring.covered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: allLit)
            .accessibilityHidden(true)
    }
}

final class PreviewSurface: NSView {
    let preview = AVCaptureVideoPreviewLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        preview.videoGravity = .resizeAspectFill
        layer?.addSublayer(preview)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) não é usado") }
    override func layout() { super.layout(); preview.frame = bounds }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> PreviewSurface {
        let view = PreviewSurface()
        view.preview.session = session
        Self.mirror(view.preview)
        return view
    }
    func updateNSView(_ view: PreviewSurface, context: Context) { Self.mirror(view.preview) }
    /// Prévia como espelho: a direita da pessoa aparece à direita, como o anel orienta.
    private static func mirror(_ layer: AVCaptureVideoPreviewLayer) {
        guard let connection = layer.connection, connection.isVideoMirroringSupported,
              !connection.isVideoMirrored || connection.automaticallyAdjustsVideoMirroring else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = true
    }
    static func dismantleNSView(_ view: PreviewSurface, coordinator: ()) { view.preview.session = nil }
}
