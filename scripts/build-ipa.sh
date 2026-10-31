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
mkdir -p build

# Copy đúng file .app mới build ra
cp -R build/xderived/Build/Products/$CONFIG-iphoneos/iOSCustomize.app Payload/
rm -rf Payload/iOSCustomize.app/_CodeSignature

# Nén thành file IPA chuẩn
zip -r build/iOSCustomize.ipa Payload

echo "✅ IPA created at build/iOSCustomize.ipa"