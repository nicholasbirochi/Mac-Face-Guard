import SwiftUI
import AppKit

/// Estado visual da ilha: recolhida no entalhe, aberta durante o cadastro ou concluída.
@MainActor
final class IslandState: ObservableObject {
    @Published var expanded = false
    @Published var success = false
    var closedSize = CGSize(width: 190, height: 32)
    var topInset: CGFloat = 32
}

/// Painel sem borda no topo da tela, no lugar do entalhe da câmera, no estilo da Dynamic Island.
/// Não ativa o app nem recebe foco; some ao encerrar, expirar ou concluir a sessão.
@MainActor
final class NotchIsland {
    static let openSize = CGSize(width: 380, height: 380)
    private var panel: IslandPanel?
    private let state = IslandState()
    private var closing: Task<Void, Never>?

    func show(model: AppModel) {
        closing?.cancel()
        closing = nil
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let notch: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notch = screen.frame.width - left.width - right.width
        } else { notch = 0 }
        // Sem entalhe, a ilha nasce como uma pílula sob a barra de menus.
        let top = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : NSStatusBar.system.thickness
        state.topInset = top
        state.closedSize = CGSize(width: notch > 0 ? notch : 190, height: top)
        state.success = false
        let size = CGSize(width: Self.openSize.width + 40, height: top + Self.openSize.height)
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)
        let panel = self.panel ?? IslandPanel(contentRect: frame)
        panel.setFrame(frame, display: false)
        panel.contentView = NSHostingView(rootView: IslandView(model: model, state: state))
        panel.orderFrontRegardless()
        self.panel = panel
        // O primeiro quadro desenha a ilha fechada; a abertura anima em seguida.
        DispatchQueue.main.async { [state] in state.expanded = true }
    }

    /// Recolhe a ilha. Com sucesso, mostra o anel completo por um instante antes de fechar.
    func close(success: Bool) {
        guard panel != nil, closing == nil else { return }
        if success { state.success = true }
        closing = Task { [weak self] in
            if success { try? await Task.sleep(for: .seconds(1.6)) }
            guard !Task.isCancelled, let self else { return }
            self.state.expanded = false
            try? await Task.sleep(for: .seconds(0.45))
            guard !Task.isCancelled else { return }
            self.panel?.orderOut(nil)
            self.panel?.contentView = nil
            self.closing = nil
        }
    }
}

private final class IslandPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    /// A ilha precisa cobrir a barra de menus e o entalhe; o AppKit normalmente empurraria a janela para baixo.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Contorno do entalhe: abas côncavas no alto e cantos largos embaixo.
private struct EnrollmentNotchShape: Shape {
    var bottomRadius: CGFloat
    var topRadius: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, topRadius) }
        set { bottomRadius = newValue.first; topRadius = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        let t = min(topRadius, rect.width / 4)
        let b = min(bottomRadius, (rect.width - 2 * t) / 2, rect.height - t)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t), control: CGPoint(x: rect.minX + t, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        path.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY), control: CGPoint(x: rect.minX + t, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b), control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - t, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

private struct IslandView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: IslandState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let open = state.expanded
        let width = open ? NotchIsland.openSize.width : state.closedSize.width
        let height = open ? state.topInset + NotchIsland.openSize.height - 24 : state.closedSize.height
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                EnrollmentNotchShape(bottomRadius: open ? 44 : 10, topRadius: open ? 14 : 6)
                    .fill(.black)
                if open { content.transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .top))) }
            }
            .frame(width: width + (open ? 28 : 12), height: height)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.45, dampingFraction: 0.78), value: open)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: state.success)
        .preferredColorScheme(.dark)
    }

    private var content: some View {
        VStack(spacing: 14) {
            HStack {
                Label(state.success ? "Cadastrado" : "Cadastro facial", systemImage: "faceid")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                if !state.success {
                    HStack(spacing: 5) {
                        ForEach(0..<3) { step in
                            Circle().fill(step < model.sampleCount ? ringGreen : .white.opacity(0.22)).frame(width: 6, height: 6)
                        }
                    }.accessibilityHidden(true)
                    Button { model.stop(message: "Cadastro cancelado") } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                            .frame(width: 22, height: 22).background(.white.opacity(0.14), in: Circle())
                    }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.8))
                        .accessibilityLabel("Cancelar cadastro")
                }
            }.padding(.horizontal, 30)
            ZStack {
                RingTicks(ring: model.ring, diameter: 236, allLit: state.success)
                if state.success {
                    Circle().fill(ringGreen.opacity(0.14)).frame(width: 180, height: 180)
                    Image(systemName: "checkmark").font(.system(size: 64, weight: .semibold)).foregroundStyle(ringGreen)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    CameraPreview(session: model.camera.session)
                        .frame(width: 180, height: 180).clipShape(Circle())
                    Circle().stroke(model.sampleCount == 0 && model.poseReady ? ringGreen : .white.opacity(0.12), lineWidth: 2)
                        .frame(width: 180, height: 180)
                }
            }.frame(width: 236, height: 236)
            Text(state.success ? "Rosto cadastrado" : model.captureHint)
                .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                .multilineTextAlignment(.center).lineLimit(2).padding(.horizontal, 30)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.captureHint)
        }
        .padding(.top, state.topInset + 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(state.success ? "Rosto cadastrado" :
            "Cadastro facial. Anel de giro em \(Int(model.ring.coverage * 100)) por cento, \(model.sampleCount) de 3 amostras. \(model.captureHint)")
    }
}
