import SwiftUI
import AVFoundation

struct ContentView: View {
    @EnvironmentObject private var ext: ExtensionManager
    @EnvironmentObject private var pipeline: Pipeline
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var overlays: OverlayStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section("Extension caméra") {
                LabeledContent("État", value: ext.status)
                HStack {
                    Button("Installer / mettre à jour", action: ext.activate)
                    Button("Désinstaller", role: .destructive, action: ext.deactivate)
                }
            }

            Section("Source vidéo") {
                Picker("Caméra", selection: $pipeline.selectedCameraID) {
                    ForEach(pipeline.cameras, id: \.uniqueID) { device in
                        Text(device.localizedName).tag(Optional(device.uniqueID))
                    }
                }
                HStack {
                    Button(pipeline.isRunning ? "Arrêter" : "Démarrer", action: pipeline.toggle)
                        .keyboardShortcut(.defaultAction)
                    Spacer()
                    if pipeline.sinkConnected {
                        Label("Reliée à la caméra virtuelle", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Caméra virtuelle non trouvée", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                if let message = pipeline.message {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Effets vidéo macOS…", action: pipeline.showVideoEffects)
                    Spacer()
                    if pipeline.portraitActive {
                        Label("Portrait actif", systemImage: "person.crop.rectangle")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                Text("Portrait, Studio Light… : à activer pour MaCam (effet appliqué avant les bandeaux) et à laisser désactivés dans Teams pour la caméra MaCam, sinon les bandeaux seront floutés.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Bandeaux") {
                ForEach(Array(overlays.items.enumerated()), id: \.element.id) { index, item in
                    Toggle(isOn: Binding(get: { overlays.isVisible(item) }, set: { _ in overlays.toggle(item) })) {
                        HStack {
                            Text(item.label)
                            Text(item.style.label).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if index < 9 {
                                Text("⌃⌥\(index + 1)").font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                HStack {
                    Button("Gérer les bandeaux…") { app.showWindow(MaCamApp.overlaysWindowID, using: openWindow) }
                    Spacer()
                    Button(overlays.rotationRunning ? "Arrêter la rotation" : "Lancer la rotation") {
                        overlays.toggleRotation()
                    }
                    .disabled(!overlays.rotationRunning && overlays.rotationItems.isEmpty)
                    .help("⌃⌥R — bandeaux cochés « Inclure dans la rotation »")
                    Button("Tout masquer") { overlays.hideAll() }
                        .disabled(overlays.visible.isEmpty && !overlays.rotationRunning)
                }
            }

            Section {
                Toggle("Démarrer la caméra au lancement", isOn: $pipeline.autoStart)
                Toggle("Lancer MaCam à l'ouverture de session", isOn: $app.launchAtLogin)
                Toggle("Afficher l'icône dans le Dock", isOn: $app.showDockIcon)
                if let message = app.loginItemMessage {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
            } header: {
                Text("Réglages")
            } footer: {
                Text("Les modifications sont enregistrées automatiquement. MaCam reste accessible depuis la barre des menus.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Aperçu (image envoyée à la caméra virtuelle)") {
                Toggle("Afficher l'aperçu", isOn: $pipeline.previewEnabled)
                if pipeline.previewEnabled {
                    PreviewView(previewLayer: pipeline.previewLayer)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }
}

/// Affiche le calque d'aperçu alimenté par le compositeur.
struct PreviewView: NSViewRepresentable {
    let previewLayer: CALayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.layer = previewLayer       // vue « layer-hosting »
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
