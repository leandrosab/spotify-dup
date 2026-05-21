<#
.SYNOPSIS
    Spotify "Authorization Code Flow" - Login mit eigenem Account und
    Zugriff auf private/eigene Playlists.

.DESCRIPTION
    Stellt vier Funktionen bereit:
      Connect-Spotify          OAuth-Login: oeffnet Browser, faengt Callback
                               auf Port 8888 ab, tauscht Auth-Code gegen Tokens,
                               speichert sie in config.json.
      Get-SpotifyAccessToken   liefert einen GUELTIGEN Access-Token.
                               Refresht automatisch, wenn er abgelaufen ist.
      Get-MyPlaylists          listet die Playlists des eingeloggten Users.
      Get-PlaylistTracksUser   holt die Tracks einer Playlist mit User-Token.

    Hintergrund:
    Der "Client Credentials Flow" (in Get-SpotifyTracks.ps1) reicht nur fuer
    OEFFENTLICHE Playlists per URL. Fuer die EIGENEN Playlists eines Users
    braucht man einen User-Login - das ist genau der "Authorization Code Flow".

.NOTES
    Voraussetzung: Im Spotify Dashboard muss bei "Redirect URIs"
    http://localhost:8888/callback eingetragen sein.
#>

# Konstanten - werden mehrfach verwendet
# Spotify verbietet seit 2025 'http://localhost' als Redirect URI -
# erlaubt sind nur 'https://...' oder die Loopback-IP 'http://127.0.0.1...'.
$script:CALLBACK_HOST = '127.0.0.1'
$script:CALLBACK_PORT = 8888
$script:CALLBACK_URI  = "http://$($script:CALLBACK_HOST):$($script:CALLBACK_PORT)/callback"
# Scopes:
#   playlist-read-private/collaborative -> private/eigene Playlists lesen
#   user-read-private                    -> Region/Country aus dem Token
# (Modify-Scopes nicht enthalten, da Spotify Track-Modify-Operationen
#  in Development Mode ohnehin mit 403 blockiert.)
$script:OAUTH_SCOPES  = 'playlist-read-private playlist-read-collaborative user-read-private'
$script:TOKEN_URL     = 'https://accounts.spotify.com/api/token'

# ---- Hilfsfunktion: Spotify-Fehlerdetails aus einer Exception ziehen ----
# Spotify gibt im Body oft ein JSON wie {"error":{"status":403,"message":"..."}} zurueck.
# Invoke-RestMethod versteckt das aber - wir holen es hier manuell raus, damit
# der User sieht, WAS schiefgelaufen ist (statt nur "Server hat Fehler zurueckgegeben").
function Get-SpotifyErrorDetail {
    param($Exception)
    $statusCode = '?'
    $body = $null
    if ($Exception.Response) {
        try {
            $statusCode = [int]$Exception.Response.StatusCode
        } catch { }
        try {
            $stream = $Exception.Response.GetResponseStream()
            if ($stream.CanSeek) { $stream.Position = 0 }
            $reader = [System.IO.StreamReader]::new($stream)
            $body = $reader.ReadToEnd()
            $reader.Dispose()
        } catch { }
    }
    $msg = "HTTP $statusCode"
    if ($body) { $msg += " - Spotify: $body" }
    return $msg
}

# ---- Tokens in config.json speichern ----
# Wir schreiben immer alle Spotify-Felder gemeinsam, damit das JSON konsistent bleibt.
function Save-SpotifyTokens {
    param(
        [string]$ConfigPath,
        [string]$ClientId,
        [string]$ClientSecret,
        [string]$AccessToken,
        [string]$RefreshToken,
        [int]$ExpiresIn,
        [string]$Scope = ''      # Welche Berechtigungen Spotify wirklich gegeben hat
    )
    $cfg = @{
        Spotify = @{
            ClientId     = $ClientId
            ClientSecret = $ClientSecret
            AccessToken  = $AccessToken
            RefreshToken = $RefreshToken
            # -60 Sekunden Sicherheitspuffer, damit wir nicht im letzten Moment refreshen.
            TokenExpiry  = (Get-Date).AddSeconds($ExpiresIn - 60).ToString('o')
            Scope        = $Scope
        }
    }
    $json = $cfg | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($ConfigPath, $json, [System.Text.UTF8Encoding]::new($false))
}

