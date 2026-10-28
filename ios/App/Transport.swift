import Foundation
import CryptoKit
import Security

enum FileDigest {
    static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 256 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

final class Transport: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {
    private let peer: Peer
    private let progress: (Double) -> Void
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = 3600
        config.httpMaximumConnectionsPerHost = 1
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    init(peer: Peer, progress: @escaping (Double) -> Void) { self.peer = peer; self.progress = progress }

    private func url(_ path: String) throws -> URL {
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = peer.host
        parts.port = peer.port
        parts.path = path
        guard let url = parts.url else { throw DropError.message("接收端位址錯誤。") }
        return url
    }

    func send(_ file: URL, digest: String) async throws {
        defer { session.invalidateAndCancel() }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        var offer = URLRequest(url: try url("/v1/offers"))
        offer.httpMethod = "POST"
        offer.setValue("application/json", forHTTPHeaderField: "Content-Type")
        offer.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": file.lastPathComponent, "size": size, "sha256": digest, "sender": "iPhone"
        ])
        let (data, response) = try await session.data(for: offer)
        try check(response, data)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? String, let token = object["token"] as? String,
              id.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil else {
            throw DropError.message("接收端回應格式不正確。")
        }
        var upload = URLRequest(url: try url("/v1/files/" + id))
        upload.httpMethod = "PUT"
        upload.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        upload.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        upload.setValue(String(size), forHTTPHeaderField: "Content-Length")
        let (receipt, result) = try await session.upload(for: upload, fromFile: file)
        try check(result, receipt)
        guard let object = try JSONSerialization.jsonObject(with: receipt) as? [String: Any],
              object["verified"] as? Bool == true,
              object["sha256"] as? String == digest,
              (object["size"] as? NSNumber)?.int64Value == Int64(size) else {
            throw DropError.message("接收校驗回報不一致，請在 Windows 檢查檔案。")
        }
    }

    private func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw DropError.message(object?["error"] as? String ?? "接收端拒絕或傳輸失敗。")
        }
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let certificate = SecTrustGetCertificateAtIndex(trust, 0) else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        let der = SecCertificateCopyData(certificate) as Data
        let fingerprint = SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
        guard fingerprint == peer.fingerprint else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if task.originalRequest?.httpMethod == "PUT", totalBytesExpectedToSend > 0 {
            progress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
