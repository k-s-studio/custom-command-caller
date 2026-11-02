# 專案架構與設計

## 安裝方式
從 GitHub repo clone main 分支，在本地 repo 執行 .\ccc-router install

## 指令表

### Repo 層級 (安裝前使用)
- `.\ccc-router install` 只安裝指令工具。
- `.\ccc-router install --beauty --vscode` 安裝指令工具 + 美化器 VSCode 插件。

### 全域層級 (安裝後使用)
- `ccc-router init` 在當前目錄新增 cccrouter.json (從`/.ccc`複製模板)。
- `ccc-router status` 檢查`/.ccc`裡是否有缺少檔案或毀損、檢查是否已安裝美化器插件、檢查 GitHub main 自安裝以來是否有動到工具本身（`scripts/`、`components/`）的更新。
- `ccc-router upgrade` 從 GitHub 抓取最新版本的工具，如果已安裝美化器插件則一同更新。
- `ccc-router template` 用筆記本開啟`/.ccc`裡的cccrouter.json模板，供使用者編輯。
- `ccc-router uninstall` 移除 ccc, ccc-router 與美化器插件。不用刪除經由 init 產生的 cccrouter.json。
- `ccc-router uninstall --stay-beauty` 移除 ccc, ccc-router 但保留美化器插件。
- `ccc-router beauty install --vscode` 已安裝 ccc-router 但未安裝美化器插件時，安裝美化器插件。
- `ccc-router beauty uninstall --vscode` 只移除美化器插件。
- `ccc-router --help` 印出可用指令。

### 專案層級 (全域可呼叫但依賴當下目錄的 cccrouter.json)
- `ccc <command> [args]` 根據 cccrouter.json 執行用戶自訂指令 。

---
# 機制說明

## ccc / ccc-router 機制說明

### 兩個指令
- `ccc <command...> [args...]`（`ccc.ps1`）：純路由。讀 `cccrouter.json`，把指令映射成 powershell 指令並以隔離 scope 執行。
- `ccc-router`（`ccc-router.ps1`）：管理用途——`init` / `template` / `status` / `install` / `upgrade` / `uninstall` / `beauty`。每個子指令都轉呼叫對應的 `*.ps1`（`template` 例外，直接 inline 用記事本開 `~/.ccc/cccrouter.json`；`beauty install` 轉呼 `install-highlighter.ps1`、`beauty uninstall` 轉呼 `uninstall.ps1 --beauty`，只動插件、不碰 ccc 工具本身）。

### ccc 執行流程

```
ccc <command...> [args...]
  ↓
讀取 cccrouter.json
  ↓
逐 token 走 commands 樹（value 是物件→命名空間，繼續往下；是字串→這是一條指令）
  ↓
解析命中 key 的簽章「<name> ^a=def ^b=def」，用 CLI args 依序填各參數（^0/^name…）
（缺值用簽章預設；再缺則送進 powershell 前一次列出「Expected param(s): ^a ^b」）
  ↓
回顯 > <實際指令>（設定在 variables 的 $VAR 會顯示成實際值）
  ↓
以子 scope 執行 scriptblock（原生程式的輸出直接接在主控台上）
```

### 路由與簽章

- key 的「第一個空白前 token」是 routable 名稱：`"uncommit ^0=1 ^1=--soft"` → `uncommit`、`"git"` → `git`。路由時逐 token 比對這個名稱。
- 其餘 token 是參數宣告：`^key`（必填）或 `^key=default`（可省略）。`^key` 可為數字 `^0` 或具名 `^name`。預設值可引用 `$VAR`，會用 `variables` 的值展開（例：`^0=$DEFAULT_MIGRATION_NAME` → `AAAA`）。
- value 用 `^key` 引用參數，可重排、可夾在字面值中間（`git reset HEAD~^0 ^1`、`user.name ^name`）。
- CLI args 依參數「在簽章裡出現的順序」填入；超過宣告數量的 CLI 參數，直接接在指令尾端。

