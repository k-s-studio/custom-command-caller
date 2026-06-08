## 基本規格
- 安裝在系統層級後，能在專案目錄使用指令ccc
- ccc只是一個command的router。使用像是 `ccc {tool operation} {param}` 簡化我常用的工具指令，例如 `ccc git-reset --soft` => `git reset HEAD~1 --soft`，以及`ccc ef db-update` 這樣
- 做這個的目的是因為我的很多專案使用 efcore ，雖然指令變化不大 但是參數都很長；而且切換不同專案使用不同的資料庫來源 DbContext名稱不一樣。然後既然要做就做成不只轉接ef core 其他常用工具都包含。雖然我最常用的也只有git和dotnet ef
- 運作機制：在任何目錄使用時，去找該位置是否有cccrouter.json。
    - cccrouter.json 是設置參數的地方
    - 沒有就不執行任何事情，若有則檢查但需求參數未設定，就顯示「unconfigured parameter: $param」。
- 要有一個init指令，新增空白的cccrouter.json模板
- 有一個verify指令，驗證所有cccrouter.json需要的參數都被設置

### 安裝
- 從GitHub上clone下來，用一行指令或一個執行檔註冊系統指令，就能直接到專案目錄裡跑 `ccc init` 新增cccrouter.json

### 依賴
- 不依賴任何runtime
- 跑在powershell

cccrouter.json 範例:
```
{
    "params":{
        "DbContext" : "SqlDbContext",
        "env" : "Development"
    }
    "commands":{
        "db-update" : "dotnet ef database update --context $DbContext -p Models -s Api -- --environment $env"
    }
}
```

### 未來計畫(本次不實作)
- 調整readme，作為完整規格文件
- 有個prompt讓agent幫我抓需要的值，再有個skill告訴agent如何使用router