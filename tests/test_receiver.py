import hashlib
import http.client
import io
import json
from pathlib import Path
import socket
import ssl
import tempfile
import threading
import time
import unittest

from receiver.core import Receiver, Server, identity, safe_name


class ReceiverTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.data = b"test MOV compressed bytes\x00\xff" * 50000
        self.events = []
        self.approval = True
        self.asked = 0
        def approve(offer):
            self.asked += 1
            if self.approval is not None:
                offer.accepted = self.approval
                offer.answer.set()
        self.receiver = Receiver(self.root / "received", approve,
            lambda kind, data: self.events.append((kind, data)), approval_timeout=0.08, token_ttl=0.2)
        cert, key, self.fp = identity(self.root / "identity")
        self.server = Server(("127.0.0.1", 0), self.receiver, cert, key)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.tmp.cleanup()

    def request(self, method, path, body=None, headers=None):
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE
        client = http.client.HTTPSConnection("127.0.0.1", self.server.server_port, context=context, timeout=3)
        client.connect()
        # Same full DER certificate pin used by iOS, not merely encryption.
        actual = hashlib.sha256(client.sock.getpeercert(binary_form=True)).hexdigest()
        self.assertEqual(self.fp, actual)
        client.request(method, path, body=body, headers=headers or {})
        response = client.getresponse()
        result = response.status, json.loads(response.read())
        client.close()
        return result

    def metadata(self, **changes):
        result = {"name": "IMG_0001.MOV", "size": len(self.data),
                  "sha256": hashlib.sha256(self.data).hexdigest(), "sender": "iPhone"}
        result.update(changes)
        return result

    def offer(self, **changes):
        return self.request("POST", "/v1/offers", json.dumps(self.metadata(**changes)),
                            {"Content-Type": "application/json"})

    def upload(self, ticket, data=None, token=None, headers_only=False):
        headers = {"Authorization": "Bearer " + (ticket["token"] if token is None else token)}
        if headers_only:
            # Verify authorization is checked before reading any payload bytes.
            headers["Content-Length"] = str(len(self.data))
            return self.request("PUT", "/v1/files/" + ticket["id"], b"", headers)
        return self.request("PUT", "/v1/files/" + ticket["id"], self.data if data is None else data, headers)

    def test_encrypted_transfer_and_receipt(self):
        status, ticket = self.offer()
        self.assertEqual(status, 201)
        status, receipt = self.upload(ticket)
        self.assertEqual(status, 200)
        self.assertTrue(receipt["verified"])
        self.assertEqual(receipt["sha256"], self.metadata()["sha256"])
        self.assertEqual((self.receiver.destination / receipt["name"]).read_bytes(), self.data)
        self.assertEqual(self.asked, 1)
        self.assertIn("progress", [kind for kind, _ in self.events])
        self.assertEqual(list(self.receiver.destination.glob("*.partial")), [])

    def test_decline_never_creates_file(self):
        self.approval = False
        self.assertEqual(self.offer()[0], 403)
        self.assertEqual(list(self.receiver.destination.iterdir()), [])

    def test_no_response_times_out(self):
        self.approval = None
        self.assertEqual(self.offer()[0], 408)
        self.assertIsNone(self.receiver.active)

    def test_reject_corruption_and_recover(self):
        _, ticket = self.offer()
        corrupt = bytes([self.data[0] ^ 1]) + self.data[1:]
        self.assertEqual(self.upload(ticket, corrupt)[0], 422)
        self.assertEqual(list(self.receiver.destination.iterdir()), [])
        self.assertIsNone(self.receiver.active)
        self.assertEqual(self.offer()[0], 201)

    def test_reject_wrong_size(self):
        _, ticket = self.offer()
        self.assertEqual(self.upload(ticket, b"short")[0], 403)
        self.assertEqual(list(self.receiver.destination.iterdir()), [])

    def test_reject_wrong_token_and_replay(self):
        _, ticket = self.offer()
        self.assertEqual(self.upload(ticket, token="bad", headers_only=True)[0], 403)
        self.assertEqual(self.upload(ticket)[0], 200)
        self.assertEqual(self.upload(ticket, headers_only=True)[0], 403)

    def test_expired_token(self):
        _, ticket = self.offer()
        time.sleep(0.25)
        self.assertEqual(self.upload(ticket, headers_only=True)[0], 403)
        self.assertEqual(self.offer()[0], 201)

    def test_busy(self):
        self.assertEqual(self.offer()[0], 201)
        self.assertEqual(self.offer()[0], 409)

    def test_unauthorized_upload(self):
        self.assertEqual(self.request("PUT", "/v1/files/" + "a" * 32, b"x")[0], 403)

    def test_metadata_validation(self):
        cases = [{"name": "../escape.mov"}, {"name": "C:\\escape.mov"}, {"name": "test.exe"},
                 {"name": "x\n.mov"}, {"size": True}, {"size": -1}, {"size": 21 * 1024**3},
                 {"sha256": "wrong"}, {"sender": "x\r\ny"}]
        for case in cases:
            with self.subTest(case=case): self.assertEqual(self.offer(**case)[0], 400)
        self.assertEqual(self.asked, 0)

    def test_interrupted_stream_removes_partial(self):
        _, ticket = self.offer()
        offer = self.receiver.claim(ticket["id"], ticket["token"], len(self.data))
        with self.assertRaisesRegex(ValueError, "interrupted"):
            self.receiver.save(offer, io.BytesIO(b"partial"))
        self.assertEqual(list(self.receiver.destination.iterdir()), [])
        self.assertIsNone(self.receiver.active)

    def test_duplicate_filename_preserves_both(self):
        _, one = self.offer()
        self.assertEqual(self.upload(one)[0], 200)
        _, two = self.offer()
        self.assertEqual(self.upload(two)[0], 200)
        self.assertEqual(len(list(self.receiver.destination.iterdir())), 2)

    def test_identity_persists(self):
        self.assertEqual(identity(self.root / "identity")[2], self.fp)

    def test_windows_reserved_names(self):
        self.assertEqual(safe_name("CON.mov"), "_CON.mov")
        self.assertEqual(safe_name("a:b.mp4"), "a_b.mp4")

    def test_plaintext_is_not_http(self):
        with socket.create_connection(("127.0.0.1", self.server.server_port), timeout=2) as client:
            client.sendall(b"GET /v1/health HTTP/1.0\r\n\r\n")
            try: data = client.recv(100)
            except (ConnectionResetError, ConnectionAbortedError): data = b""
            self.assertNotIn(b"200 OK", data)


if __name__ == "__main__":
    unittest.main()
