"""HTTPS protocol. No payload is accepted before an explicit local approval."""
from __future__ import annotations

import datetime as dt
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import ssl
import threading
import time
from dataclasses import dataclass, field
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Callable
import uuid

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

MAX_FILE = 20 * 1024**3
CHUNK = 256 * 1024


def identity(directory: Path) -> tuple[Path, Path, str]:
    directory.mkdir(parents=True, exist_ok=True)
    cert, key = directory / "certificate.pem", directory / "private-key.pem"
    if not cert.exists() or not key.exists():
        private = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "DropMP4")])
        now = dt.datetime.now(dt.timezone.utc)
        certificate = (x509.CertificateBuilder().subject_name(subject).issuer_name(subject)
                       .public_key(private.public_key()).serial_number(x509.random_serial_number())
                       .not_valid_before(now - dt.timedelta(minutes=5))
                       .not_valid_after(now + dt.timedelta(days=3650))
                       .sign(private, hashes.SHA256()))
        # State directory belongs to this user's profile; never ship these files.
        with key.open("wb") as output:
            output.write(private.private_bytes(serialization.Encoding.PEM,
                         serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
        try:
            key.chmod(0o600)
        except OSError:
            pass
        cert.write_bytes(certificate.public_bytes(serialization.Encoding.PEM))
    fingerprint = x509.load_pem_x509_certificate(cert.read_bytes()).fingerprint(hashes.SHA256()).hex()
    return cert, key, fingerprint


def safe_name(name: str) -> str:
    if not isinstance(name, str) or not name or len(name) > 240:
        raise ValueError("Invalid filename")
    if "/" in name or "\\" in name or any(ord(c) < 32 for c in name):
        raise ValueError("Filename must not contain paths or control characters")
    cleaned = re.sub(r'[<>:"|?*]', "_", name).rstrip(" .")
    if not cleaned or cleaned in {".", ".."} or Path(cleaned).suffix.lower() not in {".mov", ".mp4"}:
        raise ValueError("Only MOV and MP4 files are accepted")
    stem = cleaned.split(".")[0].upper()
    if stem in {"CON", "PRN", "AUX", "NUL", *(f"COM{i}" for i in range(10)), *(f"LPT{i}" for i in range(10))}:
        cleaned = "_" + cleaned
    return cleaned


@dataclass
class Offer:
    name: str
    size: int
    sha256: str
    sender: str
    id: str = field(default_factory=lambda: uuid.uuid4().hex)
    token: str = field(default_factory=lambda: secrets.token_hex(32))
    answer: threading.Event = field(default_factory=threading.Event)
    accepted: bool = False
    expires: float = 0
    uploading: bool = False


class Receiver:
    def __init__(self, destination: Path, approve: Callable[[Offer], None],
                 event: Callable[[str, dict], None] = lambda *_: None,
                 approval_timeout: float = 60, token_ttl: float = 120):
        self.destination = destination.resolve()
        self.destination.mkdir(parents=True, exist_ok=True)
        self.approve, self.event = approve, event
        self.approval_timeout, self.token_ttl = approval_timeout, token_ttl
        self.lock = threading.Lock()
        self.active: Offer | None = None

    def offer(self, data: dict) -> tuple[int, dict]:
        try:
            name = safe_name(data["name"])
            size, digest = data["size"], data["sha256"]
            if type(size) is not int or not 0 < size <= MAX_FILE:
                raise ValueError("File size must be between 1 byte and 20 GiB")
            if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
                raise ValueError("Invalid SHA-256")
            sender = data.get("sender", "iPhone")
            if not isinstance(sender, str) or len(sender) > 100 or any(ord(c) < 32 for c in sender):
                raise ValueError("Invalid sender")
            if shutil.disk_usage(self.destination).free < size + 64 * 1024**2:
                return 507, {"error": "Not enough free disk space"}
        except (ValueError, KeyError, TypeError) as error:
            return 400, {"error": str(error)}
        with self.lock:
            if (self.active and self.active.answer.is_set() and not self.active.uploading
                    and self.active.expires > 0 and self.active.expires < time.monotonic()):
                self.active = None
            if self.active:
                return 409, {"error": "Receiver busy"}
            offer = Offer(name, size, digest, sender)
            self.active = offer
        try:
            self.approve(offer)
            answered = offer.answer.wait(self.approval_timeout)
            with self.lock:
                if not answered or not offer.accepted:
                    if self.active is offer:
                        self.active = None
                    return (408 if not answered else 403), {"error": "Approval timed out" if not answered else "Declined"}
                offer.expires = time.monotonic() + self.token_ttl
            return 201, {"id": offer.id, "token": offer.token, "expiresIn": self.token_ttl}
        except Exception:
            with self.lock:
                if self.active is offer:
                    self.active = None
            raise

    def claim(self, id_: str, token: str, size: int) -> Offer | None:
        with self.lock:
            item = self.active
            if (not item or item.id != id_ or not item.accepted or not item.answer.is_set()
                    or item.uploading or item.expires < time.monotonic() or item.size != size
                    or not hmac.compare_digest(item.token, token)):
                return None
            item.uploading = True
            return item

    def save(self, offer: Offer, stream) -> dict:
        partial = self.destination / f".{offer.id}.partial"
        final = self.destination / f"{offer.id[:12]}_{offer.name}"
        digest = hashlib.sha256()
        received = 0
        started = time.monotonic()
        last_event = 0.0
        try:
            with partial.open("xb") as output:
                while received < offer.size:
                    if time.monotonic() - started > 3600:
                        raise ValueError("Transfer exceeded one hour")
                    block = stream.read(min(CHUNK, offer.size - received))
                    if not block:
                        raise ValueError("Transfer interrupted")
                    output.write(block)
                    digest.update(block)
                    received += len(block)
                    now = time.monotonic()
                    if now - last_event >= 0.15 or received == offer.size:
                        self.event("progress", {"received": received, "size": offer.size, "name": offer.name})
                        last_event = now
                output.flush()
                os.fsync(output.fileno())
            if not hmac.compare_digest(digest.hexdigest(), offer.sha256):
                raise ValueError("SHA-256 mismatch; incomplete file discarded")
            # On Windows rename is atomic and refuses existing destinations.
            # POSIX rename overwrites; a same-volume hard link is used there instead.
            if os.name == "nt":
                os.rename(partial, final)
            else:
                os.link(partial, final)
            result = {"name": final.name, "size": received, "sha256": digest.hexdigest(), "verified": True}
            self.event("complete", result)
            return result
        finally:
            partial.unlink(missing_ok=True)
            with self.lock:
                if self.active is offer:
                    self.active = None


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address, receiver: Receiver, cert: Path, key: Path):
        super().__init__(address, Handler)
        self.receiver = receiver
        self.slots = threading.BoundedSemaphore(8)
        self.context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        self.context.minimum_version = ssl.TLSVersion.TLSv1_2
        self.context.load_cert_chain(cert, key)

    def process_request(self, request, client_address):
        if not self.slots.acquire(blocking=False):
            request.close()
            return
        try:
            super().process_request(request, client_address)
        except Exception:
            self.slots.release()
            raise

    def process_request_thread(self, request, client_address):
        try:
            request.settimeout(20)
            secure = self.context.wrap_socket(request, server_side=True)
            super().process_request_thread(secure, client_address)
        except (OSError, ssl.SSLError):
            request.close()
        finally:
            self.slots.release()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, *_):
        pass

    def reply(self, status: int, data: dict):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)

    def length(self) -> int:
        values = self.headers.get_all("Content-Length", [])
        if len(values) != 1 or not re.fullmatch(r"[0-9]{1,12}", values[0]) or self.headers.get("Transfer-Encoding"):
            raise ValueError("A single Content-Length is required; chunked uploads unsupported")
        return int(values[0])

    def do_GET(self):
        self.reply(200, {"app": "DropMP4", "version": 1}) if self.path == "/v1/health" else self.reply(404, {"error": "Not found"})

    def do_POST(self):
        if self.path != "/v1/offers":
            self.reply(404, {"error": "Not found"})
            return
        try:
            size = self.length()
            if not 0 < size <= 16 * 1024:
                raise ValueError("Offer too large")
            data = json.loads(self.rfile.read(size))
            if not isinstance(data, dict):
                raise ValueError("Expected an object")
            status, response = self.server.receiver.offer(data)
            self.reply(status, response)
        except (ValueError, OSError) as error:
            self.reply(400, {"error": str(error)})

    def do_PUT(self):
        try:
            size = self.length()
            match = re.fullmatch(r"/v1/files/([0-9a-f]{32})", self.path)
            auth = self.headers.get("Authorization", "")
            if not match or not auth.startswith("Bearer "):
                self.reply(403, {"error": "Unauthorized"})
                return
            offer = self.server.receiver.claim(match[1], auth[7:], size)
            if not offer:
                self.reply(403, {"error": "Invalid, expired, or consumed authorization"})
                return
            self.reply(200, self.server.receiver.save(offer, self.rfile))
        except (ValueError, OSError) as error:
            self.server.receiver.event("error", {"message": str(error)})
            self.reply(422, {"error": str(error)})
