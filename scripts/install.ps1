param(
    # extra flags: --ext --vscode [--local] to also install the VS Code highlighter
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$Rest
)

$installDir = "$env:USERPROFILE\.ccc"
$scriptDir  = $PSScriptRoot

# create install directory
if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir | Out-Null
}

# copy ccc.ps1
Copy-Item "$scriptDir\ccc.ps1" "$installDir\ccc.ps1" -Force

# create ccc.cmd wrapper (allows calling 'ccc' from any terminal)
$cmdWrapper = '@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ccc.ps1" %*'
Set-Content "$installDir\ccc.cmd" $cmdWrapper -Encoding ASCII

# add to user PATH if not already present
$userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($userPath -notlike "*$installDir*") {
    [Environment]::SetEnvironmentVariable("PATH", "$userPath;$installDir", "User")
    Write-Host "Added $installDir to user PATH."
} else {
    Write-Host "$installDir is already in PATH."
}

Write-Host "Installed. Restart your terminal, then use 'ccc' in any project directory."

# optionally install the VS Code highlighter extension in the same run:
#   ccc install --ext --vscode [--local]
if ($Rest -contains "--ext") {
    Write-Host ""
    Write-Host "Installing highlighter extension ..."
    $highlighterArgs = @("install")
    if ($Rest -contains "--vscode") { $highlighterArgs += "--vscode" }
    if ($Rest -contains "--local")  { $highlighterArgs += "--local" }
    & "$scriptDir\install-highlighter.ps1" @highlighterArgs
}
