import SwiftUI
import MacFaceGuardCore

/// Aba Desbloqueio: senha guardada, Acessibilidade, armação e limiar.
struct UnlockPanel: View {
    @ObservedObject var unlock: UnlockCoordinator
    let hasEnrollment: Bool
    @State private var password = ""
    @State private var confirmDelete = false

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: unlock.scanning ? "faceid" : unlock.armed ? "lock.open.fill" : "lock.fill")
                        .font(.system(size: 22)).foregroundStyle(unlock.armed ? accent : .secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(unlock.armed ? "Desbloqueio facial armado" : "Desbloqueio facial desarmado")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                        Text(unlock.status).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                Divider()
                requirement("Cadastro facial", ok: hasEnrollment, detail: hasEnrollment ? "Pronto" : "Faça o cadastro na aba Cadastro.")
                HStack {
                    requirement("Acessibilidade", ok: unlock.accessibility,
                                detail: unlock.accessibility ? "Pode digitar a senha" : "Necessária para digitar a senha.")
                    Spacer()
                    if !unlock.accessibility {
                        Button("Permitir…") { unlock.requestAccessibility() }
                        Button("Verificar") { unlock.refresh() }
                    }
                }
                requirement("Senha do Mac", ok: unlock.hasPassword,
                            detail: unlock.hasPassword ? "Cifrada no Chaves, aberta só com Touch ID" : "Guarde a senha abaixo.")
                HStack {
                    SecureField(unlock.hasPassword ? "Trocar a senha guardada" : "Senha de login do Mac", text: $password)
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                        .onSubmit(save)
                    Button("Guardar senha", action: save).disabled(password.isEmpty || unlock.busy)
                }
                Text("A senha é conferida no diretório local antes de ser guardada. Ela nunca sai deste Mac.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Limiar de semelhança").font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text("\(unlock.threshold, specifier: "%.2f")").font(.system(size: 12, design: .monospaced))
                    }
                    Slider(value: $unlock.threshold, in: UnlockGate.minimumThreshold...UnlockGate.maximumThreshold, step: 0.01)
                        .disabled(unlock.scanning)
                    Text(unlock.lastSimilarity.map { String(format: "Última semelhança medida: %.3f", $0) }
                         ?? "Use a aba Comparação para ver quanto o seu rosto costuma marcar e ajuste o limiar abaixo disso.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    if unlock.armed {
                        Button("Desarmar") { unlock.disarm() }.buttonStyle(.bordered).controlSize(.large)
                    } else {
                        Button {
                            Task { await unlock.arm() }
                        } label: {
                            HStack {
                                if unlock.busy { ProgressView().controlSize(.small) }
                                Text("Armar com Touch ID")
                            }
                        }.buttonStyle(.borderedProminent).controlSize(.large)
                            .disabled(unlock.busy || !hasEnrollment || !unlock.hasPassword || !unlock.accessibility)
                    }
                    Spacer()
                    Button("Apagar senha", role: .destructive) { confirmDelete = true }
                        .disabled(!unlock.hasPassword || unlock.busy)
                }
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                .background(panel, in: RoundedRectangle(cornerRadius: 15))

            VStack(alignment: .leading, spacing: 16) {
                Text("Como funciona").font(.system(size: 17, weight: .semibold, design: .rounded))
                step("Bloqueie o Mac", "Bloquear não liga a câmera.")
                step("Desperte a tela", "Com a tela bloqueada, a câmera liga por até 15 segundos.")
                step("Olhe para a câmera", "Rosto reconhecido em 2 quadros e anti-fraude real em 3 seguidos.")
                step("Entrou", "A senha é digitada no campo de login e a câmera desliga.")
                Text("Rosto errado, mais de um rosto, suspeita de fraude ou tempo esgotado: a câmera desliga e você digita a senha. São até 3 tentativas por bloqueio.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(20).frame(width: 270, alignment: .leading)
                .background(panel, in: RoundedRectangle(cornerRadius: 15))
        }
        .onAppear { unlock.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in unlock.refresh() }
        .alert("Desbloqueio facial", isPresented: Binding(get: { unlock.error != nil }, set: { if !$0 { unlock.error = nil } })) {
            Button("Entendi", role: .cancel) { unlock.error = nil }
        } message: { Text(unlock.error ?? "") }
        .confirmationDialog("Apagar a senha guardada e desarmar?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Apagar", role: .destructive) { unlock.deletePassword() }
        }
    }

    private func save() {
        guard !password.isEmpty else { return }
        let typed = password
        password = ""
        Task { await unlock.storePassword(typed) }
    }

    private func requirement(_ title: String, ok: Bool, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed").foregroundStyle(ok ? accent : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private func step(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 12, weight: .medium))
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
