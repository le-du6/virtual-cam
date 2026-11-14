import Foundation

/// Apparence d'un bandeau.
enum OverlayStyle: String, Codable, CaseIterable, Identifiable {
    case sobre, marque, carte
    var id: String { rawValue }
    var label: String {
        switch self {
        case .sobre: "Sobre"
        case .marque: "Marqué"
        case .carte: "Carte QR code"
        }
    }
}

/// Emplacement à l'écran. Un seul bandeau par zone (haut / bas) à la fois.
enum OverlayPosition: String, Codable, CaseIterable, Identifiable {
    case bottomLeft, bottomCenter, topLeft, topRight
    var id: String { rawValue }
    var label: String {
        switch self {
        case .bottomLeft: "Bas gauche"
        case .bottomCenter: "Bas centre"
        case .topLeft: "Haut gauche"
        case .topRight: "Haut droite"
        }
    }
    var isTop: Bool { self == .topLeft || self == .topRight }
}

/// Animation d'entrée ; la sortie la rejoue à l'envers.
enum OverlayAnimation: String, Codable, CaseIterable, Identifiable {
    case deroule, glissement, fondu
    var id: String { rawValue }
    var label: String {
        switch self {
        case .deroule: "Déroulé"
        case .glissement: "Glissement"
        case .fondu: "Fondu"
        }
    }
}

struct OverlayItem: Codable, Identifiable, Equatable {
    var id = UUID()
    /// Nom court affiché dans les menus.
    var label: String
    var style: OverlayStyle
    var position: OverlayPosition
    var animation: OverlayAnimation
    /// Secondes avant masquage automatique ; 0 = reste affiché.
    var autoHide: Double
    /// Bandeau : nom. Carte : titre.
    var title: String
    /// Bandeau : fonction. Carte : description.
    var subtitle: String
    /// Carte : symbole SF (rendu duotone) ou nom d'un fichier du dossier Icônes (SVG Font Awesome…).
    var icon: String = ""
    /// Carte : URL encodée dans le QR code.
    var url: String = ""
    /// Carte : complément affiché après l'URL (ex. « § 4 »).
    var urlNote: String = ""
    /// Logo : nom d'un fichier du dossier Logos, ou URL (téléchargée puis mise en cache).
    var logo: String = ""
    /// Logo recoloré en blanc pour les fonds sombres (logo à fond transparent requis).
    var logoWhite: Bool = true
    /// Fait partie de la rotation automatique.
    var inRotation: Bool = false
}

/// Décodage tolérant : les bandeaux enregistrés par une version précédente restent lisibles.
extension OverlayItem {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        style = try c.decode(OverlayStyle.self, forKey: .style)
        position = try c.decode(OverlayPosition.self, forKey: .position)
        animation = try c.decode(OverlayAnimation.self, forKey: .animation)
        autoHide = try c.decode(Double.self, forKey: .autoHide)
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decode(String.self, forKey: .subtitle)
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        urlNote = try c.decodeIfPresent(String.self, forKey: .urlNote) ?? ""
        logo = try c.decodeIfPresent(String.self, forKey: .logo) ?? ""
        logoWhite = try c.decodeIfPresent(Bool.self, forKey: .logoWhite) ?? (style != .carte)
        inRotation = try c.decodeIfPresent(Bool.self, forKey: .inRotation) ?? false
    }
}

/// Réglages de la rotation automatique.
struct RotationSettings: Codable, Equatable {
    /// Durée d'affichage des bandeaux sans masquage automatique (s).
    var duration: Double = 12
    /// Pause entre deux bandeaux (s).
    var pause: Double = 2
    var loop: Bool = true
}

extension OverlayItem {
    static let me = "Benoit LEGER-DERVILLE"
    static let stelauLogo = "https://www.stelau.com/brand/logo.stelau.png"

    /// Jeu de départ (modifiable dans la fenêtre Bandeaux).
    static let defaults: [OverlayItem] = [
        OverlayItem(label: "Stelau · iDAKTO", style: .sobre, position: .bottomLeft, animation: .deroule,
                    autoHide: 8, title: me, subtitle: "Expert Cyber · Stelau · iDAKTO",
                    logo: stelauLogo, inRotation: true),
        OverlayItem(label: "LSTI", style: .marque, position: .bottomLeft, animation: .deroule,
                    autoHide: 8, title: me, subtitle: "Auditeur eIDAS · LSTI"),
        OverlayItem(label: "EPITA", style: .marque, position: .bottomLeft, animation: .deroule,
                    autoHide: 8, title: me, subtitle: "Enseignant Cours de Cryptographie · EPITA · Stelau",
                    logo: stelauLogo),
        OverlayItem(label: "Cours : ouverture", style: .carte, position: .bottomCenter, animation: .glissement,
                    autoHide: 20, title: "Introduction à la Cryptographie Moderne",
                    subtitle: "Les supports du cours, à suivre en direct",
                    icon: "graduationcap.fill", url: "https://cours.stelau.com/cours.html#/ouverture",
                    logoWhite: false),
        OverlayItem(label: "Atelier crypto", style: .carte, position: .bottomCenter, animation: .glissement,
                    autoHide: 20, title: "L'Atelier crypto",
                    subtitle: "Les primitives cryptographiques, à manipuler en ligne",
                    icon: "flask.fill", url: "https://crypto.stelau.com/", logoWhite: false, inRotation: true),
        OverlayItem(label: "Formation cryptographie", style: .carte, position: .bottomCenter, animation: .glissement,
                    autoHide: 20, title: "Formation Cryptographie moderne",
                    subtitle: "Programme, modalités et inscription",
                    icon: "key.fill", url: "https://www.stelau.com/formations/cryptographie-moderne/",
                    logoWhite: false, inRotation: true),
        OverlayItem(label: "Stelau", style: .carte, position: .bottomCenter, animation: .glissement,
                    autoHide: 20, title: "Stelau",
                    subtitle: "Conseil en cybersécurité et identité numérique",
                    icon: "shield.lefthalf.filled", url: "https://www.stelau.com/", logoWhite: false),
    ]

    /// Modèle vierge pour le bouton « + ».
    static func blank(_ style: OverlayStyle) -> OverlayItem {
        style == .carte
            ? OverlayItem(label: "Nouvelle carte", style: .carte, position: .bottomCenter, animation: .glissement,
                          autoHide: 20, title: "Titre", subtitle: "Description",
                          icon: "link", url: "https://www.stelau.com/", logoWhite: false)
            : OverlayItem(label: "Nouveau bandeau", style: style, position: .bottomLeft, animation: .deroule,
                          autoHide: 8, title: me, subtitle: "Fonction")
    }
}
