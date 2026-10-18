// Adaptado de Glance (https://github.com/jonnyoo/glance), NotchOverlayController.swift.
// MIT License, Copyright (c) 2026 Jonathan Zhou. Aviso completo em THIRD_PARTY_NOTICES.md.
//
//  The only file other code should touch to show the notch overlay.
//
//  Interaction is hover-driven, not click-driven: a non-activating panel
//  otherwise needs a first click just to gain focus before a second click
//  registers — hover avoids that "have to double-click" bug entirely.
//

import AppKit
import SwiftUI
import Observation

/// Estilo da animação de desbloqueio, como no Glance (o MacFaceGuard usa `.original`).
enum UnlockAnimationStyle: Equatable {
    case original
    case minimal
    case none
}

@Observable
@MainActor
final class NotchOverlayController {
    /// One overlay window for the whole app — sharing one instance guarantees
    /// the triggers never run concurrently, rather than leaving that incidental.
    static let shared = NotchOverlayController()

    enum Phase: Equatable {
        /// While armed, the window stays on-screen here (hover-reactive); otherwise ordered out.
        case closed
        /// Expanded, showing the idle still image — actively looking for a face.
        case scanning
        /// Success animation playing, then auto-collapses.
        case success
        /// Failure animation playing/held; collapses after a hold unless
        /// the user hovers first to retry.
        case failure
        case collapsing
    }

    /// Kept as an enum so the call sites match Glance's; only scan media exists here.
    enum Content: Equatable {
        case scan(ScanMedia)
    }

    private(set) var phase: Phase = .closed
    private(set) var content: Content = .scan(.idle)
    /// Read-only convenience for the scan-mode view/callers.
    var media: ScanMedia {
        if case .scan(let media) = content { return media }
        return .idle
    }
    private(set) var geometry: NotchGeometry = .forMainScreen()
    /// Read by the view for the hover-driven size/shadow bump — irrelevant
    /// to the phase state machine itself.
    private(set) var isArmed = false

    /// Pill style only: whether the pill is parked on screen at rest vs. off-screen.
    /// Deliberately separate from `isArmed` — it lags it by a frame on the way in
    /// (making the pill slide into place) and leads it on the way out.
    private(set) var isPillDocked = false

    /// O MacFaceGuard usa sempre o estilo original do Glance (animação completa).
    private(set) var activeUnlockStyle: UnlockAnimationStyle = .original

    /// What a hover-driven activation should do — set by `arm()` (persists
    /// across scan cycles) or by one-shot `present(onRetry:)` (single use).
    private var onActivate: (() -> Void)?

    private let windowController = NotchWindowController()
    private var resolveTask: Task<Void, Never>?
    private var scanTimeoutTask: Task<Void, Never>?


    /// Matches the success asset duration (~1.22s) plus a short beat to read the final frame.
    private let successHoldDuration: Duration = .milliseconds(1_700)
    /// Non-private so UnlockCoordinator's auto-retry can wait this out too.
    let failureHoldDuration: Duration = .seconds(5)
    /// Igual à janela de busca do UnlockGate (15 s), para os dois relógios expirarem juntos.
    private let scanTimeoutDuration: Duration = .seconds(15)
    /// Long enough for the closing spring to fully settle before the window is
    /// hidden/left closed — collapsing state too early made the window visibly pop away.
    let collapseAnimationDuration: Duration = .milliseconds(700)

    private init() {
        windowController.contentView = NSHostingView(rootView: NotchOverlayView(controller: self))
        // A display connecting/disconnecting mid-flow can flip notch vs. pill style.
        windowController.onScreenParametersChanged = { [weak self] in
            guard let self else { return }
            self.geometry = self.windowController.currentGeometry
        }
    }

    // MARK: - Armed mode (UnlockCoordinator)

