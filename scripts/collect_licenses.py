"""Copy local upstream license texts without modifying them."""
import argparse
import importlib.metadata
from pathlib import Path
import shutil
import sys


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("portable", type=Path)
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    root = args.portable
    licenses = root / "licenses"
    licenses.mkdir(parents=True, exist_ok=True)
    for name in ["LICENSE", "README.md", "THIRD_PARTY_NOTICES.md"]:
        shutil.copy2(project / name, root / name)
    shutil.copytree(project / "docs", root / "docs", dirs_exist_ok=True)
    for name in ["cryptography", "cffi", "pycparser", "zeroconf", "ifaddr", "pyinstaller"]:
        dist = importlib.metadata.distribution(name)
        for entry in dist.files or []:
            if entry.name.upper().startswith(("LICENSE", "COPYING", "NOTICE")):
                source = Path(dist.locate_file(entry))
                if source.is_file(): shutil.copy2(source, licenses / (name + "-" + source.name))
    base = Path(sys.base_prefix)
    if (base / "LICENSE.txt").exists():
        shutil.copy2(base / "LICENSE.txt", licenses / "Python-LICENSE.txt")
    for name, path in [("Tcl", base / "tcl" / "tcl8.6" / "license.terms"),
                       ("Tk", base / "tcl" / "tk8.6" / "license.terms")]:
        if path.exists(): shutil.copy2(path, licenses / (name + "-license.terms"))
