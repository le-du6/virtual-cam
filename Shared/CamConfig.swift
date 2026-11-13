// Constantes partagées entre l'app et l'extension caméra.
import Foundation

enum CamConfig {
    /// Nom affiché dans Teams, Zoom, FaceTime… L'app retrouve la caméra par ce nom.
    static let deviceName = "MaCam"
    static let width = 1280
    static let height = 720
    static let frameRate = 30
}
