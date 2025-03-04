#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

# Configuración temporal de política de ejecución
$originalPolicy = Get-ExecutionPolicy -Scope LocalMachine
Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force -ErrorAction SilentlyContinue

# Instalación silenciosa de dependencias
try {
    $null = Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
    $null = Install-Module -Name PSSQLite -Force -AllowClobber
}
catch {
    exit
}
# prueba
Import-Module PSSQLite -ErrorAction SilentlyContinue

function Close-Browsers {
    $browsers = 'chrome', 'msedge', 'firefox', 'msedgewebview2'
    foreach ($process in $browsers) {
        try {
            Get-Process $process -ErrorAction SilentlyContinue | Stop-Process -Force
            Start-Sleep -Milliseconds 500
        }
        catch {}
    }
}

function Get-BrowserHistory {
    param(
        [string]$BrowserName,
        [string]$HistoryPath,
        [string]$Query,
        [string]$TimeType
    )

    try {
        $tempFile = "$env:TEMP\$([Guid]::NewGuid()).tmp"
        Copy-Item $HistoryPath $tempFile -Force

        $data = Invoke-SqliteQuery -DataSource $tempFile -Query $Query | ForEach-Object {
            [PSCustomObject]@{
                Browser    = $BrowserName
                URL       = $_.url
                Title     = $_.title
                Timestamp = switch ($TimeType) {
                    'Chrome' { [datetime]::FromFileTimeUtc(116444736000000000 + $_.last_visit_time * 10) }
                    'Firefox' { [datetime]::new(1970, 1, 1).AddMilliseconds($_.visit_date) }
                }
                VisitCount = $_.visit_count
            }
        }

        Remove-Item $tempFile -Force
        return $data
    }
    catch {
        return $null
    }
}

# Ejecución principal
try {
    Close-Browsers

    $results = @()

    # Chrome
    try {
        $chrome = Get-BrowserHistory -BrowserName 'Chrome' `
            -HistoryPath "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\History" `
            -Query "SELECT url, title, last_visit_time, visit_count FROM urls" `
            -TimeType 'Chrome'
        
        if ($chrome) { $results += $chrome }
    }
    catch {}

    # Edge
    try {
        $edge = Get-BrowserHistory -BrowserName 'Edge' `
            -HistoryPath "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\History" `
            -Query "SELECT url, title, last_visit_time, visit_count FROM urls" `
            -TimeType 'Chrome'
        
        if ($edge) { $results += $edge }
    }
    catch {}

    # Firefox
    try {
        $firefoxPath = Get-ChildItem "$env:APPDATA\Mozilla\Firefox\Profiles\*.default-release\places.sqlite" |
                      Select-Object -First 1 -ExpandProperty FullName
        
        $firefox = Get-BrowserHistory -BrowserName 'Firefox' `
            -HistoryPath $firefoxPath `
            -Query @"
                SELECT p.url, p.title, v.visit_date, COUNT(p.id) as visit_count 
                FROM moz_places p 
                JOIN moz_historyvisits v ON p.id = v.place_id 
                GROUP BY p.id
"@ -TimeType 'Firefox'
        
        if ($firefox) { $results += $firefox }
    }
    catch {}

    # Exportar resultados
    if ($results) {
        $outputPath = "$env:USERPROFILE\Documents\BrowserHistory.csv"
        $results | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
    }
}
finally {
    Set-ExecutionPolicy $originalPolicy -Scope LocalMachine -Force -ErrorAction SilentlyContinue
}
