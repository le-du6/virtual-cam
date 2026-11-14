import SwiftUI

/// Fenêtre « Bandeaux » : liste à gauche, éditeur et aperçu à droite.
struct OverlaysView: View {
    @EnvironmentObject private var store: OverlayStore
    @State private var selection: UUID?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                    OverlayRow(item: item, index: index, isVisible: store.isVisible(item))
                        .tag(item.id)
                }
                .onMove { store.move(from: $0, to: $1) }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                Divider()
                RotationPanel()
                Divider()
                HStack(spacing: 4) {
                    Menu {
                        ForEach(OverlayStyle.allCases) { style in
                            Button(style.label) { selection = store.add(style) }
                        }
                    } label: { Image(systemName: "plus") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Nouveau bandeau")

                    Button { if let id = selection { selection = store.duplicate(id) } } label: {
                        Image(systemName: "plus.square.on.square")
                    }
                    .help("Dupliquer")
                    .disabled(selection == nil)

                    Button {
                        if let id = selection { store.delete(id); selection = store.items.first?.id }
                    } label: { Image(systemName: "minus") }
                    .help("Supprimer")
                    .disabled(selection == nil)

                    Spacer()
                    Button("Tout masquer") { store.hideAll() }
                        .disabled(store.visible.isEmpty && !store.rotationRunning)
                }
                .buttonStyle(.borderless)
                .padding(8)
                }
                .background(.bar)
            }
            .navigationSplitViewColumnWidth(min: 230, ideal: 260)
        } detail: {
            if let id = selection, let binding = binding(for: id) {
                OverlayEditor(item: binding)
            } else {
                Text("Sélectionnez un bandeau").foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 860, minHeight: 620)
        .onAppear { if selection == nil { selection = store.items.first?.id } }
    }

    private func binding(for id: UUID) -> Binding<OverlayItem>? {
        guard let current = store.items.first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { store.items.first(where: { $0.id == id }) ?? current },
            set: { newValue in
                if let i = store.items.firstIndex(where: { $0.id == id }) { store.items[i] = newValue }
            })
    }
}

/// Réglages et commande de la rotation automatique.
private struct RotationPanel: View {
    @EnvironmentObject private var store: OverlayStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Rotation", systemImage: "arrow.triangle.2.circlepath").font(.headline)
                Spacer()
                Button(store.rotationRunning ? "Arrêter" : "Lancer") { store.toggleRotation() }
                    .disabled(!store.rotationRunning && store.rotationItems.isEmpty)
            }
            Text("\(store.rotationItems.count) bandeau(x) inclus · ⌃⌥R")
                .font(.caption).foregroundStyle(.secondary)
            Stepper("Durée par défaut : \(Int(store.rotation.duration)) s",
                    value: $store.rotation.duration, in: 3...120, step: 1)
                .help("Pour les bandeaux sans masquage automatique ; sinon leur propre durée")
            Stepper("Pause entre bandeaux : \(Int(store.rotation.pause)) s",
                    value: $store.rotation.pause, in: 0...60, step: 1)
            Toggle("En boucle", isOn: $store.rotation.loop)
        }
        .controlSize(.small)
        .padding(10)
    }
}

private struct OverlayRow: View {
    let item: OverlayItem
    let index: Int
    let isVisible: Bool

    var body: some View {
        HStack {
            Image(systemName: isVisible ? "eye.fill" : "eye.slash")
                .foregroundStyle(isVisible ? Color.accentColor : Color.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.label)
                Text(item.style.label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if item.inRotation {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Dans la rotation")
            }
            if index < 9 {
                Text("⌃⌥\(index + 1)").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
    }
}

private struct OverlayEditor: View {
    @Binding var item: OverlayItem
    @EnvironmentObject private var store: OverlayStore

    var body: some View {
        Form {
            Section {
                if let preview = OverlayRenderer.preview(item) {
                    Image(decorative: preview, scale: 1)
                        .resizable()
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                HStack {
                    Button(store.isVisible(item) ? "Masquer" : "Afficher dans la caméra") { store.toggle(item) }
                        .keyboardShortcut(.return, modifiers: .command)
                    Spacer()
                    Text(item.autoHide > 0 ? "Masquage automatique après \(Int(item.autoHide)) s" : "Reste affiché")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            Section("Présentation") {
                TextField("Nom dans les menus", text: $item.label)
                Picker("Style", selection: $item.style) {
                    ForEach(OverlayStyle.allCases) { Text($0.label).tag($0) }
                }
                Picker("Position", selection: $item.position) {
                    ForEach(OverlayPosition.allCases) { Text($0.label).tag($0) }
                }
                Picker("Animation", selection: Binding(get: { item.animation }, set: { item.animation = $0 })) {
                    ForEach(OverlayAnimation.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Inclure dans la rotation", isOn: $item.inRotation)
                LabeledContent("Masquage automatique") {
                    HStack {
                        Slider(value: $item.autoHide, in: 0...60, step: 1)
                        Text(item.autoHide > 0 ? "\(Int(item.autoHide)) s" : "jamais")
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            }

            Section("Logo") {
                TextField("Logo", text: $item.logo, prompt: Text("fichier du dossier Logos ou URL https"))
                Toggle("Logo en blanc (fonds sombres)", isOn: $item.logoWhite)
                HStack {
                    Text("Un logo à fond transparent (PNG ou SVG) rend le mieux, surtout en blanc.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Recharger") { Logos.reload() }
                    Button("Dossier Logos") { Logos.revealFolder() }
                }
            }

            Section(item.style == .carte ? "Contenu de la carte" : "Contenu") {
                TextField(item.style == .carte ? "Titre" : "Nom", text: $item.title)
                TextField(item.style == .carte ? "Description" : "Fonction", text: $item.subtitle)
                if item.style == .carte {
                    TextField("URL (QR code)", text: $item.url)
                    TextField("Complément après l'URL", text: $item.urlNote, prompt: Text("ex. § 4"))
                    TextField("Icône", text: $item.icon, prompt: Text("symbole SF ou fichier du dossier Icônes"))
                    HStack {
                        Text("Symbole SF (ex. flask.fill) ou SVG Font Awesome Duotone déposé dans le dossier Icônes.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Dossier Icônes") { Icons.revealFolder() }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
