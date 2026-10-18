// Adaptado de Glance (https://github.com/jonnyoo/glance), LockMonitor.swift.
// MIT License, Copyright (c) 2026 Jonathan Zhou. Aviso completo em THIRD_PARTY_NOTICES.md.
import AppKit
import CoreGraphics

/// Observa bloqueio, desbloqueio, descanso de tela e despertar. Notificações só disparam a verificação;
/// o estado real do bloqueio é sempre relido do WindowServer.
@MainActor
final class LockMonitor {
    enum Event { case locked, unlocked, wake, willSleep }

    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    private(set) var isSleeping = false
    var handler: ((Event) -> Void)?

    nonisolated static var isScreenLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    func start() {
        guard tokens.isEmpty else { return }
        let distributed = DistributedNotificationCenter.default()
        let pairs: [(String, Event)] = [("com.apple.screenIsLocked", .locked), ("com.apple.screenIsUnlocked", .unlocked),
                                        ("com.apple.screensaver.didstop", .wake)]
        for (name, event) in pairs {
            let token = distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handler?(event) }
            }
            tokens.append((distributed, token))
        }
        let workspace = NSWorkspace.shared.notificationCenter
        tokens.append((workspace, workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isSleeping = true
                self?.handler?(.willSleep)
            }
        }))
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
            tokens.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isSleeping = false
                    self?.handler?(.wake)
                }
            }))
        }
    }

    func stop() {
        for (center, token) in tokens { center.removeObserver(token) }
        tokens.removeAll()
        isSleeping = false
    }
}
