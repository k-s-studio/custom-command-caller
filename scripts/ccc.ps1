param(
    [Parameter(Position=0)]
    [string]$Command,
    [Parameter(Position=1, ValueFromRemainingArguments=$true)]
    [string[]]$ExtraArgs
)

$configFileName = "cccrouter.json"

function Get-Config {
    $configPath = Join-Path (Get-Location) $configFileName
    if (-not (Test-Path $configPath)) {
        Write-Host "cccrouter.json not found. Run 'ccc init' to create one."
        exit 1
    }
    try {
        return Get-Content $configPath -Raw | ConvertFrom-Json
    } catch {
        Write-Host "Invalid cccrouter.json: $_"
        exit 1
    }
}

function Get-UsedParams($text) {
    $found = [regex]::Matches($text, '\$\{([A-Za-z_]\w*)\}')
    return ($found | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
}

# resolves {0}, {1}, {0=default} positional placeholders against CLI args.
# args up to the highest placeholder index fill the placeholders in order;
# anything beyond that is returned as "Remaining" to be appended at the end.
function Resolve-PositionalArgs([string]$template, [string[]]$extraArgs) {
    if ($null -eq $extraArgs) { $extraArgs = @() }

    $pattern = '\{(\d+)(?:=([^{}]*))?\}'
    $placeholders = [regex]::Matches($template, $pattern)
    if ($placeholders.Count -eq 0) {
        return [PSCustomObject]@{ Template = $template; Remaining = $extraArgs }
    }

    $maxIndex = ($placeholders | ForEach-Object { [int]$_.Groups[1].Value } | Measure-Object -Maximum).Maximum
    $values = @{}
    for ($i = 0; $i -le $maxIndex; $i++) {
        if ($extraArgs.Count -gt $i) {
            $values[$i] = $extraArgs[$i]
            continue
        }
        $withDefault = $placeholders | Where-Object { [int]$_.Groups[1].Value -eq $i -and $_.Groups[2].Success } | Select-Object -First 1
        if ($null -eq $withDefault) {
            Write-Host "missing positional argument: {$i}"
            exit 1
        }
        $values[$i] = $withDefault.Groups[2].Value
    }

    $resolved = $template
    for ($i = $placeholders.Count - 1; $i -ge 0; $i--) {
        $m = $placeholders[$i]
        $idx = [int]$m.Groups[1].Value
        $resolved = $resolved.Remove($m.Index, $m.Length).Insert($m.Index, $values[$idx])
    }

    $consumed = $maxIndex + 1
    $remaining = @()
    if ($extraArgs.Count -gt $consumed) {
        $remaining = $extraArgs[$consumed..($extraArgs.Count - 1)]
    }
    return [PSCustomObject]@{ Template = $resolved; Remaining = $remaining }
}

# no command
if (-not $Command) {
    Write-Host "Usage: ccc <command> [args]"
    Write-Host "       ccc init      create cccrouter.json template in current directory"
    Write-Host "       ccc verify    verify all parameters in cccrouter.json are configured"
    exit 0
}

# ── init ──────────────────────────────────────────────────────────────────────
if ($Command -eq "init") {
    $configPath = Join-Path (Get-Location) $configFileName
    if (Test-Path $configPath) {
        Write-Host "cccrouter.json already exists."
        exit 1
    }
    $template = @'
{
    "params": {
        "ENV_LOCAL": "",
        "DbContext": "",
        "EF_MIGRATION_CSPROJ_PATH":"",
        "EF_STARTUP_PROJECT_PATH" : "",
        "DefaultMigrationName" : ""
    },
    "commands": {
        "hide": "Add-Content .git\\info\\exclude \"`ncccrouter.json\"",

        "rebase": "git pull --rebase",
        "git-uncommit": "git reset HEAD~1",
        "git-exclude": "Add-Content .git\\info\\exclude",

        "db-update": "dotnet run --project ${EF_STARTUP_PROJECT_PATH} -- --settings-base-path ${EF_STARTUP_PROJECT_PATH} --environment ${ENV_LOCAL}",
        "db-reset":"dotnet ef migrations remove --context ${DbContext} -p ${EF_MIGRATION_CSPROJ_PATH} -s ${EF_STARTUP_PROJECT_PATH} -- --environment ${ENV_LOCAL}",
        "ef-list": "dotnet ef migrations list --context ${DbContext} -p ${EF_MIGRATION_CSPROJ_PATH} -s ${EF_STARTUP_PROJECT_PATH}",
        "ef-add": "dotnet ef migrations add ${DefaultMigrationName} --context ${DbContext} -p ${EF_MIGRATION_CSPROJ_PATH} -s ${EF_STARTUP_PROJECT_PATH} -o Migrations"
    }
}
'@
    Set-Content $configPath $template -Encoding UTF8
    Write-Host "Created cccrouter.json"
    if (Test-Path (Join-Path (Get-Location) ".git")) {
        Write-Host "Tip: git detected. Use 'ccc hide' to exclude cccrouter.json from this repo."
    }
    exit 0
}

# ── verify ────────────────────────────────────────────────────────────────────
if ($Command -eq "verify") {
    $config = Get-Config
    $usedParams = @()
    foreach ($cmd in $config.commands.PSObject.Properties) {
        $usedParams += Get-UsedParams $cmd.Value
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

$cmdTemplate = $cmdEntry.Value

# verify every $VAR / ${VAR} param referenced in the template is configured
$hasErrors = $false
foreach ($paramName in (Get-UsedParams $cmdTemplate)) {
    $entry = $config.params.PSObject.Properties[$paramName]
    if ($null -eq $entry -or [string]::IsNullOrEmpty($entry.Value)) {
        Write-Host "unconfigured parameter: `$$paramName"
        $hasErrors = $true
    }
}
if ($hasErrors) {
    exit 1
}

# resolve {0}, {1}, {0=default} positional placeholders from CLI args;
# args beyond the highest placeholder index are appended at the end
$positional = Resolve-PositionalArgs $cmdTemplate $ExtraArgs
$commandText = $positional.Template
if ($positional.Remaining.Count -gt 0) {
    $commandText = "$commandText $($positional.Remaining -join ' ')"
}

# run in an isolated scope seeded only with the configured params, so
# PowerShell expands $VAR / ${VAR} natively without touching ccc's own state
$variables = [System.Collections.Generic.List[psvariable]]::new()
foreach ($param in $config.params.PSObject.Properties) {
    $variables.Add([psvariable]::new($param.Name, $param.Value))
}

Write-Host "> $commandText"
[scriptblock]::Create($commandText).InvokeWithContext($null, $variables, $null)
