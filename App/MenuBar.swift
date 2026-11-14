import SwiftUI

/// Icône de la barre des menus : caméra pleine quand l'image est envoyée.
struct MenuBarIcon: View {
    @ObservedObject var pipeline: Pipeline

    var body: some View {
        Image(systemName: pipeline.isRunning ? "video.fill" : "video.slash")
            .accessibilityLabel(pipeline.isRunning ? "MaCam active" : "MaCam en pause")
    }
}

/// Menu de la barre des menus : les commandes utiles pendant une visio.
struct MenuBarContent: View {
    @EnvironmentObject private var ext: ExtensionManager
    @EnvironmentObject private var pipeline: Pipeline
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var overlays: OverlayStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if pipeline.sinkConnected {
            Text(pipeline.isRunning ? "Caméra en service" : "Caméra en pause")
        } else {
            Text("Caméra virtuelle non trouvée")
            Text("Extension : \(ext.status)")
        }

        Divider()

        Button(pipeline.isRunning ? "Arrêter la caméra" : "Démarrer la caméra", action: pipeline.toggle)

        Picker("Source vidéo", selection: $pipeline.selectedCameraID) {
            ForEach(pipeline.cameras, id: \.uniqueID) { device in
                Text(device.localizedName).tag(Optional(device.uniqueID))
            }
        }

        Divider()

        // Bandeaux : coche = affiché ; raccourcis globaux ⌃⌥1…9, ⌃⌥0 pour tout masquer
        ForEach(Array(overlays.items.enumerated()), id: \.element.id) { index, item in
            let toggle = Toggle(item.label, isOn: Binding(get: { overlays.isVisible(item) },
                                                          set: { _ in overlays.toggle(item) }))
            if index < 9 {
                toggle.keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.control, .option])
            } else {
                toggle
            }
        }
        Button("Tout masquer") { overlays.hideAll() }
            .keyboardShortcut("0", modifiers: [.control, .option])
            .disabled(overlays.visible.isEmpty)

        Divider()

        Button("Gérer les bandeaux…") { app.showWindow(MaCamApp.overlaysWindowID, using: openWindow) }
        Button("Ouvrir MaCam…") { app.showWindow(MaCamApp.mainWindowID, using: openWindow) }
            .keyboardShortcut(",")

        Menu("Réglages") {
            Toggle("Démarrer la caméra au lancement", isOn: $pipeline.autoStart)
            Toggle("Lancer à l'ouverture de session", isOn: $app.launchAtLogin)
            Toggle("Icône dans le Dock", isOn: $app.showDockIcon)
        }

        Divider()

        Button("Quitter MaCam") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
