#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "IPA compilation requires macOS and Xcode. Use the included GitHub Actions workflow." >&2
  exit 1
fi

mkdir -p build
xcodebuild -resolvePackageDependencies -project ios/App/App.xcodeproj -scheme App
xcodebuild build \
  -project ios/App/App.xcodeproj \
  -scheme App \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  COMPILER_INDEX_STORE_ENABLE=NO \
  | tee build/xcodebuild.log

app='build/DerivedData/Build/Products/Release-iphoneos/App.app'
test -d "$app"
mkdir -p build/Payload
ditto "$app" build/Payload/BiliMusic.app
ditto -c -k --norsrc --keepParent build/Payload build/BiliMusic-iOS-unsigned.ipa
shasum -a 256 build/BiliMusic-iOS-unsigned.ipa > build/SHA256SUMS.txt
echo "Created build/BiliMusic-iOS-unsigned.ipa for AltStore/Sideloadly signing."
