param(
    # extra flags: --beauty --vscode [--local] to also install the VS Code highlighter
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$Rest
)

$installDir = "$env:USERPROFILE\.ccc"
$repoRoot   = $PSScriptRoot
$scriptDir  = Join-Path $repoRoot "scripts"

# the repo bootstrap (ccc-router.bat) forwards the verb, i.e. 'install [--beauty ...]';
# drop a leading 'install' token so only flags remain.
if ($Rest.Count -ge 1 -and $Rest[0] -ieq "install") {
    $Rest = @($Rest | Select-Object -Skip 1)
}

# create install directory (or upgrade an existing install in place)
$libDir = Join-Path $installDir "lib"
if (Test-Path (Join-Path $installDir "ccc.cmd")) {
    Write-Host "Existing install found at $installDir - upgrading in place."
}
New-Item -ItemType Directory -Force -Path $libDir | Out-Null

# copy everything the global commands rely on: the .ps1 scripts go to lib\ and the two .cmd
# wrappers (ccc.cmd / ccc-router.cmd) shipped in scripts/ go to the install dir, the only
# folder on PATH; their %~dp0lib\ resolves the scripts. the scripts stay out of the PATH
# folder because PowerShell runs any .ps1 there by its bare name, in the caller's own
# process. install.ps1 itself is the repo-only bootstrap (run via the repo's
# ccc-router.bat) and is deliberately NOT shipped — once installed you update with
# 'ccc-router upgrade', never a self-invoked install.
$libScripts = @("ccc.ps1", "ccc-router.ps1", "uninstall.ps1", "install-highlighter.ps1", "status.ps1", "upgrade.ps1")
foreach ($file in $libScripts) {
    Copy-Item (Join-Path $scriptDir $file) (Join-Path $libDir $file) -Force
}
foreach ($file in @("ccc.cmd", "ccc-router.cmd")) {
    Copy-Item (Join-Path $scriptDir $file) (Join-Path $installDir $file) -Force
}
# installs up to 7f65b23 kept the scripts beside the wrappers; remove those copies
foreach ($file in $libScripts) {
    Remove-Item (Join-Path $installDir $file) -Force -ErrorAction SilentlyContinue
}

# install the cccrouter.json template that 'ccc-router init' clones into a project.
# source of truth is <repo>/components/cccrouter.json; when re-running from an already
# installed copy (no repo alongside) just keep the template already in place.
$templateDst = Join-Path $installDir "cccrouter.json"
$templateSrc = Join-Path $repoRoot "components\cccrouter.json"
if ((Test-Path $templateSrc) -and ((Resolve-Path $templateSrc).Path -ne (Resolve-Path -LiteralPath $templateDst -ErrorAction SilentlyContinue).Path)) {
    Copy-Item $templateSrc $templateDst -Force
    Write-Host "Installed cccrouter.json template (used by 'ccc-router init')."
} elseif (-not (Test-Path $templateDst)) {
    Write-Host "Warning: components\cccrouter.json not found; 'ccc-router init' will have no template to copy."
}

# stamp the installed commit (one line) so 'ccc-router status' / 'upgrade' can
# self-check without the source repo (the clone can be deleted after install). only
# record a real commit; if we can't determine one (re-running install from the
# installed copy, or a non-git source) keep any existing .base rather than clobbering it.
$stampPath = Join-Path $installDir ".base"
$commit = ""
if (Test-Path (Join-Path $repoRoot ".git")) {
    try { $commit = (git -C $repoRoot rev-parse HEAD 2>$null).Trim() } catch { $commit = "" }
}
if ($commit) {
    Set-Content $stampPath $commit -Encoding UTF8
}
# clean up the legacy stamp left by older installs
Remove-Item (Join-Path $installDir "install.json") -Force -ErrorAction SilentlyContinue

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
#   ccc-router install --beauty --vscode [--local]
if ($Rest -contains "--beauty") {
    Write-Host ""
    Write-Host "Installing beautifier extension ..."
    $highlighterArgs = @("install")
    if ($Rest -contains "--vscode") { $highlighterArgs += "--vscode" }
    if ($Rest -contains "--local")  { $highlighterArgs += "--local" }
    & "$scriptDir\install-highlighter.ps1" @highlighterArgs
}
