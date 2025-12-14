# =====================================
# Malicious Driver Services Disabler
# =====================================
$LogFile = "C:\Temp\Driver_Services_Disable.log"
New-Item -ItemType Directory -Path "C:\Temp" -ErrorAction SilentlyContinue | Out-Null
Start-Transcript -Path $LogFile -Append

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Malicious Driver Services Disabler" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Lista dei driver da cercare (case-insensitive)
$targetDrivers = @(
    "hlpdrv.sys",
    "havoc.sys",
    "HWAuidoOs2Ec.sys",
    "HWAudio.sys",
    "HWAudioOs2Ec.sys",
    "vuln.sys",
    "fidget.sys",
    "epmntdrv.sys",
    "epmntdrv,5.sys",
    "epmntdrv64.sys",
    "epmntdrv,3.sys",
    "rwdrv.sys"
)

Write-Host "`n[*] Target drivers to search:" -ForegroundColor Yellow
$targetDrivers | ForEach-Object { Write-Host "    - $_" -ForegroundColor White }

$foundServices = @()

# Percorsi del registro da analizzare
$registryPaths = @(
    "HKLM:\SYSTEM\CurrentControlSet\Services",
    "HKLM:\SYSTEM\ControlSet001\Services",
    "HKLM:\SYSTEM\ControlSet002\Services"
)

Write-Host "`n[*] Scanning registry for services using these drivers..." -ForegroundColor Cyan

foreach ($basePath in $registryPaths) {
    if (-not (Test-Path $basePath)) {
        Write-Host "[*] Path not found: $basePath" -ForegroundColor Yellow
        continue
    }
    
    $controlSetName = Split-Path $basePath -Leaf
    Write-Host "`n[*] Scanning $controlSetName..." -ForegroundColor Cyan
    
    # Ottieni tutti i servizi
    $services = Get-ChildItem -Path $basePath -ErrorAction SilentlyContinue
    
    foreach ($service in $services) {
        try {
            # Leggi le proprietà del servizio
            $imagePath = Get-ItemProperty -Path $service.PSPath -Name "ImagePath" -ErrorAction SilentlyContinue
            $type = Get-ItemProperty -Path $service.PSPath -Name "Type" -ErrorAction SilentlyContinue
            $start = Get-ItemProperty -Path $service.PSPath -Name "Start" -ErrorAction SilentlyContinue
            
            if ($imagePath -and $imagePath.ImagePath) {
                $imagePathValue = $imagePath.ImagePath
                
                # Verifica se il path contiene uno dei driver target
                foreach ($driver in $targetDrivers) {
                    if ($imagePathValue -match [regex]::Escape($driver)) {
                        
                        # Determina il tipo di servizio
                        $serviceType = "Unknown"
                        if ($type.Type -eq 1) { $serviceType = "Kernel Driver" }
                        elseif ($type.Type -eq 2) { $serviceType = "File System Driver" }
                        elseif ($type.Type -eq 16) { $serviceType = "Win32 Service" }
                        elseif ($type.Type -eq 32) { $serviceType = "Win32 Share Process" }
                        
                        # Determina lo stato di Start
                        $startType = "Unknown"
                        if ($start.Start -eq 0) { $startType = "Boot" }
                        elseif ($start.Start -eq 1) { $startType = "System" }
                        elseif ($start.Start -eq 2) { $startType = "Auto" }
                        elseif ($start.Start -eq 3) { $startType = "Manual" }
                        elseif ($start.Start -eq 4) { $startType = "Disabled" }
                        
                        $foundServices += [PSCustomObject]@{
                            ServiceName = $service.PSChildName
                            Driver = $driver
                            ImagePath = $imagePathValue
                            RegistryPath = $service.PSPath
                            ControlSet = $controlSetName
                            Type = $serviceType
                            StartType = $startType
                            StartValue = $start.Start
                        }
                        
                        Write-Host "[!] FOUND: $($service.PSChildName)" -ForegroundColor Red
                        Write-Host "    Driver: $driver" -ForegroundColor White
                        Write-Host "    Path: $imagePathValue" -ForegroundColor White
                        Write-Host "    Type: $serviceType | Start: $startType" -ForegroundColor White
                        
                        break
                    }
                }
            }
        } catch {
            # Ignora errori di accesso
        }
    }
}

# Riepilogo dei servizi trovati
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "DISCOVERY SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if ($foundServices.Count -eq 0) {
    Write-Host "[+] No services found using the target drivers" -ForegroundColor Green
    Stop-Transcript
    exit 0
}

