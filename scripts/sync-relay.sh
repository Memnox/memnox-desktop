#!/bin/sh
# Copies the relay client from memnox-ios, so this Mac reaches a server over the relay exactly as the iPhone does.
# The reverse of memnox-ios/scripts/sync-shared.sh, which copies from this repo to the phone.
#
# Copied into Sources/MemnoxVoiceCore under the same folders they hold on the phone:
#   Infrastructure/Relay: NoiseRelayLink, NoiseTunnel, RelayPairer, WebSocketRelay
#   Infrastructure/Noise: Noise
#   Domain/Relay: NoiseSchedule, RelayAddress, RelayFraming, Resubscribe, StreamEnd
#   Domain/Pairing: PairedMachine, PairedMachines, PairingInvitation, PairingWire, Base64URL
#   Application: RequestIds, and the ports PairedStore, Pairer, RelaySocket, PushRegistrar
# and MemnoxNoise.xcframework into Vendor, from memnox-runtime's build when there is one, else the phone's copy.
#
# Left out on purpose: the phone's PairingLines, since this Mac has its own by that name, and its
# KeychainPairedStore, since a Mac keeps its servers under a service of its own (KeychainPairedServers).
#
# Edits after copying stay minimal, and these are the only ones, to make again by hand after a --force:
#   PairingWire.swift: PhoneIntroduction carries an optional kind, so a Mac introduces itself as a desktop.
#   RelayPairer.swift: init takes that kind and passes it on; the Touch ID words come from ReasonedKey instead.
# Without --force a copy that differs from the phone's is kept and named, so those edits are never lost by accident.
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
ios="${MEMNOX_IOS:-$here/../memnox-ios}"
runtime="${MEMNOX_RUNTIME:-$here/../memnox-runtime}"
from="$ios/Sources/MemnoxPhoneCore"
core="$here/Sources/MemnoxVoiceCore"
force="${1:-}"

copy() {
  mkdir -p "$(dirname "$core/$1")"
  if [ -f "$core/$1" ] && ! cmp -s "$from/$1" "$core/$1" && [ "$force" != "--force" ]; then
    echo "kept $1, which differs from the phone's; compare by hand or run with --force"
    return
  fi
  cp "$from/$1" "$core/$1"
  echo "copied $1"
}

for file in \
  Infrastructure/Relay/NoiseRelayLink.swift \
  Infrastructure/Relay/NoiseTunnel.swift \
  Infrastructure/Relay/RelayPairer.swift \
  Infrastructure/Relay/WebSocketRelay.swift \
  Infrastructure/Noise/Noise.swift \
  Domain/Relay/NoiseSchedule.swift \
  Domain/Relay/RelayAddress.swift \
  Domain/Relay/RelayFraming.swift \
  Domain/Relay/Resubscribe.swift \
  Domain/Relay/StreamEnd.swift \
  Domain/Pairing/PairedMachine.swift \
  Domain/Pairing/PairedMachines.swift \
  Domain/Pairing/PairingInvitation.swift \
  Domain/Pairing/PairingWire.swift \
  Domain/Pairing/Base64URL.swift \
  Application/RequestIds.swift \
  Application/Ports/PairedStore.swift \
  Application/Ports/Pairer.swift \
  Application/Ports/RelaySocket.swift \
  Application/Ports/PushRegistrar.swift
do
  copy "$file"
done

# The one Noise build, snow behind a C ABI, so this Mac, the phone and the runtime run the same crate.
noise="$runtime/native/noise/build/MemnoxNoise.xcframework"
[ -d "$noise" ] || noise="$ios/Vendor/MemnoxNoise.xcframework"
if [ ! -d "$noise" ]; then
  echo "no MemnoxNoise.xcframework in memnox-runtime or memnox-ios, so build it with native/noise/scripts/build-xcframework.sh first" >&2
  exit 1
fi
rm -rf "$here/Vendor/MemnoxNoise.xcframework"
mkdir -p "$here/Vendor"
cp -R "$noise" "$here/Vendor/MemnoxNoise.xcframework"
echo "copied $noise"
