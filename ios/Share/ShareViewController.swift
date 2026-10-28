import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let label = UILabel()
    private let done = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        label.text = "正在匯入影片…請保持這個視窗開啟。"
        label.numberOfLines = 0
        label.textAlignment = .center
        done.setTitle("完成", for: .normal)
        done.isEnabled = false
        done.addTarget(self, action: #selector(finish), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [label, done])
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.movie.identifier) }
        guard providers.count == 1, let provider = providers.first else {
            show("請一次分享一部 MOV 或 MP4 影片。")
            return
        }
        // No Data(contentsOf:) for large videos, and no unsupported opening of the host app.
        provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, error in
            do {
                guard let url else { throw error ?? DropError.message("照片未提供影片檔案。") }
                _ = try Inbox.importFile(url)
                self?.show("影片已匯入。\n按完成後，請手動開啟 DropMP4 選擇電腦傳送。")
            } catch { self?.show("匯入失敗：\(error.localizedDescription)") }
        }
    }

    private func show(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.label.text = text
            self?.done.isEnabled = true
        }
    }

    @objc private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