# ---- Hauptfunktion: Login per Browser ----
function Connect-Spotify {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ConfigPath)

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "config.json fehlt. Erst Client ID/Secret einrichten ('config'-Befehl)."
    }
    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $clientId     = $config.Spotify.ClientId
    $clientSecret = $config.Spotify.ClientSecret

    if (-not $clientId -or -not $clientSecret -or $clientId -like 'DEIN-*') {
        throw "Client ID/Secret nicht eingerichtet. Erst 'config' ausfuehren."
    }

    # CSRF-Schutz: zufaelliger State-Wert, der beim Callback geprueft wird.
    # Verhindert, dass jemand ueber einen Link einen fremden OAuth-Code unterjubelt.
    $state = [guid]::NewGuid().ToString('N')

    # Authorize-URL zusammenbauen. EscapeDataString sorgt dafuer, dass z.B.
    # die Leerzeichen in den Scopes als %20 codiert werden.
    # show_dialog=true zwingt Spotify, IMMER die Consent-Page zu zeigen -
    # sonst wird die alte Zustimmung wiederverwendet und neue Scopes werden
    # nie gewaehrt (klassische "warum hat der Token meine neuen Rechte nicht?"-
    # Falle). Etwas nervig, aber zuverlaessig.
    $authUrl = 'https://accounts.spotify.com/authorize?' +
        'response_type=code' +
        '&client_id=' + [Uri]::EscapeDataString($clientId) +
        '&scope=' + [Uri]::EscapeDataString($script:OAUTH_SCOPES) +
        '&redirect_uri=' + [Uri]::EscapeDataString($script:CALLBACK_URI) +
        '&state=' + $state +
        '&show_dialog=true'

    # Wir verwenden TcpListener (statt HttpListener), weil HttpListener auf
    # 127.0.0.1 unter Windows eine URL-ACL-Reservierung oder Admin-Rechte
    # braucht. TcpListener bindet einen einfachen Socket - kein urlacl noetig.
    $tcp = [System.Net.Sockets.TcpListener]::new(
        [System.Net.IPAddress]::Loopback, $script:CALLBACK_PORT
    )
    try {
        $tcp.Start()
    } catch {
        throw "Konnte Listener auf 127.0.0.1:$($script:CALLBACK_PORT) nicht starten. Laeuft schon ein anderer Prozess auf diesem Port? Details: $($_.Exception.Message)"
    }

    try {
        # Browser oeffnen mit Login-URL.
        Start-Process $authUrl

        # Auf TCP-Verbindung des Browsers warten (max. 5 Minuten).
        $acceptTask = $tcp.AcceptTcpClientAsync()
        if (-not $acceptTask.AsyncWaitHandle.WaitOne([TimeSpan]::FromMinutes(5))) {
            throw "Timeout: kein Spotify-Callback innerhalb von 5 Minuten erhalten."
        }
        $client = $acceptTask.GetAwaiter().GetResult()

        $code = $null; $returnedState = $null; $errorParam = $null

        try {
            $stream = $client.GetStream()
            $reader = [System.IO.StreamReader]::new($stream)

            # HTTP-Request-Zeile lesen, z.B. "GET /callback?code=...&state=... HTTP/1.1"
            $requestLine = $reader.ReadLine()
            if ([string]::IsNullOrEmpty($requestLine)) {
                throw "Leere HTTP-Anfrage erhalten."
            }
            $reqParts = $requestLine -split ' '
            if ($reqParts.Count -lt 2) {
                throw "Ungueltige HTTP-Anfrage: $requestLine"
            }
            $reqPath = $reqParts[1]

            # Header bis zur Leerzeile ueberspringen (Body interessiert uns nicht).
            while ($reader.Peek() -ge 0) {
                $line = $reader.ReadLine()
                if ([string]::IsNullOrEmpty($line)) { break }
            }

            # Query-Parameter aus dem Pfad extrahieren.
            $uri = [System.Uri]::new("http://$($script:CALLBACK_HOST):$($script:CALLBACK_PORT)$reqPath")
            $queryParams = @{}
            foreach ($pair in $uri.Query.TrimStart('?') -split '&') {
                if (-not $pair) { continue }
                $kv = $pair -split '=', 2
                if ($kv.Count -eq 2) {
                    $queryParams[$kv[0]] = [System.Uri]::UnescapeDataString($kv[1])
                }
            }
            $code          = $queryParams['code']
            $returnedState = $queryParams['state']
            $errorParam    = $queryParams['error']

            # HTTP-Antwort zusammenbauen und ueber den TCP-Stream rausschicken.
            $html = if ($errorParam) {
                "<html><body style='font-family:sans-serif;background:#0d1117;color:#f85149;padding:2rem;'>" +
                "<h2>Spotify-Login fehlgeschlagen</h2><p>$errorParam</p>" +
                "<p style='color:#8b949e'>Du kannst diesen Tab schliessen.</p></body></html>"
            } else {
                "<html><body style='font-family:sans-serif;background:#0d1117;color:#56d364;padding:2rem;'>" +
                "<h2>Login erfolgreich!</h2>" +
                "<p style='color:#8b949e'>Du kannst diesen Tab schliessen und zum duplichecker zurueckkehren.</p>" +
                "</body></html>"
            }
            $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($html)
            $headerStr = "HTTP/1.1 200 OK`r`n" +
                         "Content-Type: text/html; charset=utf-8`r`n" +
                         "Content-Length: $($bodyBytes.Length)`r`n" +
                         "Connection: close`r`n`r`n"
            $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($headerStr)
            $stream.Write($headerBytes, 0, $headerBytes.Length)
            $stream.Write($bodyBytes, 0, $bodyBytes.Length)
            $stream.Flush()
        }
        finally {
            $client.Close()
        }

        # Validierungen NACH dem Schliessen, damit die HTML-Antwort sicher beim Browser ist.
        if ($errorParam) { throw "Spotify-Login fehlgeschlagen: $errorParam" }
        if (-not $code) { throw "Kein Auth-Code im Callback erhalten." }
        if ($returnedState -ne $state) {
            throw "State-Mismatch (CSRF-Schutz). Bitte erneut versuchen."
        }

        # Auth-Code gegen Access-Token + Refresh-Token tauschen.
        $authPair   = "${clientId}:${clientSecret}"
        $authBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($authPair))

        try {
            $tokenResponse = Invoke-RestMethod `
                -Method POST `
                -Uri $script:TOKEN_URL `
                -Headers @{ Authorization = "Basic $authBase64" } `
                -Body @{
                    grant_type   = 'authorization_code'
                    code         = $code
                    redirect_uri = $script:CALLBACK_URI
                } `
                -ContentType 'application/x-www-form-urlencoded'
        } catch {
            throw "Token-Tausch fehlgeschlagen. Pruefe ob '$($script:CALLBACK_URI)' im Spotify-Dashboard als Redirect URI eingetragen ist. Details: $($_.Exception.Message)"
        }

        Save-SpotifyTokens -ConfigPath $ConfigPath `
            -ClientId $clientId -ClientSecret $clientSecret `
            -AccessToken $tokenResponse.access_token `
            -RefreshToken $tokenResponse.refresh_token `
            -ExpiresIn $tokenResponse.expires_in `
            -Scope $tokenResponse.scope

        # Diagnose-Ausgabe: zeigt, was Spotify wirklich gewaehrt hat.
        Write-Host "  [scopes] $($tokenResponse.scope)" -ForegroundColor DarkGray

        return $true
    }
    finally {
        $tcp.Stop()
    }
}

