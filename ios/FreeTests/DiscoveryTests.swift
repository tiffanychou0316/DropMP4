import XCTest
@testable import DropMP4Free

final class DiscoveryTests: XCTestCase {
    @MainActor
    func testRestartIgnoresPreviousBrowserFailure() {
        let discovery = Discovery()
        let oldBrowser = discovery.browser
        discovery.start()
        let status = discovery.status
        discovery.netServiceBrowser(oldBrowser, didNotSearch: [:])
        XCTAssertEqual(discovery.status, status)
        XCTAssertFalse(discovery.browser === oldBrowser)
        discovery.browser.stop()
    }

    @MainActor
    func testSearchFailurePreservesResolvedPeerStatus() {
        let discovery = Discovery()
        discovery.peers = [Peer(id: "test", name: "Test PC", host: "test.local.",
                                port: 8765, fingerprint: String(repeating: "a", count: 64))]
        discovery.netServiceBrowser(discovery.browser, didNotSearch: [:])
        XCTAssertEqual(discovery.peers.count, 1)
        XCTAssertTrue(discovery.status.hasPrefix("找到 1 台電腦"))
    }
}