Write-Host "[!] Found $($foundServices.Count) service(s) using malicious drivers`n" -ForegroundColor Red

# Raggruppa per nome servizio (potrebbero esserci duplicati tra ControlSet)
$uniqueServices = $foundServices | Group-Object ServiceName

Write-Host "Services to disable:" -ForegroundColor Yellow
foreach ($group in $uniqueServices) {
    $service = $group.Group[0]
    Write-Host "  - $($service.ServiceName) (uses $($service.Driver))" -ForegroundColor White
}

# Chiedi conferma
Write-Host "`n[?] Do you want to disable these services? (Y/N): " -ForegroundColor Yellow -NoNewline
$confirmation = Read-Host

if ($confirmation -ne 'Y' -and $confirmation -ne 'y') {
    Write-Host "[*] Operation cancelled by user" -ForegroundColor Yellow
    Stop-Transcript
    exit 0
}

# Disabilita i servizi
Write-Host "`n[*] Disabling services..." -ForegroundColor Cyan

$disabledCount = 0
$failedCount = 0

foreach ($service in $foundServices) {
    try {
        # Verifica se già disabilitato
        if ($service.StartValue -eq 4) {
            Write-Host "[*] $($service.ServiceName) already disabled in $($service.ControlSet)" -ForegroundColor Yellow
            continue
        }
        
        # Disabilita il servizio (Start = 4)
        Set-ItemProperty -Path $service.RegistryPath -Name "Start" -Value 4 -Force
        Write-Host "[+] Disabled $($service.ServiceName) in $($service.ControlSet)" -ForegroundColor Green
        $disabledCount++
        
    } catch {
        Write-Host "[!] FAILED to disable $($service.ServiceName) in $($service.ControlSet): $_" -ForegroundColor Red
        $failedCount++
    }
}

# Verifica se i servizi sono attualmente in esecuzione
Write-Host "`n[*] Checking running services..." -ForegroundColor Cyan
$runningServices = @()

foreach ($group in $uniqueServices) {
    $serviceName = $group.Name
    $runningService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    
    if ($runningService -and $runningService.Status -eq 'Running') {
        $runningServices += $serviceName
        Write-Host "[!] WARNING: Service '$serviceName' is currently RUNNING" -ForegroundColor Red
    }
}

if ($runningServices.Count -gt 0) {
    Write-Host "`n[!] The following services are still running:" -ForegroundColor Red
    $runningServices | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
    Write-Host "`n[*] Attempting to stop running services..." -ForegroundColor Yellow
    
    foreach ($serviceName in $runningServices) {
        try {
            Stop-Service -Name $serviceName -Force -ErrorAction Stop
            Write-Host "[+] Stopped service: $serviceName" -ForegroundColor Green
        } catch {
            Write-Host "[!] FAILED to stop $serviceName : $_" -ForegroundColor Red
            Write-Host "    You may need to restart the system to fully disable this service" -ForegroundColor Yellow
        }
    }
}

# Verifica driver caricati in memoria
Write-Host "`n[*] Checking if drivers are loaded in memory..." -ForegroundColor Cyan
$loadedDrivers = @()

foreach ($driver in $targetDrivers) {
    $driverName = $driver -replace '\.sys$', ''
    $loaded = driverquery | Select-String -Pattern $driverName -CaseSensitive:$false
    if ($loaded) {
        $loadedDrivers += $driver
        Write-Host "[!] WARNING: $driver is currently LOADED in memory" -ForegroundColor Red
    }
}

# Report finale
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "FINAL REPORT" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total services found: $($foundServices.Count)" -ForegroundColor White
Write-Host "Services disabled: $disabledCount" -ForegroundColor Green
Write-Host "Failed operations: $failedCount" -ForegroundColor $(if($failedCount -gt 0){"Red"}else{"Green"})

if ($loadedDrivers.Count -gt 0) {
    Write-Host "`n[!] CRITICAL: The following drivers are still loaded:" -ForegroundColor Red
    $loadedDrivers | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
    Write-Host "`n[!] SYSTEM RESTART REQUIRED to unload these drivers" -ForegroundColor Red
} else {
    Write-Host "`n[+] No target drivers are currently loaded" -ForegroundColor Green
}

if ($runningServices.Count -gt 0 -or $loadedDrivers.Count -gt 0) {
    Write-Host "`n[!] RECOMMENDATION: Restart the system to ensure all changes take effect" -ForegroundColor Yellow
}

Write-Host "`n[*] Operation completed" -ForegroundColor Cyan
Write-Host "[*] Log file: $LogFile" -ForegroundColor Cyan

Stop-Transcript