<#
.SYNOPSIS
Recolector modular de historiales de navegación

.DESCRIPTION
Cierra navegadores y copia sus archivos de historial a una ubicación específica

.NOTES
- Diseñado para expansión modular
- Usa métodos no intrusivos
#>

function Initialize-BackupEnvironment {
    param(
        [string]$BasePath = "$env:USERPROFILE\Documents\BrowserHistory"
    )

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $targetFolder = Join-Path $BasePath $timestamp
    
    if (-not (Test-Path $targetFolder)) {
        New-Item -Path $targetFolder -ItemType Directory -Force | Out-Null
    }
    
    return $targetFolder
}

function Close-Browsers {
    param(
        [string[]]$BrowserProcesses = @('chrome', 'msedge', 'firefox', 'msedgewebview2')
    )

    Write-Host "Cerrando navegadores..." -ForegroundColor Yellow
    
    foreach ($process in $BrowserProcesses) {
        try {
            if (Get-Process $process -ErrorAction SilentlyContinue) {
                Write-Verbose "Cerrando proceso: $process"
                Stop-Process -Name $process -Force -ErrorAction Stop
                Start-Sleep -Milliseconds 500  # Espera para liberación de archivos
            }
        }
        catch {
            Write-Warning "No se pudo cerrar $process : $_"
        }
    }
}

function Backup-BrowserData {
    param(
        [string]$TargetFolder,
        [string]$BrowserName,
        [string]$ProcessName,
        [string]$SourcePath,
        [string]$FileName
    )

    $result = [PSCustomObject]@{
        Browser  = $BrowserName
        Success  = $false
        FilePath = $null
        Error    = $null
    }

    try {
        if (-not (Test-Path $SourcePath)) {
            throw "Archivo no encontrado"
        }

        $destPath = Join-Path $TargetFolder $FileName
        Copy-Item -Path $SourcePath -Destination $destPath -Force
        
        $result.Success = $true
        $result.FilePath = $destPath
    }
    catch {
        $result.Error = $_
    }

    return $result
}

#------------------- EJECUCIÓN PRINCIPAL -------------------
$targetFolder = Initialize-BackupEnvironment

# 1. Cierre de navegadores (opcional, comentar si no se necesita)
Close-Browsers

# 2. Recolección de historiales
$backupResults = @()

# Chrome
$backupResults += Backup-BrowserData -TargetFolder $targetFolder `
    -BrowserName "Chrome" -ProcessName "chrome" `
    -SourcePath "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\History" `
    -FileName "chrome_history.db"

# Microsoft Edge
$backupResults += Backup-BrowserData -TargetFolder $targetFolder `
    -BrowserName "Edge" -ProcessName "msedge" `
    -SourcePath "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\History" `
    -FileName "edge_history.db"

# Firefox
$firefoxPath = Get-ChildItem "$env:APPDATA\Mozilla\Firefox\Profiles\*.default-release\places.sqlite" |
               Select-Object -First 1 -ExpandProperty FullName

$backupResults += Backup-BrowserData -TargetFolder $targetFolder `
    -BrowserName "Firefox" -ProcessName "firefox" `
    -SourcePath $firefoxPath `
    -FileName "firefox_places.sqlite"

# 3. Resultados
$backupResults | Format-Table -AutoSize

Write-Host "`nProceso completado. Archivos disponibles en: $targetFolder`n" -ForegroundColor Green