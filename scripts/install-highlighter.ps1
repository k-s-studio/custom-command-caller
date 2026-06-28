param(
    [Parameter(Position=0, ValueFromRemainingArguments=$true)]
    [string[]]$Rest
)

$Repo = "k-s-studio/custom-command-caller"

# Invoked by install.ps1 (`ccc-router install --beauty --vscode [--local]`) and by
# `ccc-router beauty install --vscode [--local]`.
if ($Rest.Count -lt 2 -or $Rest[0] -ne "install" -or $Rest[1] -ne "--vscode") {
    Write-Host "Usage: ccc-router install --beauty --vscode [--local]"
    Write-Host "  (default) install the published extension from the latest GitHub Release"
    Write-Host "  --local   build the extension from the cloned source and install that"
    exit 0
}
$Local = $Rest -contains "--local"

if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
    Write-Host "VS Code 'code' CLI not found in PATH."
    exit 1
}

$extensionDir = Join-Path $PSScriptRoot "..\editor\vscode-cccrouter-syntax"

if ($Local) {
    # Build from the cloned source — use this after editing the syntax to your own style.
    if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
        Write-Host "Node.js / npx not found in PATH — required for --local build."
        exit 1
    }
    Write-Host "Packaging extension from source ..."
    Push-Location $extensionDir
    try {
        npx --yes @vscode/vsce package
        $packaged = ($LASTEXITCODE -eq 0)
    } finally {
        Pop-Location
    }
    if (-not $packaged) {
        Write-Host "Packaging failed."
        exit 1
    }
    $vsix = Get-ChildItem $extensionDir -Filter "cccrouter-syntax-*.vsix" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $vsix) {
        Write-Host "No .vsix was produced in $extensionDir."
        exit 1
    }
    $target  = $vsix.FullName
    $cleanup = $false
}
else {
    # Download the published .vsix from the latest GitHub Release (no Node required).
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $headers = @{ 'User-Agent' = 'ccc-highlighter'; 'Accept' = 'application/vnd.github+json' }

    function Invoke-GitHubApi([string]$url) {
        # GitHub's API edge occasionally returns transient 5xx (e.g. /releases/latest
        # 504s) — retry a few times before giving up.
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

    Write-Host "Fetching latest release from $Repo ..."
    try {
        $release = Invoke-GitHubApi "https://api.github.com/repos/$Repo/releases/latest"
    } catch {
        # /releases/latest is flaky on GitHub's edge; the list endpoint is more reliable.
        Write-Host "  /releases/latest unavailable; falling back to releases list ..."
        try {
            $release = Invoke-GitHubApi "https://api.github.com/repos/$Repo/releases" |
                Where-Object { -not $_.draft -and -not $_.prerelease } | Select-Object -First 1
        } catch {
            Write-Host "Failed to query GitHub releases: $($_.Exception.Message)"
            Write-Host "If you customized the syntax locally, install from source with: ccc-router install --beauty --vscode --local"
            exit 1
        }
    }
    if (-not $release) {
        Write-Host "No published release found for $Repo."
        exit 1
    }

    $asset = $release.assets | Where-Object { $_.name -like '*.vsix' } | Select-Object -First 1
    if (-not $asset) {
        Write-Host "No .vsix asset found in release '$($release.tag_name)'."
        exit 1
    }

    $target = Join-Path $env:TEMP $asset.name
    Write-Host "Downloading $($asset.name) ($($release.tag_name)) ..."
    $ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $target -Headers $headers -ErrorAction Stop
    } catch {
        Write-Host "Download failed: $($_.Exception.Message)"
        exit 1
    }
    $cleanup = $true
}

& code --install-extension $target --force
$code = $LASTEXITCODE
if ($cleanup) { Remove-Item $target -ErrorAction SilentlyContinue }
if ($code -eq 0) {
    Write-Host "Installed. Reload the VS Code window for the highlighting to take effect."
}
exit $code
