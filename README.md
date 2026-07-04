## 說明
ccc 是一個 command router。在 `cccrouter.json` 自訂指令與參數，然後用 `ccc` 呼叫：
```
ccc <command...> <optional positional args...>
```

### Quick Start
Step 1 - Clone the repo.

Step 2 - 在 repo 目錄使用 `.\ccc-router install` 註冊指令至系統層級。
  ```
  .\ccc-router install                  # 安裝 ccc 與 ccc-router
  .\ccc-router install --beauty --vscode   # 一併安裝 vscode highlighter 插件
  ```
  `--beauty --vscode` 會從 GitHub Release 下載最新發佈的 `.vsix` 安裝（不需要 Node）。
  如果 Step 2 沒加 `--beauty`，之後用 `ccc-router beauty install --vscode` 即可補裝插件（不需要 repo）。
Step 3 - 回到你的專案目錄跑 `ccc-router init`。

### 環境需求
- windows
- powershell
- 就這樣，不用任何 runtime。

### 語法規則
- **巢狀分流**：value 是物件時代表命名空間，可繼續往下分流；value 是字串時代表這是一條指令。路由時逐 token 比對 key 的第一個字（`"uncommit ^0=1"` 的 routable 名稱是 `uncommit`）。
- **參數簽章**：key 在子指令名後面可宣告參數 `^0 ^1 ...` 或具名 `^name ^email ...`，並可用 `^key=default` 給預設值。預設值本身可引用 `$VAR`（會用 variables 的值展開）。
- **參數填值**：呼叫時在指令尾端依序提供值，依「在簽章裡出現的順序」填入各參數（不論是數字或具名）。沒提供且沒有預設值，就在送進 powershell 前一次列出全部缺漏：`Expected param(s): ^name ^email`。超過簽章宣告數量的參數仍會被使用，接在最尾。
- **variables 變數**：value 裡的 `$VAR` / `${VAR}` 在執行時由 powershell 在隔離 scope 內展開（variables 同時也會 export 成 process 環境變數供子程序讀取）。沒在 variables 設定的變數（如 `$PROFILE`）交給 powershell 原生解析。
- **執行前回顯**：每次執行前印出 `> ...`，其中有設定在 variables 的 `$VAR` 會顯示成實際值，未設定的保留原樣。

### 美化器
`editor\vscode-cccrouter-syntax` 是一個用於美化 cccrouter.json 編輯器的 vscode 插件——把 `cccrouter.json` 當成 PowerShell 上色，同時讓 ccc 的佔位符（`${var}`、`$var`、`^n`、`^n=default`）醒目。

#### 調整 VSCode 的語法顏色
若要調整 cccrouter.json 的語法顏色，在 `/.vscode/settings.json` 加上:

```json
{
    "editor.semanticHighlighting.enabled": true,
    "editor.semanticTokenColorCustomizations": {
        "rules": {
            "cccPlaceholder": { "foreground": "#f1d900", "fontStyle": "bold" },
            "cccPositional": { "foreground": "#ff4dbb", "fontStyle": "bold" },
            "cccDefault": { "foreground": "#4646db", "fontStyle": "bold" },
            "cccCommand": { "foreground": "#dcdcaa", "fontStyle": "bold" },
            "cccKeyword": { "foreground": "#c586c0", "fontStyle": "bold" },
            "cccParameter": { "foreground": "#9cdcfe" },
            "cccOperator": { "foreground": "#d4d4d4" },
            "cccString": { "foreground": "#ce9178" }
        }
    }
}
```
就會覆蓋預設顏色設定，存檔後執行 **Developer: Reload Window** 即生效。

> *Alternative*: 
-`Ctrl+Shift+P` → **CCC Router Syntax: Customize Colors** 將預設顏色設定寫入使用者層級 settings.json 供編輯。
`Ctrl+Shift+P` → **CCC Router Syntax: Reset Colors** 移除使用者層級 settings.json 裡的顏色設定，恢復預設值。

### 未來計畫
- 一個 prompt 讓 agent 從專案判斷常用的指令寫進 cccrouter.json & 一個 skill 告訴 agent 如何使用 ccc
