import AppKit
import SwiftUI

@MainActor
private enum SettingsWindowPresenter {
    static func present(retriesRemaining: Int = 20) {
        NSApp.activate(ignoringOtherApps: true)

        guard let appMenu = NSApp.mainMenu?.items.first?.submenu,
              let settingsItemIndex = appMenu.items.firstIndex(where: { item in
                  item.keyEquivalent == ","
                      && item.keyEquivalentModifierMask.contains(.command)
              }) else {
            // SwiftUI installs the Settings command asynchronously during launch.
            guard retriesRemaining > 0 else {
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                present(retriesRemaining: retriesRemaining - 1)
            }
            return
        }

        appMenu.performActionForItem(at: settingsItemIndex)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { window in
                window.isVisible && window.canBecomeKey && !(window is NSPanel)
            })?.makeKeyAndOrderFront(nil)
        }
    }
}

@MainActor
private final class UsageBeaconApplicationDelegate: NSObject, NSApplicationDelegate {
    static var shouldPresentSettingsOnLaunch = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard DebugCommandRunner.command(from: CommandLine.arguments) == nil,
              Self.shouldPresentSettingsOnLaunch else {
            return
        }

        // Wait until SwiftUI has registered the Settings scene before asking AppKit to show it.
        DispatchQueue.main.async {
            SettingsWindowPresenter.present()
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        guard DebugCommandRunner.command(from: CommandLine.arguments) == nil else {
            return true
        }

        SettingsWindowPresenter.present()
        return true
    }
}

@main
struct UsageBeaconApp: App {
    @NSApplicationDelegateAdaptor(UsageBeaconApplicationDelegate.self) private var applicationDelegate
    private let debugCommand = DebugCommandRunner.command(from: CommandLine.arguments)
    @StateObject private var model: AppModel
    @StateObject private var updater: UpdaterController

    init() {
        if debugCommand == nil {
            let model = AppModel()
            UsageBeaconApplicationDelegate.shouldPresentSettingsOnLaunch = model.configuration.providers.isEmpty
            _model = StateObject(wrappedValue: model)
            _updater = StateObject(wrappedValue: UpdaterController())
        } else {
            _model = StateObject(wrappedValue: AppModel(autoStart: false))
            _updater = StateObject(wrappedValue: UpdaterController(startUpdater: false))
            let command = debugCommand
            DispatchQueue.main.async {
                guard let command else {
                    return
                }
                Task { @MainActor in
                    await DebugCommandRunner.run(command)
                }
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            if let debugCommand {
                DebugCommandView(command: debugCommand)
            } else {
                MenuBarRootView(model: model)
            }
        } label: {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .accessibilityLabel("UsageBeacon")
        }
        .menuBarExtraStyle(.window)

        Settings {
            if let debugCommand {
                DebugCommandView(command: debugCommand)
            } else {
                SettingsView(model: model, updater: updater)
            }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }
        }
    }
}

private struct DebugCommandView: View {
    let command: DebugCommand

    var body: some View {
        Text("Running diagnostic…")
            .frame(width: 300, height: 80)
    }
}
