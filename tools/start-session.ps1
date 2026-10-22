<#
.SYNOPSIS
    Starts a real director session on this PC: the companion in its own window, then Arma 3 with the group's mod
    list and the installed director mod.
.DESCRIPTION
    Reads the mod list from an Arma 3 Launcher preset export, finds each mod in the Steam Workshop folder, adds the
    director mod (installed by tools\install.ps1) and starts arma3_x64.exe directly. Starting the game directly
    means BattlEye is off, which the director's extension needs. Host the game from the Multiplayer menu as usual;
    the other players join with the same preset in the launcher and need nothing else.

    When the session ends, press Ctrl+C in the companion window to write the after-action report.
.PARAMETER Campaign
    The companion's campaign (logs, reports, story so far). Default: infinizo
.PARAMETER Personality
    The director's style: balanced, cinematic, merciless, supportive or one from companion\personalities.toml.
    Remembered for the campaign; leave it out to use the campaign's.
.PARAMETER Preset
    The launcher preset export. Default: .hemtt\presets\infinizo.html
.PARAMETER ModDir
    The installed director mod. Default: install\@AIDirector
.PARAMETER NoGame
    Start only the companion (for example when Arma is already running).
.PARAMETER DryRun
    Check everything and print the commands, but start nothing.
#>
param(
    [string]$Campaign = 'infinizo',
    [string]$Personality = '',
    [string]$Preset = '.hemtt\presets\infinizo.html',
    [string]$ModDir = 'install\@AIDirector',
    [switch]$NoGame,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$companion = Join-Path $root 'companion'

if (-not (Test-Path (Join-Path $ModDir 'ai_director_x64.dll'))) {
    throw "The director mod isn't installed in $ModDir; run tools\install.ps1 first."
}
if (-not (Test-Path (Join-Path $companion '.venv\Scripts\python.exe'))) {
    throw 'The companion has no venv; see README: Setup.'
}

# Mod paths first, so nothing starts if a mod is missing.
$mods = @()
if (-not $NoGame) {
    $arma = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\bohemia interactive\arma 3').main
    # <library>\steamapps\common\Arma 3 -> <library>\steamapps\workshop\content\107410 (Arma 3's app id)
    $workshop = Join-Path (Split-Path (Split-Path $arma -Parent) -Parent) 'workshop\content\107410'
    $ids = [regex]::Matches((Get-Content -Raw -Encoding UTF8 $Preset), 'filedetails/\?id=(\d+)') |
        ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
    $missing = $ids | Where-Object { -not (Test-Path (Join-Path $workshop $_)) }
    if ($missing) {
        throw "Not downloaded from the Workshop: $($missing -join ', '). Subscribe in Steam or open the preset in the launcher, then try again."
    }
    $mods = @($ids | ForEach-Object { Join-Path $workshop $_ }) + $ModDir
}

$style = ''
if ($Personality) { $style = "--personality $Personality " }
$serve = "Set-Location '$companion'; `$host.UI.RawUI.WindowTitle = 'AI Director ($Campaign)'; " +
    "& .\.venv\Scripts\python.exe -m director --campaign $Campaign $($style)serve"
# Windows PowerShell's Start-Process joins arguments with spaces and doesn't quote them, so quote -mod here.
$arguments = @('-noSplash', '-skipIntro', '-world=empty', "`"-mod=$($mods -join ';')`"")

if ($DryRun) {
    Write-Host "Companion: powershell.exe -NoExit -Command $serve"
    if (-not $NoGame) {
        Write-Host "Arma 3: $(Join-Path $arma 'arma3_x64.exe') $($arguments[0..2] -join ' ') -mod=<$($mods.Count) mods>"
        Write-Host "  $($mods.Count - 1) Workshop mods from $Preset, all downloaded, plus $ModDir"
    }
    return
}

Start-Process powershell.exe -ArgumentList '-NoExit', '-Command', $serve
Write-Host "Companion started in its own window (campaign $Campaign)."

if (-not $NoGame) {
    Start-Process (Join-Path $arma 'arma3_x64.exe') -ArgumentList $arguments -WorkingDirectory $arma
    Write-Host "Arma 3 starting with $($mods.Count) mods, BattlEye off. Host from the Multiplayer menu."
}
