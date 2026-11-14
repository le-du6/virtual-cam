import Foundation

/// Clés des réglages enregistrés automatiquement (UserDefaults, domaine fr.stelau.macam).
enum Prefs {
    static let preferredCamera = "preferredCameraID"
    static let overlays = "overlays"
    static let rotation = "rotation"
    static let logosMigrated = "logosMigrated"
    static let autoStart = "autoStart"
    static let showDockIcon = "showDockIcon"
}

extension UserDefaults {
    func bool(forKey key: String, default value: Bool) -> Bool {
        object(forKey: key) as? Bool ?? value
    }
}
