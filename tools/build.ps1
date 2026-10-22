<#
.SYNOPSIS
    Builds the extension and the mod: cargo build, copy the DLL into the mod root, hemtt build.
.PARAMETER Release
    Run `hemtt release` instead of `hemtt build` (signed PBOs and a zip in releases/).
#>
param([switch]$Release)

# Native tools write progress to stderr, which 'Stop' would turn into errors in Windows PowerShell;
# failures are caught through $LASTEXITCODE instead.
$root = Split-Path $PSScriptRoot -Parent
$hemtt = 'hemtt'

Push-Location (Join-Path $root 'extension')
try {
    cargo test --release
    if ($LASTEXITCODE -ne 0) { throw 'cargo test failed' }
    cargo build --release
    if ($LASTEXITCODE -ne 0) { throw 'cargo build failed' }
} finally {
    Pop-Location
}
# Arma loads the 64-bit extension as <name>_x64.dll.
Copy-Item (Join-Path $root 'extension\target\release\ai_director.dll') (Join-Path $root 'ai_director_x64.dll') -Force -ErrorAction Stop

Push-Location $root
try {
    if ($Release) { & $hemtt release } else { & $hemtt build }
    if ($LASTEXITCODE -ne 0) { throw 'hemtt failed' }
} finally {
    Pop-Location
}
