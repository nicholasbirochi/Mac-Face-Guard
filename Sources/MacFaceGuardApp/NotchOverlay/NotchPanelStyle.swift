// Adaptado de Glance (https://github.com/jonnyoo/glance), NotchPanelStyle.swift.
// MIT License, Copyright (c) 2026 Jonathan Zhou. Aviso completo em THIRD_PARTY_NOTICES.md.
//
//  Which silhouette the overlay panel wears on a given screen — passed down
//  through the environment so onboarding's step views can adapt without a parameter.
//

import SwiftUI

enum NotchPanelStyle {
    /// Inverted top corners, flush with the screen's top edge.
    case notch
    /// Fully-rounded pill / floating rounded rectangle, detached from the edge.
    case pill
}

extension EnvironmentValues {
    @Entry var notchPanelStyle: NotchPanelStyle = .notch
}
