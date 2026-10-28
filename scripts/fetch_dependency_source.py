"""Include exact unmodified LGPL dependency source in the portable distribution."""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    metadata_url = "https://pypi.org/pypi/zeroconf/0.148.0/json"
    with urllib.request.urlopen(metadata_url, timeout=30) as response:
        metadata = json.load(response)
    source = next(item for item in metadata["urls"] if item["packagetype"] == "sdist")
    if not source["url"].startswith("https://files.pythonhosted.org/"):
        raise RuntimeError("Unexpected package source host")
    with urllib.request.urlopen(source["url"], timeout=30) as response:
        data = response.read(10 * 1024 * 1024)
    if hashlib.sha256(data).hexdigest() != source["digests"]["sha256"]:
        raise RuntimeError("Source archive digest mismatch")
    args.destination.mkdir(parents=True, exist_ok=True)
    target = args.destination / Path(source["filename"]).name
    target.write_bytes(data)
    print(target.name + " SHA-256 " + hashlib.sha256(data).hexdigest())
