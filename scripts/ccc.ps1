param(
    [Parameter(Position=0, ValueFromRemainingArguments=$true)]
    [string[]]$Tokens
)

$configFileName = "cccrouter.json"

function Get-Config {
    $configPath = Join-Path (Get-Location) $configFileName
    if (-not (Test-Path $configPath)) {
        Write-Host "cccrouter.json not found. Run 'ccc-router init' to create one."
        exit 1
    }
    try {
        return Get-Content $configPath -Raw | ConvertFrom-Json
    } catch {
        Write-Host "Invalid cccrouter.json: $_"
        exit 1
    }
}

# substitute $VAR / ${VAR} that ARE configured in params with their values, so the
# echoed line shows real values; references not configured here (e.g. $PROFILE) are
# left untouched for PowerShell to resolve natively at execution time.
function Expand-ConfiguredParams([string]$text, $params) {
    if ($null -eq $params) { return $text }
    return [regex]::Replace($text, '\$(?:\{([A-Za-z_]\w*)\}|([A-Za-z_]\w*))', {
        param($m)
        $name = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
        $p = $params.PSObject.Properties[$name]
        if ($null -ne $p) { return [string]$p.Value }
        return $m.Value
    })
}

# the first whitespace-delimited token of a key is its routable name
# ("uncommit ^0=1 ^1=--soft" -> "uncommit", "git" -> "git").
function Get-KeyName([string]$key) {
    return ($key -split '\s+', 2)[0]
}

if (-not $Tokens -or $Tokens.Count -eq 0) {
    Write-Host "Usage: ccc <command> [args]"
    Write-Host "       ccc-router init       create cccrouter.json in current directory"
    exit 0
}

$config = Get-Config

# ── route: walk the command tree, matching each token against a child key name ──
$node = $config.commands
$i = 0
$template = $null
$matchedKey = $null
while ($true) {
    if ($node -isnot [System.Management.Automation.PSCustomObject]) { break }
    if ($i -ge $Tokens.Count) { break }
    $token = $Tokens[$i]
    $child = $node.PSObject.Properties | Where-Object { (Get-KeyName $_.Name) -eq $token } | Select-Object -First 1
    if ($null -eq $child) {
        Write-Host "Unknown command: $($Tokens[0..$i] -join ' ')"
        exit 1
    }
    $i++
    if ($child.Value -is [string]) {
        $template = $child.Value
        $matchedKey = $child.Name
        break
    }
    $node = $child.Value
}

if ($null -eq $template) {
    if ($node -is [System.Management.Automation.PSCustomObject]) {
        $subs = $node.PSObject.Properties | ForEach-Object { Get-KeyName $_.Name }
        Write-Host "Incomplete command: $($Tokens -join ' '). Available: $($subs -join ', ')"
    } else {
        Write-Host "Unknown command: $($Tokens -join ' ')"
    }
    exit 1
}

$argTokens = @()
if ($Tokens.Count -gt $i) { $argTokens = @($Tokens[$i..($Tokens.Count - 1)]) }

# ── parse the matched key's signature: "<name> ^0=def ^1=def ..." ───────────────
$sigTokens = $matchedKey -split '\s+'
$defaults = @{}     # index -> default text (Expand-ConfiguredParams applied on use)
$declared = @{}     # index -> $true
if ($sigTokens.Count -gt 1) {
    foreach ($t in $sigTokens[1..($sigTokens.Count - 1)]) {
        if ($t -match '^\^(\d+)(?:=(.*))?$') {
            $idx = [int]$Matches[1]
            $declared[$idx] = $true
            if ($Matches.ContainsKey(2)) { $defaults[$idx] = $Matches[2] }
        }
    }
}

# any ^N referenced in the template also counts as declared (so it gets filled)
foreach ($rm in [regex]::Matches($template, '\^(\d+)')) {
    $declared[[int]$rm.Groups[1].Value] = $true
}

# ── resolve positional values from CLI args, falling back to declared defaults ──
$maxIndex = -1
foreach ($k in $declared.Keys) { if ($k -gt $maxIndex) { $maxIndex = $k } }

$values = @{}
for ($n = 0; $n -le $maxIndex; $n++) {
    if ($argTokens.Count -gt $n) {
        $values[$n] = $argTokens[$n]
    } elseif ($defaults.ContainsKey($n)) {
        $values[$n] = Expand-ConfiguredParams $defaults[$n] $config.params
    } else {
        Write-Host "缺少參數 ^$n"
        exit 1
    }
}

# substitute ^N in the template (right-to-left so indices stay valid)
$resolved = $template
$ph = [regex]::Matches($template, '\^(\d+)')
for ($k = $ph.Count - 1; $k -ge 0; $k--) {
    $m = $ph[$k]
    $idx = [int]$m.Groups[1].Value
    $val = if ($values.ContainsKey($idx)) { $values[$idx] } else { "" }
    $resolved = $resolved.Remove($m.Index, $m.Length).Insert($m.Index, $val)
}

# CLI args beyond the highest declared index are appended at the end
$consumed = $maxIndex + 1
if ($argTokens.Count -gt $consumed) {
    $rest = $argTokens[$consumed..($argTokens.Count - 1)]
    $resolved = "$resolved $($rest -join ' ')"
}

# echo what we hand to PowerShell, with configured $VAR resolved to real values
Write-Host "> $(Expand-ConfiguredParams $resolved $config.params)"

# run in an isolated scope seeded only with the configured params, so PowerShell
# expands $VAR / ${VAR} natively (and unconfigured globals like $PROFILE still work).
# also export each param as a process env var, so child processes spawned by the
# command (e.g. dotnet/EF reading the connection string from $env:...) inherit them.
# ccc runs as its own short-lived process, so these never leak into the user's shell.
$variables = [System.Collections.Generic.List[psvariable]]::new()
foreach ($param in $config.params.PSObject.Properties) {
    $variables.Add([psvariable]::new($param.Name, $param.Value))
    [Environment]::SetEnvironmentVariable($param.Name, $param.Value, "Process")
}
[scriptblock]::Create($resolved).InvokeWithContext($null, $variables, $null)
