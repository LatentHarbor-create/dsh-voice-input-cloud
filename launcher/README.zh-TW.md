# Windows 一鍵語音啟動器

[English](README.md) | **中文**

**首版只支援 Windows；macOS／Linux 尚未支援，請勿套用本啟動器與安裝流程。**
需要 Windows PowerShell 5.1+、Node 18+。先解開完整 source 包，保持本資料夾的
三個程式檔案放在一起；僅安裝兩個 npm 套件不會取得啟動器。
先建置已套用補丁的 Epicenter、安裝 DSH ≥ 0.1.7-rc.2 與語音插件。
啟動器提供設定精靈與服務啟動，不會代替 host 建置或插件安裝。

## 第一次使用

雙擊 `start-voice.bat`，在英文主控台依序設定：

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

再雙擊 BAT。它保留符合路徑的已有服務，啟動缺少的 Epicenter／bridge，等健康
狀態為 `epicenter: ok` 後開啟 DSH。埠被不相關進程占用會報錯，不終止進程或
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
```

`-Check` 不建立首次設定或啟動服務。`-NoBrowser` 不保存或顯示新 DSH 的認證網址。
BAT 僅對這次 PowerShell 進程使用 ExecutionPolicy Bypass，不修改系統執行原則；
組織管理政策仍可能阻止執行。

## 本機資料與限制

| 位置 | 內容 |
|---|---|
| `%LOCALAPPDATA%\dsh-voice-launcher\paths.json` | 程式路徑與 DSH 埠 |
| `%APPDATA%\dsh-voice-bridge\config.json` | 轉錄／整理 Key、prompt、配對 token |
| 原檔旁的 `.backup-*` | 舊版私密設定 |

Key 以一般 JSON 存在本機，沒有加密；以同一 Windows 使用者執行的程式可讀取。
隱藏輸入用於避免畫面顯示。已填設定、備份、設定截圖、認證網址與日誌都不公開。
公開啟動器沒有附帶真實 Key，也不將 Key 放進程序參數。啟動只請求本機健康狀態；
錄音與雲端請求仍需使用者操作語音按鈕。

39152 同時只能由一個 bridge／profile 使用；其他安裝版本占用時會顯示衝突。
若要沿用該服務，明確填入它的 bridge 路徑。啟動器檢查路徑、Node 版本、進程與
本機健康，不檢查 DSH 版本相容性或雲端帳戶權限。host 元件需 Bun 時仍須安裝；
若使用者慣用的 `.bun/bin` 存在，helper 會加入 PATH。
進程路徑檢查無法證明已有服務使用相同環境／資料 profile；隔離測試環境應分開處理。
helper 不保存原始進程輸出，深入排錯請在本機使用原手動命令，再脫敏分享訊息。

啟動器以合成資料獨立驗證；之前語音驗收結果仍保留，尚無完整新使用者首次安裝
並操作啟動器的實機紀錄。
