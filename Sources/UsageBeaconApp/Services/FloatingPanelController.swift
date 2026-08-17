import AppKit
import SwiftUI

@MainActor
final class FloatingPanelController {
    private var panel: NSPanel?
    private var hasPositionedPanel = false
    private var collapsedSize = NSSize(width: 220, height: 44)

    func update(with snapshots: [ProviderSnapshotState], visible: Bool) {
        if !visible || snapshots.isEmpty {
            panel?.orderOut(nil)
            return
        }

        let content = FloatingHUDView(snapshots: snapshots) { [weak self] isExpanded in
            self?.resizePanel(isExpanded: isExpanded)
        }
        let hostingView = NSHostingView(rootView: content)
        let panel = panel ?? makePanel()
        panel.contentView = hostingView

        collapsedSize = NSSize(width: 220, height: snapshots.count > 1 ? 76 : 44)
        panel.setContentSize(collapsedSize)
        if !hasPositionedPanel {
            position(panel)
            hasPositionedPanel = true
        }

        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 44),
            styleMask: [.nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
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

    private func resizePanel(isExpanded: Bool) {
        guard let panel else { return }
        let size = isExpanded ? NSSize(width: 250, height: 208) : collapsedSize
        let currentTop = panel.frame.maxY
        let currentRight = panel.frame.maxX
        panel.setContentSize(size)
        panel.setFrameOrigin(
            CGPoint(
                x: currentRight - panel.frame.width,
                y: currentTop - panel.frame.height
            )
        )
    }
}
