import SwiftUI

@main
struct UsageBeaconApp: App {
    private let debugCommand = DebugCommandRunner.command(from: CommandLine.arguments)
    @StateObject private var model: AppModel

    init() {
        if debugCommand == nil {
            _model = StateObject(wrappedValue: AppModel())
        } else {
            _model = StateObject(wrappedValue: AppModel(autoStart: false))
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
        MenuBarExtra("UsageBeacon", systemImage: "chart.line.uptrend.xyaxis") {
            if let debugCommand {
                DebugCommandView(command: debugCommand)
            } else {
                MenuBarRootView(model: model)
            }
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

private struct DebugCommandView: View {
    let command: DebugCommand

    var body: some View {
        Text("Running diagnostic…")
            .frame(width: 300, height: 80)
    }
}
