param(
    [Parameter(Position=0, ValueFromRemainingArguments=$true)]
    [string[]]$Rest
)

if ($Rest.Count -ne 2 -or $Rest[0] -ne "install" -or $Rest[1] -ne "--vscode") {
    Write-Host "Usage: ccc highlighter install --vscode"
    exit 0
}

if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
    Write-Host "VS Code 'code' CLI not found in PATH."
    exit 1
}

$extensionDir = Join-Path $PSScriptRoot "..\editor\vscode-cccrouter-syntax"
$vsix = Get-ChildItem $extensionDir -Filter "cccrouter-syntax-*.vsix" -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1
if (-not $vsix) {
    Write-Host "No packaged extension found in $extensionDir."
    Write-Host "Run 'npx --yes @vscode/vsce package' there first, then retry."
    exit 1
}

& code --install-extension $vsix.FullName --force
if ($LASTEXITCODE -eq 0) {
    Write-Host "Installed. Reload the VS Code window for the highlighting to take effect."
}
exit $LASTEXITCODE
