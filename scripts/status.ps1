$installDir     = "$env:USERPROFILE\.ccc"
$configFileName = "cccrouter.json"
$extMatch       = "cccrouter-syntax"   # the VS Code extension id contains this
$Repo           = "k-s-studio/custom-command-caller"

# ── ccc tool: are all the files install.ps1 places still present? ──
# (install.ps1 itself is the repo-only bootstrap and is never installed here.)
$required = @(
    "lib\ccc.ps1", "lib\ccc-router.ps1", "lib\uninstall.ps1",
    "lib\install-highlighter.ps1", "lib\status.ps1", "lib\upgrade.ps1",
    "ccc.cmd", "ccc-router.cmd", $configFileName
)
$missing = @($required | Where-Object { -not (Test-Path (Join-Path $installDir $_)) })
$toolStatus = if ($missing.Count -eq 0) { "healthy" } else { "corrupted" }

# ── vscode beautifier: live query, only care whether it is installed ──
$beautyStatus = "not installed"
if (Get-Command code -ErrorAction SilentlyContinue) {
    $ids = @(& code --list-extensions 2>$null | Where-Object { $_ -like "*$extMatch*" })
    if ($ids.Count -gt 0) { $beautyStatus = "installed" }
}

# ── table ──
"{0,-30} {1}" -f "Item", "Status"
"-" * 46
"{0,-30} {1}" -f "ccc tool", $toolStatus
"{0,-30} {1}" -f "vscode beautifier", $beautyStatus

# ── best-effort upstream check: flag an update only when the tool itself changed ──
function Get-InstalledCommit {
    $p = Join-Path $installDir ".base"
    if (-not (Test-Path $p)) { return $null }
    try { return (Get-Content $p -Raw).Trim() } catch { return $null }
}

$commit = Get-InstalledCommit
if ($commit) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $headers = @{ 'User-Agent' = 'ccc-router'; 'Accept' = 'application/vnd.github+json' }
    try {
        # compare .base...main, then only flag an update when the diff touches the tool
        # itself (scripts/ + components/) — README / SPEC / editor-only commits are noise.
        $cmp = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/compare/$commit...main" -Headers $headers -ErrorAction Stop
        $toolChanged = @($cmp.files | Where-Object { $_.filename -like "scripts/*" -or $_.filename -like "components/*" }).Count -gt 0
        if ($toolChanged) {
            Write-Host ""
            Write-Host 'Note: New version exists. Run `ccc-router upgrade` to get the latest version.'
        }
    } catch {
        # network / API hiccup (incl. 4xx, timeout) — status is still useful, just skip the Note
    }
}

exit 0
