# DropMP4 protocol v1

All endpoints are HTTPS only; no cleartext fallback, no redirects. Server certificate is self-signed. iOS pins SHA-256 of the full DER leaf certificate to the fingerprint advertised by the selected Bonjour service. DNS-SD itself is unauthenticated: users MUST compare the first 12 hex characters, grouped `AAAA-BBBB-CCCC`, with the receiver screen every time. Without comparison, an active LAN attacker can impersonate a receiver. Tokens alone do not establish receiver identity.

## Discovery

DNS-SD service `_dropmp4._tcp.local.`; SRV advertises dynamic/configured HTTPS port (default 47321). TXT: `v=1`, `fp=<64 lowercase hex>`, `name=<display computer name>`. IPv4 LAN supported. iOS resolves the `.local.` hostname via Bonjour. No payload or token is published in TXT.

## Offer

`POST /v1/offers`, JSON (max 16 KiB):

```json
{"name":"IMG_0001.mov","size":123456,"sha256":"<64 lowercase hex>","sender":"iPhone"}
```

Size 1..20 GiB; only `.mov` / `.mp4` filenames; no paths or control characters. Receiver checks free space (size + 64 MiB). Content is opaque; filename extension is not content validation. Do not automatically open received files.

Wait up to 60 seconds for local desktop user approval. Reject: 403, timeout: 408, busy: 409, metadata error: 400, insufficient disk: 507. Success: 201:

```json
{"id":"<32 hex>","token":"<64 hex>","expiresIn":120}
```

One active offer/upload at a time. Accepted upload must start within 120 seconds. There is no permanent pairing, listing of user files, or auto-accept mode in the product.

## Payload

`PUT /v1/files/<id>` with `Authorization: Bearer <token>`, `Content-Type: application/octet-stream`, single `Content-Length` equal to approved size. Chunked encoding is rejected. Receiver checks authorization before reading body, consumes the token when upload starts, and streams in 256 KiB chunks. Idle read timeout 20 seconds; total upload limit one hour. Invalid/expired/consumed token: 403. A rejected large body can cause a client connection error because server closes without consuming unauthorized bytes; treat as a failed transfer, not success.

Receiver writes `.<id>.partial` under the destination, verifies exact advertised size and SHA-256, flushes/fsyncs, then atomically publishes to `<id-prefix>_<safe-name>` without overwrite. Windows uses same-directory `os.rename` (which refuses existing targets on Windows); other platforms use a same-volume hard link to avoid POSIX rename overwrites. On normal exception the partial is discarded and the active slot cleared. No final file exists on a digest mismatch. Crash leftovers are not exposed as completed files.

200 receipt after publish:

```json
{"name":"ab12cd34ef56_IMG_0001.mov","size":123456,"sha256":"<64 hex>","verified":true}
```

Client checks all three of verified, size, and digest before displaying success. An interrupted response can leave a valid receiver file while sender reports failure; a retry uses a new filename rather than overwriting. Size/hash/storage errors: 422 with `{"error":"..."}`. Server does not inspect codec or transcode. Client remux is independent of this transport protocol.

`GET /v1/health` returns `{"app":"DropMP4","version":1}` for diagnostics only.

## Boundaries

Eight concurrent HTTPS handler slots, one active transfer, bounded metadata/body chunks. TLS handshakes occur in per-request threads so a stalled handshake does not freeze accept(). No mutual client certificate; sender identity text is untrusted. The Windows user approves each offered filename/size and compares the receiver code with the phone. A malicious LAN peer can still generate unsolicited prompts or occupy limited connection slots; do not expose the port to the Internet. Private key stored under the receiver user's profile and not included in deliverables. No cloud dependencies at runtime.
