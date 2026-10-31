#!/bin/bash
set -e

CONFIG=${1:-Release}

echo "Generating Xcode project..."
xcodegen generate

echo "Building iOSCustomize..."
xcodebuild -project iOSCustomize.xcodeproj -scheme iOSCustomize -configuration $CONFIG -destination generic/platform=iOS -derivedDataPath build/xderived CODE_SIGNING_ALLOWED=NO build

echo "Packaging unsigned IPA..."
rm -rf Payload
mkdir Payload
cp -R build/xderived/Build/Products/$CONFIG-iphoneos/iOSCustomize.app Payload/
rm -rf Payload/iOSCustomize.app/_CodeSignature
zip -r iOSCustomize.ipa Payload

echo "IPA created: iOSCustomize.ipa"