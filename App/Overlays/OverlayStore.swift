import Foundation
import QuartzCore

/// Liste des bandeaux (enregistrée automatiquement) et état d'affichage.
final class OverlayStore: ObservableObject {
    @Published var items: [OverlayItem] {
        didSet {
            save()
            refreshVisible(previous: oldValue)
        }
    }
    @Published private(set) var visible: Set<UUID> = []

    let engine = OverlayEngine()
    private let defaults: UserDefaults
    private var hideTimers: [UUID: DispatchWorkItem] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Prefs.overlays),
           let saved = try? JSONDecoder().decode([OverlayItem].self, from: data), !saved.isEmpty {
            _items = Published(initialValue: saved)
        } else {
            _items = Published(initialValue: OverlayItem.defaults)
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

    func show(_ item: OverlayItem) {
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
        scheduleAutoHide(item, after: delay + OverlayEngine.enterDuration)
    }

    func hide(_ id: UUID) {
        hideTimers.removeValue(forKey: id)?.cancel()
        engine.hide(id: id)
        visible.remove(id)
    }

    func hideAll() {
        for id in Array(visible) { hide(id) }
    }

    private func scheduleAutoHide(_ item: OverlayItem, after offset: CFTimeInterval) {
        hideTimers.removeValue(forKey: item.id)?.cancel()
        guard item.autoHide > 0 else { return }
        let id = item.id
        let work = DispatchWorkItem { [weak self] in self?.hide(id) }
        hideTimers[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + offset + item.autoHide, execute: work)
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

    func resetToDefaults() {
        hideAll()
        items = OverlayItem.defaults
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
