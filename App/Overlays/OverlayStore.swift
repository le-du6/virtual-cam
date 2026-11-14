import Foundation
import QuartzCore

/// Liste des bandeaux (enregistrée automatiquement), état d'affichage et rotation.
final class OverlayStore: ObservableObject {
    @Published var items: [OverlayItem] {
        didSet {
            save()
            refreshVisible(previous: oldValue)
        }
    }
    @Published private(set) var visible: Set<UUID> = []

    @Published var rotation: RotationSettings {
        didSet { if let data = try? JSONEncoder().encode(rotation) { defaults.set(data, forKey: Prefs.rotation) } }
    }
    @Published private(set) var rotationRunning = false

    let engine = OverlayEngine()
    private let defaults: UserDefaults
    private var hideTimers: [UUID: DispatchWorkItem] = [:]
    private var rotationTimer: DispatchWorkItem?
    private var rotationIndex = 0
    private var rotationCurrent: UUID?
    private var logoObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        var loaded = OverlayItem.defaults
        if let data = defaults.data(forKey: Prefs.overlays),
           let saved = try? JSONDecoder().decode([OverlayItem].self, from: data), !saved.isEmpty {
            loaded = saved
        }
        // Mise à niveau unique des bandeaux existants : logo Stelau et rotation de départ
        let migrate = !defaults.bool(forKey: Prefs.logosMigrated)
        if migrate {
            for i in loaded.indices {
                if loaded[i].style != .carte, loaded[i].logo.isEmpty, loaded[i].subtitle.contains("Stelau") {
                    loaded[i].logo = OverlayItem.stelauLogo
                }
            }
            if !loaded.contains(where: \.inRotation) {
                if let first = loaded.firstIndex(where: { $0.style != .carte && $0.subtitle.contains("Stelau") }) {
                    loaded[first].inRotation = true
                }
                for i in loaded.indices where loaded[i].style == .carte
                    && (loaded[i].url.contains("crypto.stelau.com") || loaded[i].url.contains("/formations/")) {
                    loaded[i].inRotation = true
                }
            }
        }
        _items = Published(initialValue: loaded)

        if let data = defaults.data(forKey: Prefs.rotation),
           let saved = try? JSONDecoder().decode(RotationSettings.self, from: data) {
            _rotation = Published(initialValue: saved)
        } else {
            _rotation = Published(initialValue: RotationSettings())
        }

        if migrate {
            save()
            defaults.set(true, forKey: Prefs.logosMigrated)
        }

        // Logo téléchargé : redessiner les bandeaux affichés et les aperçus
        logoObserver = NotificationCenter.default.addObserver(forName: .logosDidChange, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            for item in self.items where self.visible.contains(item.id) {
                self.engine.update(id: item.id, layers: OverlayRenderer.render(item), position: item.position,
                                   animation: item.animation)
            }
            self.objectWillChange.send()
        }
    }

    // MARK: Affichage

    func isVisible(_ item: OverlayItem) -> Bool { visible.contains(item.id) }

    func toggle(_ item: OverlayItem) {
        isVisible(item) ? hide(item.id) : show(item)
    }

    /// Raccourcis ⌃⌥1…9 : index dans la liste.
    func toggle(index: Int) {
        guard items.indices.contains(index) else { return }
        toggle(items[index])
    }

    /// `autoHide: false` : c'est l'appelant (la rotation) qui décide quand masquer.
    func show(_ item: OverlayItem, autoHide: Bool = true) {
        // Un seul bandeau par zone : l'occupant sort, le nouveau entre ensuite.
        var delay: CFTimeInterval = 0
        for other in items where other.id != item.id && visible.contains(other.id)
                                 && other.position.isTop == item.position.isTop {
            hide(other.id)
            delay = OverlayEngine.leaveDuration * 0.8
        }
        engine.show(id: item.id, layers: OverlayRenderer.render(item), position: item.position,
                    animation: item.animation, delay: delay)
        visible.insert(item.id)
        hideTimers.removeValue(forKey: item.id)?.cancel()
        if autoHide { scheduleAutoHide(item, after: delay + OverlayEngine.enterDuration) }
    }

    func hide(_ id: UUID) {
        hideTimers.removeValue(forKey: id)?.cancel()
        engine.hide(id: id)
        visible.remove(id)
    }

    /// ⌃⌥0 : masque tout et arrête la rotation.
    func hideAll() {
        stopRotation()
        for id in Array(visible) { hide(id) }
    }

    private func scheduleAutoHide(_ item: OverlayItem, after offset: CFTimeInterval) {
        guard item.autoHide > 0 else { return }
        let id = item.id
        let work = DispatchWorkItem { [weak self] in self?.hide(id) }
        hideTimers[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + offset + item.autoHide, execute: work)
    }

    // MARK: Rotation

    /// Bandeaux de la rotation, dans l'ordre de la liste.
    var rotationItems: [OverlayItem] { items.filter(\.inRotation) }

    func toggleRotation() {
        rotationRunning ? stopRotation() : startRotation()
    }

    func startRotation() {
        guard !rotationItems.isEmpty else { return }
        stopRotation()
        rotationRunning = true
        rotationIndex = 0
        rotationStep()
    }

    func stopRotation() {
        rotationTimer?.cancel()
        rotationTimer = nil
        if rotationRunning, let current = rotationCurrent { hide(current) }
        rotationCurrent = nil
        rotationRunning = false
    }

    /// Affiche le bandeau suivant pendant sa durée (masquage automatique, sinon durée par défaut),
    /// le masque, marque la pause, puis recommence.
    private func rotationStep() {
        guard rotationRunning else { return }
        let list = rotationItems
        guard !list.isEmpty else { stopRotation(); return }
        if rotationIndex >= list.count {
            guard rotation.loop else { stopRotation(); return }
            rotationIndex = 0
        }
        let item = list[rotationIndex]
        rotationIndex += 1

        show(item, autoHide: false)
        rotationCurrent = item.id
        let shown = OverlayEngine.enterDuration + (item.autoHide > 0 ? item.autoHide : rotation.duration)

        schedule(after: shown) { [weak self] in
            guard let self, self.rotationRunning else { return }
            self.hide(item.id)
            self.rotationCurrent = nil
            self.schedule(after: OverlayEngine.leaveDuration + self.rotation.pause) { [weak self] in
                self?.rotationStep()
            }
        }
    }

    private func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) {
        let work = DispatchWorkItem(block: block)
        rotationTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: Édition

    @discardableResult
    func add(_ style: OverlayStyle) -> UUID {
        let item = OverlayItem.blank(style)
        items.append(item)
        return item.id
    }

    @discardableResult
    func duplicate(_ id: UUID) -> UUID? {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = items[i]
        copy.id = UUID()
        copy.label += " (copie)"
        items.insert(copy, at: i + 1)
        return copy.id
    }

    func delete(_ id: UUID) {
        hide(id)
        items.removeAll { $0.id == id }
    }

    func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: Persistance et mise à jour à chaud

    private func save() {
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: Prefs.overlays) }
    }

    /// Un bandeau modifié pendant qu'il est affiché est redessiné aussitôt.
    private func refreshVisible(previous: [OverlayItem]) {
        for item in items where visible.contains(item.id) {
            guard previous.first(where: { $0.id == item.id }) != item else { continue }
            engine.update(id: item.id, layers: OverlayRenderer.render(item), position: item.position,
                          animation: item.animation)
        }
        for id in Array(visible) where !items.contains(where: { $0.id == id }) { hide(id) }
    }
}