# ---- Gueltigen Access-Token holen (refresht automatisch) ----
function Get-SpotifyAccessToken {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ConfigPath)

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "config.json fehlt. Erst 'config' und dann Login ausfuehren."
    }
    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json

    if (-not $config.Spotify.RefreshToken) {
        throw "Nicht mit Spotify verbunden. Erst 'connect' im Spotify-Modus ausfuehren."
    }

    # Wenn wir noch einen gueltigen Access-Token haben: direkt zurueckgeben.
    if ($config.Spotify.AccessToken -and $config.Spotify.TokenExpiry) {
        try {
            $expiry = [DateTime]::Parse($config.Spotify.TokenExpiry)
            if ((Get-Date) -lt $expiry) {
                return $config.Spotify.AccessToken
            }
        } catch { }
    }

    # Sonst: Token mit Refresh-Token erneuern.
    $authPair   = "$($config.Spotify.ClientId):$($config.Spotify.ClientSecret)"
    $authBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($authPair))

    try {
        $response = Invoke-RestMethod `
            -Method POST `
            -Uri $script:TOKEN_URL `
            -Headers @{ Authorization = "Basic $authBase64" } `
            -Body @{
                grant_type    = 'refresh_token'
                refresh_token = $config.Spotify.RefreshToken
            } `
            -ContentType 'application/x-www-form-urlencoded'
    } catch {
        throw "Token-Refresh fehlgeschlagen. Eventuell musst du dich neu einloggen ('connect'). Details: $($_.Exception.Message)"
    }

    # Spotify gibt manchmal einen NEUEN Refresh-Token zurueck, manchmal nicht.
    $newRefresh = if ($response.refresh_token) { $response.refresh_token } else { $config.Spotify.RefreshToken }
    # Scope kann auch beim Refresh aktualisiert werden - sonst alten behalten.
    $newScope   = if ($response.scope) { $response.scope } else { $config.Spotify.Scope }

    Save-SpotifyTokens -ConfigPath $ConfigPath `
        -ClientId $config.Spotify.ClientId -ClientSecret $config.Spotify.ClientSecret `
        -AccessToken $response.access_token `
        -RefreshToken $newRefresh `
        -ExpiresIn $response.expires_in `
        -Scope $newScope

    return $response.access_token
}