```jsonc
// ccc git uncommit 3            → git reset HEAD~3 --soft
// ccc git uncommit 1 --hard     → git reset HEAD~1 --hard
// ccc git user Rick a@b.com     → git config --local user.name Rick; git config --local user.email a@b.com
// ccc git user                  → 報錯：Expected param(s): ^name ^email
// ccc git exclude               → 報錯：Expected param(s): ^0
"git": {
    "uncommit ^0=1 ^1=--soft": "git reset HEAD~^0 ^1",
    "user ^name ^email": "git config --local user.name ^name; git config --local user.email ^email",
    "exclude ^0": "Add-Content .git/info/exclude ^0"
}
```

### variables 變數

事前 regex 驗證**已移除**。`$VAR` 的處理規則：

- value 裡的 `$VAR` / `${VAR}` 在執行時由 powershell 在隔離 scope 內展開；`variables` 同時也會 export 成 process 環境變數，供指令 spawn 的子程序（dotnet/EF 等）透過 `$env:...` 讀取。
- 沒在 `variables` 設定的 `$`（automatic variable `$PROFILE`/`$HOME`、`$env:VAR`、一般賦值 `$x = ...`）照 powershell 原生規則運作，不受 ccc 干涉。
- `${VAR}`（帶大括號）在需要界定變數名邊界時仍必要，例如 `${EXTS_VERSION}.vsix`——裸寫 `$EXTS_VERSION.vsix` 在 scriptblock 會被當成對 `$EXTS_VERSION` 的 `.vsix` 成員存取而壞掉。

```jsonc
// ✅ 讀系統既有值，不需在 variables 宣告，也不會被 ccc 的 variables 蓋掉
"profile": "notepad $PROFILE.CurrentUserAllHosts",
"open":    "code $env:USERPROFILE/projects",

// ✅ 中間值可用一般 PS 賦值；${VAR} 仍是 variables 管理的變數
"pack": "$dir = Split-Path ${PCKG_DIR}; code --install-extension $dir/foo.vsix"
```

### 回顯

執行前印 `> <實際指令>`：其中設定在 `variables` 的 `$VAR` / `${VAR}` 會替換成實際值（所以你看到的就是 powershell 會收到的內容），未設定的（如 `$PROFILE`）保留原樣交給 powershell。
當指令是兩行併一行，則輸出成兩行。
```powershell
PS: C:\> ccc test
> echo 1
> echo 2
1
2
```

### 執行 scope

```powershell
foreach ($var in $config.variables.PSObject.Properties) {
    [Environment]::SetEnvironmentVariable($var.Name, $var.Value, "Process")
}
& {
    param($__cccCommand, $__cccVariables)
    foreach ($__cccVariable in $__cccVariables) { Set-Variable -Name $__cccVariable.Name -Value $__cccVariable.Value }
    Remove-Variable __cccVariable, __cccVariables -ErrorAction SilentlyContinue
    & ([scriptblock]::Create($__cccCommand))
} $resolved @($config.variables.PSObject.Properties)
```

指令在子 scope 執行，`variables` 裡定義的變數注入成 PS 變數。字串插值（`"$(...)"`）與管線在 scriptblock 內完全正常運作。env var 只設在 ccc 這個短命 process，不會外洩到使用者 shell。PowerShell 是動態 scope，ccc.ps1 自己的 script 變數（`$config`、`$Tokens` 等）在指令裡仍讀得到，指令不要依賴或撞名。

**一定要用 `&` 當一般陳述式呼叫，不能用 `InvokeWithContext` 這類 .NET 方法**：.NET 呼叫會把輸出收集成集合再回傳，PowerShell 因此把原生程式（node、dotnet、git…）的 stdout 重導向——(1) 指令結束前畫面上什麼都看不到；(2) Windows PowerShell 5.1 用主控台字碼頁（繁中 Windows 是 Big5）解讀收集到的 UTF-8 位元組，中文與框線字元變亂碼。以 `&` 陳述式呼叫時，原生程式的 stdout 直接接在主控台上：即時、不經解碼。（舊版用 `InvokeWithContext`，就有這兩個問題。）

`cccrouter.json` 以 `Get-Content -Encoding UTF8` 讀取：5.1 讀沒有 BOM 的檔案預設用 ANSI 字碼頁，設定檔裡的中文會壞掉。

