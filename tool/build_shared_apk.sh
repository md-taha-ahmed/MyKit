#!/usr/bin/env bash
# A release APK to give to other people: Google sign-in (Drive backup,
# YouTube import) built in, but NOT your Gemini key — each person adds their
# own free key in Settings → Setup checklist → AI features.
#
#   tool/build_shared_apk.sh        → build/app/outputs/flutter-apk/MyKit-shared.apk
set -euo pipefail
cd "$(dirname "$0")/.."

defines=()
if [[ -f config/google_oauth.local.json ]]; then
  defines+=(--dart-define-from-file=config/google_oauth.local.json)
else
  echo "note: config/google_oauth.local.json not found; Google sign-in will be off" >&2
fi

flutter build apk --release "${defines[@]}"
out=build/app/outputs/flutter-apk
cp "$out/app-release.apk" "$out/MyKit-shared.apk"
echo "Shareable APK (no Gemini key): $out/MyKit-shared.apk"
