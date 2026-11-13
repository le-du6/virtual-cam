import Foundation
import SystemExtensions

/// Installe, met à jour ou retire l'extension caméra.
final class ExtensionManager: NSObject, ObservableObject, OSSystemExtensionRequestDelegate {
    @Published private(set) var status = "—"
    var onActivated: (() -> Void)?

    private var isDeactivating = false
    private var identifier: String {
        (Bundle.main.bundleIdentifier ?? "fr.stelau.macam") + ".extension"
    }

    func activate() {
        isDeactivating = false
        submit(.activationRequest(forExtensionWithIdentifier: identifier, queue: .main), status: "Activation…")
    }

    func deactivate() {
        isDeactivating = true
        submit(.deactivationRequest(forExtensionWithIdentifier: identifier, queue: .main), status: "Désinstallation…")
    }

    private func submit(_ request: OSSystemExtensionRequest, status: String) {
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
        self.status = status
    }

    // MARK: OSSystemExtensionRequestDelegate (appelé sur la file principale)

    func request(_ request: OSSystemExtensionRequest,
                 actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        status = "Mise à jour \(existing.bundleVersion) → \(ext.bundleVersion)…"
        return .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        status = "À autoriser dans Réglages Système (extensions de caméra)"
    }

    func request(_ request: OSSystemExtensionRequest,
                 didFinishWithResult result: OSSystemExtensionRequest.Result) {
        switch result {
        case .completed:
            status = isDeactivating ? "Extension retirée" : "Extension active"
            if !isDeactivating { onActivated?() }
        case .willCompleteAfterReboot:
            status = "Effectif après redémarrage"
        @unknown default:
            status = "Terminé (\(result.rawValue))"
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        status = "Erreur : \(error.localizedDescription)"
    }
}
