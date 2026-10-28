# 交付與驗證紀錄

日期：2026-10-29（Asia/Taipei）。本文件區分實際執行證據與仍待驗收的項目，不以原始碼存在等同實機成功。

## 已交付及已實測

| 項目 | 結果與範圍 |
| --- | --- |
| Windows 核心 | Python 3.12.14 / Windows 11 x64；15 項 unittest 通過 |
| TLS + 寫檔 | 真正 HTTPS 連線、leaf certificate SHA-256 比對、串流接收與回報校驗一致 |
| 接收授權 | 拒絕、60 秒設計的可縮短測試逾時、忙碌、token 過期、錯誤 token 與重放被拒絕 |
| 檔案保護 | traversal / 控制字元 / 副檔名 / 大小等輸入檢查；錯誤大小、損毀資料與中斷清理；同名檔案不覆寫 |
| Bonjour | 1 項獨立整合測試通過：真實 IPv4 網卡廣播、另一個 Zeroconf browser 發現服務、port 與 fingerprint 一致 |
| Windows 執行檔 | PyInstaller 6.16.0 onedir 成功，視窗正常啟動，顯示等待連線、核對碼、儲存位置 |
| iOS 專案設定 | YAML 語法、來源目錄及 App / Share Extension / XCTest 依賴檢查通過；這不是 Swift 編譯測試 |
| Windows GUI 接收 | 經實際確認對話框按「是」，接收 1,638,400 bytes 合成資料；進度條完成，畫面顯示 SHA-256 校驗通過 |

GUI 合成資料的 SHA-256：`99c89c5f95c8627ca23684dfa1cb0545183228f603bad520a7ed8529f10e9728`。它不是可播放的影片，測的是完整桌面確認 → HTTPS → 寫檔 → 校驗 → UI 完成路徑。測試寫入獨立工作目錄，未包含於下載包。

打包檢查曾發現 bundled Python 的 SSL 模組需要額外 `codex-rejected-cas.pem`；已將原有憑證資源一併帶入 portable 的 `_internal/`，沒有移除或繞過驗證。建置腳本也有針對此環境的條件式資源收集。一般官方 Python 沒有這個檔案時不需要加入。

## 尚未執行

- iOS XcodeGen 產生與 Xcode build / XCTest：沒有 macOS、Apple SDK 與簽署環境。
- 真實 iPhone 的 Share Extension、App Group、區域網路權限與 Bonjour 連 Windows。
- 真實 H.264 / HEVC MOV 的 AVFoundation passthrough 與壓縮樣本比對。
- HDR、Dolby Vision、旋轉、多音軌、特殊 MOV 及 iCloud Photos 分享表示的實機相容性。
- iOS URLSession 與自簽憑證釘選在實際裝置 / ATS 設定下的互通。
- 乾淨 Windows 機器的 portable、SmartScreen / 程式碼簽署、長時間大檔與低磁碟空間測試。
- GitHub Actions：workflow 已附上，未上傳或執行遠端 CI。

因此目前定位是「Windows 已可執行並完成本機測試；iOS 已完成待 Apple 環境驗證的 MVP 實作」。不能稱為已經跑通的雙機產品。

## Apple 環境驗收順序

1. 在 macOS 依 README 產生專案、build-for-testing；先解決任何 SDK / Swift 相容性問題。選 Simulator 執行四項 XCTest：SHA-256 已知向量、MP4 原檔分支、錯誤 MOV 保留來源、產生 H.264 MOV 後 passthrough 與內容比對。
2. 設定自己的 Bundle IDs、Team 與相同 App Group，安裝兩個 Target 到 iPhone。檢查照片分享選單只有一次一部影片匯入，複製完成再返回主 App，檔名、長度及來源符合預期。
3. Windows 開啟接收端，同一私人 Wi-Fi。iPhone 允許區域網路存取，可找到電腦；關閉接收端後裝置從清單移除。權限拒絕、VPN、訪客隔離、雙網卡與防火牆封鎖都應能合理排查。
4. 比對核對碼，Windows 點拒絕；iPhone 必須顯示失敗，Windows 沒有完成檔。再次送出並接受，兩端進度與回報一致。
5. 故意在 iPhone / 測試 client 使用不同 fingerprint，TLS 必須失敗。變更接收端憑證後核對碼須改變，舊 pin 不可連線。
6. 以真實素材測試下表；每次保留原始 MOV、傳輸後檔案及檢查記錄。可使用 macOS `ffprobe -show_streams -show_format` 對比 metadata，並在 iPhone 與 Windows 比較旋轉、色彩、音畫同步及 HDR 行為。
7. 測試中途取消、斷 Wi-Fi、接收端關閉、手機鎖定、重送、磁碟不足、超過 20 GiB。同時送第二份應顯示忙碌。錯誤狀況不得顯示「已校驗完成」。

| 真實素材 | 應有行為 |
| --- | --- |
| 一般 H.264 + AAC MOV | 若 AVFoundation 支援且嚴格比對通過，準備 MP4；否則允許原 MOV |
| HEVC + AAC MOV | 同上；Windows 播放可能需 HEVC 解碼器 |
| HEVC HDR / Dolby Vision MOV | 不保證所有 metadata，需顏色/HDR 實機驗收；原 MOV 一直可選 |
| 無音訊 H.264 / HEVC MOV | 可嘗試；需比對影音資料、旋轉、時長 |
| ProRes / PCM / 額外軌道 MOV | 本版保守提示無法確認免重編碼封裝，提供原 MOV |
| 旋轉直式、多音軌、慢動作 | 嚴格比對或額外軌道可能拒絕，需核對時間軸、方向與聲音 |
| 已有 MP4 | 原樣傳送，傳輸校驗一致；不宣稱檔案編碼可在所有電腦播放 |

## 分階段交付

| 階段 | 本次狀態 | 交付門檻 |
| --- | --- | --- |
| 1A 傳輸基礎與 Windows | 完成並本機測試 | 可執行接收端、TLS、確認、進度、校驗、Bonjour、自動測試 |
| 1B iOS 實作 | 原始碼完成，待 macOS 驗證 | Xcode build / XCTest 通過、真機分享匯入、實際 pin 連線 |
| 1C 雙機 MVP 驗收 | 尚未完成 | 真實影片、格式保留/原檔分支、拒收/中斷、私人網路互通全流程 |
| 2 公開免費測試版 | 後續工作 | 發布授權與依賴檢查、程式碼簽署、隱私說明、商店/安裝管道、使用者回饋 |
| 3 可選自願支持 | 未實作 | 約 NT$30 的一次性自願支持，核心功能免費，不強迫註冊 |

未公開部署、未建立遠端儲存庫、未上傳任何使用者影片。專案採 MIT 授權；第三方元件保留各自授權。
