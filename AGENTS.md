# AGENTS.md

## Owner requirements
- Read this file before editing and keep it updated with decisions, verification results and recovery details.
- Produce exactly one unsigned arm64 IPA containing the app and its VPN extension. Do not add a signed/TestFlight build, a build matrix or duplicate IPA artifacts.
- Publish exactly one GitHub Release using the stable tag `latest`. Replace its IPA asset in place, remove historical Releases/release tags, and do not retain GitHub Actions IPA artifacts. Workflow-run logs may remain for diagnostics.
- Versioning follows the previously chosen calendar format `ISO-year.ISO-week.ISO-weekday` in Europe/Rome time, e.g. `2026.39.3`. Use the same value for `CFBundleShortVersionString`, `CFBundleVersion` and the Release title.
- Automatic builds run only for app/extension source, resources, Go source/dependencies, project.yml or build-script changes on main. Markdown, README, AGENTS.md and workflow-only edits must not automatically compile. Use Run workflow when validating CI-only edits.
- Keep Go dependencies, the generated Go library/header pair and Xcode incremental build caches. Cache keys must include the Apple toolchain and relevant source inputs.
- Combine related changes into one commit on main where possible; never force-push the main branch to overwrite someone else's work. The stable Release tag `latest` is intentionally moved to the verified build commit.
- Keep the recovery copy in `SiNaPsEr0x/Pubblici/ios-location-spoofer/backup/` up to date when changing CI. Do not put backup YAML under Pubblici/.github/workflows. Never copy signing material or tokens.

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

### 2026-09-23 runtime fix: coordinate handoff
- A real-device test showed `Go proxy ready but coord confirmation timed out`. The proxy was listening, but activation incorrectly depended on cross-process App Group/UserDefaults synchronization plus IPC confirmation.
- Coordinates are now authoritative in `NETunnelProviderSession.startTunnel(options:)`: the app passes `spoofEnabled`, `spoofLatitude` and `spoofLongitude`; `PacketTunnelProvider.startTunnel(options:)` uses those values directly and only falls back to App Group storage when options are absent.
- IPC `getCoords` remains diagnostic only and must never block activation. TCP readiness remains the runtime gate because Go receives the explicit coordinates before starting its HTTP proxy.
- Keep this direct start-options handoff when merging upstream changes.

### Runtime fix verification
- Run 5 (`35914949898`) on commit `1edb09f33fddd204dab1c1d48c1bb28e714d7560` completed successfully.
- Xcode compiled the direct `NETunnelProviderSession.startTunnel(options:)` coordinate handoff for both cold start and hot restart.
- The Release `latest` was replaced successfully and now points to commit `1edb09f33fddd204dab1c1d48c1bb28e714d7560`.
- Current IPA: `LocationSpoofer-unsigned.ipa`, 4,207,901 bytes, SHA-256 `0711839ed3dc1c9da2bcc43bb0907cadc4937c0eba16435a84aaf661a1c91d10`.
- Real-device behavior still requires installing/signing this new IPA and retrying location spoofing; CI verifies build/package correctness, not GPS behavior on-device.

### 2026-09-23 iOS 27 / persistent VPN fix
- Found an explicit app-side `stopVPNTunnel()` after the restart-location tutorial. This was the direct cause of the VPN appearing to disable itself; it has been removed.
- Spoofing now enables `NEOnDemandRuleConnect` with `isOnDemandEnabled = true`. The app also explicitly reconnects on launch and after an unexpected `.disconnected` status while spoofing is active.
- Disabling spoofing first disables/saves On Demand and only then stops the tunnel, preventing immediate unwanted reconnects.
- The Packet Tunnel is now proxy-only: no default IPv4 route is claimed because `packetFlow` is intentionally unused. HTTP/S proxy settings use catch-all `matchDomains = [""]`; non-proxy IP traffic stays on the normal interface.
- The old custom DNS override was removed. This avoids forcing Italian/iOS 27 devices through the upstream Chinese DNS pair and reduces interaction with iOS 27 Connectivity Assist.
- The tunnel stores the last `NEProviderStopReason` in the App Group for future diagnostics.
- Apple iOS 27 release notes do not document a breaking Packet Tunnel API change. Current Apple Developer Forum reports do describe intermittent NetworkExtension path bypass with Connectivity Assist, so keep the proxy-only routing and On Demand recovery logic unless a confirmed Apple fix supersedes it.

### iOS 27 build verification
- Run 6 (`35916907202`) on commit `bdea353c758c3f44f5bacca7a182bfa0d19f1377` completed successfully.
- The iOS 27 proxy-only tunnel, Connect On Demand, auto-start/reconnect, and removal of the post-tutorial `stopVPNTunnel()` all compiled and packaged successfully.
- Release `latest` was replaced with one asset: `LocationSpoofer-unsigned.ipa`, 4,212,400 bytes, SHA-256 `d7f9e4933559318d67ce95004e4dbca691e0ade981f4c18184ca675f4b6baa8d`.
- CI cannot prove the location spoof succeeds on a physical iOS 27 device; the next validation is to sign/install this exact IPA and retry. If it still fails, inspect the saved tunnel stop reason and diagnostics rather than reverting the persistent-VPN changes.
