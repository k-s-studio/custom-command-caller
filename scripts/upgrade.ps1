$installDir     = "$env:USERPROFILE\.ccc"
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

# scripts to refresh: <installed name> <- <path in repo>. install.ps1 is the repo-only
# bootstrap and is never installed, so it is not refreshed here either.
$scripts = [ordered]@{
    "ccc.ps1"                 = "scripts/ccc.ps1"
    "ccc-router.ps1"          = "scripts/ccc-router.ps1"
    "uninstall.ps1"           = "scripts/uninstall.ps1"
    "install-highlighter.ps1" = "scripts/install-highlighter.ps1"
    "status.ps1"              = "scripts/status.ps1"
    "upgrade.ps1"             = "scripts/upgrade.ps1"
}

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
    foreach ($name in $scripts.Keys) {
        Invoke-WebRequest -Uri "$rawBase/$($scripts[$name])" -OutFile (Join-Path $tmp $name) -Headers $headers -ErrorAction Stop
    }
    # the template too, but it is user-editable — only applied if missing (see below)
    Invoke-WebRequest -Uri "$rawBase/components/$configFileName" -OutFile (Join-Path $tmp $configFileName) -Headers $headers -ErrorAction Stop
} catch {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Download failed: $($_.Exception.Message)"
    exit 1
}

# commit the refreshed scripts. this script is being run from a temp copy (see the
# 'upgrade' case in ccc-router.ps1), so overwriting the install dir's upgrade.ps1 /
# ccc-router.ps1 here is never overwriting the file we are currently executing.
foreach ($name in $scripts.Keys) {
    Copy-Item (Join-Path $tmp $name) (Join-Path $installDir $name) -Force
}

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
        & (Join-Path $installDir "install-highlighter.ps1") install --vscode
    }
}

Write-Host "Upgraded to $($latest.Substring(0, 7)) (main)."
exit 0
