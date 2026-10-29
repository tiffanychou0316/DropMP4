"""Package the standalone iPhone build for LOCAL re-signing. Never embeds credentials."""
import argparse
import hashlib
from pathlib import Path
import plistlib
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("app", type=Path)
parser.add_argument("output", type=Path)
args = parser.parse_args()
app = args.app.resolve()
with (app / "Info.plist").open("rb") as stream:
    info = plistlib.load(stream)
if info.get("CFBundleIdentifier") != "org.dropmp4.freetest" or "SharedGroup" in info:
    raise SystemExit("Refusing to package the App Group build as the free standalone variant")
if info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
    raise SystemExit("Expected an iPhoneOS build, not a Simulator app")
if (app / "PlugIns").exists() or (app / "embedded.mobileprovision").exists():
    raise SystemExit("Free package must not include extensions or provisioning profiles")
if not (app / info["CFBundleExecutable"]).is_file():
    raise SystemExit("Missing app executable")
args.output.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(args.output, "w", zipfile.ZIP_DEFLATED) as archive:
    for file in sorted(app.rglob("*")):
        if file.is_symlink():
            raise SystemExit("Unexpected symlink in app bundle")
        if file.is_file():
            archive.write(file, Path("Payload") / app.name / file.relative_to(app))
digest = hashlib.sha256(args.output.read_bytes()).hexdigest()
args.output.with_suffix(".ipa.sha256").write_text(f"{digest}  {args.output.name}\n", encoding="ascii")
print(f"Packaged unsigned iPhone IPA: {args.output.name}; SHA-256 {digest}")
