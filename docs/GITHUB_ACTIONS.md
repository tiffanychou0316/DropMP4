# 免費雲端 Mac 編譯

此流程只在公開儲存庫使用 GitHub 標準 `macos-15-intel` runner，固定 Xcode 16.4。原先的 `macos-15` Apple 晶片 runner 排程壅塞，改用同樣免費的 Intel 標準 runner。沒有 Apple 帳號、開發者簽署憑證、付款、TestFlight 或影片上傳。模擬器使用本機 ad-hoc 簽署；iPhone SDK 產物保持未簽署。若儲存庫改為私人，工作會跳過，避免消耗私人額度或產生費用。

## 流程內容

1. 在雲端 Mac 安裝 XcodeGen，從 `ios/project.yml` 產生 Xcode 專案。
2. 對 iOS Simulator 執行 `build-for-testing`，編譯主 App、分享擴充功能及四項 XCTest 的原始碼。
3. 對 iPhone SDK 執行未簽署的 `build`，檢查與 Simulator 不同的平台編譯問題。
4. 從已安裝的 iOS 18.5 模擬器選取一台可用 iPhone，啟動後執行 `test-without-building`，執行四項 XCTest，不自動重試失敗測試。
5. 從 `.xcresult` 讀取實際測試摘要，要求四項通過、零失敗、零跳過；空跑不算成功。
6. 不論成功或失敗，都保留純文字記錄、JSON 摘要、Xcode `.xcresult` 與產生的專案設定，保留三天。

測試涵蓋 SHA-256 已知向量、原始 MP4 分支、損毀 MOV 保留來源，以及模擬器產生 H.264 MOV 的 passthrough 與壓縮影音資料校驗。模擬器測試不能取代真實 iPhone 的分享匯入、HEVC / HDR 或區域網路互通驗收。未簽署的 iPhone 產物也不能直接安裝到手機。

## 啟動與看結果

將專案根目錄內容放在 GitHub 儲存庫根目錄（根目錄應直接看得到 `ios`、`receiver` 與 `.github`，不要多包一層 `DropMP4`）。推送 `main` 或建立 PR 都會啟動。也可到 Actions → DropMP4 checks → Run workflow 手動啟動。

通過的標準是該次執行的 **iOS build and Simulator tests** 工作綠燈，且工作摘要顯示 `4 passed, 0 failed, 0 skipped`；Windows receiver 是獨立檢查，不能用它的綠燈代替 iOS 結果。若失敗，先看失敗步驟最後的 `error:`，或下載 `ios-build-diagnostics-<編號>`。修正後再推送新的提交，檢查新提交對應的執行結果。

不需要設定 GitHub Secrets。請勿上傳私鑰、`.p12`、provisioning profiles、Apple 密碼或影片。GitHub 連線工具若看不到新儲存庫，可到連線設定授權該儲存庫；Actions workflow 寫入權限若未開放，需使用 GitHub 網站完成首次 workflow 檔案上傳。

GitHub 官方計費說明：https://docs.github.com/en/actions/concepts/billing-and-usage

## 免費 iPhone 測試包工作

同一 workflow 的 **Free iPhone test package (9 tests)** 獨立建置 `DropMP4Free`，跑原四項影音測試、三項本機儲存測試與兩項搜尋狀態測試，要求 9 通過、0 失敗、0 跳過。iPhone Release 產物不含 App Groups、分享擴充功能或 provisioning profile。只有九項測試通過才提供 `DropMP4-Free-unsigned` artifact，包含 IPA、SHA-256 與安裝指引，保留七天。儲存測試除了確認可寫入，也明確拒絕 iOS 保留的 Documents/Inbox 路徑，避免模擬器較寬鬆的行為掩蓋真機限制。

這個 IPA 需要在 Windows 由使用者自己的免費 Apple 帳號簽署，GitHub 不接受 Apple 密碼或憑證。不使用 TestFlight；[安裝步驟](IPHONE_WINDOWS_FREE.md)。[Run #7](https://github.com/tiffanychou0316/DropMP4/actions/runs/40791310508) 已完成第一次六項測試與打包驗證。

