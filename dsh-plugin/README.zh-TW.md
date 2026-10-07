# dsh-voice-input-cloud

[English](README.md) | **中文**

**首版只支援 Windows；macOS／Linux 尚未支援，請勿套用本安裝流程。**
兩個 npm 套件皆聲明 `os: ["win32"]`。含路徑及 Key 精靈的 Windows 啟動器放在
完整 source 包的 `launcher/`，僅此插件套件不包含它。

這個 DSH 網頁插件在輸入框顯示一個語音按鈕。錄音與雲端請求交給本機
`dsh-voice-bridge` 和 Epicenter host；插件只操作介面與插入草稿，不持有雲端 Key。
結果不會自動送出，也不會整份覆蓋原有草稿。

## 安裝

本候選最低要求 DSH `0.1.7-rc.2`，本輪實機測試亦使用該版本。
先啟動包含 voice-bridge 補丁的 Epicenter host，以及監聽 `127.0.0.1:39152` 的 bridge。
這個插件套件本身不包含它們。

1. DSH 插件中心 → 新增插件，填入解開的來源 `dsh-plugin/` 的絕對路徑。
   本版未上架 npm registry，不以套件名稱安裝。
2. 啟用插件並重新整理 DSH 分頁。
3. 開啟 <http://127.0.0.1:39152>，在 DSH 分頁的開發者主控台貼入該頁提供的配對片段。
   `localStorage` 的 `dsh-voice-bridge` 欄位保存 `{ url, token }`；請保密此 token。
4. 點「🎤 語音輸入」開始，點「停止並轉寫」結束。檢查轉錄留在同一對話草稿，沒有送出。

bridge 預設 `requireToken: false`；未配對時插件使用預設本機 URL，不帶 token。
若啟用 `requireToken: true`，需重新確認配對設定並重啟 bridge。

## 兩個雲端 Key

兩者只填於本機 `%APPDATA%\dsh-voice-bridge\config.json`，不填在插件或瀏覽器：

| 欄位 | 用途 | 必要性 |
|---|---|---|
| `transcription.apiKey` | 語音轉錄：WAV 送至該 section 的轉錄服務 | 必填 |
| `transformation.apiKey` | 文字整理：原始轉錄與 prompt 送至該 section 的文字服務，不傳 WAV | 可選，另需 `transformation.enabled: true` |

只設定第一個 Key 即可使用。整理關閉、Key 留空或整理失敗時保留原始轉錄；
缺少轉錄 Key 會回報 `CloudNotConfigured`，不改用本地模型。
每個 section 的 Key、endpoint、model 要對應同一服務商。

## 草稿與按鈕行為

- 新對話與已有對話的輸入框都只顯示一個語音按鈕。
- 錄音前記錄插入位置；如果期間草稿改動，重新取得目前游標插入並顯示提示。
- 保留手動文字，沒有自動提交；確認內容後才由使用者決定送出。
- 轉寫中按鈕停用，避免同一控制同時啟動多個請求。

找不到按鈕時先檢查插件啟用狀態及 DSH 版本；`EpicenterUnreachable` 表示 host
未啟動或沒有補丁；`CloudNotConfigured` 表示本機轉錄設定未完成。
請用合成句子重現問題，不附 Key、配對頁、真實轉錄或錄音。

MIT，見 [LICENSE](LICENSE)。

本版在 GitHub Release 提供 source／tgz，未上架 npm registry。使用解開的插件目錄或
依來源包 docs/INSTALL_RELEASE.zh-TW.md 安裝 tgz 後的目錄，不以套件名稱安裝。
啟動錄音等待中按鈕暫停操作，連點不會重複送出 start。
