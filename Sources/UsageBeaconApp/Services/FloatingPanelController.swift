import AppKit
import SwiftUI

@MainActor
final class FloatingHUDState: ObservableObject {
    @Published var isExpanded = false
    @Published var selectedProviderID: UUID?
}

@MainActor
final class FloatingPanelController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<FloatingHUDView>?
    private let hudState = FloatingHUDState()
    private var hasPositionedPanel = false
    private var collapsedSize = NSSize(width: 220, height: 44)

    func update(with snapshots: [ProviderSnapshotState], visible: Bool) {
        if !visible || snapshots.isEmpty {
            panel?.orderOut(nil)
            return
        }

        if let selectedProviderID = hudState.selectedProviderID,
           snapshots.contains(where: { $0.id == selectedProviderID }) == false {
            hudState.selectedProviderID = nil
        }

        let content = FloatingHUDView(snapshots: snapshots, state: hudState) { [weak self] isExpanded in
            self?.resizePanel(isExpanded: isExpanded)
        }
        let panel = panel ?? makePanel()
        if let hostingView {
            hostingView.rootView = content
        } else {
            let hostingView = NSHostingView(rootView: content)
            self.hostingView = hostingView
            panel.contentView = hostingView
        }

        collapsedSize = NSSize(width: 220, height: snapshots.count > 1 ? 76 : 44)
        resizePanel(isExpanded: hudState.isExpanded)
        if !hasPositionedPanel {
            position(panel)
            hasPositionedPanel = true
        } else {
            moveOnScreenIfNeeded(panel)
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
        panel.isReleasedWhenClosed = false
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

    private func moveOnScreenIfNeeded(_ panel: NSPanel) {
        let isOnVisibleScreen = NSScreen.screens.contains { screen in
            panel.frame.intersection(screen.visibleFrame).width >= 44
                && panel.frame.intersection(screen.visibleFrame).height >= 24
        }
        guard isOnVisibleScreen == false else {
            return
        }

        position(panel)
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