# ---- Eigene Playlists des Users abrufen ----
function Get-MyPlaylists {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$AccessToken)

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $playlists = New-Object System.Collections.Generic.List[object]
    $url = 'https://api.spotify.com/v1/me/playlists?limit=50'

    while ($url) {
        try {
            $page = Invoke-RestMethod -Method GET -Uri $url `
                -Headers @{ Authorization = "Bearer $AccessToken" }
        } catch {
            throw "Konnte Playlists nicht laden: $(Get-SpotifyErrorDetail $_.Exception)"
        }
        foreach ($pl in $page.items) {
            if ($null -eq $pl) { continue }

            # Spotify hat das Feld umbenannt: 'tracks' (alt) -> 'items' (neu).
            $trackCount = 0
            if ($null -ne $pl.tracks -and $null -ne $pl.tracks.total) {
                $trackCount = [int]$pl.tracks.total
            } elseif ($null -ne $pl.items -and $null -ne $pl.items.total) {
                $trackCount = [int]$pl.items.total
            }
            $ownerName = if ($pl.owner -and $pl.owner.display_name) {
                $pl.owner.display_name
            } else { 'unknown' }

            $playlists.Add([pscustomobject]@{
                Id            = $pl.id
                Name          = $pl.name
                Owner         = $ownerName
                OwnerId       = if ($pl.owner) { $pl.owner.id } else { '' }
                Collaborative = [bool]$pl.collaborative
                TrackCount    = $trackCount
            })
        }
        $url = $page.next
    }
    return @($playlists.ToArray())
}

# ---- Tracks einer Playlist mit User-Token holen ----
# Wir holen bewusst die volle Antwort (kein 'fields'-Filter), weil die
# verschachtelte Klammer-Syntax in der URL bei einigen Apps zu 403 fuehrt.
# Das macht die Antwort etwas groesser, aber zuverlaessiger.
function Get-PlaylistTracksUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PlaylistId,
        [Parameter(Mandatory)][string]$AccessToken
    )

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $tracks = New-Object System.Collections.Generic.List[object]
    $url = "https://api.spotify.com/v1/playlists/$PlaylistId/items?limit=100&additional_types=track"

    # Position = Index des Items in der Playlist (0-basiert).
    # Wichtig fuer Remove-DuplicateTracksFromPlaylist: Spotify will pro URI
    # eine Liste der Positionen, die geloescht werden sollen.
    $position = 0

    while ($url) {
        try {
            $page = Invoke-RestMethod -Method GET -Uri $url `
                -Headers @{ Authorization = "Bearer $AccessToken" }
        } catch {
            throw "Tracks konnten nicht geladen werden: $(Get-SpotifyErrorDetail $_.Exception)"
        }
        foreach ($item in $page.items) {
            $payload = ConvertTo-TrackPayload $item
            if ($null -ne $payload) {
                # Position als Property mit dranhaengen.
                $payload | Add-Member -NotePropertyName Position -NotePropertyValue $position -Force
                $tracks.Add($payload)
            }
            # IMMER hochzaehlen, auch fuer uebersprungene Items (lokale Dateien),
            # damit die Positionen mit den echten Spotify-Indizes uebereinstimmen.
            $position++
        }
        $url = $page.next
    }
    return @($tracks.ToArray())
}

