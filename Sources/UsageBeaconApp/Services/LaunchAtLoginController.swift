import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
}

@MainActor
protocol LaunchAtLoginControlling {
    var status: LaunchAtLoginStatus { get }

    func setEnabled(_ enabled: Bool) throws
    func openSystemSettings()
}

@MainActor
final class LaunchAtLoginController: LaunchAtLoginControlling {
    private let service = SMAppService.mainApp

    var status: LaunchAtLoginStatus {
        switch service.status {
        case .notRegistered:
            return .disabled
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard service.status == .notRegistered || service.status == .notFound else {
                return
            }
            try service.register()
        } else {
            guard service.status != .notRegistered else {
                return
            }
            try service.unregister()
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
