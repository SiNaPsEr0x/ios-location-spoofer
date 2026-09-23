# Unsigned IPA build

The `Build unsigned IPA` workflow produces exactly one `LocationSpoofer-unsigned.ipa` and publishes it to exactly one GitHub Release. The canonical Release always uses the stable tag `latest`; a new successful build moves that tag to the producing commit, updates the Release title/notes and replaces the IPA asset.

Historical GitHub Releases and their release tags are deleted. The workflow also deletes GitHub Actions artifacts, so the Release is the only retained IPA download. Workflow-run logs remain available for diagnostics.

## Versioning

The project reuses the previously chosen calendar scheme:

```text
ISO-year.ISO-week.ISO-weekday
```

The workflow calculates it in `Europe/Rome` time. Example for Wednesday 23 September 2026: `2026.39.3`.

The same version is written to both `CFBundleShortVersionString` and `CFBundleVersion` for the app and Packet Tunnel extension, and is shown in the Release title. Multiple builds on the same calendar day intentionally replace the same single Release and keep the same calendar version.

## When a build runs

Pushes to main run the build when App, Tunnel, Resources, Go source/headers/dependencies, project.yml or scripts/ci change. Markdown, documentation, AGENTS.md, workflow-only changes and changes only to the generated project.pbxproj do not trigger a build. Run workflow remains available for manual verification. Concurrent builds for the same ref are cancelled in favour of the newer run.

## Build inputs and caches

Go is selected from GoSpoofer/go.mod. The macos-latest runner's default Xcode is used and fingerprinted along with its iOS SDK and XcodeGen version. Caches contain Go modules/build data, the arm64 C archive together with its generated header, and Xcode DerivedData. No certificates, profiles, API keys or signing secrets are needed to compile.

The canonical Xcode project specification is project.yml. Go's deployment target and the app both default to iOS 18. The generated C header is always copied from the same cached/built output as its archive.

## Validation

CI runs `go mod verify`, `go test -race` and `go vet` before building. Packaging checks one app and one VPN extension, arm64 executables, identical expected calendar versions, absence of signing/provisioning/static-library payloads and ZIP integrity. The SHA-256 is printed in the run summary.

The Release step then verifies that GitHub contains exactly one Release and that Release contains exactly one asset.

## Installation caveat

Unsigned means ready for subsequent signing, not directly installable. The signer must support both bundles and provision their Network Extension and App Group entitlements consistently. Source entitlements remain in Resources/ and Tunnel/.

## Recovery after an upstream update

The independent copy is in `SiNaPsEr0x/Pubblici/backups/github-actions/ios-location-spoofer/`. Keep the customized workflow, project.yml and both build scripts together. `original/build.yml` is the historical TestFlight configuration, not the unsigned configuration to restore. Review upstream changes before restoring files; do not reset the entire app to an old revision.
