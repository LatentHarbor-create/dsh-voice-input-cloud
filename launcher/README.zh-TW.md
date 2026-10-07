# Windows 一鍵語音啟動器

[English](README.md) | **中文**

**首版只支援 Windows；macOS／Linux 尚未支援，請勿套用本啟動器與安裝流程。**
BAT 選單與終端提示全部使用英文 ASCII；更新後請關閉舊選單，再重新雙擊 BAT。
啟動器會確認 host／Bridge 進程建立，再等待健康檢查；錯誤會指出失敗步驟。
若只是瀏覽器無法開啟，已就緒的服務仍繼續運行，畫面會提供可手動開啟的本機網址。

需要 Windows PowerShell 5.1+、Node 18+。先解開完整 source 包，保持本資料夾的
所有 BAT、PowerShell 與 Node 程式檔案放在一起；僅安裝兩個 npm 套件不會取得啟動器。
先建置已套用補丁的 Epicenter、安裝 DSH ≥ 0.1.7-rc.2 與語音插件。
啟動器提供設定精靈與服務啟動，不會代替 host 建置或插件安裝。

## 第一次使用

雙擊唯一的 `start-voice.bat`，在英文選單選 **1 Start**；也可選 **5 設定**，只設定而不啟動。
首次使用時，在英文設定精靈依序填入：

1. `epicenterExe`：已建置的 Epicenter `.exe`；`bridgeEntry`：bridge `.mjs`。
   bridge 預設使用 source 包附帶的版本。
2. `nodeExe` 與 `dshEntry`：Node 執行檔、DSH 的 `lib/bin.js`。標準 npm 全域安裝
   可自動尋找；其他安裝方式需自行填絕對路徑。支援中文、空白及環境變數路徑。
3. DSH 埠，預設 3080；bridge 固定為 39152。
4. 轉錄選 `1 Groq`、`2 OpenAI` 或 `3 相容服務`，填該服務的 baseURL、model、Key。
5. `Enable optional text polish?` 選 `y` 啟用文字整理，選 `n` 略過。
   啟用時再填 OpenAI／相容服務的 URL、model、整理 Key 與單一 prompt。

Key 隱藏輸入；Enter 保留既有值，換 endpoint 時需填對應 Key。URL 自動移除
`/audio/transcriptions`／`/chat/completions` 後綴；prompt 換行可輸入 `\n`。
填入 Key 不代表已驗證模型權限或帳戶額度，設定不呼叫雲端。免費轉錄額度取決於
服務商，OpenAI 整理另依其方案計費。路徑及 prompt 既有值會在本機主控台顯示，
設定畫面也請保留私密。

全部輸入驗證完成後保存。既有配對 token、其他 bridge 欄位及停用整理時的設定
均保留；無效或不可讀的設定不覆寫。每個檔案各自原子寫入，原檔另存
`.backup-<隨機 id>` 備份。兩份設定不是同一筆交易；若第二份寫入失敗，檢查本機
備份並重新設定。寫入前偵測到其他編輯會停止，避免覆蓋新內容。較深設定保留於支援的巢狀上限內；
超出上限會在保存兩個檔案前拒絕，避免截斷內容。

## 之後使用

再雙擊同一個 BAT，選 **1 啟動**。它依序檢查 Epicenter → Bridge → DSH，缺少的元件
按順序啟動，健康元件保留；已確認身分但失效的語音元件才單獨重啟。
先確認 host 健康再啟動 Bridge，後端健康後才啟動 DSH。
全正常時重複按 Start 不會改變任何元件的 PID。瞬間的進程／埠快照衝突會再核對，
真正無法辨識的 owner 才阻止操作並指出 host 或埠。
埠被不相關進程占用會報錯，不終止進程或
重啟已有 DSH 草稿。另有其他或無法辨識的 Epicenter 安裝正在執行時也會停止啟動，
避免兩個 host 共用 discovery。成功後關閉啟動器視窗，服務仍執行；新啟動 DSH 的隱藏 Node
helper 需保留執行，以接收其輸出。沒有設定開機自啟、排程工作或 Windows 服務。

