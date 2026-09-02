import FirebaseAnalytics
import FirebaseCore
import FirebaseCrashlytics
import Foundation

@MainActor
protocol TelemetryReporting: AnyObject {
    func updateConsent(crashReportsEnabled: Bool, usageAnalyticsEnabled: Bool)
    func track(_ event: TelemetryEvent)
    func recordRefreshFailure(
        providerKind: ProviderKind,
        category: TelemetryFailureCategory,
        attempts: Int
    )
}

enum TelemetryEvent: Equatable {
    case appLaunched(enabledProviderCount: Int)
    case providerAdded(kind: ProviderKind)
    case providerRemoved(kind: ProviderKind)
    case refreshFinished(
        providerKind: ProviderKind,
        outcome: TelemetryRefreshOutcome,
        failureCategory: TelemetryFailureCategory?,
        attempts: Int,
        durationBucket: TelemetryDurationBucket
    )
    case featureChanged(feature: TelemetryFeature, enabled: Bool)

    fileprivate var name: String {
        switch self {
        case .appLaunched:
            return "app_launched"
        case .providerAdded:
            return "provider_added"
        case .providerRemoved:
            return "provider_removed"
        case .refreshFinished:
            return "provider_refresh_finished"
        case .featureChanged:
            return "feature_changed"
        }
    }

    fileprivate var parameters: [String: Any] {
        switch self {
        case let .appLaunched(enabledProviderCount):
            return ["enabled_provider_count": enabledProviderCount]
        case let .providerAdded(kind), let .providerRemoved(kind):
            return ["provider_kind": kind.rawValue]
        case let .refreshFinished(providerKind, outcome, failureCategory, attempts, durationBucket):
            var values: [String: Any] = [
                "provider_kind": providerKind.rawValue,
                "outcome": outcome.rawValue,
                "attempt_count": attempts,
                "duration_bucket": durationBucket.rawValue
            ]
            if let failureCategory {
                values["failure_category"] = failureCategory.rawValue
            }
            return values
        case let .featureChanged(feature, enabled):
            return [
                "feature": feature.rawValue,
                "enabled": enabled ? 1 : 0
            ]
        }
    }
}

enum TelemetryRefreshOutcome: String, Equatable {
    case succeeded
    case failed
}

enum TelemetryFeature: String, Equatable {
    case crashReporting
    case usageAnalytics
    case floatingHUD
    case launchAtLogin
}

enum TelemetryFailureCategory: String, Equatable {
    case authentication
    case configuration
    case network
    case parsing
    case rateLimit
    case server
    case unknown

    init(error: Error) {
        guard let failure = error as? ProviderFailure else {
            self = .unknown
            return
        }

        switch failure {
        case .misconfigured:
            self = .configuration
        case .authentication:
            self = .authentication
        case .network:
            self = .network
        case let .httpStatus(code, _, _):
            if code == 401 || code == 403 {
                self = .authentication
            } else if code == 429 {
                self = .rateLimit
            } else if (500 ... 599).contains(code) {
                self = .server
            } else {
                self = .network
            }
        case .parsing:
            self = .parsing
        }
    }
}

enum TelemetryDurationBucket: String, Equatable {
    case underOneSecond
    case oneToFiveSeconds
    case fiveToFifteenSeconds
    case fifteenToThirtySeconds
    case overThirtySeconds

    init(seconds: TimeInterval) {
        switch seconds {
        case ..<1:
            self = .underOneSecond
        case ..<5:
            self = .oneToFiveSeconds
        case ..<15:
            self = .fiveToFifteenSeconds
        case ..<30:
            self = .fifteenToThirtySeconds
        default:
            self = .overThirtySeconds
        }
    }
}

@MainActor
final class TelemetryController: TelemetryReporting {
    static let shared = TelemetryController()

    private(set) var crashReportsEnabled = false
    private(set) var usageAnalyticsEnabled = false
    private var isFirebaseConfigured = false

    private init() {}

    func updateConsent(crashReportsEnabled: Bool, usageAnalyticsEnabled: Bool) {
        self.crashReportsEnabled = crashReportsEnabled
        self.usageAnalyticsEnabled = usageAnalyticsEnabled

        if crashReportsEnabled || usageAnalyticsEnabled {
            configureFirebaseIfNeeded()
        }

        guard isFirebaseConfigured else {
            return
        }

        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(crashReportsEnabled)
        Analytics.setAnalyticsCollectionEnabled(usageAnalyticsEnabled)
        if crashReportsEnabled == false {
            Crashlytics.crashlytics().deleteUnsentReports()
        }
    }

    func track(_ event: TelemetryEvent) {
        guard usageAnalyticsEnabled else {
            return
        }
        configureFirebaseIfNeeded()
        guard isFirebaseConfigured else {
            return
        }
        Analytics.logEvent(event.name, parameters: event.parameters)
    }

    func recordRefreshFailure(
        providerKind: ProviderKind,
        category: TelemetryFailureCategory,
        attempts: Int
    ) {
        guard crashReportsEnabled, category.isActionableNonFatal else {
            return
        }
        configureFirebaseIfNeeded()
        guard isFirebaseConfigured else {
            return
        }

        let sanitizedError = NSError(
            domain: "com.rekindle.usagebeacon.provider-refresh",
            code: category.errorCode,
            userInfo: [NSLocalizedDescriptionKey: "Provider refresh failed"]
        )
        Crashlytics.crashlytics().record(
            error: sanitizedError,
            userInfo: [
                "provider_kind": providerKind.rawValue,
                "failure_category": category.rawValue,
                "attempt_count": attempts
            ]
        )
    }

    private func configureFirebaseIfNeeded() {
        guard isFirebaseConfigured == false else {
            return
        }
        guard Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil else {
            return
        }

        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        isFirebaseConfigured = FirebaseApp.app() != nil
    }
}

private extension TelemetryFailureCategory {
    var isActionableNonFatal: Bool {
        self == .parsing || self == .unknown
    }

    var errorCode: Int {
        switch self {
        case .authentication:
            return 1
        case .configuration:
            return 2
        case .network:
            return 3
        case .parsing:
            return 4
        case .rateLimit:
            return 5
        case .server:
            return 6
        case .unknown:
            return 7
        }
    }
}
