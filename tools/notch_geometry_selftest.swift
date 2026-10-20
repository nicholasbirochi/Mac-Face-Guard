//
//  notch_geometry_selftest.swift
//  Glance Verde (tools)
//
//  Teste offline, sem tela de bloqueio, da geometria do painel em telas sem entalhe (entalhe simulado ou pílula). O
//  projeto não tem alvo de testes, então compila junto dos arquivos reais, com substitutos mínimos para os ajustes e
//  as etapas do cadastro:
//
//      swiftc -o /tmp/notch_geometry_selftest glance/NotchOverlay/NotchGeometry.swift \
//          glance/NotchOverlay/NotchPanelStyle.swift glance/Onboarding/OnboardingMetrics.swift \
//          tools/notch_geometry_selftest.swift && /tmp/notch_geometry_selftest
//
//  Também confere, lendo o código-fonte, que a janela, o cadastro e os Ajustes usam a mesma opção.
//

import AppKit

// Substitutos: só o que `NotchGeometry` e `OnboardingMetrics` leem.
@MainActor
final class GlanceSettings {
    static let shared = GlanceSettings()
    var preferredDisplayID: String?
}

enum OnboardingStep: String, CaseIterable {
    case intro, permissions, securityNotice, preSetup, selectCamera, enroll, name, password, complete
}

nonisolated(unsafe) var failures = 0
func check(_ condition: Bool, _ name: String) {
    print(condition ? "ok    \(name)" : "FALHA \(name)")
    if !condition { failures += 1 }
}

func source(_ path: String) -> String {
    (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
}

// Dentro de `@main`, não solto no arquivo: com mais de um arquivo, o `swiftc` só aceita código solto em `main.swift`.
@main
enum NotchGeometrySelfTest {
    static func main() {
        // 1. Entalhe simulado: colado no topo, com a silhueta de entalhe.
        let simulated = NotchGeometry.withoutNotch(simulatesNotch: true)
        check(simulated.style == .notch, "entalhe simulado usa o estilo de entalhe, colado no topo")
        check(!simulated.isPhysicalNotch && simulated.isSimulatedNotch, "entalhe simulado não se passa por entalhe físico")
        check(simulated.closedSize == CGSize(width: 72, height: 31), "entalhe simulado fechado mede 72 × 31 pt")

        // 2. O corpo visível bate com o espaço entre as abas do Alcove (70 pt).
        let alcoveBody = simulated.closedSize.width + NotchGeometry.alcoveNotchWidthAdjust
        check(alcoveBody == 70, "corpo do Alcove entre as abas: 72 − 2 = 70 pt")

        // 3. Aberto na facial: nunca mais estreito que o piso do entalhe.
        let open = simulated.notchScanOpenSize
        check(open.width == max(NotchGeometry.notchOpenSize.width, 72 - 2 + 35 * 2), "painel aberto respeita o piso de largura")
        check(open.width >= 140, "painel aberto cobre a ilha do Alcove (140 pt)")

        // 4. Desligado: volta a pílula solta de antes.
        let pill = NotchGeometry.withoutNotch(simulatesNotch: false)
        check(pill.style == .pill, "opção desligada volta para a pílula")
        check(!pill.isSimulatedNotch && pill.closedSize == NotchGeometry.pillClosedSize, "pílula mantém o tamanho original")

        // 5. A janela comporta o painel aberto no estilo de entalhe.
        let window = NotchGeometry.windowSize(for: simulated.style)
        check(window.width >= open.width && window.height >= open.height, "janela comporta o painel aberto")

        // 6. Janela, cadastro e Ajustes leem a mesma opção.
        let windowController = source("glance/NotchOverlay/NotchWindowController.swift")
        check(windowController.contains("GlanceSettings.shared.simulatesNotch"), "janela lê a opção do entalhe simulado")
        let onboarding = source("glance/Onboarding/OnboardingController.swift")
        check(onboarding.contains("GlanceSettings.shared.simulatesNotch"), "cadastro lê a mesma opção")
        let settings = source("glance/Settings/GlanceSettings.swift")
        check(settings.contains("?? true"), "entalhe simulado vem ligado por padrão")
        let general = source("glance/Settings/Pages/GeneralSettingsPage.swift")
        check(general.contains("$settings.simulatesNotch"), "Ajustes → General mostra a opção")

        print(failures == 0 ? "\nTudo certo." : "\n\(failures) falha(s).")
        exit(failures == 0 ? 0 : 1)
    }
}
