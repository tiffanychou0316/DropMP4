import Foundation

enum DropError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

enum Inbox {
    static func directory() throws -> URL {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "SharedGroup") as? String,
              let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw DropError.message("App Group 尚未設定，請檢查兩個 Target 的簽署設定。")
        }
        let url = root.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // Must be called inside loadFileRepresentation's completion: its URL is temporary.
    static func importFile(_ source: URL) throws -> URL {
        guard ["mov", "mp4"].contains(source.pathExtension.lowercased()) else {
            throw DropError.message("目前只接受 MOV 或 MP4 影片。")
        }
        let name = String(source.deletingPathExtension().lastPathComponent.prefix(100))
        let target = try directory().appendingPathComponent(
            "\(UUID().uuidString.prefix(8))_\(name).\(source.pathExtension.lowercased())")
        let staging = target.appendingPathExtension("importing")
        do {
            try FileManager.default.copyItem(at: source, to: staging)
            try FileManager.default.moveItem(at: staging, to: target)
            return target
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    static func files() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory(), includingPropertiesForKeys: nil)
            .filter { ["mov", "mp4"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
