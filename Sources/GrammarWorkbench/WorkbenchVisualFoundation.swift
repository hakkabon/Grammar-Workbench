#if os(macOS)
import SwiftUI

/// Shared dimensions for the native application's primary workspace and its
/// contextual artifact-detail popover.
enum WorkbenchVisualFoundation {
    static let windowMinimumWidth: CGFloat = 1_120
    static let windowMinimumHeight: CGFloat = 720

    static let navigationMinimumWidth: CGFloat = 180
    static let navigationIdealWidth: CGFloat = 210
    static let navigationMaximumWidth: CGFloat = 280

    static let sourceMinimumWidth: CGFloat = 300
    static let sourceIdealWidth: CGFloat = 380
    static let sourceMaximumWidth: CGFloat = 620

    static let workspaceMinimumWidth: CGFloat = 460

    static let inspectorMinimumWidth: CGFloat = 320
    static let inspectorIdealWidth: CGFloat = 420
    static let inspectorMaximumWidth: CGFloat = 560

    static var requiredPaneWidth: CGFloat {
        sourceMinimumWidth + workspaceMinimumWidth
    }

    static var expandedPaneWidth: CGFloat {
        navigationMinimumWidth + requiredPaneWidth
    }
}
#endif
