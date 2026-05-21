<#
.SYNOPSIS
    Startet einen kleinen lokalen Webserver für die Web-Oberfläche.

.DESCRIPTION
    Dieser Server ist KEIN ersatz für das Hauptskript - er ist nur eine
    bequeme Oberfläche im Browser. Die eigentliche Logik liegt weiterhin
    in den PowerShell-Modulen (Import-SongCsv, Find-Duplicates).

    Ablauf:
      1. .NET-HttpListener auf http://localhost:8080 starten.
      2. GET-Anfragen liefern die statischen Web-Dateien (HTML/CSS/JS).
      3. POST /api/check empfängt den CSV-Inhalt im Body, ruft die
         PowerShell-Funktionen auf und gibt das Ergebnis als JSON zurück.

.PARAMETER Port
    Port, auf dem der Server lauscht. Standard: 8080.

.EXAMPLE
    .\Start-WebServer.ps1
    .\Start-WebServer.ps1 -Port 9090
#>
[CmdletBinding()]
param(
    [int]$Port = 8080
)

# Module einbinden - dieselben wie das CLI-Skript verwendet.
. (Join-Path $PSScriptRoot 'modules\Import-SongCsv.ps1')
. (Join-Path $PSScriptRoot 'modules\Find-Duplicates.ps1')
. (Join-Path $PSScriptRoot 'modules\Export-Results.ps1')
. (Join-Path $PSScriptRoot 'modules\Get-SpotifyTracks.ps1')
. (Join-Path $PSScriptRoot 'modules\Connect-Spotify.ps1')

$webRoot    = Join-Path $PSScriptRoot 'web'
$configPath = Join-Path $PSScriptRoot 'config.json'

# HttpListener ist eine .NET-Klasse für sehr einfache HTTP-Server.
# Reicht für ein Schulprojekt voll und ganz.
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$Port/")

try {
    $listener.Start()
}
catch {
    Write-Host "Konnte Webserver auf Port $Port nicht starten." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Web-UI läuft auf http://localhost:$Port/" -ForegroundColor Green
Write-Host "Im Browser öffnen und CSV-Datei hochladen." -ForegroundColor Yellow
Write-Host "Beenden: Strg+C oder Taste 'Q' drücken." -ForegroundColor Yellow
Write-Host ""

# Strg+C nicht direkt PowerShell beenden lassen, sondern als normale Eingabe
# behandeln. So können wir den Listener sauber stoppen.
[Console]::TreatControlCAsInput = $true

# Hilfsfunktion: schickt eine statische Datei (HTML/CSS/JS) als Antwort.
# no-cache, damit nach Code-Aenderungen der Browser sofort die neue Version
# laedt - sonst muesste man jedes Mal Strg+F5 druecken.
function Send-StaticFile {
    param($Response, [string]$FilePath)

    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    $Response.ContentType = switch ([System.IO.Path]::GetExtension($FilePath).ToLower()) {
        '.html' { 'text/html; charset=utf-8' }
        '.css'  { 'text/css; charset=utf-8' }
        '.js'   { 'application/javascript; charset=utf-8' }
        default { 'application/octet-stream' }
    }
    $Response.ContentLength64 = $bytes.Length
    $Response.Headers.Add('Cache-Control', 'no-cache, must-revalidate')
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
}

# Hilfsfunktion: schickt ein PowerShell-Objekt als JSON-Antwort.
# API-Antworten duerfen NIE vom Browser gecacht werden, sonst zeigt
# /api/config noch den alten "nicht eingeloggt"-Status nach dem Login.
function Send-JsonResponse {
    param($Response, $Object, [int]$StatusCode = 200)

    $json  = $Object | ConvertTo-Json -Depth 5 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)

    $Response.StatusCode      = $StatusCode
    $Response.ContentType     = 'application/json; charset=utf-8'
    $Response.ContentLength64 = $bytes.Length
    $Response.Headers.Add('Cache-Control', 'no-store, no-cache, must-revalidate')
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
}