### 參數語法

| 語法 | 說明 |
|------|------|
| `^0` / `^name`（value 裡） | 引用對應參數 |
| `^0` / `^name`（key 簽章裡） | 宣告為必填參數 |
| `^0=default` / `^name=default` | 簽章裡帶預設值，可省略；預設可為 `$VAR` |
| `^0=` | 預設為空字串 |
| 超過宣告數量的參數 | 直接接在指令尾端 |

### 撰寫需要切換目錄的指令

ccc 永遠在 `cccrouter.json` 所在目錄（專案根目錄）執行。
若指令需要在子目錄執行（例如 `vsce package`），用 `Push-Location` / `Pop-Location`：

```jsonc
"ext-update": "Push-Location ${EXTS_DIR}; npx --yes @vscode/vsce package; Pop-Location; code --install-extension ${EXTS_DIR}/cccrouter-syntax-${EXTS_VERSION}.vsix --force"
```

### 安裝機制

`install.ps1` 是 **repo 限定的 bootstrap**，由 repo 根目錄的 `ccc-router.bat`（`.\ccc-router install`）直接呼叫，**本身不會被裝進 `~/.ccc`**：
1. 把 `ccc.ps1`、`ccc-router.ps1`（及 `uninstall.ps1` / `install-highlighter.ps1` / `status.ps1` / `upgrade.ps1`，**不含 `install.ps1` 自己**）以及兩個現成 wrapper `scripts/ccc.cmd` / `scripts/ccc-router.cmd` 一起複製到 `~/.ccc/`。wrapper 用 `%~dp0` 解析旁邊的 `.ps1`，所以複製到哪都對、不需要在腳本裡 hardcode 內容。
2. 把 `components/cccrouter.json` 模板複製到 `~/.ccc/cccrouter.json`（給 `ccc-router init` 用）
3. 寫 `~/.ccc/.base`（一行 commit hash，`git -C <repo> rev-parse HEAD`），給 `status` / `upgrade` 自我檢查。**只在抓得到真 commit 時才寫**；抓不到（如從已安裝副本重跑、非 git 來源）就保留舊 `.base`，不要蓋掉好的紀錄。順手刪掉舊版留下的 `install.json`。
4. 把 `~/.ccc` 加進 user PATH
5. 帶 `--beauty --vscode` 時一併安裝 highlighter 插件

因為 install 已把腳本 + 模板 + commit stamp 都放進 `~/.ccc`，**裝完之後 clone 來的 repo 就可以刪**，`status` / `upgrade` 都不依賴它。

`ccc-router init` 不再 hardcode 模板，而是把 `~/.ccc/cccrouter.json` 複製到當前目錄；沒有就報錯叫你先 `ccc-router install`（契約就是 install 先、init 後）。`components/cccrouter.json` 是模板的 single source of truth，會合併進 main；repo 根目錄的 `cccrouter.json` 列在 `.dev-files`，只留在 dev。

**`install` 為什麼是 repo 限定**：repo 根目錄的 `ccc-router.bat` 和 install.ps1 寫進 `~/.ccc` 的 `ccc-router.cmd` 是**兩個不同的 wrapper**，各自指向不同邏輯——
- repo 的 `ccc-router.bat`：只認 `install`，把它(連旗標)轉呼 `scripts/install.ps1`；其他子指令一律擋下並提示「裝完才有」。
- `~/.ccc/ccc-router.cmd`：指向 `~/.ccc/ccc-router.ps1`，那支 router **根本沒有 `install` case**（只有 init / template / status / upgrade / uninstall / beauty / --help）。打 `ccc-router install` 只會印一行「install 要在 repo 跑、更新請用 upgrade」就結束。

所以「限定在 repo 層」不是靠 runtime 偵測，而是**安裝後那一份壓根不帶 install**：install.ps1 不複製、router 沒有 install case、`upgrade` 下載清單與 `status` 健檢清單也都不含 install.ps1。從 repo 重跑 `.\ccc-router install` 仍會就地覆蓋升級（`ccc.ps1` 換新、補上 `ccc-router.*`，PATH 已存在那筆不變）。注意 `ccc init` / `ccc verify` 等舊子指令已移除（移到 `ccc-router`）。

