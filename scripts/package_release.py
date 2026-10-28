"""Create source/portable ZIPs; excludes caches, state, signing data and build output."""
import argparse
import hashlib
from pathlib import Path
import zipfile


def archive(directory: Path, destination: Path, source=False):
    excluded = {"__pycache__", ".venv", ".git", "build", "dist", "DerivedData", ".DS_Store"}
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as output:
        for file in sorted(directory.rglob("*")):
            relative = file.relative_to(directory)
            if any(part in excluded for part in relative.parts): continue
            if source and any(part.endswith(".xcodeproj") for part in relative.parts): continue
            if file.is_file() and file.suffix not in {".pyc", ".pfx", ".p12", ".mobileprovision"}:
                output.write(file, Path(directory.name) / relative)
    print(f"{destination.name}: {destination.stat().st_size:,} bytes; SHA-256 {hashlib.sha256(destination.read_bytes()).hexdigest()}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--portable", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    archive(project, args.output / "DropMP4-source.zip", source=True)
    archive(args.portable, args.output / "DropMP4-Windows.zip")
