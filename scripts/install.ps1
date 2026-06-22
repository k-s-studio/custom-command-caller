param(
    # extra flags: --ext --vscode [--local] to also install the VS Code highlighter
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$Rest
)

$installDir = "$env:USERPROFILE\.ccc"
$scriptDir  = $PSScriptRoot

# create install directory (or upgrade an existing install in place)
if (Test-Path (Join-Path $installDir "ccc.ps1")) {
    Write-Host "Existing install found at $installDir - upgrading in place (overwrites ccc.ps1, adds ccc-router)."
}
if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir | Out-Null
}

# copy the scripts both global commands rely on
foreach ($file in @("ccc.ps1", "ccc-router.ps1", "install.ps1", "uninstall.ps1", "install-highlighter.ps1")) {
    $src = Join-Path $scriptDir $file
    if (Test-Path $src) { Copy-Item $src (Join-Path $installDir $file) -Force }
}

# create .cmd wrappers so both commands work from any terminal:
#   ccc         -> routes a command through cccrouter.json
#   ccc-router  -> init / install / uninstall
$cccWrapper = '@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ccc.ps1" %*'
Set-Content "$installDir\ccc.cmd" $cccWrapper -Encoding ASCII

$routerWrapper = '@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ccc-router.ps1" %*'
Set-Content "$installDir\ccc-router.cmd" $routerWrapper -Encoding ASCII

# add to user PATH if not already present
$userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($userPath -notlike "*$installDir*") {
    [Environment]::SetEnvironmentVariable("PATH", "$userPath;$installDir", "User")
    Write-Host "Added $installDir to user PATH."
} else {
    Write-Host "$installDir is already in PATH."
}

Write-Host "Installed. Restart your terminal, then use 'ccc' / 'ccc-router' in any directory."

# optionally install the VS Code highlighter extension in the same run:
#   ccc-router install --ext --vscode [--local]
if ($Rest -contains "--ext") {
    Write-Host ""
    Write-Host "Installing highlighter extension ..."
    $highlighterArgs = @("install")
    if ($Rest -contains "--vscode") { $highlighterArgs += "--vscode" }
    if ($Rest -contains "--local")  { $highlighterArgs += "--local" }
    & "$scriptDir\install-highlighter.ps1" @highlighterArgs
}
