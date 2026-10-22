<#
.SYNOPSIS
    Builds the director (tools\build.ps1) and installs the built mod into a fixed mod folder for real sessions.
.DESCRIPTION
    Real sessions load the mod from this folder (tools\start-session.ps1 does, or add it once in the Arma 3
    Launcher as a local mod). Run it again after pulling changes. Arma must be closed, as it locks the DLL.
.PARAMETER Destination
    The mod folder. Default: install\@AIDirector
#>
param([string]$Destination = 'install\@AIDirector')

$root = Split-Path $PSScriptRoot -Parent

& (Join-Path $PSScriptRoot 'build.ps1')
if (-not $?) { throw 'build failed' }

$built = Join-Path $root '.hemttout\build'
New-Item -ItemType Directory -Force $Destination | Out-Null
# Mirror the build so files removed from the mod don't linger.
robocopy $built $Destination /MIR /NJH /NJS /NDL /NFL | Out-Null
# robocopy exit codes below 8 mean success (copied, extra files removed, nothing to do).
if ($LASTEXITCODE -ge 8) { throw "copy to $Destination failed (robocopy exit $LASTEXITCODE); is Arma still running?" }
Write-Host "Installed to $Destination"
exit 0  # not robocopy's success code (1 = files copied)
