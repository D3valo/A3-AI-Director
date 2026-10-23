# Settings for this PC that don't belong in the repo, such as paths. Dot-source it, then call Get-LocalSetting.
# They come from tools\local-settings.psd1 if it exists (not in git; copy local-settings.example.psd1 to start one).

$localSettingsFile = Join-Path $PSScriptRoot 'local-settings.psd1'
$localSettings = @{}
if (Test-Path $localSettingsFile) { $localSettings = Import-PowerShellDataFile $localSettingsFile }

# The named setting from local-settings.psd1, or the default when it isn't set there.
function Get-LocalSetting([string]$Name, $Default) {
    if ($localSettings.ContainsKey($Name) -and $localSettings[$Name]) { return $localSettings[$Name] }
    $Default
}
