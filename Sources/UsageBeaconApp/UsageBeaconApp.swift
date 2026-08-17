import SwiftUI

@main
struct UsageBeaconApp: App {
    private let debugCommand = DebugCommandRunner.command(from: CommandLine.arguments)
    private let shouldPresentSettingsOnLaunch: Bool
    @StateObject private var model: AppModel

    init() {
        if debugCommand == nil {
            _model = StateObject(wrappedValue: AppModel())
            shouldPresentSettingsOnLaunch = true
        } else {
            _model = StateObject(wrappedValue: AppModel(autoStart: false))
            shouldPresentSettingsOnLaunch = false
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
            UsageBeaconMenuBarLabel(
                shouldPresentSettingsOnLaunch: shouldPresentSettingsOnLaunch
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            if let debugCommand {
                DebugCommandView(command: debugCommand)
            } else {
                SettingsView(model: model)
            }
        }
    }
}

private struct UsageBeaconMenuBarLabel: View {
    let shouldPresentSettingsOnLaunch: Bool

    @Environment(\.openSettings) private var openSettings
    @State private var didPresentSettings = false

    var body: some View {
        Label("UsageBeacon", systemImage: "chart.line.uptrend.xyaxis")
            .task {
                guard shouldPresentSettingsOnLaunch, !didPresentSettings else {
                    return
                }

                didPresentSettings = true
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
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
