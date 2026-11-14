import SwiftUI

@main
struct MaCamApp: App {
    static let mainWindowID = "main"
    static let overlaysWindowID = "overlays"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Fenêtre principale : caméra, bandeaux, réglages
        Window("MaCam", id: Self.mainWindowID) {
            ContentView()
                .environmentObject(delegate.ext)
                .environmentObject(delegate.pipeline)
                .environmentObject(delegate.appState)
                .environmentObject(delegate.overlays)
        }
        .windowResizability(.contentSize)
        // En mode « barre des menus seule », pas de fenêtre au lancement
        .defaultLaunchBehavior(delegate.appState.showDockIcon ? .presented : .suppressed)

        // Éditeur de bandeaux
        Window("Bandeaux", id: Self.overlaysWindowID) {
            OverlaysView()
                .environmentObject(delegate.overlays)
        }
        .defaultSize(width: 960, height: 680)
        .defaultLaunchBehavior(.suppressed)

        // Accès rapide depuis la barre des menus
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(delegate.ext)
                .environmentObject(delegate.pipeline)
                .environmentObject(delegate.appState)
                .environmentObject(delegate.overlays)
        } label: {
            MenuBarIcon(pipeline: delegate.pipeline)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Possède les objets de l'app : ils vivent indépendamment des fenêtres.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let ext = ExtensionManager()
    let appState = AppState()
    let overlays: OverlayStore
    let pipeline: Pipeline
    private var hotKeys: HotKeys?

    override init() {
        let overlays = OverlayStore()
        self.overlays = overlays
        self.pipeline = Pipeline(overlays: overlays.engine)
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(appState.showDockIcon ? .regular : .accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let pipeline = self.pipeline
        ext.onActivated = { [weak pipeline] in pipeline?.reconnect() }
        ext.activate()          // installe ou met à jour l'extension à chaque lancement
        pipeline.bootstrap()    // démarre la caméra si « Démarrer au lancement » est coché

        // ⌃⌥1…9 : afficher / masquer le bandeau n ; ⌃⌥0 : tout masquer
        hotKeys = HotKeys { [weak overlays] number in
            guard let overlays else { return }
            number == 0 ? overlays.hideAll() : overlays.toggle(index: number - 1)
        }
    }

    /// Fermer la fenêtre ne quitte pas MaCam : la caméra continue d'alimenter la visio.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
