# 只有 Windows 的 iPhone 免費實測流程

本次目標：把自己的 DropMP4 測試版用免費 Apple 帳號安裝到自己的 iPhone，先測 LAN 搜尋、免重編碼封裝、確認接收、進度與檔案校驗。不使用 TestFlight、不購買開發者會員。

## 這個測試版與完整版的差異

`DropMP4 Test` 是獨立 Target：`org.dropmp4.freetest`。它使用 App 自己的 Documents/ImportedVideos，不含 App Groups、分享擴充功能或付費功能。影片先從照片儲存到「檔案 → 我的 iPhone」，再由 App 的「從檔案匯入影片」匯入。這是為了減少免費簽署的能力需求，不代表照片分享流程已完成真機驗收。原本的完整版與照片分享擴充功能保留在 `DropMP4` Target。

0.1.1（build 2）修正真機匯入時無法寫入 Inbox 的錯誤：iOS 的 Documents/Inbox 是系統保留、不能由 App 建立或寫入的資料夾；舊版模擬器通過不能代表真機可寫。新增路徑與寫入回歸檢查，另修正重新搜尋時舊回報覆蓋電腦已找到狀態。升級時在 Sideloadly 使用同一 Apple 帳號、同一 bundle ID 覆蓋安裝即可，不需先刪除 App。真機仍須重新驗收匯入、傳送、接收確認與 SHA-256。

主 App 的 HTTPS、憑證核對、接收確認、SHA-256、AVFoundation passthrough 與原始 MOV 選項共用同一份程式。測試版不會把簽署用的 Apple 帳號當作 App 登入帳號；App 本身沒有帳號功能。

## 先取得測試檔

GitHub Actions 的 **Free iPhone test package (9 tests)** 工作通過後，下載該次執行的 `DropMP4-Free-unsigned` artifact，解壓縮後找到：

- `DropMP4-Free-unsigned.ipa`：未簽署 iPhoneOS / arm64 安裝內容。
- `DropMP4-Free-unsigned.ipa.sha256`：下載完整性校驗碼。

這個 IPA 不能直接點擊安裝。GitHub 沒有你的 Apple 帳號或簽署憑證；必須在 Windows 本機簽署後才能裝到 iPhone。不要把模擬器 `.app` 當成手機安裝包。

## Windows 準備：由使用者自行安裝與登入

可使用第三方工具 **Sideloadly**，官方網站僅使用 https://sideloadly.io/ ，不要從相似網域下載。

官方目前列出 Windows 需要網頁安裝版 iTunes 與 iCloud，下載連結在該網站的「Before you install」。請先安裝官方頁面連到的 Apple 元件，再安裝 Sideloadly。若電腦已有 Microsoft Store 版本，不要直接混裝或由代理程式自行移除；先檢查現有同步／備份用途，再依官方要求處理。

這些是第三方簽署工具與 Apple 驅動／認證依賴，涉及安裝條款、系統權限及 Apple 帳號，請由你親自操作。不要在聊天或 GitHub Secrets 提供密碼、驗證碼或復原碼。不要因為側載錯誤而停用防毒、兩步驟驗證或進階資料保護。

## 接線與簽署安裝

1. 用可傳資料的 USB 線連接 iPhone，保持解鎖。若要讓這台 Windows 存取手機，請自行確認「信任這部電腦」。
2. 開啟 Sideloadly，確認裝置清單能看到你的 iPhone。若看不到，先處理 Apple 驅動與 USB 連線，不要急著登入。
3. 將 `DropMP4-Free-unsigned.ipa` 拖進 Sideloadly。
4. 使用自己的免費 Apple 帳號，密碼與 2FA 驗證碼僅在工具的登入流程親自輸入。工具是第三方軟體；若你不願讓它處理 Apple 認證，替代方案是借 Mac 用 Xcode。
5. 保留一般安裝模式，先不啟用 tweak / dylib 注入、移除限制、換 App 圖示或其他進階修改。不要購買 Patreon、付費 Remote Anisette 或簽署服務；免費認證失敗時記下錯誤再排查。
6. 按 Start 等待完成。免費方案通常七天到期，最多同時三個免費側載 App，並受每七天 App ID 數量限制。若有既有側載 App，不要隨意撤銷憑證，避免影響它們。
7. 若 iPhone 顯示「未受信任的開發者」，由你在「設定 → 一般 → VPN 與裝置管理」查看並信任自己的開發者身分。不要信任來歷不明的企業描述檔。
8. 若要求開發者模式，依 iPhone 提示到「設定 → 隱私權與安全性 → 開發者模式」啟用並重新啟動。此設定降低裝置的部分開發限制，請你自行決定與操作；若選項未出現，不要安裝來源不明的描述檔來強開，先回報畫面。

免費簽署與認證由 Apple 服務和第三方工具共同決定，準備好 IPA 並不保證每個帳號／iOS 版本都能順利登入。登入、信任、開發者模式與手機畫面不是此工作環境可代替你完成的步驟。

## 第一輪雙機驗收

1. Windows 開啟 `DropMP4.exe`，電腦與手機使用同一個私人 Wi-Fi，保持接收視窗開啟。防火牆詢問時由你決定是否允許私人網路。
2. 在照片選一部 5–10 秒短影片，分享 → 儲存到檔案 →「我的 iPhone」；如有格式選項，優先保留目前／原始格式。Photos 交出的檔案可能是 MP4 或 MOV，App 不會把它冒稱為未修改的相機原始檔。
3. 開啟 `DropMP4 Test`，允許區域網路存取，按「從檔案匯入影片」。
4. 先測原始檔：MOV 可按「傳送原始 MOV」；MP4 原樣傳送。點電腦，核對兩端核對碼，再送出。第一輪 Windows 先點拒絕，確認沒有顯示傳送成功。
5. 再次送出並接受，保持 App 在前景，等待兩邊顯示 SHA-256 校驗完成。Windows 檢查接收檔案能開啟，聲音、旋轉與時長合理。
6. 再測一部相容 MOV 的 MP4 passthrough。若 App 無法確認免重編碼，保留原 MOV；不要把 HEVC MP4 播放器缺少解碼器誤判成傳輸損毀。HDR／Dolby Vision 不保證所有 metadata 完全保留。
7. 最後測中斷取消與重新傳送。不要一次先測大型或重要的唯一副本；App 不會刪除照片圖庫的影片。

## 七天後如何繼續測

以相同 Apple 帳號及相同 Bundle ID 重新簽署並覆蓋安裝，可避免先刪 App 導致本機匯入副本遺失。實際是否保留資料以工具與 iOS 行為為準，重要原檔要留在照片／檔案中。初次測試先不用設定背景自動更新；也不需要付款來解鎖 DropMP4 功能。

## 回報時只需提供

iPhone 型號、iOS 版本、Windows 版本、工具版本、哪一步失敗與錯誤文字。請遮掉 Apple 帳號、裝置序號、UDID、密碼、驗證碼與憑證。不要把完整登入日誌公開貼到 GitHub。

來源：[Sideloadly 官方網站](https://sideloadly.io/)、[官方 FAQ](https://sideloadly.io/faq)、[Apple 開發者模式說明](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)、[Apple 信任電腦說明](https://support.apple.com/109054)。
