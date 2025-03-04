Set-ExecutionPolicy Unrestricted -Scope LocalMachine -Force
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force		
Install-Module -Name PSSQLite -Force 

# Importar el módulo pslite
Import-Module PSSQLite

# Ruta a la base de datos de historial de Chrome
$dbPath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\History"

# Verificar si el archivo de historial existe
if (-not (Test-Path $dbPath)) {
    Write-Host "El archivo de historial de Chrome no se encontró. Asegúrate de que Chrome esté cerrado." -ForegroundColor Red
    exit
}

# Función para convertir la marca de tiempo de Chrome a una fecha legible
function Convert-ChromeTime {
    param (
        [long]$chromeTime
    )
    $epoch = [datetime]::FromFileTimeUtc(116444736000000000)
    return $epoch.AddSeconds($chromeTime / 1000000)
}

# Consultar la tabla 'urls' que contiene el historial de navegación
$query = "SELECT url, title, last_visit_time FROM urls"

# Ejecutar la consulta
try {
    $results = Invoke-SqliteQuery -Query $query -DataSource $dbPath

    # Convertir las marcas de tiempo y preparar los datos para guardar
    $output = $results | ForEach-Object {
        $lastVisitTime = Convert-ChromeTime $_.last_visit_time
        [PSCustomObject]@{
            URL           = $_.url
            Title         = $_.title
            LastVisitTime = $lastVisitTime
        }
    }

    # Mostrar los resultados en la consola
    $output | Format-Table -AutoSize

    # Ruta de la carpeta donde se guardará el archivo
    $outputFolder = "C:\Users"
    $outputFilePath = Join-Path -Path $outputFolder -ChildPath "config.txt"

    # Crear la carpeta si no existe
    if (-not (Test-Path $outputFolder)) {
        New-Item -ItemType Directory -Path $outputFolder | Out-Null
    }

    # Guardar los resultados en un archivo de texto
    $output | ForEach-Object {
        "URL: $($_.URL)"
        "Título: $($_.Title)"
        "Última visita: $($_.LastVisitTime)"
        "----------------------------------------"
    } | Out-File -FilePath $outputFilePath -Encoding UTF8

    Write-Host "El historial de Chrome se ha guardado en: $outputFilePath" -ForegroundColor Green
}
catch {
    Write-Host "Error al consultar el historial de Chrome: $_" -ForegroundColor Red
}