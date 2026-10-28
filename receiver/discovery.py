"""Bonjour DNS-SD advertisement on IPv4 LAN interfaces."""
import socket
from zeroconf import IPVersion, ServiceInfo, Zeroconf

SERVICE = "_dropmp4._tcp.local."


class Advertisement:
    def __init__(self, port: int, fingerprint: str, addresses: list[str] | None = None):
        addresses = addresses or sorted({item[4][0] for item in socket.getaddrinfo(
            socket.gethostname(), None, socket.AF_INET, socket.SOCK_STREAM)
            if not item[4][0].startswith("127.")})
        if not addresses:
            raise RuntimeError("No LAN IPv4 address found; connect Wi-Fi or use --ip")
        self.addresses = addresses
        self.zc = Zeroconf(ip_version=IPVersion.V4Only)
        host = "dropmp4-" + fingerprint[:12]
        self.info = ServiceInfo(SERVICE, f"{host}.{SERVICE}",
            addresses=[socket.inet_aton(ip) for ip in addresses], port=port,
            properties={"v": "1", "fp": fingerprint, "name": socket.gethostname()[:60]},
            server=host + ".local.")
        try:
            self.zc.register_service(self.info, allow_name_change=True)
        except Exception:
            self.zc.close()
            raise

    def close(self):
        self.zc.unregister_service(self.info)
        self.zc.close()
