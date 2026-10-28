"""Manual GUI smoke test; synthetic bytes, NOT a playable video. No auto-accept."""
import argparse
import hashlib
import http.client
import json
from pathlib import Path
import ssl
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=47321)
    parser.add_argument("--fingerprint", required=True, help="Full SHA-256 cert fingerprint, NOT the 12-digit code")
    args = parser.parse_args()
    payload = b"DropMP4 synthetic GUI test; not a playable movie.\n" * 32768
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    def request(method, path, body, headers=None):
        client = http.client.HTTPSConnection(args.host, args.port, context=context, timeout=90)
        try:
            client.connect()
            actual = hashlib.sha256(client.sock.getpeercert(binary_form=True)).hexdigest()
            if actual != args.fingerprint.lower(): raise RuntimeError("Certificate pin mismatch")
            client.request(method, path, body, headers or {})
            response = client.getresponse()
            result = json.loads(response.read())
            if response.status not in (200, 201): raise RuntimeError(f"HTTP {response.status}: {result}")
            return result
        finally: client.close()
    digest = hashlib.sha256(payload).hexdigest()
    print("Waiting for GUI approval (60 seconds)…", flush=True)
    ticket = request("POST", "/v1/offers", json.dumps({
        "name": "SYNTHETIC-GUI-TEST.MOV", "size": len(payload),
        "sha256": digest, "sender": "Local developer smoke test"
    }), {"Content-Type": "application/json"})
    receipt = request("PUT", "/v1/files/" + ticket["id"], payload,
                      {"Authorization": "Bearer " + ticket["token"]})
    assert receipt["verified"] is True and receipt["sha256"] == digest and receipt["size"] == len(payload)
    print(json.dumps(receipt), flush=True)


if __name__ == "__main__": main()
