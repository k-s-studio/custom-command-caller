## 說明
ccc 是一個command router。
```
`ccc {custom key} {custom optional params...}` 
```
例如
```
ccc git-exclude {file} => Add-Content .git/info/exclude '`n{file}'
```
在`cccrouter.json`自訂需要的指令與參數。
```
{
    "params": {
        "ENV_LOCAL": "Development",
        "DbContext": "CccDbContext",
    },
    "commands": {
        "git-exclude": "Add-Content .git/info/exclude {0}",
        "db-reset":"dotnet ef migrations remove --context ${DbContext} -- --environment ${ENV_LOCAL}"
    }
}
```

### 基本規格

註冊指令至系統層級，然後在任何專案的目錄使用 `ccc`。
- `ccc init`: 新增空白的 cccrouter.json 模板。
- `ccc verify`: 驗證所有 cccrouter.json 指令需要的參數都被設置，可以是空值，但至少要有鍵。
- `ccc <custom-command-key>`: 將 cccrouter.json 裡對應的指令與參數送給powershell，以隔離的 scope 執行。

### Quick Start
Step 1 - Clone the repo. 
Step 2 - 在 ccc repo 目錄使用 `ccc install` 或者 `.\ccc install` 註冊指令至系統層級。
Step 3 - 如果你使用 vscode，考慮安裝專用於美化 cccrouter.json 的 highlighter。
  ```
  ccc highlighter install --vscode
  ```
Step 4 - 回到你的專案目錄跑 `ccc init`。

### 美化器
`editor\vscode-cccrouter-syntax` 是一個用於美化 cccrouter.json 編輯器的 vscode 插件，讓字串裡的placeholder: `${var}`, `$var`, `{n}`, `{m=default}` 變得醒目。

調整 `editor\vscode-cccrouter-syntax\syntaxes\cccrouter.tmLanguage.json` 成為你的 own-style。最後再執行一次 `ccc highlighter install --vscode` 套用變更。

### 環境需求
- windows
- powershell
- 就這樣，不用任何 runtime。

### 語法規則
- 在指令中需要的參數必須宣告。可以為空值，但要有鍵。
- 使用 `ccc` 可以在 commands 尾加上不限長度的參數 它們依數字順序填入被動placeholder {0}, {1}, {2}, ...，超過 placeholder 數量的參數仍會被使用，接在最尾。

### 未來計畫
- 調整 readme，作為完整規格文件
- 有個 prompt 讓 agent 幫我抓需要的值，再有個 skill 告訴 agent 如何使用 router