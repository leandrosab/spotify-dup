<#
.SYNOPSIS
    Holt die Songs einer oeffentlichen Spotify-Playlist via Spotify Web API.

.DESCRIPTION
    Nutzt den "Client Credentials Flow" - das ist der einfachste Auth-Weg
    bei Spotify, weil KEIN User-Login noetig ist:
      1. Client ID + Secret aus config.json einlesen.
      2. Mit POST /api/token einen Access-Token holen (gueltig 1 Stunde).
      3. Mit GET /v1/playlists/{id}/tracks die Tracks abrufen.
         Die API liefert max. 100 pro Seite -> wir blaettern mit "next".
      4. Pro Track ein PowerShell-Objekt mit Title/Artist/Album bauen
         - exakt dieselbe Struktur wie aus Import-SongCsv. Dadurch
         koennen wir Find-Duplicates ohne Aenderung weiter benutzen.

    Voraussetzungen:
      - Spotify Developer App: https://developer.spotify.com/dashboard
      - config.json mit Client ID + Client Secret (siehe config.example.json)
      - Playlist muss oeffentlich sein.

.PARAMETER PlaylistUrlOrId
    Akzeptiert verschiedene Formate:
      - https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M
      - https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=abc
      - spotify:playlist:37i9dQZF1DXcBWIGoYBM5M
      - 37i9dQZF1DXcBWIGoYBM5M

.PARAMETER ConfigPath
    Pfad zur config.json mit Spotify-Credentials.

.EXAMPLE
    Get-SpotifyTracks -PlaylistUrlOrId "https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M" -ConfigPath ".\config.json"
#>
function Get-SpotifyTracks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PlaylistUrlOrId,

        [Parameter(Mandatory)]
        [string]$ConfigPath
    )

    # PowerShell 5.1 verwendet standardmaessig nicht TLS 1.2.
    # Spotify (und fast jede moderne API) braucht TLS 1.2 - hier erzwingen.
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # ---- 1. Config einlesen ----
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "Config-Datei nicht gefunden: $ConfigPath. Bitte config.example.json kopieren und Credentials einfuegen."
    }

    try {
        $config = Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Config-Datei konnte nicht gelesen werden (gueltiges JSON?). Details: $($_.Exception.Message)"
    }

    $clientId     = $config.Spotify.ClientId
    $clientSecret = $config.Spotify.ClientSecret

    if ([string]::IsNullOrWhiteSpace($clientId) -or [string]::IsNullOrWhiteSpace($clientSecret) `
        -or $clientId -like 'DEIN-*' -or $clientSecret -like 'DEIN-*') {
        throw "Spotify-Credentials fehlen oder sind Platzhalter. Bitte in $ConfigPath ClientId/ClientSecret eintragen."
    }

    # ---- 2. Playlist-ID extrahieren ----
    # Akzeptiert URL, Spotify-URI oder reine ID.
    $playlistId = $null
    if ($PlaylistUrlOrId -match 'playlist[/:]([a-zA-Z0-9]+)') {
        $playlistId = $matches[1]
    } else {
        $playlistId = $PlaylistUrlOrId.Trim()
    }

    if ($playlistId -notmatch '^[a-zA-Z0-9]{22}$') {
        throw "Ungueltige Playlist-ID: '$playlistId'. Format erwartet: 22 alphanumerische Zeichen."
    }

    # ---- 3. Access-Token holen (Client Credentials Flow) ----
    # Authorization-Header braucht Base64("clientid:clientsecret").
    $authPair  = "${clientId}:${clientSecret}"
    $authBytes = [System.Text.Encoding]::UTF8.GetBytes($authPair)
    $authBase64 = [Convert]::ToBase64String($authBytes)

    try {
        $tokenResponse = Invoke-RestMethod `
            -Method POST `
            -Uri 'https://accounts.spotify.com/api/token' `
            -Headers @{ Authorization = "Basic $authBase64" } `
            -Body 'grant_type=client_credentials' `
            -ContentType 'application/x-www-form-urlencoded'
    } catch {
        throw "Spotify-Authentifizierung fehlgeschlagen. Pruefe Client ID/Secret. Details: $($_.Exception.Message)"
    }

    $accessToken = $tokenResponse.access_token

    # ---- 4. Tracks abrufen (mit Pagination) ----
    # /items statt /tracks (neuer Endpunkt, /tracks ist deprecated).
    # additional_types=track macht klar, dass wir Songs wollen (nicht Podcasts).
    $tracks = New-Object System.Collections.Generic.List[object]
    $url = "https://api.spotify.com/v1/playlists/$playlistId/items?limit=100&additional_types=track"

    while ($url) {
        try {
            $page = Invoke-RestMethod -Method GET -Uri $url `
                -Headers @{ Authorization = "Bearer $accessToken" }
        } catch {
            throw "Spotify-Playlist konnte nicht geladen werden. Ist sie oeffentlich? Details: $($_.Exception.Message)"
        }

        foreach ($item in $page.items) {
            # Flexibles Parsen via Helfer aus Connect-Spotify.ps1
            # (deckt $item.track, $item.episode und $item direkt ab).
            $payload = ConvertTo-TrackPayload $item
            if ($null -eq $payload) { continue }
            $tracks.Add($payload)
        }

        # next ist null/leer, wenn es keine weitere Seite gibt.
        $url = $page.next
    }

    # @() garantiert: immer ein Array zurueck, auch wenn nur 1 Track drin ist.
    return @($tracks.ToArray())
}
