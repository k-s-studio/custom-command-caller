param(
    [Parameter(Position=0)]
    [string]$Command,
    [Parameter(Position=1, ValueFromRemainingArguments=$true)]
    [string[]]$Rest
)

$configFileName = "cccrouter.json"
$installDir = "$env:USERPROFILE\.ccc"

function Show-Usage {
    Write-Host "Usage: ccc-router <command>"
    Write-Host "       ccc-router init        create cccrouter.json in current directory"
    Write-Host "       ccc-router install     register 'ccc' and 'ccc-router' for any directory"
    Write-Host "       ccc-router uninstall   remove the registered commands"
    Write-Host ""
    Write-Host "Run 'ccc <command> [args]' to route a command through cccrouter.json."
}

switch ($Command) {

    "init" {
        $configPath = Join-Path (Get-Location) $configFileName
        if (Test-Path $configPath) {
            Write-Host "cccrouter.json already exists."
            exit 1
        }
        $template = @'
{
    "variables": {
        "ENVIRONMENT": "Development"
    },
    "commands": {
        "hide": "Add-Content .git/info/exclude \"`ncccrouter.json\"",
        "profile": "notepad $PROFILE.CurrentUserAllHosts",
        "git": {
            "uncommit ^0=1 ^1=--soft": "git reset HEAD~^0 ^1",
            "user ^name ^email": "git config --local user.name ^name; git config --local user.email ^email",
            "exclude ^0": "Add-Content .git/info/exclude ^0"
        }
    }
}
'@
        Set-Content $configPath $template -Encoding UTF8
        Write-Host "Created cccrouter.json"
        if (Test-Path (Join-Path (Get-Location) ".git")) {
            Write-Host "Tip: git detected. Use 'ccc hide' to exclude cccrouter.json from this repo."
        }
        exit 0
    }

    "install" {
        & "$PSScriptRoot\install.ps1" @Rest
        exit $LASTEXITCODE
    }

    "uninstall" {
        & "$PSScriptRoot\uninstall.ps1" @Rest
        exit $LASTEXITCODE
    }

    default {
        Show-Usage
        if ($Command) { exit 1 }
        exit 0
    }
}