    /// Arms the overlay for the lock-screen flow: shows the window and keeps it
    /// up until `disarm()`. `onActivate` restarts scanning on hover.
    func arm(onActivate: @escaping () -> Void) {
        isArmed = true
        self.onActivate = onActivate
        geometry = windowController.currentGeometry
        phase = .closed
        content = .scan(.idle)
        isPillDocked = false
        windowController.show()
        updateInteractivity()

        guard geometry.style == .pill else {
            // The notch silhouette has nowhere to travel from — it's on top of hardware already there.
            isPillDocked = true
            return
        }
        // Render one real frame with the pill still off-screen, so flipping the
        // flag next runloop animates it down instead of appearing already docked.
        windowController.displaySynchronously()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isArmed else { return }
            self.isPillDocked = true
        }
    }

    /// Truly hides the window. Only call once the lock-screen attempt is
    /// completely done — while armed, resolving an attempt goes back to `.closed`, not this.
    ///
    /// If a success/collapse sequence is already resolving, let it finish
    /// naturally: setting `isArmed = false` is enough, since the already-scheduled
    /// `collapse()` checks `isArmed` once its hold expires and hides for real then.
    func disarm() {
        isArmed = false
        onActivate = nil
        // Undocked before the guard: if a success collapse is already in flight, this
        // turns it into a full slide-off-screen exit rather than a shrink to a resting pill.
        isPillDocked = false
        guard phase != .success, phase != .collapsing else { return }
        resolveTask?.cancel(); resolveTask = nil
        scanTimeoutTask?.cancel(); scanTimeoutTask = nil
        // Re-measured here, not just trusted from `arm()` — `arm()` typically
        // fires right around wake/unlock, when AppKit may not have finished
        // laying out the menu bar yet, so `auxiliaryTopLeftArea`/`RightArea`
        // can read back momentarily wrong. Refreshing right before settling
        // to `.closed` (the shape most directly compared against the real
        // notch) self-corrects instead of baking in a bad first reading.
        geometry = windowController.currentGeometry
        phase = .closed
        content = .scan(.idle)
        windowController.setInteractive(false)

        guard geometry.style == .pill, windowController.isVisible else {
            windowController.hide()
            return
        }
        // The pill is visible at rest, so hiding the window right now would blink it
        // away instead of playing the slide-up (visibility check above skips hidden windows).
        Task { [weak self] in
            try? await Task.sleep(for: self?.collapseAnimationDuration ?? .milliseconds(700))
            guard let self, !self.isArmed, self.phase == .closed else { return }
            self.windowController.hide()
        }
    }

    /// Shows the idle still; auto-collapses silently (no failure animation) after
    /// `scanTimeoutDuration` if nothing resolves it.
    func beginScanning() {
        resolveTask?.cancel(); resolveTask = nil
        scanTimeoutTask?.cancel()
        geometry = windowController.currentGeometry
        activeUnlockStyle = .original
        content = .scan(.idle)
        phase = .scanning
        updateInteractivity()

        scanTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: self?.scanTimeoutDuration ?? .seconds(5))
            guard let self, !Task.isCancelled, self.phase == .scanning else { return }
            await self.collapse()
        }
    }

    // MARK: - Resolving (shared by both modes)

    /// Resolves the current attempt. Success plays its animation and then
    /// collapses on its own; failure plays its animation and holds until
    /// either the hold expires or the user hovers to retry.
    func finish(success: Bool) {
        resolveTask?.cancel()
        scanTimeoutTask?.cancel()

        // Unlock Animation → None just skips the success/failure video; phase and
        // retry behavior are unaffected. Reads the cycle's captured style, not live settings.
        let shouldAnimate = activeUnlockStyle != .none
        content = shouldAnimate ? .scan(success ? .success : .failure) : .scan(.idle)
        phase = success ? .success : .failure
        updateInteractivity()

        let hold = shouldAnimate ? (success ? successHoldDuration : failureHoldDuration) : Duration.milliseconds(400)
        resolveTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: hold)
            guard !Task.isCancelled else { return }
            await self.collapse()
        }
    }

    /// Hover-driven activation: wakes from a closed/armed state, or retries from a held
    /// failure frame. No-op during scanning/success/collapsing.
    func activate() {
        // Gated here rather than in `updateInteractivity()` so the cosmetic hover bump
        // stays unaffected — only the retry itself is removed.
        switch phase {
        case .closed, .failure:
            guard let onActivate else {
                if phase == .failure { Task { await collapse() } }
                return
            }
            resolveTask?.cancel(); resolveTask = nil
            if !isArmed {
                activeUnlockStyle = .original
                content = .scan(.idle)
                phase = .scanning
                updateInteractivity()
            }
            onActivate()
        case .scanning, .success, .collapsing:
            break
        }
    }

    /// Collapses gracefully: animates shut, then either leaves the window
    /// at rest (closed, still on-screen, hover-reactive) if armed, or
    /// orders it out entirely if not.
    func collapse() async {
        guard phase != .closed, phase != .collapsing else { return }
        // Capture the display's real closed notch dimensions before changing phase.
        // The phase change starts the SwiftUI closing animation; measuring afterward
        // would animate toward stale geometry, then expose the real (smaller) notch
        // when the window is hidden.
        geometry = windowController.currentGeometry
        phase = .collapsing
        updateInteractivity()
        try? await Task.sleep(for: collapseAnimationDuration)
        guard phase == .collapsing else { return }

        content = .scan(.idle)
        if isArmed {
            phase = .closed
            updateInteractivity()
        } else {
            phase = .closed
            windowController.hide()
        }
    }

    /// Tears the overlay down without any resolve animation. Deliberately a no-op while
    /// success/collapsing is in flight — interrupting that made the window vanish abruptly.
    func dismissImmediately() {
        guard phase != .success, phase != .collapsing else { return }
        resolveTask?.cancel(); resolveTask = nil
        scanTimeoutTask?.cancel(); scanTimeoutTask = nil
        phase = .closed
        content = .scan(.idle)
        isPillDocked = false
        windowController.setInteractive(false)
        windowController.hide()
    }

    private func updateInteractivity() {
        // Click-through otherwise, so the overlay never intercepts anything it doesn't
        // need to.
        windowController.setInteractive(isArmed || phase == .failure)
    }

    /// Called by `NotchOverlayView` whenever the visible panel's own frame
    /// changes (step change, expand/collapse, hover bump, …) — see
    /// `NotchWindowController.updateMousePassthrough()`.
    func updateInteractiveContentRect(_ rect: CGRect?) {
        windowController.setInteractiveContentRect(rect)
    }
}
