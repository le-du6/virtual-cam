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
}

extension OverlayItem {
    static let me = "Benoit LEGER-DERVILLE"

    /// Jeu de départ (modifiable dans la fenêtre Bandeaux).
    static let defaults: [OverlayItem] = [
        OverlayItem(label: "Stelau · iDAKTO", style: .sobre, position: .bottomLeft, animation: .deroule,
                    autoHide: 8, title: me, subtitle: "Expert Cyber · Stelau · iDAKTO"),
        OverlayItem(label: "LSTI", style: .marque, position: .bottomLeft, animation: .deroule,
                    autoHide: 8, title: me, subtitle: "Auditeur eIDAS · LSTI"),
        OverlayItem(label: "EPITA", style: .marque, position: .bottomLeft, animation: .deroule,
                    autoHide: 8, title: me, subtitle: "Enseignant Cours de Cryptographie · EPITA · Stelau"),
        OverlayItem(label: "Cours : ouverture", style: .carte, position: .bottomCenter, animation: .glissement,
                    autoHide: 20, title: "Introduction à la Cryptographie Moderne",
                    subtitle: "Les supports du cours, à suivre en direct",
                    icon: "graduationcap.fill", url: "https://cours.stelau.com/cours.html#/ouverture"),
        OverlayItem(label: "Atelier crypto", style: .carte, position: .bottomCenter, animation: .glissement,
                    autoHide: 20, title: "L'Atelier crypto",
                    subtitle: "Les primitives cryptographiques, à manipuler en ligne",
                    icon: "flask.fill", url: "https://crypto.stelau.com/"),
        OverlayItem(label: "Formation cryptographie", style: .carte, position: .bottomCenter, animation: .glissement,
                    autoHide: 20, title: "Formation Cryptographie moderne",
                    subtitle: "Programme, modalités et inscription",
                    icon: "key.fill", url: "https://www.stelau.com/formations/cryptographie-moderne/"),
        OverlayItem(label: "Stelau", style: .carte, position: .bottomCenter, animation: .glissement,
                    autoHide: 20, title: "Stelau",
                    subtitle: "Conseil en cybersécurité et identité numérique",
                    icon: "shield.lefthalf.filled", url: "https://www.stelau.com/"),
    ]

    /// Modèle vierge pour le bouton « + ».
    static func blank(_ style: OverlayStyle) -> OverlayItem {
        style == .carte
            ? OverlayItem(label: "Nouvelle carte", style: .carte, position: .bottomCenter, animation: .glissement,
                          autoHide: 20, title: "Titre", subtitle: "Description",
                          icon: "link", url: "https://www.stelau.com/")
            : OverlayItem(label: "Nouveau bandeau", style: style, position: .bottomLeft, animation: .deroule,
                          autoHide: 8, title: me, subtitle: "Fonction")
    }
}