`status.ps1`：列出 `ccc tool`（`~/.ccc` 裡 install.ps1 該放的檔都在 → `healthy`，缺檔 → `corrupted`）與 `vscode beautifier`（即時 `code --list-extensions` 比對 `*cccrouter-syntax*`，只看裝沒裝、不管版號）。再 best-effort 打 GitHub `compare/<.base>...main`，讀回傳的 `files[]`（區間 `.base`→`main` 的累積淨變動），**只要任一 `filename` 以 `scripts/` 或 `components/` 開頭就視為工具有更新**、印 `Note: New version exists...`；否則（README / SPEC / editor-only 的 commit）視為雜訊、不提示。用 `files[]` 前綴比對而非 `ahead_by`，就是為了讓「只改文件」的 commit 不再誤報。網路或 API 失敗（含 4xx、timeout）就靜默略過；`.base` 不存在也不印。

`upgrade.ps1`：從 `raw.githubusercontent.com/<repo>/main` 抓 6 個腳本（不含 repo 限定的 `install.ps1`）+ 模板，**先全部下載到 temp、成功才覆蓋** `~/.ccc`（任何一個 404/失敗就中止，不留半套）。為了不讓 upgrade 覆蓋到正在執行的自己，`ccc-router upgrade` 會先把 `~/.ccc/upgrade.ps1` 複製到 temp、再從 temp 那份執行；因此覆蓋 `~/.ccc` 裡的 `upgrade.ps1` / `ccc-router.ps1` 時，動到的都不是當前正在跑的那個檔。模板（`cccrouter.json`）是使用者資料，**只在不存在時才補**，不覆蓋。最後用 `commits/main` 的 sha 重寫 `.base`（一行 hash），並刪掉舊版的 `install.json`。**若偵測到已安裝美化器插件，會一併用最新 Release 重裝插件**（呼叫剛更新好的 `install-highlighter.ps1`），與 SPEC「如果已安裝美化器插件則一同更新」一致。

`uninstall.ps1`：預設**連 beautifier 插件一起移除**（`code --uninstall-extension`，id 用即時 `code --list-extensions` 比對 `*cccrouter-syntax*` 拿，不靠 manifest）+ 從 PATH 移除 `~/.ccc` 並刪資料夾。`--stay-beauty` 留插件只移指令；`--beauty`（即 `ccc-router beauty uninstall` 走的內部路徑）只移插件留指令。當 `ccc-router uninstall` 是從已安裝的副本執行時，自身的 `ccc-router.cmd` 被 cmd.exe 鎖住，會 fallback 成 detached cmd 等本 terminal 釋放後再刪。

### Highlighter

高亮由 `editor/vscode-cccrouter-syntax/extension.js` 的 semantic tokens provider 提供（不是 tmLanguage）。除了 ccc 自己的 `^key` / `$VAR` 佔位符，還會把 `commands` 裡的指令模板**當成 PowerShell 上色**（命令、關鍵字、參數、運算子、字串），讓 value 讀起來就像在 `.ps1` 裡。token 類型與 tokenizer 細節見下方「自訂顏色」。發佈走 GitHub Release，細節見 `editor/vscode-cccrouter-syntax/.instructions.md`。

## cccrouter-syntax

VS Code extension，讓 `cccrouter.json` 裡指令模板中的 `$PARAM` 佔位符顯示成不同顏色，方便一眼看出哪裡是參數。

實作方式是 `extension.js` 註冊一個 semantic tokens provider，只對檔名為 `cccrouter.json` 的檔案生效，不影響一般 JSON 檔案。檔案本身仍維持 `json`/`jsonc` language id，所以 VS Code 內建的 JSON 語法檢查（錯誤底線、schema 驗證）不受影響。

執行 extension 本身只需要 VS Code 內建的 extension host（自帶 Node.js runtime），不需要額外安裝任何 runtime；只有「打包」這個開發步驟需要用到 `npx`/Node。

