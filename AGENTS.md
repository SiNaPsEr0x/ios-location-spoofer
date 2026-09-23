# AGENTS.md

## Owner requirements
- Read this file before editing and keep it updated with decisions, verification results and recovery details.
- Produce exactly one unsigned arm64 IPA containing the app and its VPN extension. Do not add a signed/TestFlight build, a build matrix or duplicate IPA artifacts.
- Publish exactly one GitHub Release using the stable tag `latest`. Replace its IPA asset in place, remove historical Releases/release tags, and do not retain GitHub Actions IPA artifacts. Workflow-run logs may remain for diagnostics.
- Versioning follows the previously chosen calendar format `ISO-year.ISO-week.ISO-weekday` in Europe/Rome time, e.g. `2026.39.3`. Use the same value for `CFBundleShortVersionString`, `CFBundleVersion` and the Release title.
- Automatic builds run only for app/extension source, resources, Go source/dependencies, project.yml or build-script changes on main. Markdown, README, AGENTS.md and workflow-only edits must not automatically compile. Use Run workflow when validating CI-only edits.
- Keep Go dependencies, the generated Go library/header pair and Xcode incremental build caches. Cache keys must include the Apple toolchain and relevant source inputs.
- Combine related changes into one commit on main where possible; never force-push the main branch to overwrite someone else's work. The stable Release tag `latest` is intentionally moved to the verified build commit.
- Keep the recovery copy in `SiNaPsEr0x/Pubblici/backups/github-actions/ios-location-spoofer/` up to date when changing CI. Do not put backup YAML under Pubblici/.github/workflows. Never copy signing material or tokens.

## Project invariants
- `project.yml` is the source of truth. CI regenerates the checked-in Xcode project; editing only project.pbxproj does not alter CI output.
- Keep bundle IDs, App Group, VPN extension and CGo exports compatible. Unsigned builds do not waive the signing/entitlement requirements for installation on a real device.
- Keep user-visible UI in English. Do not change routing, DNS, location-spoofing behavior or certificates merely to modify the build pipeline.
- GoSpoofer/build/libgolocationspoofer.a is a link dependency, never a bundle resource. HACKS.md describes the current linking constraint; do not restore the old manual PBX patch.
- Keep existing tests. Repair invalid fixtures and add regressions instead of skipping failures. Current checks include Go race tests and vet, unsigned Mach-O verification, matching app/extension versions and ZIP integrity.

## 2026-09-23 maintenance
Replaced certificate-dependent TestFlight workflow with an unsigned cached build; removed unused SwiftNIO/swift-log packages, invalid Swift language mode and duplicate/resource-only build inputs. Added Combine imports, exact ARPC reads and FunctionId preservation, HTTP passthrough body restoration, proxy cleanup after tunnel setup failure, repaired pre-existing Swift string errors and corrected Go c-archive linking.

Run 3 (`35912394315`) on commit `232c1c62ff4d52db4a5ef1d0e3229a29d21af2db` was the first fully successful unsigned IPA build: tests, Go iOS archive, Xcode archive, unsigned validation and direct artifact upload passed.

The next CI revision replaces per-run IPA artifacts with one stable GitHub Release and restores the prior `year.week.day` version scheme. Verify the Release count, asset count, embedded bundle versions and cleanup behavior after the first run of that revision.

Original source baseline: `bfb44fa3b00e2cc8820536fb58e375d7269ef90a`. See `docs/unsigned-ipa.md` for build and recovery guidance.

### Rolling Release verification
- Run 4 (`35913536096`) on commit `9dfc64786539b627efe41d023c55caa864b1e4b5` completed successfully.
- Calculated version: `2026.39.3` using Europe/Rome and the `ISO-year.ISO-week.ISO-weekday` scheme.
- GitHub now contains exactly one Release: tag `latest`, title `Location Spoofer 2026.39.3`.
- The Release contains exactly one asset: `LocationSpoofer-unsigned.ipa`, 4,207,689 bytes, SHA-256 `02718de3d44f69a950d0e117d0e0e037b9a208a5f4e4dc8713b78b6e0dcb4220`.
- Historical Actions artifacts were deleted; both the previous successful run and the rolling-Release run report zero retained workflow artifacts.
