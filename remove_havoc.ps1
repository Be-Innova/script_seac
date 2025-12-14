# =====================================
# Generic Driver Removal Script
# =====================================
$LogFile = "C:\Temp\Driver_Removal.log"
New-Item -ItemType Directory -Path "C:\Temp" -ErrorAction SilentlyContinue | Out-Null
Start-Transcript -Path $LogFile -Append

Write-Host "[*] Starting driver removal script" -ForegroundColor Cyan

$foundDrivers = @()

# 1. Find all .sys files in user Temp folders
Write-Host "`n[*] Scanning user Temp folders..." -ForegroundColor Cyan
$userDirs = Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue

foreach ($user in $userDirs) {
    $tempPath = Join-Path $user.FullName "AppData\Local\Temp"
    if (Test-Path $tempPath) {
        $sysFiles = Get-ChildItem -Path $tempPath -Filter "*.sys*" -File -ErrorAction SilentlyContinue
        foreach ($file in $sysFiles) {
            $driverName = $file.Name -replace '\.sys.*$', ''
            $foundDrivers += [PSCustomObject]@{
                DriverName = $driverName
                FullPath = $file.FullName
                FileName = $file.Name
                Location = "$($user.Name)'s Temp"
            }
            Write-Host "[*] Found: $($file.Name) in $($user.Name)'s Temp folder" -ForegroundColor Yellow
        }
    }
}

# 2. Find all .sys files in Windows\Temp
Write-Host "`n[*] Scanning Windows\Temp folder..." -ForegroundColor Cyan
$windowsTempPath = "C:\Windows\Temp"
if (Test-Path $windowsTempPath) {
    $sysFiles = Get-ChildItem -Path $windowsTempPath -Filter "*.sys*" -File -ErrorAction SilentlyContinue
    foreach ($file in $sysFiles) {
        $driverName = $file.Name -replace '\.sys.*$', ''
        $foundDrivers += [PSCustomObject]@{
            DriverName = $driverName
            FullPath = $file.FullName
            FileName = $file.Name
            Location = "Windows\Temp"
        }
        Write-Host "[*] Found: $($file.Name) in Windows\Temp folder" -ForegroundColor Yellow
    }
}

if ($foundDrivers.Count -eq 0) {
    Write-Host "`n[*] No driver files found in Temp folders" -ForegroundColor Green
    Stop-Transcript
    exit 0
}

Write-Host "`n[*] Total driver files found: $($foundDrivers.Count)" -ForegroundColor Cyan

# 3. Get unique driver names for registry cleanup
$uniqueDriverNames = $foundDrivers | Select-Object -ExpandProperty DriverName -Unique

# 4. Verify drivers are not loaded
Write-Host "`n[*] Checking if drivers are loaded in memory..." -ForegroundColor Cyan
$loadedDrivers = @()

foreach ($driverName in $uniqueDriverNames) {
    $loaded = driverquery | Select-String -Pattern "^$driverName\s" -CaseSensitive:$false
    if ($loaded) {
        $loadedDrivers += $driverName
        Write-Host "[!] WARNING: $driverName driver is currently LOADED" -ForegroundColor Red
    }
}

if ($loadedDrivers.Count -gt 0) {
    Write-Host "`n[!] The following drivers are loaded and cannot be removed:" -ForegroundColor Red
    $loadedDrivers | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
    Write-Host "[!] ABORTING removal process" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

Write-Host "[+] No drivers are loaded in memory" -ForegroundColor Green

# 5. Remove registry keys for each unique driver
Write-Host "`n[*] Removing registry keys..." -ForegroundColor Cyan
foreach ($driverName in $uniqueDriverNames) {
    Write-Host "`n[*] Processing driver: $driverName" -ForegroundColor Cyan
    
    $regPaths = @(
        "HKLM:\SYSTEM\CurrentControlSet\Services\$driverName",
        "HKLM:\SYSTEM\ControlSet001\Services\$driverName",
        "HKLM:\SYSTEM\ControlSet002\Services\$driverName"
    )
    
    foreach ($path in $regPaths) {
        if (Test-Path $path) {
            try {
                Remove-Item -Path $path -Recurse -Force
                Write-Host "  [+] Removed registry key $path" -ForegroundColor Green
            } catch {
                Write-Host "  [!] FAILED to remove $path : $_" -ForegroundColor Red
            }
        }
    }
}

# 6. Delete all found driver files
Write-Host "`n[*] Deleting driver files..." -ForegroundColor Cyan
foreach ($driver in $foundDrivers) {
    if (Test-Path $driver.FullPath) {
        try {
            Remove-Item $driver.FullPath -Force
            Write-Host "  [+] Deleted $($driver.FullPath)" -ForegroundColor Green
        } catch {
            Write-Host "  [!] FAILED to delete $($driver.FullPath) : $_" -ForegroundColor Red
        }
    } else {
        Write-Host "  [*] File already removed: $($driver.FullPath)" -ForegroundColor Yellow
    }
}

# 7. Final verification
Write-Host "`n[*] Performing final verification..." -ForegroundColor Cyan
$registryIssues = @()

foreach ($driverName in $uniqueDriverNames) {
    $stillThere = reg query HKLM\SYSTEM /s /f $driverName 2>$null
    if ($stillThere) {
        $registryIssues += $driverName
        Write-Host "[!] WARNING: Registry references still exist for $driverName" -ForegroundColor Yellow
    } else {
        Write-Host "[+] No registry references found for $driverName" -ForegroundColor Green
    }
}

# 8. Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "REMOVAL SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total drivers processed: $($uniqueDriverNames.Count)" -ForegroundColor White
Write-Host "Total files deleted: $($foundDrivers.Count)" -ForegroundColor White

if ($registryIssues.Count -gt 0) {
    Write-Host "`nDrivers with remaining registry entries:" -ForegroundColor Yellow
    $registryIssues | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
} else {
    Write-Host "`n[+] All registry entries cleaned successfully" -ForegroundColor Green
}

Write-Host "`n[*] Driver removal completed" -ForegroundColor Cyan
Write-Host "[*] Log file: $LogFile" -ForegroundColor Cyan
Stop-Transcript