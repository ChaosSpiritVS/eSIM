import Foundation
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
#endif
#if canImport(FirebaseCrashlytics)
import FirebaseCrashlytics
#endif

final class Telemetry {
    static let shared = Telemetry()
    private var isConfigured = false
    private var analyticsEnabled = false
    private var crashEnabled = false

    func setup() {
        guard !isConfigured else { return }
        guard AppConfig.enableTelemetry else { return }
        #if canImport(FirebaseCore)
        #if DEBUG
        if let devPath = Bundle.main.path(forResource: "GoogleService-Info-Dev", ofType: "plist"), let options = FirebaseOptions(contentsOfFile: devPath) {
            FirebaseApp.configure(options: options)
            isConfigured = true
        }
        #endif
        if !isConfigured, let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"), let options = FirebaseOptions(contentsOfFile: path) {
            FirebaseApp.configure(options: options)
            isConfigured = true
        }
        if isConfigured {
            analyticsEnabled = AppConfig.enableAnalytics
            crashEnabled = AppConfig.enableCrashlytics
            #if canImport(FirebaseAnalytics)
            Analytics.setAnalyticsCollectionEnabled(analyticsEnabled)
            #endif
        }
        #endif
    }

    func identify(_ userId: String?) {
        guard isConfigured, AppConfig.enableTelemetry else { return }
        #if canImport(FirebaseAnalytics)
        if analyticsEnabled { Analytics.setUserID(userId) }
        #endif
        #if canImport(FirebaseCrashlytics)
        if crashEnabled { Crashlytics.crashlytics().setUserID(userId ?? "") }
        #endif
    }

    func setUserProperty(_ value: String?, name: String) {
        guard isConfigured, AppConfig.enableTelemetry else { return }
        #if canImport(FirebaseAnalytics)
        if analyticsEnabled { Analytics.setUserProperty(value, forName: name) }
        #endif
    }

    func logEvent(_ name: String, parameters: [String: Any]?) {
        guard isConfigured, AppConfig.enableTelemetry else { return }
        #if canImport(FirebaseAnalytics)
        let enabled = analyticsEnabled
        if enabled {
            DispatchQueue.global(qos: .utility).async {
                Analytics.logEvent(name, parameters: parameters)
            }
        }
        #endif
    }

    func logEventDeferred(_ name: String, parameters: [String: Any]?) {
        DispatchQueue.main.async { [weak self] in
            self?.logEvent(name, parameters: parameters)
        }
    }

    func record(error: Error) {
        guard isConfigured, AppConfig.enableTelemetry else { return }
        #if canImport(FirebaseCrashlytics)
        let enabled = crashEnabled
        if enabled {
            DispatchQueue.global(qos: .utility).async {
                Crashlytics.crashlytics().record(error: error)
            }
        }
        #endif
    }

    func log(_ message: String) {
        guard isConfigured, AppConfig.enableTelemetry else { return }
        #if canImport(FirebaseCrashlytics)
        let enabled = crashEnabled
        if enabled {
            DispatchQueue.global(qos: .utility).async {
                Crashlytics.crashlytics().log(message)
            }
        }
        #endif
    }

    func setAnalyticsEnabled(_ enabled: Bool) {
        analyticsEnabled = enabled
        #if canImport(FirebaseAnalytics)
        if isConfigured { Analytics.setAnalyticsCollectionEnabled(enabled) }
        #endif
    }

    func setCrashEnabled(_ enabled: Bool) {
        crashEnabled = enabled
    }
}