# ---- Helfer: aus einem rohen Spotify-Item ein normalisiertes Song-Objekt bauen ----
# Versucht in dieser Reihenfolge: $item.track -> $item.episode -> $item direkt.
# Gibt $null zurueck, wenn nichts brauchbares gefunden wird.
function ConvertTo-TrackPayload {
    param($Item)
    if ($null -eq $Item) { return $null }

    # Welcher Wrapper enthaelt die Daten? Spotify hat die Struktur mehrfach
    # umgebaut - wir checken die Felder in dieser Reihenfolge:
    #   1. $Item.track    -> klassische /tracks-API (PSCustomObject mit name)
    #   2. $Item.item     -> neue /items-API: Track-Daten liegen unter 'item'
    #                        (im Inneren steht 'track: true' als reiner Flag)
    #   3. $Item.episode  -> Podcast-Episode (wir nehmen Show-Name als Artist)
    #   4. $Item direkt   -> ohne Wrapper
    $payload = $null
    if ($null -ne $Item.track -and ($Item.track -is [System.Management.Automation.PSCustomObject]) `
        -and -not [string]::IsNullOrEmpty($Item.track.name)) {
        $payload = $Item.track
    } elseif ($null -ne $Item.item -and ($Item.item -is [System.Management.Automation.PSCustomObject]) `
        -and -not [string]::IsNullOrEmpty($Item.item.name)) {
        $payload = $Item.item
    } elseif ($null -ne $Item.episode -and ($Item.episode -is [System.Management.Automation.PSCustomObject]) `
        -and -not [string]::IsNullOrEmpty($Item.episode.name)) {
        $payload = $Item.episode
    } elseif (-not [string]::IsNullOrEmpty($Item.name)) {
        $payload = $Item
    }
    if ($null -eq $payload -or [string]::IsNullOrEmpty($payload.name)) { return $null }

    # Artists (oder Show fuer Podcasts) zusammenbauen.
    $artistName = ''
    if ($payload.artists) {
        $artistName = ($payload.artists | ForEach-Object { $_.name }) -join ', '
    } elseif ($payload.show -and $payload.show.name) {
        $artistName = $payload.show.name
    }

    # Album-Name (Podcasts haben kein Album).
    $albumName = ''
    if ($payload.album -and $payload.album.name) {
        $albumName = $payload.album.name
    }

    return [pscustomobject]@{
        Title  = $payload.name
        Artist = $artistName
        Album  = $albumName
        Uri    = $payload.uri   # fuer das spaetere Loeschen via Spotify-API
    }
}

# Hinweis: Eine `Remove-DuplicateTracksFromPlaylist`-Funktion war hier
# vorgesehen, wurde aber entfernt. Spotify sperrt die Track-Modify-API in
# Development Mode mit HTTP 403, ohne den eigentlichen Grund preiszugeben.
# Das Tool zeigt Duplikate jetzt nur an; das Loeschen erfolgt manuell in
# der Spotify-App.
