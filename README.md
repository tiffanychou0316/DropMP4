# DropMP4 — iPhone → Windows LAN MVP

這是可執行的第一階段開發版：Windows 桌面接收端與 iOS 原生 App / 分享擴充功能的完整原始碼。無帳號、不經雲端、不實作付款，也不包含 Android。

**驗證範圍：Windows 已執行 16 項 HTTPS / 校驗 / 自動搜尋測試。iOS 已在免費 GitHub 雲端 Mac / Xcode 16.4 完成模擬器及 iPhone SDK 編譯，並在 iOS 18.5 Simulator 實際通過四項 XCTest：4 通過、0 失敗、0 跳過。** [編譯與測試成功紀錄](https://github.com/tiffanychou0316/DropMP4/actions/runs/40750419859)。尚未進行真實 iPhone 驗收或產生可安裝的簽署版本；詳見 [測試紀錄](docs/VALIDATION.md) 與 [雲端測試說明](docs/GITHUB_ACTIONS.md)。

## 技術取捨與內容

只有 Windows、想免費裝到自己的 iPhone：請看 [Windows 免費安裝與真機驗收流程](docs/IPHONE_WINDOWS_FREE.md)。已提供不含 App Groups / 分享擴充功能的 `DropMP4 Test` 獨立版本，使用「檔案」匯入。它已通過六項模擬器測試並產生未簽署 IPA；需要你在 Windows 用自己的免費 Apple 帳號本機簽署後才能安裝。原本照片分享完整版保留。[Run #7 建置與測試紀錄](https://github.com/tiffanychou0316/DropMP4/actions/runs/40791310508)。

現有機器無 Flutter、Dart、.NET 或 Xcode。第一版採 SwiftUI + AVFoundation（iPhone）與 Python 3.12 + Tkinter（Windows），先交付可測試的傳輸協定與原生影音流程。共用 UI 可於下一階段導入 Flutter，沿用 HTTPS 協定；目前不宣稱已有 Flutter 專案。

| 目錄 | 內容 |
| --- | --- |
| `receiver/` | Windows GUI、HTTPS、接收確認、串流寫入、SHA-256、Bonjour 廣播 |
| `ios/` | SwiftUI App、AVFoundation passthrough、檔案校驗、Bonjour 搜尋、憑證釘選 |
| `ios/Share/` | 照片分享選單 → App Group 本機匯入，一次一部影片 |
| `tests/` | 可執行 Python 核心與 mDNS 整合測試 |
| `ios/Tests/` | Apple 環境可執行的影音與 SHA-256 測試 |
| `docs/` | 協定、實機驗收清單、目前限制與階段交付 |

## Windows：直接啟動

本次交付另附 `DropMP4-Windows.zip`。解壓縮整個資料夾後開啟 `DropMP4.exe`，請保留旁邊的 `_internal` 資料夾。這是未簽章的個人開發版，不是安裝程式；公開發行前需補程式碼簽署與乾淨機器驗收。

預設接收目錄是 `%USERPROFILE%\Downloads\DropMP4`。每次影片進來都會詢問是否接收，等待核准最多 60 秒。儲存檔名前加隨機識別碼，避免覆寫同名影片。請保持視窗開啟。

Windows 防火牆若詢問，請由使用者決定是否允許 **私人網路**；App 不會自行修改防火牆。使用同一個私人 Wi-Fi，勿使用會隔離裝置的訪客網路。需要 TCP 47321 與 UDP 5353（mDNS）；不要在路由器設定對外轉發。

## Windows：從原始碼執行

安裝官方 Python 3.12（含 Tcl/Tk），在本目錄開啟 PowerShell：

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m receiver
```

多張網卡、VPN 或虛擬網卡導致錯誤位址時，指定真正 Wi-Fi 的 IPv4：

```powershell
.\.venv\Scripts\python.exe -m receiver --ip 192.168.1.23 --destination D:\Videos\DropMP4
```

自動搜尋以 IPv4 LAN 為本階段範圍。`--ip` 只改廣播位址；伺服器監聽所有 IPv4 介面，應由私人網路的防火牆限制存取。無 Bonjour for Windows / iTunes 安裝需求。

憑證與私鑰在 `%LOCALAPPDATA%\DropMP4`，不隨程式打包。請保護此目錄；同一 Windows 使用者帳號下的惡意程式不在威脅防護範圍。刪除身分檔會產生新的核對碼。

重建執行檔：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build-windows.ps1
```

這只對當次建置執行腳本，不會永久修改執行政策。也可手動執行腳本內的命令。

## iOS：macOS + Xcode 建置與簽署

需求：macOS、Xcode 15+（iOS 16+ SDK）、XcodeGen、可簽署的 Apple 開發者 Team，以及一部 iPhone。App Groups 能力須由 Team / provisioning profile 支援；個人免費簽署可能無法使用所需 App Group，請以 Xcode 顯示為準。

```sh
brew install xcodegen
cd ios
xcodegen generate
open DropMP4.xcodeproj
```

1. 在 Xcode 中選擇自己的 Team，兩個 Target 都要設定（`DropMP4`、`DropMP4Share`）。
2. 將 `org.dropmp4.app` 與 `org.dropmp4.app.share` 改成自己可使用的唯一 Bundle ID。可直接在 `project.yml` 修改後重新產生。
3. 修改 `project.yml` 的 `GROUP_ID`，例如 `group.com.yourname.dropmp4`；在兩個 Target 的 Signing & Capabilities 啟用相同 App Group，確保 App ID / profile 都支援。App 與擴充功能的 `SharedGroup` Info 值與 entitlement 必須一致。
4. 選擇真實 iPhone，Run `DropMP4` scheme。第一次搜尋時允許區域網路存取。
5. 開啟照片，選一部影片 → 分享 → 更多 → DropMP4。一次一部。等畫面顯示匯入完成，按完成後**手動開啟 DropMP4**。
6. 選影片，等待相容性檢查；成功會準備 MP4，不相容可點「傳送原始 MOV」。
7. 點電腦，核對 iPhone 與 Windows 的 12 位十六進位碼完全一致，才點「相同，傳送」。Windows 端再確認接收。
8. 保持 iPhone App 在前景，待兩邊顯示校驗完成。iPhone 的匯入副本可在 App 中移除，照片圖庫原檔不受影響。

Share Extension 不使用非公開 API 強行開啟主 App，也不在記憶體載入整部影片。照片 App / iCloud Photos 可能先下載或產生分享表示；App 保留的是系統交給擴充功能的檔案，不保證等同照片圖庫內最初拍攝的位元組。若要測試原始 MOV，請選「目前 / 保留原始格式」等可用的照片分享選項，並記錄實際收到的副檔名與編碼。

純編譯檢查（不簽署）：

```sh
cd ios
xcodegen generate
xcodebuild -project DropMP4.xcodeproj -scheme DropMP4 \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build-for-testing
```

單元測試：在 Xcode 選擇可用 iPhone Simulator 後按 Product → Test（⌘U），或 `xcodebuild ... -destination 'platform=iOS Simulator,id=<你的模擬器 UUID>' test`。GitHub Actions 已實際執行並通過四項測試，且檢查 `.xcresult` 的通過／失敗／跳過數量。分享匯入、區域網路權限、HDR / HEVC 與兩機傳輸仍須真機測試。

## 「免重編碼」的邊界

- 僅嘗試影片軌為 H.264 / HEVC、音訊為 AAC（或無音訊）、無額外軌道的 MOV。這是保守子集合，不代表其他 MOV 永遠不能轉。
- 使用 `AVAssetExportPresetPassthrough`，並先確認 `.mp4` 是支援輸出；完全不啟動有損重新編碼。失敗不會偷偷降畫質。
- 封裝前後用 `AVAssetReader(outputSettings: nil)` 串流比對各軌壓縮資料的 SHA-256、資料長度、sample 數、編碼，另比對時長及旋轉。嚴格比對可能拒絕原本可接受的封裝，此時改傳原始 MOV。
- 壓縮影音內容一致 **不代表整個容器位元組、所有 metadata、色彩或 Dolby Vision / HDR 行為完全一致**。原始 MOV 保留；重視原始資料者可直接選原檔。MP4 也不等於 H.264；HEVC MP4 在 Windows 上仍可能需要解碼器。
- 檔案傳輸 SHA-256 校驗針對「最後選擇傳送的 MP4 或 MOV」，與 remux 前後的軌道比對是兩種不同檢查。

Apple 官方 API 說明：[AVAssetExportSession](https://developer.apple.com/documentation/avfoundation/avassetexportsession)、[passthrough preset](https://developer.apple.com/documentation/avfoundation/avassetexportpresetpassthrough)、[Bonjour](https://developer.apple.com/documentation/foundation/bonjour)。

## 測試

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s tests -p test_receiver.py -v
.\.venv\Scripts\python.exe -m unittest discover -s tests -p test_discovery.py -v
```

第一組建立真正 HTTPS server 並透過 TLS 傳輸資料，不需要 iPhone；第二組使用真實網卡觀察 Bonjour 廣播，防火牆或 CI 隔離環境可能阻擋，應在實際私人網路測試。測試資料是合成二進位資料，不等同真實影片播放驗收。

後續依 [驗收清單與階段](docs/VALIDATION.md) 完成真實 MOV 樣本測試、實機分享與雙裝置驗收後，才能稱為已跑通的 iPhone → Windows MVP。

## 目前限制

一次一部影片、同時一個傳輸、最大 20 GiB；沒有續傳、背景傳輸、批次、Windows 自動更新或安裝器。連線中斷需重新送出。程序正常處理中斷會移除 partial；強制結束或斷電可能遺留 `.partial`，下次不會當成完成檔案，也不會自動刪掉使用者資料。iPhone 匯入副本佔用 App Group 空間；remux 和校驗需要額外讀寫及暫存空間。

此版支援本機私有網路，沒有抗惡意 LAN 拒絕服務的完整設計。TLS 最低 1.2，完整憑證 SHA-256 釘選，核對碼取前 48 bits，每次由使用者比對；接收許可為單次短效 token。無強制註冊、雲端存檔、遙測與付款。

未來如提供約 NT$30 一次性自願支持，核心傳輸功能維持免費；本階段尚無相關程式碼或商店付款整合。
