<p align="center">
  <img src="Design/AppIcon.svg" width="140" alt="Icône MaCam">
</p>

<h1 align="center">MaCam</h1>

<p align="center"><em>Caméra virtuelle macOS avec bandeaux animés, cartes QR code et logos</em><br>
<sub>v0.4 · Swift · CoreMediaIO · macOS 15+</sub></p>

Caméra virtuelle macOS (Teams, Zoom, Meet, FaceTime…) alimentée par une petite app Swift qui compose l'image : webcam + bandeaux animés (nom, fonction, cartes QR code). Pilotable depuis la barre des menus et au clavier.

```
Webcam ──► App MaCam ──► Compositor (Core Image / Metal) ──► sink ─┐
           (AVCaptureSession)  + calques (bandeau…)                │
                                                                   ▼
                    Teams / Zoom / FaceTime ◄── source ◄── Extension CoreMediaIO « MaCam »
```

## Prérequis

- Xcode (connecté à votre compte : *Xcode › Réglages › Comptes*)
- XcodeGen : `brew install xcodegen`
- Votre **Team ID** dans `project.yml` (`DEVELOPMENT_TEAM`)

## Compiler et lancer

```sh
scripts/run.sh
```

Le script compile, copie l'app dans **/Applications** (obligatoire pour une extension système) et la lance. Le numéro de build est horodaté : à chaque lancement, l'app remplace l'extension par la nouvelle version.

Au premier lancement de MaCam, autorisez la nouvelle extension dans **Réglages Système** (extensions de caméra), puis choisissez **MaCam** comme caméra dans Teams.

## Utilisation

- **Barre des menus** (icône caméra) : démarrer ou arrêter, choisir la source, afficher / masquer les bandeaux, ouvrir les fenêtres, réglages, quitter.
- **Fenêtre** (*Ouvrir MaCam…* ou ⌘,) : tous les réglages, aperçu de la sortie réelle.
- **Réglages enregistrés automatiquement** : caméra préférée (reprise dès qu'elle est rebranchée), bandeaux, démarrage de la caméra au lancement, lancement à l'ouverture de session, icône dans le Dock.
- Fermer la fenêtre ne quitte pas MaCam. Pour quitter : *Quitter MaCam* dans le menu.
- Icône du Dock masquée : MaCam démarre sans fenêtre, uniquement dans la barre des menus.

## Bandeaux

- **Styles** : *Sobre* (bandeau d'origine), *Marqué* (bleu nuit / turquoise / orange, deux étages), *Carte QR code* (titre + icône duotone, description, URL et QR code) — horizontale en bas, **verticale en haut gauche / haut droite**.
- **Effets vidéo macOS** (Portrait, Studio Light) : à activer pour **MaCam** (appliqués à la webcam, avant les bandeaux) et à laisser désactivés dans Teams pour la caméra MaCam — sinon macOS floute aussi les bandeaux. Bouton *Effets vidéo macOS…* dans la fenêtre principale.
- **Animations** : *Déroulé* (accent, puis fond, puis texte), *Glissement*, *Fondu* ; la sortie rejoue l'entrée à l'envers.
- **Zones** : un bandeau à la fois en haut et un en bas ; en afficher un autre dans la même zone remplace le précédent.
- **Masquage automatique** réglable par bandeau (0 = reste affiché).
- **Pilotage** : menu de la barre des menus, fenêtre principale, et raccourcis globaux **⌃⌥1 … ⌃⌥9** (ordre de la liste), **⌃⌥0** pour tout masquer — utilisables pendant que Teams est au premier plan.
- **Édition** : *Gérer les bandeaux…* — liste réordonnable, aperçu, ajout / duplication / suppression. Tout est enregistré automatiquement.
- **Rotation** : enchaîne les bandeaux cochés « Inclure dans la rotation » (ordre de la liste), chacun pendant sa durée de masquage automatique (sinon la durée par défaut), avec une pause entre deux, en boucle ou pour un seul tour. **⌃⌥R** pour lancer / arrêter ; ⌃⌥0 arrête aussi la rotation.
- **Logos** : sur les trois styles (à droite). Référence = fichier du *Dossier Logos* (`~/Library/Application Support/MaCam/Logos`) ou URL https (téléchargée une fois, ex. `https://www.stelau.com/brand/logo.stelau.png`). Option « Logo en blanc » pour les fonds sombres (logo à fond transparent).
- **Icônes des cartes** : un symbole SF (rendu duotone « hiérarchique »), ou un SVG Font Awesome Duotone de votre abonnement déposé dans le *Dossier Icônes* (`~/Library/Application Support/MaCam/Icons`) : `flask.svg` → icône `flask`. Il est recoloré automatiquement, couche secondaire à 40 %.

## Dépannage

| Symptôme | Piste |
|---|---|
| Statut « À autoriser… » | Validez l'extension dans Réglages Système. |
| Mire « en attente de l'application » | L'app n'envoie pas d'images : *Démarrer la caméra*. |
| Teams ne voit pas MaCam | Quittez complètement Teams (⌘Q) puis relancez-le. |
| « Ouverture de session : à valider » | Réglages Système › Général › éléments de connexion. |

```sh
systemextensionsctl list
log stream --predicate 'subsystem == "fr.stelau.macam"' --level info
defaults read fr.stelau.macam          # réglages enregistrés
```

## Organisation du code

| Fichier | Rôle |
|---|---|
| `Extension/ExtensionProvider.swift` | Périphérique CMIO : flux *source* (lu par la visio) et *sink* (alimenté par l'app), mire d'attente |
| `App/MaCamApp.swift` | Scènes (fenêtre + barre des menus), `AppDelegate` propriétaire des objets |
| `App/MenuBar.swift` | Menu et icône de la barre des menus |
| `App/AppState.swift` | Icône du Dock, lancement à l'ouverture de session |
| `App/Pipeline.swift` | Orchestration et réglages enregistrés |
| `App/Prefs.swift` | Clés des réglages (UserDefaults) |
| `App/SinkFeeder.swift` | Liaison vers le sink (API C CoreMediaIO) |
| `App/CameraCapture.swift` | Capture de la webcam physique |
| `App/Compositor.swift` | Composition 1280×720 : caméra + bandeaux |
| `App/Overlays/OverlayModel.swift` | Bandeaux : modèle, styles, positions, jeu de départ |
| `App/Overlays/OverlayRenderer.swift` | Dessin des styles (calques séparés), QR code, aperçu |
| `App/Overlays/OverlayEngine.swift` | Animations image par image, placement |
| `App/Overlays/OverlayStore.swift` | Liste enregistrée, affichage par zone, masquage auto |
| `App/Overlays/OverlaysView.swift` | Fenêtre « Bandeaux » (éditeur) |
| `App/Overlays/HotKeys.swift` | Raccourcis globaux ⌃⌥0…9 |
| `App/Overlays/Logos.swift` | Logos : dossier Logos ou URL mise en cache, teinte blanche |
| `App/Overlays/Icons.swift` | Icônes : dossier Icônes (SVG FA Duotone) ou symboles SF |
