import AppKit
import SwiftUI

@MainActor
final class FloatingPanelController {
    private var panel: NSPanel?
    private var hasPositionedPanel = false

    func update(with snapshots: [ProviderSnapshotState], visible: Bool) {
        if !visible || snapshots.isEmpty {
            panel?.orderOut(nil)
            return
        }

        let content = FloatingHUDView(snapshots: snapshots)
        let hostingView = NSHostingView(rootView: content)
        let panel = panel ?? makePanel()
        panel.contentView = hostingView

        let height = max(110, CGFloat(max(1, snapshots.count)) * 92 + 20)
        panel.setContentSize(NSSize(width: 320, height: height))
        if !hasPositionedPanel {
            position(panel)
            hasPositionedPanel = true
        }

        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
            styleMask: [.nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else {
            return
        }

        let visibleFrame = screen.visibleFrame
        let origin = CGPoint(
            x: visibleFrame.maxX - panel.frame.width - 20,
            y: visibleFrame.maxY - panel.frame.height - 20
        )
        panel.setFrameOrigin(origin)
    }
}
