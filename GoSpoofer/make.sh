#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
MIN_IOS_VERSION="${IOS_DEPLOYMENT_TARGET:-18.0}"
BUILD_DIR="$SCRIPT_DIR/build"
IOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
command -v go >/dev/null
mkdir -p "$BUILD_DIR"
export CGO_ENABLED=1 GOOS=ios GOARCH=arm64
export CC="$(xcrun --sdk iphoneos --find clang)"
export CGO_CFLAGS="-arch arm64 -isysroot \"$IOS_SDK\" -miphoneos-version-min=$MIN_IOS_VERSION"
export CGO_LDFLAGS="$CGO_CFLAGS"
printf 'Building Go library for iOS %s+, arm64\nSDK: %s\n' "$MIN_IOS_VERSION" "$IOS_SDK"
go build -mod=readonly -trimpath -ldflags="-s -w" -buildmode=c-archive \
  -tags=ios -o "$BUILD_DIR/libgolocationspoofer.a" .
test -s "$BUILD_DIR/libgolocationspoofer.a"
test -s "$BUILD_DIR/libgolocationspoofer.h"
xcrun lipo "$BUILD_DIR/libgolocationspoofer.a" -verify_arch arm64
cp "$BUILD_DIR/libgolocationspoofer.h" "$SCRIPT_DIR/golocationspoofer.h"
ln -sfn build/libgolocationspoofer.a "$SCRIPT_DIR/libgolocationspoofer.a"
echo 'Go static library and matching C header are ready.'
