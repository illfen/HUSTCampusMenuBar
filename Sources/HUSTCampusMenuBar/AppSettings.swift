import Foundation

@MainActor
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    var username: String {
        get { defaults.string(forKey: "username") ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "username") }
    }

    var manualPortalURL: String {
        get { defaults.string(forKey: "manualPortalURL") ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "manualPortalURL") }
    }

    var intervalSeconds: Int {
        get {
            let value = defaults.integer(forKey: "intervalSeconds")
            return value > 0 ? value : 30
        }
        set { defaults.set(newValue, forKey: "intervalSeconds") }
    }

    var autoReconnect: Bool {
        get {
            if defaults.object(forKey: "autoReconnect") == nil {
                return true
            }
            return defaults.bool(forKey: "autoReconnect")
        }
        set { defaults.set(newValue, forKey: "autoReconnect") }
    }
}
