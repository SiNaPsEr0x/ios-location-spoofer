# AGENTS.md

## Owner requirements
- Read this file before editing and keep it updated with decisions, verification results and recovery details.
- Produce exactly one unsigned arm64 IPA containing the app and its VPN extension. Do not add a signed/TestFlight build, a build matrix or duplicate IPA artifacts.
- Automatic builds run only for app/extension source, resources, Go source/dependencies, project.yml or build-script changes on main. Markdown, README, AGENTS.md and workflow-only edits must not automatically compile. Use Run workflow when validating CI-only edits.
- Keep Go dependencies, the generated Go library/header pair and Xcode incremental build caches. Cache keys must include the Apple toolchain and relevant source inputs.
- Combine related changes into one commit on main where possible; never force-push to overwrite someone else's work.
- Keep the recovery copy in `SiNaPsEr0x/Pubblici/backups/github-actions/ios-location-spoofer/` up to date when changing CI. Do not put backup YAML under Pubblici/.github/workflows. Never copy signing material or tokens.

## Project invariants
- `project.yml` is the source of truth. CI regenerates the checked-in Xcode project; editing only project.pbxproj does not alter CI output.
- Keep bundle IDs, App Group, VPN extension and CGo exports compatible. Unsigned builds do not waive the signing/entitlement requirements for installation on a real device.
- Keep user-visible UI in English. Do not change routing, DNS, location-spoofing behavior or certificates merely to modify the build pipeline.
- GoSpoofer/build/libgolocationspoofer.a is a link dependency, never a bundle resource. HACKS.md describes a historical workaround; do not reapply its PBX patch with the current project.yml.
- Keep existing tests. Repair invalid fixtures and add regressions instead of skipping failures. Current checks include Go race tests and vet, unsigned Mach-O verification, matching app/extension versions and ZIP integrity.

## 2026-09-23 maintenance
Replaced certificate-dependent TestFlight workflow with an unsigned cached build; removed unused SwiftNIO/swift-log packages, invalid Swift language mode and duplicate/resource-only build inputs. Added Combine imports, exact ARPC reads and FunctionId preservation, HTTP passthrough body restoration, and proxy cleanup after tunnel setup failure. Four original test names are retained and five regression tests added.

Validation before push: Bash/YAML/embedded Python syntax, modified Swift parsing and two isolated ARPC tests with the race detector passed locally. Full Go module tests and Xcode archive must be checked in the GitHub Actions run before claiming the IPA works. Device/VPN behavior requires a separately signed on-device test.

Original source baseline: `bfb44fa3b00e2cc8820536fb58e375d7269ef90a`. See `docs/unsigned-ipa.md` for build and recovery guidance.

### Validation follow-up
- Run 1: Go race tests/vet passed; fixed Apple `lipo` argument order.
- Run 2: Go tests, Go iOS archive and XcodeGen passed; Xcode exposed two pre-existing unterminated Swift diagnostic strings, one unescaped settings string, and a missing `libgolocationspoofer` search path. These are fixed in the next source commit; final IPA success must still be verified from Actions.
