$komorebiConfigHome = Join-Path $env:USERPROFILE ".config\komorebi"
$profileScript = $PROFILE

# Check if the profile script exists
if (-not (Test-Path $profileScript)) {
    New-Item -Path $profileScript -ItemType File -Force
}

# Check if the environment variable is already set
if (-not (Get-Content -Path $profileScript | Select-String -Pattern 'KOMOREBI_CONFIG_HOME')) {
    Add-Content -Path $profileScript -Value "`n`$Env:KOMOREBI_CONFIG_HOME = '$komorebiConfigHome'"
    Write-Host "Added KOMOREBI_CONFIG_HOME to $profileScript"
} else {
    Write-Host "KOMOREBI_CONFIG_HOME is already set in $profileScript"
}

. $PROFILE
komorebic.exe fetch-app-specific-configuration
