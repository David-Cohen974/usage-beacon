import Combine
import Foundation
import Sparkle

@MainActor
final class UpdaterController: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let betaUpdatesDefaultsKey = "UsageBeaconReceiveBetaUpdates"

    private var standardController: SPUStandardUpdaterController!
    private var observations: [NSKeyValueObservation] = []

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = true
    @Published private(set) var automaticallyDownloadsUpdates = false
    @Published private(set) var receivesBetaUpdates: Bool

    init(startUpdater: Bool = true) {
        receivesBetaUpdates = UserDefaults.standard.bool(
            forKey: Self.betaUpdatesDefaultsKey
        )
        super.init()

        standardController = SPUStandardUpdaterController(
            startingUpdater: startUpdater,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        beginObservingUpdater()
    }

    func checkForUpdates() {
        standardController.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        standardController.updater.automaticallyChecksForUpdates = enabled
        synchronizePublishedState()
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        standardController.updater.automaticallyDownloadsUpdates = enabled
        synchronizePublishedState()
    }

    func setReceivesBetaUpdates(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.betaUpdatesDefaultsKey)
        receivesBetaUpdates = enabled
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        receivesBetaUpdates ? ["beta"] : []
    }

    private func synchronizePublishedState() {
        canCheckForUpdates = standardController.updater.canCheckForUpdates
        automaticallyChecksForUpdates = standardController.updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = standardController.updater.automaticallyDownloadsUpdates
    }

    private func beginObservingUpdater() {
        let updater = standardController.updater

        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in
                    self?.synchronizePublishedState()
                }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in
                    self?.synchronizePublishedState()
                }
            },
            updater.observe(\.automaticallyDownloadsUpdates, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in
                    self?.synchronizePublishedState()
                }
            }
        ]
    }
}