新啟動的 DSH 使用其本機認證網址開啟瀏覽器，登入 token 不印出或寫入啟動器
日誌／狀態檔。已有 DSH 則開一般網址；若需登入，使用原有已認證分頁或啟動連結。
首次仍需啟用插件及[配對分頁](../README.zh-TW.md#安裝順序)，啟動器不會把配對
憑證自動寫進瀏覽器。瀏覽器開啟失敗或逾時會單獨提示，不印出認證網址。
建議先配對，再開啟 `requireToken: true`；啟用後直接用瀏覽器開 bridge 頁面會得到 401。
既有保護設定請從本機 config 取 token 填入配對片段，之後重新整理 DSH 分頁，勿公開 token。

在此資料夾的終端執行：

```powershell
.\start-voice.bat -Configure   # 修改路徑、Key、prompt 後啟動
.\start-voice.bat -SetupOnly   # 只設定，不啟動服務
.\start-voice.bat -Check       # 檢查已有設定、埠占用、bridge 健康
.\start-voice.bat -NoBrowser   # 啟動服務，不開瀏覽器
.\start-voice.bat -Action Stop     # 停止 Voice Bridge 與指定 Epicenter host
.\start-voice.bat -Action Restart  # 重啟語音後端，保留 DSH
.\start-voice.bat -Action Status   # 只讀檢查各服務與語音後端健康
```

亦可使用 `start-voice.bat -Action Stop`、`-Action Restart`、`-Action Status`，或
`-Stop`、`-Restart`、`-Status`；一次只能選一種動作，`-Check` 等同 Status。
不帶指令參數時，同一個 BAT 顯示 **1 啟動、2 停止、3 重啟、4 狀態、5 設定、0 離開**。
執行結果會保留，按 Enter 回到選單；指令失敗或狀態未就緒也可回到選單繼續操作。
設定選項不啟動服務；離開只關閉選單，服務仍執行。帶指令參數時直接執行該指令。
狀態分別顯示 Epicenter、bridge、DSH
及 PID，並檢查語音後端健康；進程仍在不代表服務健康。退出碼：0 成功／健康、
1 指令失敗、2 狀態未就緒或有衝突。

**停止／重啟或修復失效元件前，請先結束錄音並等待轉錄完成。** 停止／重啟會終止指定 Epicenter
及已驗證的子進程（包括 Bun host、WebView）；同一 Epicenter 實例的其他視窗與功能
也會停止。DSH、瀏覽器分頁、草稿、配對與雲端設定均保留。重啟只啟動兩個語音
後端，即使 DSH 未執行也不會啟動它，不開瀏覽器；健康狀態穩定後才報告成功。
此操作不會替尚未完成的錄音或雲端請求收尾。
停止前會核對精確程式路徑、腳本參數、進程建立時間，並先取得 OS 進程 handle，
避免 PID 重用誤停；不使用程式名稱或埠號直接批次殺進程。其他／無法辨識的語音
服務占用會阻止操作。服務已停止時再按停止仍成功，不會啟動任何服務。
停止不要求有效 API Key 或可讀的 bridge config，但需已有啟動器路徑設定；
重啟會先驗證設定與程式路徑，通過後才停止服務。

## 啟動／重啟時清理歷史

兩個語音後端均停止後的 Start，以及每次 Restart，只清除 `<Epicenter 資料根目錄>/blobs/` 中帶有本插件歸屬標記的 WAV、
本插件標記的未完成暫存、Voice Bridge 歷史日誌及 `state.json` 錄音 ID。
Bridge 在每次成功開始錄音時，於 `%APPDATA%/dsh-voice-bridge/recording-owners/`
保存錄音 ID、owner 和精確音訊目錄；標記不含音訊、轉錄文字或 Key。
Restart 先停止指定後端，再清理，完成後啟動。部分恢復及全正常時再按 Start 會保留
執行中的元件，將歷史清理延後至 Restart 或下次兩個後端都停止後的 Start，避免刪除使用中的音訊。
沒有標記的舊錄音及其他功能錄音均保留。
更新啟動器時也要更新 Bridge，bridge.mjs 和 recording-history.mjs 必須放在一起。
若無法保存標記，開始錄音會取消／拒絕，避免產生無法追蹤的錄音。
沒有保留條數或天數，也不建立錄音備份。
Key、prompt、配對、DSH 草稿／對話及非 WAV blob 保留；插件沒有獨立轉錄文字歷史庫。
狀態、停止、只設定與離開選單不清理；手動直接執行 Node／Epicenter 不套用此規則。

仍在錄音時會阻止 Restart 或需要停止元件的修復。目錄結構異常、符號連結／junction、進程占用衝突也會阻止清理。
預設資料根目錄為 `%APPDATA%/so.epicenter`；已有絕對路徑 `EPICENTER_DATA_DIR` 時沿用。
預設清理 bridge 程式旁的 `bridge.log`；私密 paths.json 的 `voiceHistoryLogs` 可額外
列出絕對路徑的 `bridge.log`／`local-bridge-private.log`，不接受任意設定／文字檔路徑。
畫面只顯示刪除數量，不顯示音訊或轉錄內容。
Epicenter 本身原有的啟動流程會移除未完成的原生錄音暫存；這與啟動器依歸屬
清理已完成錄音的機制不同。

`-Check` 不建立首次設定或啟動服務。`-NoBrowser` 不保存或顯示新 DSH 的認證網址。
BAT 僅對這次 PowerShell 進程使用 ExecutionPolicy Bypass，不修改系統執行原則；
組織管理政策仍可能阻止執行。

## 本機資料與限制

| 位置 | 內容 |
|---|---|
| 啟動器旁已有的 `paths.json`；否則 `%LOCALAPPDATA%\dsh-voice-launcher\paths.json` | 程式路徑與 DSH 埠 |
| `%APPDATA%\dsh-voice-bridge\config.json` | 轉錄／整理 Key、prompt、配對 token |
| 原檔旁的 `.backup-*` | 舊版私密設定 |

Key 以一般 JSON 存在本機，沒有加密；以同一 Windows 使用者執行的程式可讀取。
隱藏輸入用於避免畫面顯示。已填設定、備份、設定截圖、認證網址與日誌都不公開。
公開啟動器沒有附帶真實 Key，也不將 Key 放進程序參數。啟動只請求本機健康狀態；
錄音與雲端請求仍需使用者操作語音按鈕。

啟動器旁已有 `paths.json` 時優先使用；BAT 選單也會明確指定它，讓全部操作沿用
同一份設定。可用 `-SettingsPath` 指定其他位置。此本機檔案沒有 API Key，
但包含安裝路徑，請勿混入公開 source 包。

39152 同時只能由一個 bridge／profile 使用；其他安裝版本占用時會顯示衝突。
若要沿用該服務，明確填入它的 bridge 路徑。啟動器檢查路徑、Node 版本、進程與
本機健康，不檢查 DSH 版本相容性或雲端帳戶權限。host 元件需 Bun 時仍須安裝；
若使用者慣用的 `.bun/bin` 存在，helper 會加入 PATH。
進程路徑檢查無法證明已有服務使用相同環境／資料 profile；隔離測試環境應分開處理。
helper 不保存原始進程輸出，深入排錯請在本機使用原手動命令，再脫敏分享訊息。

啟動器以合成資料獨立驗證；之前語音驗收結果仍保留，尚無完整新使用者首次安裝
並操作啟動器的實機紀錄。
