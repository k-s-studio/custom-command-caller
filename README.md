## 說明
ccc 是一個 command router。在 `cccrouter.json` 自訂指令與參數，然後用 `ccc` 呼叫：
```
ccc <command...> <optional positional args...>
```
指令可以巢狀分流，key 同時是「子指令 + 參數簽章」，value 是實際送進 powershell 的模板：
```json
{
    "variables": {
        "ENVIRONMENT": "Development",
        "EF_DB_CONTEXT": "CccDbContext"
    },
    "commands": {
        "profile": "notepad $PROFILE.CurrentUserAllHosts",
        "git": {
            "uncommit ^0=1 ^1=--soft": "git reset HEAD~^0 ^1",
            "user ^name ^email": "git config --local user.name ^name; git config --local user.email ^email",
            "exclude ^0": "Add-Content .git/info/exclude ^0"
        },
        "ef": {
            "roll ^0= ^1=$ENVIRONMENT": "dotnet ef database update ^0 --context $EF_DB_CONTEXT -- --environment ^1"
        }
    }
}
```
參數可以用數字 `^0` 或具名 `^name`；不論哪種，呼叫時都依「在 key 簽章裡出現的順序」依序填入。

對應的呼叫：
```
ccc git uncommit 3            => git reset HEAD~3 --soft
ccc git uncommit 1 --hard     => git reset HEAD~1 --hard
ccc git user Rick a@b.com     => git config --local user.name Rick; git config --local user.email a@b.com
ccc git user                  => 報錯：Expected param(s): ^name ^email
ccc git exclude               => 報錯：Expected param(s): ^0
ccc ef roll                   => dotnet ef database update  --context CccDbContext -- --environment Development
```

### 兩個指令
安裝後會註冊兩個系統層級指令，任何目錄都能用：
- `ccc <command...>`：把對應的指令與參數送給 powershell，以隔離的 scope 執行。
- `ccc-router`：管理用途。
  - 安裝(在 clone 來的 repo 裡執行):
    - `.\ccc-router install`：註冊 `ccc` 與 `ccc-router`。安裝後 clone 來的 repo 就可以刪了。
    - `.\ccc-router install --beauty --vscode`：一併安裝美化器 VSCode 插件。
  - 安裝後(任何目錄都能用):
    - `ccc-router init`：把共用模板複製到當前目錄成為 cccrouter.json。
    - `ccc-router template`：用記事本開啟共用模板 `~\.ccc\cccrouter.json` 編輯。
    - `ccc-router status`：列出安裝狀態(ccc tool / vscode beautifier),並檢查 GitHub 上有沒有新版。
    - `ccc-router upgrade`：直接從 GitHub 抓最新腳本覆蓋安裝(不需要 repo);已安裝美化器插件時一併更新。
    - `ccc-router uninstall`：移除已註冊的指令,**並一併解除安裝 beautifier 插件**(加 `--stay-beauty` 可保留插件)。
    - `ccc-router beauty install --vscode`：已裝 ccc-router、只想補裝美化器插件時用。
    - `ccc-router beauty uninstall --vscode`：只解除安裝美化器插件,保留指令。
    - `ccc-router --help`：印出可用指令。

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
`editor\vscode-cccrouter-syntax` 是一個用於美化 cccrouter.json 編輯器的 vscode 插件，讓字串裡的 placeholder：`${var}`、`$var`、`^n`、簽章 `^n=default` 變得醒目。

高亮由插件的 semantic tokens 提供，三種片段各自有獨立的 token type：`$VAR` / `${VAR}` → `cccPlaceholder`、`^key` → `cccPositional`、簽章預設值 `=default` → `cccDefault`。

#### 調整 VSCode 的語法顏色
若要調整 cccrouter.json 的語法顏色，在 `/.vscode/settings.json` 加上這些:

```json
{
    "editor.semanticHighlighting.enabled": true,
    "editor.semanticTokenColorCustomizations": {
        "rules": {
            "cccPlaceholder": { "foreground": "#f1d900", "fontStyle": "bold" },
            "cccPositional": { "foreground": "#6e4dff", "fontStyle": "bold" },
            "cccDefault": { "foreground": "#d4ce95", "fontStyle": "bold" }
        }
    }
}
```
就會覆蓋預設顏色設定，存檔後執行 **Developer: Reload Window** 即生效。

### 未來計畫
- 直接用 powershell style 渲染 cccrouter value 最後加上 placeholder 醒目
- 調整 readme，作為完整規格文件
- 有個 prompt 讓 agent 幫我抓需要的值，再有個 skill 告訴 agent 如何使用 router
