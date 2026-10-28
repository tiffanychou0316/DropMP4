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
    private let browser = NetServiceBrowser()
    private var services: [NetService] = []

    override init() { super.init(); browser.delegate = self }
    func start() {
        browser.stop()
        services.forEach { $0.stop() }
        services.removeAll()
        peers.removeAll()
        status = "正在尋找同一個 Wi-Fi 的 Windows 電腦…"
        browser.searchForServices(ofType: "_dropmp4._tcp.", inDomain: "local.")
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 10)
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        peers.removeAll { $0.id == service.name }
        services.removeAll { $0 == service }
        service.stop()
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        status = "搜尋失敗。請在設定允許 DropMP4 存取區域網路，再重新搜尋。"
    }
    func netServiceDidResolveAddress(_ sender: NetService) {
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
        status = "電腦回應逾時，請確認 Windows 防火牆與 Wi-Fi，再重新搜尋。"
    }
}
