import AppKit
import ServiceManagement
import SwiftUI

/// Réglages au niveau de l'application : icône du Dock, lancement à l'ouverture de session.
final class AppState: ObservableObject {
    @Published var showDockIcon: Bool {
        didSet {
            UserDefaults.standard.set(showDockIcon, forKey: Prefs.showDockIcon)
            applyActivationPolicy()
        }
    }

    /// Reflète l'état réel du service d'ouverture de session (SMAppService).
    @Published var launchAtLogin: Bool {
        didSet { if launchAtLogin != oldValue { updateLoginItem() } }
    }
    @Published private(set) var loginItemMessage: String?

    init() {
        _showDockIcon = Published(initialValue: UserDefaults.standard.bool(forKey: Prefs.showDockIcon, default: true))
        _launchAtLogin = Published(initialValue: SMAppService.mainApp.status == .enabled)
    }

    /// Avec l'icône masquée, MaCam ne vit plus que dans la barre des menus.
    func applyActivationPolicy() {
        NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
        NSApp.activate()
    }

    func showWindow(_ id: String, using openWindow: OpenWindowAction) {
        openWindow(id: id)
        NSApp.activate()
    }

    private func updateLoginItem() {
        let service = SMAppService.mainApp
        do {
            if launchAtLogin, service.status != .enabled { try service.register() }
            if !launchAtLogin, service.status == .enabled { try service.unregister() }
            loginItemMessage = service.status == .requiresApproval
                ? "Ouverture de session : à valider dans Réglages Système (éléments de connexion)"
                : nil
        } catch {
            loginItemMessage = "Ouverture de session : \(error.localizedDescription)"
        }
    }
}
