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
        # Windows PowerShell 5.1 reads a BOM-less file as the ANSI code page (Big5 on zh-TW),
        # mangling non-ASCII text in the config; read it as UTF-8 explicitly.
        return Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Write-Host "Invalid cccrouter.json: $_"
        exit 1
    }
}

# substitute $VAR / ${VAR} that ARE configured in variables with their values, so the
# echoed line shows real values; references not configured here (e.g. $PROFILE) are
# left untouched for PowerShell to resolve natively at execution time.
function Expand-ConfiguredVariables([string]$text, $variables) {
    if ($null -eq $variables) { return $text }
    return [regex]::Replace($text, '\$(?:\{([A-Za-z_]\w*)\}|([A-Za-z_]\w*))', {
        param($m)
        $name = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
        $p = $variables.PSObject.Properties[$name]
        if ($null -ne $p) { return [string]$p.Value }
        return $m.Value
    })
}

# the first whitespace-delimited token of a key is its routable name
# ("uncommit ^0=1 ^1=--soft" -> "uncommit", "git" -> "git").
function Get-KeyName([string]$key) {
    return ($key -split '\s+', 2)[0]
}

function Write-CommandEcho([string]$text) {
    $parseTokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$parseTokens, [ref]$parseErrors)

    if ($parseErrors.Count -eq 0 -and $null -ne $ast -and $null -ne $ast.EndBlock) {
        $statements = @($ast.EndBlock.Statements)
        if ($statements.Count -gt 0) {
            foreach ($statement in $statements) {
                $line = $statement.Extent.Text.Trim()
                if ($line.Length -gt 0) {
                    Write-Host "> $line"
                }
            }
            return
        }
    }

    foreach ($line in ($text -split '\r?\n')) {
        if ($line.Trim().Length -gt 0) {
            Write-Host "> $($line.Trim())"
        }
    }
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

# ── parse the matched key's signature: "<name> ^a=def ^b=def ..." ───────────────
# each param is keyed by a name or a number (^name / ^0); the order they appear in
# the signature is the order CLI args fill them.
$sigTokens = $matchedKey -split '\s+'
$paramOrder = [System.Collections.Generic.List[string]]::new()
$defaults = @{}     # key -> default text (Expand-ConfiguredVariables applied on use)
if ($sigTokens.Count -gt 1) {
    foreach ($t in $sigTokens[1..($sigTokens.Count - 1)]) {
        if ($t -match '^\^([A-Za-z_]\w*|\d+)(?:=(.*))?$') {
            $key = $Matches[1]
            if (-not $paramOrder.Contains($key)) { $paramOrder.Add($key) }
            if ($Matches.ContainsKey(2)) { $defaults[$key] = $Matches[2] }
        }
    }
}

# any ^key referenced in the template but not declared in the signature is appended
# in order of first appearance, so it still gets filled positionally.
foreach ($rm in [regex]::Matches($template, '\^([A-Za-z_]\w*|\d+)')) {
    $key = $rm.Groups[1].Value
    if (-not $paramOrder.Contains($key)) { $paramOrder.Add($key) }
}

# ── resolve values from CLI args (in declared order), falling back to defaults ──
$values = @{}
$missing = [System.Collections.Generic.List[string]]::new()
for ($n = 0; $n -lt $paramOrder.Count; $n++) {
    $key = $paramOrder[$n]
    if ($argTokens.Count -gt $n) {
        $values[$key] = $argTokens[$n]
    } elseif ($defaults.ContainsKey($key)) {
        $values[$key] = Expand-ConfiguredVariables $defaults[$key] $config.variables
    } else {
        $missing.Add("^$key")
    }
}

if ($missing.Count -gt 0) {
    Write-Host "Expected param(s): $($missing -join ' ')"
    exit 1
}

# substitute ^key in the template with its resolved value
$resolved = [regex]::Replace($template, '\^([A-Za-z_]\w*|\d+)', {
    param($m)
    $key = $m.Groups[1].Value
    if ($values.ContainsKey($key)) { return [string]$values[$key] }
    return $m.Value
})

# CLI args beyond the declared params are appended at the end
$consumed = $paramOrder.Count
if ($argTokens.Count -gt $consumed) {
    $rest = $argTokens[$consumed..($argTokens.Count - 1)]
    $resolved = "$resolved $($rest -join ' ')"
}

# echo what we hand to PowerShell, with configured $VAR resolved to real values
Write-CommandEcho (Expand-ConfiguredVariables $resolved $config.variables)

# export each variable as a process env var, so child processes spawned by the command
# (e.g. dotnet/EF reading the connection string from $env:...) inherit them.
# ccc runs as its own short-lived process, so these never leak into the user's shell.
foreach ($var in $config.variables.PSObject.Properties) {
    [Environment]::SetEnvironmentVariable($var.Name, $var.Value, "Process")
}

# run in a child scope seeded with the configured variables, so PowerShell expands
# $VAR / ${VAR} natively (and unconfigured globals like $PROFILE still work).
# invoke it with '&' as a plain statement, never through a .NET call such as
# ScriptBlock.InvokeWithContext: those collect the output, so native commands get
# their stdout redirected: nothing shows until the command ends, and Windows
# PowerShell decodes the captured UTF-8 bytes with the console code page (mojibake).
# a plain '&' statement leaves native stdout on the console: live and undecoded.
& {
    param($__cccCommand, $__cccVariables)
    foreach ($__cccVariable in $__cccVariables) { Set-Variable -Name $__cccVariable.Name -Value $__cccVariable.Value }
    Remove-Variable __cccVariable, __cccVariables -ErrorAction SilentlyContinue
    & ([scriptblock]::Create($__cccCommand))
} $resolved @($config.variables.PSObject.Properties)

# hand the command's exit code on (ccc.cmd passes it to the caller), so 'ccc build && ...' works
exit $LASTEXITCODE
