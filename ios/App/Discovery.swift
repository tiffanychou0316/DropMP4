import Foundation
import Combine

struct Peer: Identifiable, Equatable {
    let id: String
    let name: String
    let host: String
    let port: Int
    let fingerprint: String
    var code: String {
        stride(from: 0, to: 12, by: 4).map { offset in
            String(fingerprint.dropFirst(offset).prefix(4)).uppercased()
        }.joined(separator: "-")
    }
}

final class Discovery: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {
    @Published var peers: [Peer] = []
    @Published var status = "正在尋找同一個 Wi-Fi 的 Windows 電腦…"
    private(set) var browser = NetServiceBrowser()
    private var services: [NetService] = []

    override init() { super.init(); browser.delegate = self }
    func start() {
        browser.delegate = nil
        browser.stop()
        services.forEach { $0.delegate = nil; $0.stop() }
        services.removeAll()
        peers.removeAll()
        status = "正在尋找同一個 Wi-Fi 的 Windows 電腦…"
        browser = NetServiceBrowser()
        browser.delegate = self
        browser.searchForServices(ofType: "_dropmp4._tcp.", inDomain: "local.")
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard browser === self.browser else { return }
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 10)
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        guard browser === self.browser else { return }
        peers.removeAll { $0.id == service.name }
        services.removeAll { $0 == service }
        service.stop()
        status = peers.isEmpty ? "尚未找到電腦，請確認接收端已開啟且位於同一個 Wi-Fi。" : "找到 \(peers.count) 台電腦"
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        guard browser === self.browser else { return }
        if !peers.isEmpty {
            status = "找到 \(peers.count) 台電腦；搜尋已停止，可重新搜尋。"
        } else {
            status = "搜尋暫停。請確認區域網路權限與 Wi-Fi，再重新搜尋。"
        }
    }
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard services.contains(where: { $0 === sender }) else { return }
        guard let txt = sender.txtRecordData(), let host = sender.hostName else { return }
        let values = NetService.dictionary(fromTXTRecord: txt)
        guard let version = values["v"], String(data: version, encoding: .utf8) == "1",
              let data = values["fp"], let fp = String(data: data, encoding: .utf8),
              fp.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
              (1...65535).contains(sender.port) else { return }
        let name = values["name"].flatMap { String(data: $0, encoding: .utf8) } ?? sender.name
        peers.removeAll { $0.id == sender.name }
        peers.append(Peer(id: sender.name, name: name, host: host, port: sender.port, fingerprint: fp))
        status = "找到 \(peers.count) 台電腦"
    }
    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        guard services.contains(where: { $0 === sender }), peers.isEmpty else { return }
        status = "電腦回應逾時，請確認 Windows 防火牆與 Wi-Fi，再重新搜尋。"
    }
}
