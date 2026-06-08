param(
    [Parameter(Position=0)]
    [string]$Command,
    [Parameter(Position=1, ValueFromRemainingArguments=$true)]
    [string[]]$ExtraArgs
)

$configFileName = "cmdrouter.json"

function Get-Config {
    $configPath = Join-Path (Get-Location) $configFileName
    if (-not (Test-Path $configPath)) {
        Write-Host "cmdrouter.json not found. Run 'ccc init' to create one."
        exit 1
    }
    try {
        return Get-Content $configPath -Raw | ConvertFrom-Json
    } catch {
        Write-Host "Invalid cmdrouter.json: $_"
        exit 1
    }
}

# no command
if (-not $Command) {
    Write-Host "Usage: ccc <command> [args]"
    Write-Host "       ccc init      create cmdrouter.json template in current directory"
    Write-Host "       ccc verify    verify all parameters in cmdrouter.json are configured"
    exit 0
}

# ── init ──────────────────────────────────────────────────────────────────────
if ($Command -eq "init") {
    $configPath = Join-Path (Get-Location) $configFileName
    if (Test-Path $configPath) {
        Write-Host "cmdrouter.json already exists."
        exit 1
    }
    $template = @'
{
    "params": {
        "DbContext": "",
        "env": "Development"
    },
    "commands": {
        "db-update": "dotnet ef database update --context $DbContext -p Models -s Api -- --environment $env",
        "db-migration": "dotnet ef migrations add $MigrationName --context $DbContext -p Models -s Api",
        "git-reset": "git reset HEAD~1",
        "git-exclude": "Add-Content .git\\info\\exclude \"`ncmdrouter.json\""
    }
}
'@
    Set-Content $configPath $template -Encoding UTF8
    Write-Host "Created cmdrouter.json"
    if (Test-Path (Join-Path (Get-Location) ".git")) {
        Write-Host "Tip: git detected. Use 'ccc git-exclude' to exclude cmdrouter.json from this repo."
    }
    exit 0
}

# ── verify ────────────────────────────────────────────────────────────────────
if ($Command -eq "verify") {
    $config = Get-Config
    $usedParams = @()
    foreach ($cmd in $config.commands.PSObject.Properties) {
        $found = [regex]::Matches($cmd.Value, '\$([A-Za-z_]\w*)')
        foreach ($m in $found) {
            $usedParams += $m.Groups[1].Value
        }
    }
    $usedParams = $usedParams | Select-Object -Unique
    $hasErrors = $false
    foreach ($param in $usedParams) {
        $entry = $config.params.PSObject.Properties[$param]
        if ($null -eq $entry -or [string]::IsNullOrEmpty($entry.Value)) {
            Write-Host "unconfigured parameter: `$$param"
            $hasErrors = $true
        }
    }
    if (-not $hasErrors) {
        Write-Host "All parameters configured."
    }
    exit 0
}

# ── routing ───────────────────────────────────────────────────────────────────
$config = Get-Config

$cmdEntry = $config.commands.PSObject.Properties[$Command]
if ($null -eq $cmdEntry) {
    Write-Host "Unknown command: $Command"
    exit 1
}

$resolved = $cmdEntry.Value

# substitute params
foreach ($param in $config.params.PSObject.Properties) {
    $resolved = $resolved.Replace("`$$($param.Name)", $param.Value)
}

# check for unresolved placeholders
$unresolved = [regex]::Matches($resolved, '\$([A-Za-z_]\w*)')
if ($unresolved.Count -gt 0) {
    foreach ($m in $unresolved) {
        Write-Host "unconfigured parameter: `$$($m.Groups[1].Value)"
    }
    exit 1
}

# append extra args
if ($ExtraArgs -and $ExtraArgs.Count -gt 0) {
    $resolved = "$resolved $($ExtraArgs -join ' ')"
}

Write-Host "> $resolved"
Invoke-Expression $resolved
