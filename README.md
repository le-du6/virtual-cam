# MaCam — v0.2

Caméra virtuelle macOS (Teams, Zoom, Meet, FaceTime…) alimentée par une petite app Swift qui compose l'image : webcam + bandeau. Pilotable depuis la barre des menus.

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

- **Barre des menus** (icône caméra) : démarrer ou arrêter, choisir la source, afficher le bandeau, ouvrir la fenêtre, réglages, quitter.
- **Fenêtre** (*Ouvrir MaCam…* ou ⌘,) : tous les réglages, aperçu de la sortie réelle.
- **Réglages enregistrés automatiquement** : caméra préférée (reprise dès qu'elle est rebranchée), bandeau (affichage, nom, fonction), démarrage de la caméra au lancement, lancement à l'ouverture de session, icône dans le Dock.
- Fermer la fenêtre ne quitte pas MaCam. Pour quitter : *Quitter MaCam* dans le menu.
- Icône du Dock masquée : MaCam démarre sans fenêtre, uniquement dans la barre des menus.

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
| `App/Compositor.swift` | Composition 1280×720 : **point d'extension pour les masques** |
| `App/LowerThird.swift` | Bandeau de test, statique |
