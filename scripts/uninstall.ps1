param(
    # ccc-router uninstall                remove the ccc tool AND the beautifier extension
    # ccc-router uninstall --stay-beauty  remove the ccc tool, keep the extension
    # ccc-router uninstall --beauty       remove ONLY the beautifier extension
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$Rest
)

$installDir = "$env:USERPROFILE\.ccc"
$extMatch   = "cccrouter-syntax"   # the VS Code extension id contains this

function Uninstall-Beautifier {
    if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
        Write-Host "VS Code 'code' CLI not found; skipping beautifier removal."
        return
    }
    $ids = @(& code --list-extensions 2>$null | Where-Object { $_ -like "*$extMatch*" })
    if ($ids.Count -eq 0) {
        Write-Host "Beautifier extension is not installed."
        return
    }
    foreach ($id in $ids) {
        & code --uninstall-extension $id | Out-Null
        Write-Host "Removed beautifier extension: $id"
    }
}

function Remove-CccTool {
    # remove from user PATH
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($userPath -like "*$installDir*") {
        $newPath = ($userPath.Split(';') | Where-Object { $_ -ne $installDir }) -join ';'
        [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
        Write-Host "Removed $installDir from PATH."
    } else {
        Write-Host "$installDir was not found in PATH."
    }

    # delete install directory. when 'ccc-router uninstall' runs from the installed
    # copy, its own ccc-router.cmd is held open by cmd.exe, so an in-process delete
    # fails; fall back to a detached cmd that removes the folder once we have exited.
    if (Test-Path $installDir) {
        try {
            Remove-Item $installDir -Recurse -Force -ErrorAction Stop
            Write-Host "Deleted $installDir."
        } catch {
            Start-Process -WindowStyle Hidden cmd -ArgumentList "/c", "ping 127.0.0.1 -n 2 >nul & rmdir /s /q `"$installDir`""
            Write-Host "Scheduled removal of $installDir (completes after this terminal frees it)."
        }
    }
}

# --beauty: remove only the beautifier extension, leave the ccc tool in place
if ($Rest -contains "--beauty") {
    Uninstall-Beautifier
    exit 0
}

# default also removes the extension; --stay-beauty keeps it
if (-not ($Rest -contains "--stay-beauty")) {
    Uninstall-Beautifier
}
Remove-CccTool
Write-Host "Uninstalled."
