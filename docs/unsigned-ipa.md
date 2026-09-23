# Unsigned IPA build

The `Build unsigned IPA` workflow creates exactly one `LocationSpoofer-unsigned.ipa` per successful run. The app and Packet Tunnel extension are inside the same IPA. Download it from the run summary or Artifacts; upload-artifact v7 stores this file directly without an additional ZIP wrapper. Artifacts expire after 30 days. Older run artifacts are not deleted by newer runs.

## When a build runs
Pushes to main run the build when App, Tunnel, Resources, Go source/headers/dependencies, project.yml or scripts/ci change. Markdown, documentation, AGENTS.md, workflow-only changes and changes only to the generated project.pbxproj do not trigger a build. Run workflow remains available for manual verification. Concurrent builds for the same ref are cancelled in favour of the newer run.

## Build inputs and caches
Go is selected from GoSpoofer/go.mod. The macos-latest runner's default Xcode is used and fingerprinted along with its iOS SDK and XcodeGen version. Caches contain Go modules/build data, the arm64 C archive together with its generated header, and Xcode DerivedData. The first build is cold; subsequent compatible builds can reuse the caches. No certificates, profiles, API keys or signing secrets are needed to compile.

The canonical Xcode project specification is project.yml. Go's deployment target and the app both default to iOS 18. The generated C header is always copied from the same cached/built output as its archive. SwiftNIO and swift-log were unused and are not required by the current sources.

## Validation
CI runs go mod verify, go test -race and go vet before building. Packaging checks that one app and one VPN extension are present with arm64 executables and matching versions, strips/verifies any Mach-O signatures, rejects profiles/static-library resources and checks ZIP integrity. The SHA-256 is printed in the build summary. It does not attest that location spoofing works on every iOS version.

## Installation caveat
Unsigned means ready for subsequent signing, not directly installable. The signer must support both bundles and provision their Network Extension and App Group entitlements consistently. Source entitlements remain in Resources/ and Tunnel/. A generic signing certificate without these capabilities may install an app whose VPN does not start.

## Recovery after an upstream update
The independent copy is in SiNaPsEr0x/Pubblici under backups/github-actions/ios-location-spoofer/. Keep the customized workflow, project.yml and both build scripts together. Original/build.yml is the historical TestFlight configuration, not the unsigned configuration to restore. Review upstream changes before restoring files; do not reset the entire app to an old revision. Changes to the workflow alone need a manual run.