### 安裝（推薦）

用 ccc-router 內建指令從 GitHub Release 安裝最新發佈的版本（不需要 Node）：

```powershell
ccc-router install --beauty --vscode
```

這會下載最新 Release 的 `cccrouter-syntax-*.vsix`，透過 `code --install-extension` 正式安裝（VS Code 會像管理一般 extension 一樣管理它），裝完 reload window 即可生效。

### 修改語法定義後套用本機版

如果你改了 `package.json` / `extension.js` / 語法定義，想直接套用本機版本（會用 `vsce package` 從原始碼建置，需要 Node）：

```powershell
ccc-router install --beauty --vscode --local
```

`.vsix` 不再進版控，正式發佈一律走 GitHub Release：在 `package.json` 把 `version` 加上去，再到 GitHub Actions 手動跑 **Release highlighter extension** workflow，CI 會打包並建立對應的 Release。

> 不要手動把這個資料夾複製或建立 symlink 到 VS Code 的 `extensions` 目錄——那不是 VS Code 認可的安裝流程，版本更新也不會被正確追蹤。一律透過 `.vsix` + `code --install-extension` 安裝。

### 自訂顏色

`extension.js` 會回報 8 種 semantic token type，分兩類。

**ccc 自己的佔位符**（key 簽章與 value 皆會比對）：

- `${VAR}`、`$VAR`（對應 `variables` 設定的變數，也是 PowerShell 變數）→ `cccPlaceholder`
- `^key`（參數標記，可為數字 `^0` 或具名 `^name`；出現在 key 簽章 `^key=default` 或 value `HEAD~^0` 中）→ `cccPositional`
- `=default`（簽章 `^key=default` 裡 `^key` 後面的預設值，含 `=`）→ `cccDefault`

**PowerShell 語法**（只在 `commands` 子樹的 value 裡比對）：

- 命令位置的字（statement 開頭、`;` `|` `&&` `||` `&` `(` `{` 之後的第一個 token）→ `cccCommand`；若該字是 PowerShell 關鍵字（`if` / `foreach` / `return` …）則改成 `cccKeyword`
- `-Name` / `--long` 旗標（在參數位置）→ `cccParameter`；但若是字運算子（`-eq` / `-notin` / `-and` …）→ `cccOperator`
- `;` `|` `&&` `||` `&` 等分隔/管線 → `cccOperator`
- 引號字串 `'...'` 與 JSON 轉義的 `\"...\"` → `cccString`（雙引號字串裡的 `$VAR` 會被切出來留給 `cccPlaceholder`）

> 一般的引數裸字（路徑、子指令如 `git` 後面的 `config`）不上色，保留 JSON 字串本色，讓「命令 / 旗標 / 字串」三者跳出來。

#### Tokenizer 架構

不是逐行 regex，而是對整份文件做一次線性掃描（`collectTokens`），邊掃邊維護 JSON 結構：物件/陣列的進出、每個字串是 key 還是 value（看後面第一個非空白字元是不是 `:`）、以及它屬於哪個頂層區段（`stack[1].key`，即 `commands` / `variables`）。因為知道結構，才能：

- 只把 `commands` 子樹的 **value** 餵給 PowerShell lexer（`lexCommandValue`），`variables` 的值（如 `"Development"`）不會被誤判成命令；
- key 簽章另走 `lexKeySignature`（只認 `^key` / `=default` / `$VAR`）；
- 字串裡的 `{` `}`（如 scriptblock `... { git push ^0}`）不會被當成 JSON 結構誤算巢狀深度。

`lexCommandValue` 是一個單行、無跨行狀態的小型 PowerShell 掃描器（JSON value 不含實體換行）：維護一個「是否在命令位置」的旗標，遇到 `;` `|` `&` `(` `{` 重設為 true、輸出 token 後設 false。`$VAR` 與 `^key` 一律切出來交給佔位符規則，雙引號字串內的 `$VAR` 也會切出，所以所有 token **不重疊**（`provider` 只做一次 `sort` 後 `push`，不需去重）。

