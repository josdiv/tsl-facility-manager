#!/usr/bin/env bash
# Runs the app's backend locally: Auth, Firestore, Storage and Functions
# emulators, freshly seeded with test data on every start. Nothing here
# touches the live Firebase project.
#
# (The Firestore emulator can't export named databases such as tsl-app, so the
# data is re-seeded each time instead of saved between runs.)
#
# Then run the app with:  flutter run --dart-define=USE_EMULATORS=true
set -euo pipefail
cd "$(dirname "$0")/.."

npm --prefix functions run build

firebase emulators:start &
emulators=$!
trap 'kill "$emulators" 2>/dev/null' EXIT INT TERM

hub=http://127.0.0.1:4400
# Ready once the hub lists Functions and every emulator port accepts
# connections (the hub lists emulators slightly before they listen).
ready() {
  curl -sf "$hub/emulators" 2>/dev/null | grep -q '"functions"' || return 1
  for port in 9099 8080 9199 5001; do nc -z 127.0.0.1 "$port" 2>/dev/null || return 1; done
}
until ready; do
  kill -0 "$emulators" 2>/dev/null || { echo "Emulators failed to start." >&2; exit 1; }
  sleep 1
done

# Seed without firing triggers, so the seeded history isn't duplicated.
curl -sf -X PUT "$hub/functions/disableBackgroundTriggers" >/dev/null
# .emulator-test-location (untracked) holds "lat,lng" for the Test Facility.
TEST_LOCATION="$(cat .emulator-test-location 2>/dev/null || true)" \
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
GCLOUD_PROJECT=tsl-facility-manager \
  npm --prefix functions run --silent seed
curl -sf -X PUT "$hub/functions/enableBackgroundTriggers" >/dev/null

# A USB-connected Android phone reaches the emulators through these tunnels.
if command -v adb >/dev/null && adb get-state >/dev/null 2>&1; then
  for port in 9099 8080 9199 5001; do adb reverse "tcp:$port" "tcp:$port" >/dev/null; done
  echo "Phone tunnels open for ports 9099 8080 9199 5001."
fi

echo "Backend ready. Staff password: test1234. Client sign-in codes are emailed via the company mail API."
wait "$emulators"
