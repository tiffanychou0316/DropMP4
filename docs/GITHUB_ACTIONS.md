# 免費雲端 Mac 編譯

此流程只在公開儲存庫使用 GitHub 標準 `macos-15` runner，固定 Xcode 16.4。沒有 Apple 帳號、憑證、付款、TestFlight 或影片上傳。若儲存庫改為私人，工作會跳過，避免消耗私人額度或產生費用。

## 流程內容

1. 在雲端 Mac 安裝 XcodeGen，從 `ios/project.yml` 產生 Xcode 專案。
2. 對 iOS Simulator 執行 `build-for-testing`，編譯主 App、分享擴充功能及四項 XCTest 的原始碼。
3. 對 iPhone SDK 執行未簽署的 `build`，檢查與 Simulator 不同的平台編譯問題。
4. 不論成功或失敗，都保留純文字建置記錄、Xcode `.xcresult` 與產生的專案設定，保留三天。

測試程式此階段只編譯，尚未執行；未簽署的產物也不能直接安裝到 iPhone。完整真機分享、AVFoundation 行為與區域網路互通仍須後續驗收。

## 啟動與看結果

將專案根目錄內容放在 GitHub 儲存庫根目錄（根目錄應直接看得到 `ios`、`receiver` 與 `.github`，不要多包一層 `DropMP4`）。推送 `main` 或建立 PR 都會啟動。也可到 Actions → DropMP4 checks → Run workflow 手動啟動。

通過的標準是該次執行的 **iOS unsigned build (Simulator + iPhone)** 工作綠燈；Windows receiver 是獨立檢查，不能用它的綠燈代替 iOS 結果。若失敗，先看失敗步驟最後的 `error:`，或下載 `ios-build-diagnostics-<編號>`。修正後再推送新的提交，檢查新提交對應的執行結果。

不需要設定 GitHub Secrets。請勿上傳私鑰、`.p12`、provisioning profiles、Apple 密碼或影片。GitHub 連線工具若看不到新儲存庫，可到連線設定授權該儲存庫；Actions workflow 寫入權限若未開放，需使用 GitHub 網站完成首次 workflow 檔案上傳。

GitHub 官方計費說明：https://docs.github.com/en/actions/concepts/billing-and-usage
