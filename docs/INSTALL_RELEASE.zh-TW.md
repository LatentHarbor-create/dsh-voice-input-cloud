# GitHub 首版安裝

[English](INSTALL_RELEASE.md) | **中文**

只支援 Windows。本版由 [GitHub Release](https://github.com/LatentHarbor-create/dsh-voice-input-cloud/releases/tag/v0.1.0) 提供原始碼與 tgz，**未上架 npm registry**。
下載與安裝不需要 npm 帳號。npm 工具仍可安裝 tgz 網址或本地檔案；不能只填套件名稱。
本倉庫是 monorepo，也不要直接把倉庫根目錄當 npm 套件安裝。

## 建議方式：完整 source

1. 下載 source.tar.gz 與 SHA256SUMS，用 `Get-FileHash -Algorithm SHA256` 核對後解開。
2. 依根 README 套用指定版本的 Epicenter patch 並建置 host。安裝 Node ≥ 18、Bun、
   DSH ≥ 0.1.7-rc.2；交付不含 host 執行檔或完整安裝器。
3. DSH 插件中心加入 source 中 `dsh-plugin` 的絕對路徑並啟用。
4. 雙擊 `launcher/start-voice.bat`，設定路徑、轉錄 Key、可選整理 Key 與單一 prompt。
   Key 留在本機 bridge config，不填入 source 或公開資料。
5. 依說明配對 DSH 分頁，填入 localStorage 後重新整理。之後手動雙擊 BAT 啟動，沒有開機自啟。

## 可選：用 npm 安裝 GitHub tgz

```powershell
npm install -g --ignore-scripts "https://github.com/LatentHarbor-create/dsh-voice-input-cloud/releases/download/v0.1.0/dsh-voice-bridge-0.1.0.tgz"
$pluginRoot = Join-Path $env:LOCALAPPDATA 'dsh-cloud-plugin'
npm install --prefix "$pluginRoot" --ignore-scripts "https://github.com/LatentHarbor-create/dsh-voice-input-cloud/releases/download/v0.1.0/dsh-voice-input-cloud-0.1.0.tgz"
```

在 DSH 插件中心加入 `$pluginRoot\node_modules\dsh-voice-input-cloud` 的實際絕對路徑。
兩個 tgz 都不含啟動器或 Epicenter host；仍需完整 source 提供的 launcher 與 host patch。
也可先下載並核對 hash，把網址換成 tgz 本地路徑進行離線安裝。bridge CLI 為
`dsh-voice-bridge`，啟動器可填其 `bridge.mjs` 路徑或用 source 預設副本；只開一個 bridge。

## 驗證範圍與回報

這是早期版本。先前語音／整理實機驗收保留，最新連點鎖只有合成測試，完整新使用者
首次安裝啟動器尚未驗收。詳見 FIRST_INSTALL_CHECK.md／VALIDATION.md。
GitHub Issues 只提供版本、脫敏錯誤碼與合成重現步驟，勿附 Key、config、錄音、轉錄或完整日誌。
