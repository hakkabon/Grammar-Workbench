#if os(macOS)
import SwiftUI

/// Shared dimensions for the native application's primary workspace. These
/// values keep the source, task, and inspector regions as sibling split panes;
/// no region is allowed to become an overlay that obscures another one.
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

    static let inspectorMinimumWidth: CGFloat = 260
    static let inspectorIdealWidth: CGFloat = 300
    static let inspectorMaximumWidth: CGFloat = 480

    static var requiredPaneWidth: CGFloat {
        sourceMinimumWidth + workspaceMinimumWidth + inspectorMinimumWidth
    }

    static var expandedPaneWidth: CGFloat {
        navigationMinimumWidth + requiredPaneWidth
    }
}
#endif
