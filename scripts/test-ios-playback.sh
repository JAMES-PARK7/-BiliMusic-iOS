#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build native-tests/Fixtures

# Generate our own AAC audio instead of depending on a live Bilibili video.
python3 - <<'PY'
import math, struct, wave
with wave.open('build/tone.wav', 'wb') as audio:
    audio.setparams((1, 2, 22050, 0, 'NONE', 'not compressed'))
    audio.writeframes(b''.join(struct.pack('<h', int(2000 * math.sin(2 * math.pi * 440 * t / 22050))) for t in range(22050 * 4)))
PY
afconvert -f m4af -d aac -b 64000 build/tone.wav native-tests/Fixtures/tone.m4a

device="$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for runtime, devices in d["devices"].items() if "iOS" in runtime for x in devices if "iPhone" in x["name"]))')"
xcrun simctl boot "$device" || true
xcrun simctl bootstatus "$device" -b
xcodebuild test \
  -scheme BiliMusicPlaybackCore \
  -destination "platform=iOS Simulator,id=$device" \
  -destination-timeout 120 \
  -parallel-testing-enabled NO \
  -derivedDataPath build/PlaybackTests \
  -resultBundlePath build/PlaybackTests.xcresult \
  CODE_SIGNING_ALLOWED=NO \
  | tee build/native-tests.log
