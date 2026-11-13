#!/bin/zsh
# Génère le projet, compile, installe dans /Applications et lance MaCam.
# Le numéro de build est horodaté : macOS remplace ainsi l'extension à chaque itération.
set -euo pipefail
cd "${0:A:h}/.."

if grep -q 'XXXXXXXXXX' project.yml; then
  echo "⚠️  Renseignez votre Team ID (DEVELOPMENT_TEAM) dans project.yml"; exit 1
fi
command -v xcodegen >/dev/null || { echo "⚠️  Installez XcodeGen : brew install xcodegen"; exit 1; }

# Ancienne version (VirtualCam) encore installée ?
if [[ -d /Applications/VirtualCam.app ]] \
   || systemextensionsctl list 2>/dev/null | grep -Eq 'fr\.stelau\.virtualcam\.extension.*\[activated'; then
  echo "ℹ️  L'ancienne version VirtualCam est encore présente :"
  echo "    ouvrez VirtualCam › Désinstaller, puis mettez VirtualCam.app à la corbeille."
fi

BUILD_NUMBER=$(date +%s)

xcodegen generate --quiet
xcodebuild -project MaCam.xcodeproj -scheme MaCam -configuration Debug \
  -derivedDataPath build -destination 'platform=macOS' \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" -quiet build

pkill -x MaCam 2>/dev/null || true
rm -rf /Applications/MaCam.app
ditto build/Build/Products/Debug/MaCam.app /Applications/MaCam.app
open /Applications/MaCam.app
echo "✅ MaCam (build $BUILD_NUMBER) lancé depuis /Applications"
