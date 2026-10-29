import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SenderModel: ObservableObject {
    @Published var files: [URL] = []
    @Published var selected: URL?
    @Published var prepared: PreparedVideo?
    @Published var status = AppFeatures.importHint
    @Published var busy = false
    @Published var fraction: Double = 0
    @Published var failure: String?
    private var work: Task<Void, Never>?

    func refresh() {
        do { files = try Inbox.files() } catch { failure = error.localizedDescription }
    }
    func choose(_ url: URL) {
        clearPrepared()
        selected = url
        busy = true
        status = "檢查影片與免重編碼封裝相容性…"
        work = Task {
            defer { busy = false }
            do {
                let result = try await Remux.prepare(url)
                try Task.checkCancellation()
                prepared = result
                status = result.message
            } catch {
                if Task.isCancelled { status = "已取消；原始影片已保留。" }
                else { status = "無法確認可免重編碼轉 MP4：\(error.localizedDescription)\n你仍可選擇傳送原始 MOV。" }
            }
        }
    }
    func useOriginal() {
        guard let selected else { return }
        clearPrepared()
        prepared = PreparedVideo(url: selected, message: "傳送原始 \(selected.pathExtension.uppercased())，完整保留匯入檔案。", remuxed: false)
        status = prepared!.message
    }
    func send(to peer: Peer) {
        guard let file = prepared?.url else { return }
        busy = true
        fraction = 0
        status = "計算檔案校驗碼…"
        work = Task {
            defer { busy = false }
            do {
                let digest = try await Remux.digest(file)
                try Task.checkCancellation()
                status = "請在 Windows 確認接收（60 秒內）。傳送期間請保持 App 在前景。"
                let client = Transport(peer: peer) { [weak self] fraction in
                    Task { @MainActor in
                        self?.fraction = fraction
                        self?.status = fraction < 1 ? "傳送中，請保持 App 在前景…" : "Windows 正在完成檔案校驗…"
                    }
                }
                try await client.send(file, digest: digest)
                status = "傳送完成，Windows 已確認檔案大小與 SHA-256 一致。"
                fraction = 1
            } catch {
                status = Task.isCancelled ? "已取消；稍候可重新傳送。" : "傳送失敗：\(error.localizedDescription)"
            }
        }
    }
    func importFile(_ url: URL) {
        busy = true
        status = "匯入影片…"
        work = Task {
            do {
                let local = try await Self.copyImport(url)
                busy = false
                refresh()
                choose(local)
            } catch {
                busy = false
                status = "匯入未完成，請重新選擇影片。"
                failure = error.localizedDescription
            }
        }
    }
    nonisolated private static func copyImport(_ url: URL) async throws -> URL {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try Inbox.importFile(url)
    }
    func cancel() { work?.cancel() }
    func clearPrepared() {
        if let prepared, prepared.remuxed { try? FileManager.default.removeItem(at: prepared.url) }
        prepared = nil
    }
    func deleteSelected() {
        guard let selected else { return }
        do {
            try FileManager.default.removeItem(at: selected)
            clearPrepared()
            self.selected = nil
            refresh()
            status = "已移除 App 匯入副本，照片圖庫中的原始影片不受影響。"
        } catch { failure = error.localizedDescription }
    }
}

@main
struct DropMP4App: App {
    var body: some Scene { WindowGroup { SenderView() } }
}

struct SenderView: View {
    @StateObject private var model = SenderModel()
    @StateObject private var discovery = Discovery()
    @Environment(\.scenePhase) private var scenePhase
    @State private var importing = false
    @State private var confirmPeer: Peer?
    @State private var deleting = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("影片，直接送到電腦。")
                        .font(.title2.bold()).padding(.vertical, 4)
                    Text("同一個 Wi-Fi · 無需帳號 · 檔案不經雲端")
                        .foregroundStyle(.secondary)
                    Text(model.status).accessibilityIdentifier("transferStatus")
                    if model.busy {
                        ProgressView(value: model.fraction)
                        Button("取消", role: .cancel) { model.cancel() }
                    }
                }
                Section("1. 選擇影片") {
                    if model.files.isEmpty {
                        Text(AppFeatures.importHint)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.files, id: \.self) { file in
                        Button { model.choose(file) } label: {
                            Label(file.lastPathComponent,
                                  systemImage: model.selected == file ? "checkmark.circle.fill" : "film")
                        }.disabled(model.busy)
                    }
                    Button("從檔案匯入影片") { importing = true }.disabled(model.busy)
                    if model.selected?.pathExtension.lowercased() == "mov" {
                        Button("傳送原始 MOV") { model.useOriginal() }.disabled(model.busy)
                    }
                    if model.selected != nil {
                        Button("移除選取影片的匯入副本", role: .destructive) { deleting = true }
                            .disabled(model.busy)
                    }
                }
                Section("2. 選擇 Windows 電腦") {
                    Text(discovery.status).foregroundStyle(.secondary)
                    ForEach(discovery.peers) { peer in
                        Button { confirmPeer = peer } label: {
                            Label(peer.name, systemImage: "desktopcomputer")
                        }.disabled(model.busy || model.prepared == nil)
                    }
                    Button("重新搜尋") { discovery.start() }.disabled(model.busy)
                }
                Section {
                    Text("只有相容的 MOV 才能免重編碼封裝成 MP4。這一版不進行重新編碼；不相容時可傳原始 MOV。Windows 播放 HEVC 可能需要額外解碼器。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(AppFeatures.title)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.movie]) { result in
                switch result {
                case .success(let url): model.importFile(url)
                case .failure(let error): model.failure = error.localizedDescription
                }
            }
            .alert("核對接收電腦", isPresented: Binding(
                get: { confirmPeer != nil }, set: { if !$0 { confirmPeer = nil } })) {
                if let peer = confirmPeer {
                    Button("相同，傳送") { model.send(to: peer); confirmPeer = nil }
                }
                Button("取消", role: .cancel) { confirmPeer = nil }
            } message: {
                Text("請確認 Windows 的核對碼為 \(confirmPeer?.code ?? "")。只有兩邊完全相同才傳送。電腦名稱本身不能證明裝置身分。")
            }
            .alert("移除 App 中的影片副本？", isPresented: $deleting) {
                Button("移除", role: .destructive) { model.deleteSelected() }
                Button("取消", role: .cancel) {}
            } message: { Text("不會刪除照片圖庫的影片。") }
            .alert("操作失敗", isPresented: Binding(get: { model.failure != nil },
                   set: { if !$0 { model.failure = nil } })) {
                Button("好") { model.failure = nil }
            } message: { Text(model.failure ?? "") }
            .onAppear { model.refresh(); discovery.start() }
            .onChange(of: scenePhase) { phase in
                if phase == .active && !model.busy { model.refresh() }
            }
        }.tint(Color(red: 0.0, green: 0.43, blue: 0.36))
    }
}
