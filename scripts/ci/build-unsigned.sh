#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
TEMP_ROOT="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
STAGING="$(mktemp -d "$TEMP_ROOT/location-spoofer.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
OUTPUT_DIR="$TEMP_ROOT/location-spoofer-output"
mkdir -p "$OUTPUT_DIR"
IPA="$OUTPUT_DIR/LocationSpoofer-unsigned.ipa"
rm -f "$IPA"

xcodebuild archive \
  -project location-spoofer.xcodeproj \
  -scheme location-spoofer \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -sdk iphoneos \
  -derivedDataPath "$ROOT/.build/DerivedData" \
  -archivePath "$STAGING/LocationSpoofer.xcarchive" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= EXPANDED_CODE_SIGN_IDENTITY= \
  DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= \
  CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER:-1}" \
  | tee "$TEMP_ROOT/location-spoofer-xcodebuild.log"

APP_SOURCE="$STAGING/LocationSpoofer.xcarchive/Products/Applications/location-spoofer.app"
test -d "$APP_SOURCE"
mkdir -p "$STAGING/Payload"
ditto "$APP_SOURCE" "$STAGING/Payload/location-spoofer.app"
python3 - "$STAGING/Payload" <<'PY'
import pathlib, plistlib, shutil, subprocess, sys
payload = pathlib.Path(sys.argv[1])
apps = list(payload.glob('*.app'))
if len(apps) != 1:
    raise SystemExit('Expected exactly one app in Payload')
app = apps[0]
extensions = list((app / 'PlugIns').glob('*.appex'))
if len(extensions) != 1:
    raise SystemExit('Expected exactly one embedded VPN extension')
versions = []
for bundle in [app, *extensions]:
    with (bundle / 'Info.plist').open('rb') as f:
        info = plistlib.load(f)
    executable = bundle / info['CFBundleExecutable']
    if not executable.is_file():
        raise SystemExit(f'Missing executable: {executable}')
    subprocess.run(['xcrun', 'lipo', str(executable), '-verify_arch', 'arm64'], check=True)
    versions.append((info['CFBundleShortVersionString'], info['CFBundleVersion']))
    if bundle.suffix == '.appex' and info.get('NSExtension', {}).get('NSExtensionPointIdentifier') != 'com.apple.networkextension.packet-tunnel':
        raise SystemExit('Missing packet-tunnel extension point')
if len(set(versions)) != 1:
    raise SystemExit('App and extension versions differ')
for path in list(app.rglob('_CodeSignature')):
    if path.is_dir():
        shutil.rmtree(path)
for path in app.rglob('embedded.mobileprovision'):
    path.unlink()
mach_o_magic = {bytes.fromhex(x) for x in ['feedface', 'cefaedfe', 'feedfacf', 'cffaedfe', 'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca']}
checked = 0
for path in app.rglob('*'):
    if not path.is_file() or path.is_symlink():
        continue
    if path.suffix == '.a' or path.name == 'golocationspoofer':
        raise SystemExit(f'Build-only Go artifact leaked into IPA: {path}')
    with path.open('rb') as f:
        if f.read(4) not in mach_o_magic:
            continue
    probe = subprocess.run(['codesign', '--display', str(path)], capture_output=True, text=True)
    if probe.returncode == 0:
        subprocess.run(['codesign', '--remove-signature', str(path)], check=True)
    probe = subprocess.run(['codesign', '--display', str(path)], capture_output=True, text=True)
    if probe.returncode == 0 or 'not signed at all' not in probe.stderr:
        raise SystemExit(f'Cannot verify unsigned Mach-O: {path}\n{probe.stderr}')
    checked += 1
if checked < 2:
    raise SystemExit('App and VPN Mach-O executables were not both checked')
print(f'Validated one app, one VPN extension, {checked} unsigned Mach-O files.')
PY
(
  cd "$STAGING"
  COPYFILE_DISABLE=1 /usr/bin/zip -q -r -y -X "$IPA" Payload
)
unzip -tq "$IPA"
python3 - "$IPA" <<'PY'
import hashlib, os, pathlib, sys, zipfile
ipa = pathlib.Path(sys.argv[1])
if len(list(ipa.parent.glob('*.ipa'))) != 1:
    raise SystemExit('Output directory must contain exactly one IPA')
with zipfile.ZipFile(ipa) as z:
    names = z.namelist()
    if z.testzip() is not None or not all(n.startswith('Payload/') for n in names):
        raise SystemExit('Invalid IPA structure or damaged archive')
    if any('_CodeSignature/' in n or n.endswith(('.mobileprovision', '.a')) for n in names):
        raise SystemExit('IPA contains a signature, profile or static archive')
sha = hashlib.sha256(ipa.read_bytes()).hexdigest()
print(f'{ipa.name}: {ipa.stat().st_size} bytes; SHA256 {sha}')
if os.environ.get('GITHUB_OUTPUT'):
    with open(os.environ['GITHUB_OUTPUT'], 'a') as f:
        f.write(f'path={ipa}\n')
if os.environ.get('GITHUB_STEP_SUMMARY'):
    with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as f:
        f.write(f'## One unsigned IPA\n\n`{ipa.name}` — {ipa.stat().st_size:,} bytes\n\nSHA256: `{sha}`\n\nApp + VPN extension included. All Mach-O binaries verified unsigned.\n')
PY