# Haupt-Schleife: solange laufen, bis der User Strg+C oder 'Q' drückt.
#
# Wichtig: $listener.GetContext() würde den Thread blockieren, bis ein
# Browser-Request kommt - dadurch reagiert Strg+C nicht. Lösung: die
# asynchrone Variante GetContextAsync() verwenden und in einer Schleife
# kurz warten. So können wir zwischendrin die Tastatur prüfen.
$shouldStop = $false
try {
    while (-not $shouldStop -and $listener.IsListening) {

        # Anfrage asynchron starten - blockiert NICHT.
        $contextTask = $listener.GetContextAsync()

        # Warten, bis entweder ein Request reinkommt ODER eine Taste gedrückt wird.
        # WaitOne(200) wartet maximal 200 ms und gibt dann zurück.
        while (-not $contextTask.AsyncWaitHandle.WaitOne(200)) {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                $isCtrlC = ($key.Modifiers -band [ConsoleModifiers]::Control) -and ($key.Key -eq 'C')
                $isQuit  = ($key.Key -eq 'Q')
                if ($isCtrlC -or $isQuit) {
                    Write-Host ""
                    Write-Host "Server wird beendet..." -ForegroundColor Yellow
                    $shouldStop = $true
                    break
                }
            }
        }
        if ($shouldStop) { break }

        # Ab hier ganz normal weiter - der Task ist fertig, Context abholen.
        $context  = $contextTask.GetAwaiter().GetResult()
        $request  = $context.Request
        $response = $context.Response

        try {
            $reqPath = $request.Url.AbsolutePath
            $method  = $request.HttpMethod

            Write-Host "[$method] $reqPath" -ForegroundColor DarkGray

            # ---- GET: statische Dateien ausliefern ----
            # Wichtig: /api/* AUSSCHLIESSEN, sonst fangen wir hier alle
            # API-GETs ab und liefern 404 mit leerem Body, was im Browser
            # als "Unexpected end of JSON input" landet.
            if ($method -eq 'GET' -and -not $reqPath.StartsWith('/api/')) {
                # "/" -> "index.html", sonst die angefragte Datei.
                $relative = if ($reqPath -eq '/') { 'index.html' } else { $reqPath.TrimStart('/') }
                $filePath = Join-Path $webRoot $relative

                # Schutz gegen "Path Traversal" (z.B. /../../etc/passwd):
                # Der aufgelöste Pfad muss innerhalb von $webRoot liegen.
                $resolved = [System.IO.Path]::GetFullPath($filePath)
                $rootFull = [System.IO.Path]::GetFullPath($webRoot)
                if (-not $resolved.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $response.StatusCode = 403
                }
                elseif (Test-Path -LiteralPath $resolved -PathType Leaf) {
                    Send-StaticFile -Response $response -FilePath $resolved
                }
                else {
                    $response.StatusCode = 404
                }
            }
            # ---- GET /api/config: Spotify konfiguriert? eingeloggt? ----
            elseif ($method -eq 'GET' -and $reqPath -eq '/api/config') {
                $configured = $false
                $connected  = $false
                if (Test-Path -LiteralPath $configPath) {
                    try {
                        $cfg = Get-Content -LiteralPath $configPath -Raw -ErrorAction Stop |
                               ConvertFrom-Json -ErrorAction Stop
                        if ($cfg.Spotify.ClientId -and $cfg.Spotify.ClientSecret `
                            -and $cfg.Spotify.ClientId -notlike 'DEIN-*' `
                            -and $cfg.Spotify.ClientSecret -notlike 'DEIN-*') {
                            $configured = $true
                        }
                        # Refresh-Token vorhanden = Login wurde mal gemacht
                        if ($cfg.Spotify.RefreshToken) { $connected = $true }
                    } catch { }
                }
                Send-JsonResponse -Response $response -Object @{
                    configured = $configured
                    connected  = $connected
                }
            }
            # ---- POST /api/spotify/connect: OAuth-Login starten ----
            # Achtung: blockiert den Webserver, bis OAuth fertig ist (max. 5 Min).
            elseif ($method -eq 'POST' -and $reqPath -eq '/api/spotify/connect') {
                try {
                    [void](Connect-Spotify -ConfigPath $configPath)
                    Send-JsonResponse -Response $response -Object @{ success = $true }
                } catch {
                    Send-JsonResponse -Response $response -StatusCode 400 -Object @{
                        success = $false
                        error   = $_.Exception.Message
                    }
                }
            }
            # ---- GET /api/spotify/my-playlists: eigene Playlists des Users ----
            elseif ($method -eq 'GET' -and $reqPath -eq '/api/spotify/my-playlists') {
                try {
                    $token = Get-SpotifyAccessToken -ConfigPath $configPath
                    $pls   = Get-MyPlaylists -AccessToken $token
                    Send-JsonResponse -Response $response -Object @{
                        success   = $true
                        playlists = @(
                            $pls | ForEach-Object {
                                @{
                                    Id         = $_.Id
                                    Name       = $_.Name
                                    Owner      = $_.Owner
                                    TrackCount = $_.TrackCount
                                }
                            }
                        )
                    }
                } catch {
                    Send-JsonResponse -Response $response -StatusCode 401 -Object @{
                        success = $false
                        error   = $_.Exception.Message
                    }
                }
            }
            # ---- POST /api/spotify/check-by-id: eine eigene Playlist pruefen ----
            elseif ($method -eq 'POST' -and $reqPath -eq '/api/spotify/check-by-id') {
                $reader = [System.IO.StreamReader]::new($request.InputStream, $request.ContentEncoding)
                $body   = $reader.ReadToEnd()
                $reader.Dispose()
                try {
                    $payload = $body | ConvertFrom-Json -ErrorAction Stop
                    $token   = Get-SpotifyAccessToken -ConfigPath $configPath
                    $songs   = Get-PlaylistTracksUser -PlaylistId $payload.playlistId -AccessToken $token
                    $duplicates = Find-Duplicates -Songs $songs -IncludeAlbum:([bool]$payload.album)
                    Send-JsonResponse -Response $response -Object @{
                        success    = $true
                        total      = $songs.Count
                        duplicates = @(
                            $duplicates | ForEach-Object {
                                @{
                                    Title  = $_.Title
                                    Artist = $_.Artist
                                    Album  = $_.Album
                                    Count  = $_.Count
                                }
                            }
                        )
                    }
                } catch {
                    Send-JsonResponse -Response $response -StatusCode 400 -Object @{
                        success = $false
                        error   = $_.Exception.Message
                    }
                }
            }
            # ---- POST /api/config: Credentials speichern ----
            elseif ($method -eq 'POST' -and $reqPath -eq '/api/config') {
                $reader = [System.IO.StreamReader]::new($request.InputStream, $request.ContentEncoding)
                $body   = $reader.ReadToEnd()
                $reader.Dispose()

                try {
                    $payload      = $body | ConvertFrom-Json -ErrorAction Stop
                    $clientId     = ([string]$payload.clientId).Trim()
                    $clientSecret = ([string]$payload.clientSecret).Trim()

                    if ([string]::IsNullOrWhiteSpace($clientId) `
                        -or [string]::IsNullOrWhiteSpace($clientSecret)) {
                        throw "Client ID und Client Secret duerfen nicht leer sein."
                    }

                    $cfg  = @{ Spotify = @{ ClientId = $clientId; ClientSecret = $clientSecret } }
                    $json = $cfg | ConvertTo-Json -Depth 5
                    [System.IO.File]::WriteAllText(
                        $configPath, $json, [System.Text.UTF8Encoding]::new($false)
                    )

                    Send-JsonResponse -Response $response -Object @{ success = $true }
                }
                catch {
                    Send-JsonResponse -Response $response -StatusCode 400 -Object @{
                        success = $false
                        error   = $_.Exception.Message
                    }
                }
            }
            # ---- POST /api/spotify: Spotify-Playlist verarbeiten ----
            elseif ($method -eq 'POST' -and $reqPath -eq '/api/spotify') {
                # Body ist JSON: { url: "...", album: true|false }
                $reader = [System.IO.StreamReader]::new($request.InputStream, $request.ContentEncoding)
                $body   = $reader.ReadToEnd()
                $reader.Dispose()

                try {
                    $payload = $body | ConvertFrom-Json -ErrorAction Stop
                    $songs   = Get-SpotifyTracks -PlaylistUrlOrId $payload.url -ConfigPath $configPath
                    $duplicates = Find-Duplicates -Songs $songs -IncludeAlbum:([bool]$payload.album)

                    Send-JsonResponse -Response $response -Object @{
                        success    = $true
                        total      = $songs.Count
                        duplicates = @(
                            $duplicates | ForEach-Object {
                                @{
                                    Title  = $_.Title
                                    Artist = $_.Artist
                                    Album  = $_.Album
                                    Count  = $_.Count
                                }
                            }
                        )
                    }
                }
                catch {
                    Send-JsonResponse -Response $response -StatusCode 400 -Object @{
                        success = $false
                        error   = $_.Exception.Message
                    }
                }
            }
            # ---- POST /api/check: CSV verarbeiten ----
            elseif ($method -eq 'POST' -and $reqPath -eq '/api/check') {
                # CSV-Inhalt aus dem Request-Body lesen.
                $reader = [System.IO.StreamReader]::new($request.InputStream, $request.ContentEncoding)
                $body   = $reader.ReadToEnd()
                $reader.Dispose()

                # In eine temporäre Datei schreiben (ohne BOM), damit Import-Csv
                # darauf zugreifen kann wie auf jede normale CSV.
                $tempCsv = Join-Path ([System.IO.Path]::GetTempPath()) ("songs_" + [guid]::NewGuid().ToString('N') + ".csv")
                [System.IO.File]::WriteAllText($tempCsv, $body, [System.Text.UTF8Encoding]::new($false))

                try {
                    # Optionalen Album-Modus aus der Query-Parameter ?album=1 lesen.
                    $includeAlbum = ($request.QueryString['album'] -eq '1')

                    # Kernlogik wiederverwenden!
                    $songs      = Import-SongCsv -Path $tempCsv
                    $duplicates = Find-Duplicates -Songs $songs -IncludeAlbum:$includeAlbum

                    # Antwort für die Website zusammenbauen.
                    $payload = @{
                        success    = $true
                        total      = $songs.Count
                        duplicates = @(
                            $duplicates | ForEach-Object {
                                @{
                                    Title  = $_.Title
                                    Artist = $_.Artist
                                    Album  = $_.Album
                                    Count  = $_.Count
                                }
                            }
                        )
                    }
                    Send-JsonResponse -Response $response -Object $payload
                }
                catch {
                    # Fachlicher Fehler (z.B. Spalte fehlt) -> 400 mit Klartext.
                    Send-JsonResponse -Response $response -StatusCode 400 -Object @{
                        success = $false
                        error   = $_.Exception.Message
                    }
                }
                finally {
                    Remove-Item -LiteralPath $tempCsv -Force -ErrorAction SilentlyContinue
                }
            }
            else {
                $response.StatusCode = 404
            }
        }
        catch {
            # Unerwarteter Server-Fehler.
            try {
                Send-JsonResponse -Response $response -StatusCode 500 -Object @{
                    success = $false
                    error   = "Server-Fehler: $($_.Exception.Message)"
                }
            } catch { }
        }
        finally {
            # Antwort immer abschliessen, sonst hängt der Browser.
            $response.OutputStream.Close()
        }
    }
}
finally {
    # Strg+C wieder zur normalen PowerShell-Funktion zurückgeben.
    [Console]::TreatControlCAsInput = $false
    if ($listener.IsListening) { $listener.Stop() }
    $listener.Close()
    Write-Host "Server gestoppt." -ForegroundColor Green
}
