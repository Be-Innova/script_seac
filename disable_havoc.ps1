# ==============================
# Generic Driver Containment Script
# ==============================
Write-Host "[*] Driver containment script started" -ForegroundColor Cyan

$foundDrivers = @()

# 1. Find all .sys files in user Temp folders
Write-Host "`n[*] Scanning user Temp folders..." -ForegroundColor Cyan
$userDirs = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue

foreach ($user in $userDirs) {
    $tempPath = Join-Path $user.FullName "AppData\Local\Temp"
    if (Test-Path $tempPath) {
        $sysFiles = Get-ChildItem -Path $tempPath -Filter "*.sys" -File -ErrorAction SilentlyContinue
        foreach ($file in $sysFiles) {
            $foundDrivers += [PSCustomObject]@{
                DriverName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                FullPath = $file.FullName
                Location = "$($user.Name)'s Temp"
            }
            Write-Host "[*] Found driver: $($file.Name) in $($user.Name)'s Temp folder" -ForegroundColor Yellow
        }
    }
}

# 2. Find all .sys files in Windows\Temp
Write-Host "`n[*] Scanning Windows\Temp folder..." -ForegroundColor Cyan
$windowsTempPath = "C:\Windows\Temp"
if (Test-Path $windowsTempPath) {
    $sysFiles = Get-ChildItem -Path $windowsTempPath -Filter "*.sys" -File -ErrorAction SilentlyContinue
    foreach ($file in $sysFiles) {
        $foundDrivers += [PSCustomObject]@{
            DriverName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
            FullPath = $file.FullName
            Location = "Windows\Temp"
        }
        Write-Host "[*] Found driver: $($file.Name) in Windows\Temp folder" -ForegroundColor Yellow
    }
}

if ($foundDrivers.Count -eq 0) {
    Write-Host "`n[*] No .sys drivers found in Temp folders" -ForegroundColor Green
    exit
}

Write-Host "`n[*] Total drivers found: $($foundDrivers.Count)" -ForegroundColor Cyan

# 3. Process each found driver
foreach ($driver in $foundDrivers) {
    $driverName = $driver.DriverName
    Write-Host "`n[*] Processing driver: $driverName (from $($driver.Location))" -ForegroundColor Cyan
    
    # Define registry paths for all ControlSets
    $servicePaths = @(
        "HKLM:\SYSTEM\CurrentControlSet\Services\$driverName",
        "HKLM:\SYSTEM\ControlSet001\Services\$driverName",
        "HKLM:\SYSTEM\ControlSet002\Services\$driverName"
    )
    
    # Disable driver in registry
    foreach ($path in $servicePaths) {
        if (Test-Path $path) {
            try {
                Set-ItemProperty -Path $path -Name Start -Value 4 -Force
                Write-Host "  [+] Disabled driver in $path" -ForegroundColor Green
            } catch {
                Write-Host "  [!] FAILED to modify $path : $_" -ForegroundColor Red
            }
        }
    }
    
    # Rename the .sys file
    $disabledPath = "$($driver.FullPath).disabled"
    if (Test-Path $driver.FullPath) {
        try {
            if (-not (Test-Path $disabledPath)) {
                Rename-Item -Path $driver.FullPath -NewName "$([System.IO.Path]::GetFileName($driver.FullPath)).disabled" -Force
                Write-Host "  [+] Renamed $($driver.FullPath)" -ForegroundColor Green
            } else {
                Write-Host "  [*] Already renamed: $($driver.FullPath)" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  [!] FAILED to rename $($driver.FullPath) : $_" -ForegroundColor Red
        }
    }
    
    # Check if driver is currently loaded
    $loaded = driverquery | Select-String -Pattern $driverName -CaseSensitive:$false
    if ($loaded) {
        Write-Host "  [!] WARNING: $driverName driver appears loaded in memory!" -ForegroundColor Red
        $loaded
    } else {
        Write-Host "  [+] $driverName driver NOT loaded in memory" -ForegroundColor Green
    }
}

Write-Host "`n[*] Driver containment script completed" -ForegroundColor Cyan
Write-Host "[*] Total drivers processed: $($foundDrivers.Count)" -ForegroundColor Cyan