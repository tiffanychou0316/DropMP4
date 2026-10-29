import Foundation

enum DropError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

enum Inbox {
    static func directory() throws -> URL {
        #if DROPMP4_FREE_TEST
        let root = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        // Documents/Inbox is reserved by iOS for incoming documents and is not writable.
        let url = root.appendingPathComponent("ImportedVideos", isDirectory: true)
        #else
        guard let group = Bundle.main.object(forInfoDictionaryKey: "SharedGroup") as? String,
              let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw DropError.message("App Group 尚未設定，請檢查兩個 Target 的簽署設定。")
        }
        let url = root.appendingPathComponent("Inbox", isDirectory: true)
        #endif
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

enum AppFeatures {
    #if DROPMP4_FREE_TEST
    static let localImportOnly = true
    static let title = "DropMP4 測試版"
    static let importHint = "先將照片中的影片儲存到「檔案 → 我的 iPhone」，再按「從檔案匯入影片」。此免費測試版暫不含照片分享擴充功能。"
    #else
    static let localImportOnly = false
    static let title = "DropMP4"
    static let importHint = "從照片的分享選單匯入影片，再回到這裡傳送。"
    #endif
}
