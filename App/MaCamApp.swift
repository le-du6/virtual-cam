import SwiftUI

@main
struct MaCamApp: App {
    static let mainWindowID = "main"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Fenêtre de réglages complète
        Window("MaCam", id: Self.mainWindowID) {
            ContentView()
                .environmentObject(delegate.ext)
                .environmentObject(delegate.pipeline)
                .environmentObject(delegate.appState)
        }
        .windowResizability(.contentSize)
        // En mode « barre des menus seule », pas de fenêtre au lancement
        .defaultLaunchBehavior(delegate.appState.showDockIcon ? .presented : .suppressed)

        // Accès rapide depuis la barre des menus
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(delegate.ext)
                .environmentObject(delegate.pipeline)
                .environmentObject(delegate.appState)
        } label: {
            MenuBarIcon(pipeline: delegate.pipeline)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Possède les objets de l'app : ils vivent indépendamment de la fenêtre.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let ext = ExtensionManager()
    let pipeline = Pipeline()
    let appState = AppState()

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(appState.showDockIcon ? .regular : .accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let pipeline = self.pipeline
        ext.onActivated = { [weak pipeline] in pipeline?.reconnect() }
        ext.activate()          // installe ou met à jour l'extension à chaque lancement
        pipeline.bootstrap()    // démarre la caméra si « Démarrer au lancement » est coché
    }

    /// Fermer la fenêtre ne quitte pas MaCam : la caméra continue d'alimenter la visio.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