> 已知取捨：賦值右側不算命令位置（`$dir = Split-Path ...` 的 `Split-Path` 不會上命令色），數字字面值也不另外上色——寧可少上色，也不要把字面值誤標成命令。

#### 不需重新打包就能改顏色

extension 的 `configurationDefaults` 只是**預設值**，會被使用者 / 工作區的 `settings.json` 覆蓋。改 `settings.json` 後只要 **Developer: Reload Window** 即可生效，不需要重新打包 vsix、也不需要 Node。

本 repo 已在 `.vscode/settings.json` 把全部顏色接出來，要換色直接改那裡的 `foreground` 即可（工作區設定，整個團隊共用）。也可以改成放使用者層級的 `settings.json`，只挑想換的 token 覆蓋即可：

```json
"editor.semanticTokenColorCustomizations": {
    "rules": {
        "cccPlaceholder": { "foreground": "#11bee9", "fontStyle": "bold" },
        "cccPositional": { "foreground": "#ccc059", "fontStyle": "bold" },
        "cccDefault": { "foreground": "#8a8a8a", "fontStyle": "bold" },
        "cccCommand": { "foreground": "#dcdcaa", "fontStyle": "bold" },
        "cccKeyword": { "foreground": "#c586c0", "fontStyle": "bold" },
        "cccParameter": { "foreground": "#9cdcfe" },
        "cccOperator": { "foreground": "#d4d4d4" },
        "cccString": { "foreground": "#ce9178" }
    }
}
```

> 只有「顏色」能這樣外接；要改「哪些文字被上色」（比對規則）還是得改 `extension.js` 並重新打包。新增 token type（像這次的 `cccCommand` / `cccKeyword` / `cccParameter` / `cccOperator` / `cccString`）也屬於需要打包的改動。

#### 兩個換色指令（Command Palette）

除了手動編輯 `settings.json`，extension 另外註冊兩個指令，讓不熟悉 token 名稱的使用者也能換色：

- **`CCC Router Syntax: Customize Colors`**（`cccrouter.customizeColors`）：把 `configurationDefaults` 裡所有 `ccc*` 規則補進**使用者層級** `settings.json` 的 `editor.semanticTokenColorCustomizations.rules`，當作編輯起點，接著開啟 `settings.json`。採「補缺」策略——**已存在的 token 顏色一律不覆蓋**，所以重跑是安全的；若八個 token 都已寫入則跳過寫入、直接開檔。
- **`CCC Router Syntax: Reset Colors`**（`cccrouter.resetColors`）：只從使用者設定移除 `ccc*` 規則，讓顏色退回 extension 預設值。使用者自己加的非 `ccc` 規則保留不動；若移除後 `rules` 空了、整個設定物件也空了，就把整個設定清成 `undefined`，不留 `{ "rules": {} }` 空殼。

設計重點：

- 兩個指令的顏色來源是**執行期從 extension 自己的 `packageJSON.contributes.configurationDefaults` 讀回來**（`context.extension.packageJSON`），不在 `extension.js` 另存一份，維持 `configurationDefaults` 為唯一真實來源、不會漂移。
- 寫入走 VSCode 官方 `WorkspaceConfiguration.update(..., ConfigurationTarget.Global)`，由 VSCode 自己的 JSON 編輯機制改檔，**保留 `settings.json` 其餘部分的註解與格式**（這是用腳本純文字改檔做不到的，也是為什麼換色不做成 `ccc-router` CLI 子指令）。
- 取捨：一旦 `Customize Colors` 把值寫進使用者設定，該使用者就**脫離 `configurationDefaults` 的後續更新**（使用者設定永遠蓋過預設值）。日後改了預設配色，已 customize 的使用者收不到，要 `Reset Colors` 才會退回。

### 發佈新版美化器流程
1. 在 `editor\vscode-cccrouter-syntax\package.json` 把 `version` 加上去。
2. 到 GitHub 的 **Actions → Release highlighter extension**，在 `dev` 分支按 **Run workflow**。
3. CI 會用 `vsce package` 打包，並建立對應 `vX.Y.Z` 的 Release 掛上 `.vsix`。之後使用者 `ccc-router install --beauty --vscode` 就會抓到新版。