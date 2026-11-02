# 'ccc-router upgrade' downloads THIS file from GitHub main and runs it (see the 'upgrade'
# case in ccc-router.ps1), so the latest upgrader always does the upgrade: changes to the
# install layout, and the migration from older layouts, ship with the upgrade itself.
$installDir     = "$env:USERPROFILE\.ccc"
$libDir         = Join-Path $installDir "lib"
$configFileName = "cccrouter.json"
$Repo           = "k-s-studio/custom-command-caller"
$rawBase        = "https://raw.githubusercontent.com/$Repo/main"

if (-not (Test-Path $installDir)) {
    Write-Host "ccc is not installed. Run 'ccc-router install' from the repo first."
    exit 1
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$headers = @{ 'User-Agent' = 'ccc-router'; 'Accept' = 'application/vnd.github+json' }

function Invoke-GitHubApi([string]$url) {
    # GitHub's edge occasionally returns transient 5xx — retry a few times.
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            return Invoke-RestMethod -Uri $url -Headers $headers -ErrorAction Stop
        } catch {
            $status = 0
            if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
            if ($attempt -lt 3 -and ($status -eq 0 -or $status -ge 500)) {
                Start-Sleep -Seconds $attempt
                continue
            }
            throw
        }
    }
}

function Get-RepoFile([string]$path, [string]$dest) {
    Invoke-WebRequest -Uri "$rawBase/$path" -OutFile $dest -Headers $headers -UseBasicParsing -ErrorAction Stop
}

# the scripts live in lib\, out of the PATH folder (PowerShell runs any .ps1 in a PATH folder
# by its bare name, in the caller's own process); only the two .cmd entries sit in the root.
# install.ps1 is the repo-only bootstrap and is never installed, so it is not refreshed here.
$libScripts = @("ccc.ps1", "ccc-router.ps1", "uninstall.ps1", "install-highlighter.ps1", "status.ps1", "upgrade.ps1")
$wrappers   = @("ccc.cmd", "ccc-router.cmd")

Write-Host "Checking latest version on GitHub ($Repo main) ..."
try {
    $latest = (Invoke-GitHubApi "https://api.github.com/repos/$Repo/commits/main").sha
} catch {
    Write-Host "Failed to query GitHub: $($_.Exception.Message)"
    exit 1
}

# download everything into a temp dir first; only overwrite the install once every
# file has arrived, so a mid-way failure never leaves a half-updated install.
$tmp = Join-Path $env:TEMP ("ccc-upgrade-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null
$ProgressPreference = 'SilentlyContinue'
try {
    foreach ($name in $libScripts + $wrappers) { Get-RepoFile "scripts/$name" (Join-Path $tmp $name) }
    # the template too, but it is user-editable — only applied if missing (see below)
    Get-RepoFile "components/$configFileName" (Join-Path $tmp $configFileName)
} catch {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Download failed: $($_.Exception.Message)"
    exit 1
}

# migrate from the flat layout (up to 7f65b23): the scripts sat beside the wrappers in the
# PATH folder, so in PowerShell 'ccc' ran ccc.ps1 in the user's own shell (leaking the
# variables' env vars into it) and 'status' / 'upgrade' / 'uninstall' were global commands.
$flat = @($libScripts | Where-Object { Test-Path (Join-Path $installDir $_) })

# commit the refreshed files. this upgrader runs from a temp file, and the wrapper that may be
# running (ccc-router.cmd, when called from cmd.exe) is read by cmd.exe as it goes: the new
# wrappers are no longer than the old ones and end with 'exit /b', so cmd.exe reads nothing
# more from the replaced file.
New-Item -ItemType Directory -Force -Path $libDir | Out-Null
foreach ($name in $libScripts) { Copy-Item (Join-Path $tmp $name) (Join-Path $libDir $name) -Force }
foreach ($name in $wrappers) { Copy-Item (Join-Path $tmp $name) (Join-Path $installDir $name) -Force }
foreach ($name in $flat) { Remove-Item (Join-Path $installDir $name) -Force -ErrorAction SilentlyContinue }
if ($flat.Count -gt 0) { Write-Host "Moved the scripts into $libDir (they no longer act as PowerShell commands)." }

# the template is user data ('ccc-router template' / 'init') — never clobber an
# existing one; only seed it if the user somehow has none.
$templateDst = Join-Path $installDir $configFileName
if (-not (Test-Path $templateDst)) { Copy-Item (Join-Path $tmp $configFileName) $templateDst -Force }

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

# re-stamp so 'ccc-router status' reflects the new version (one-line hash in .base)
Set-Content (Join-Path $installDir ".base") $latest -Encoding UTF8
# clean up the legacy stamp left by older installs
Remove-Item (Join-Path $installDir "install.json") -Force -ErrorAction SilentlyContinue

# if the beautifier extension is already installed, refresh it to the latest release
# too (uses the just-updated install-highlighter.ps1). skip it entirely if not present.
if (Get-Command code -ErrorAction SilentlyContinue) {
    $ext = @(& code --list-extensions 2>$null | Where-Object { $_ -like "*cccrouter-syntax*" })
    if ($ext.Count -gt 0) {
        Write-Host "Updating the beautifier extension ..."
        & (Join-Path $libDir "install-highlighter.ps1") install --vscode
    }
}

Write-Host "Upgraded to $($latest.Substring(0, 7)) (main)."
exit 0
