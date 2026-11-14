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
                    Button("Tout masquer") { overlays.hideAll() }
                        .disabled(overlays.visible.isEmpty)
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

            Section("Aperçu (sortie réelle de la caméra virtuelle)") {
                Toggle("Afficher l'aperçu", isOn: $pipeline.previewEnabled)
                if pipeline.previewEnabled {
                    PreviewView(session: pipeline.previewSession)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }
}

/// Affiche une AVCaptureSession (ici : la caméra virtuelle elle-même).
struct PreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = NSColor.black.cgColor
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
