import socket
import threading
import unittest
from zeroconf import ServiceBrowser, ServiceListener, Zeroconf, IPVersion
from receiver.discovery import Advertisement, SERVICE


class DiscoveryTests(unittest.TestCase):
    def test_advertisement_is_discoverable_with_pin(self):
        found = threading.Event()
        records = []
        class Listener(ServiceListener):
            def add_service(self, zc, type_, name):
                info = zc.get_service_info(type_, name)
                if info and info.properties.get(b"fp") == b"a" * 64:
                    records.append(info)
                    found.set()
            def remove_service(self, *_): pass
            def update_service(self, *_): pass
        zc = Zeroconf(ip_version=IPVersion.V4Only)
        browser = ServiceBrowser(zc, SERVICE, Listener())
        advertisement = None
        try:
            advertisement = Advertisement(47321, "a" * 64)
            self.assertTrue(found.wait(10), "mDNS not observed on this network")
            self.assertEqual(records[0].port, 47321)
            self.assertTrue(records[0].parsed_addresses())
        finally:
            if advertisement: advertisement.close()
            browser.cancel()
            zc.close()


if __name__ == "__main__": unittest.main()
