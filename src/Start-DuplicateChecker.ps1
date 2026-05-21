<#
.SYNOPSIS
    Interaktive Shell-Oberflaeche fuer den Song-Duplikat-Checker.

.DESCRIPTION
    Das ist der "schoene" Einstiegspunkt fuer die Konsole.
    Statt Parameter zu setzen, tippt man Befehle wie in einer echten Shell:

      duplichecker$ csv
      duplichecker$ spotify
      duplichecker$ help
      duplichecker$ quit

    Wer es lieber per Parameter mag, nimmt weiterhin Find-DuplicateSongs.ps1.

.EXAMPLE
    .\Start-DuplicateChecker.ps1
#>

[CmdletBinding()]
param()

# Alle Module einbinden, die wir spaeter aufrufen koennen.
. (Join-Path $PSScriptRoot 'modules\Import-SongCsv.ps1')
. (Join-Path $PSScriptRoot 'modules\Find-Duplicates.ps1')
. (Join-Path $PSScriptRoot 'modules\Export-Results.ps1')
. (Join-Path $PSScriptRoot 'modules\Get-SpotifyTracks.ps1')
. (Join-Path $PSScriptRoot 'modules\Connect-Spotify.ps1')
. (Join-Path $PSScriptRoot 'modules\Show-UI.ps1')

# Wichtige Pfade einmalig festlegen.
$samplesDir = Join-Path $PSScriptRoot '..\data\samples'
$resultsDir = Join-Path $PSScriptRoot '..\data\results'
$configPath = Join-Path $PSScriptRoot 'config.json'

# Hilfsfunktion: nach dem Suchen anbieten, die Resultate zu exportieren.
# Nutzt Read-YesNo, damit Eingaben wie "v" oder Unsinn abgelehnt werden
# (statt stillschweigend als "ja" durchzugehen).
function Confirm-ExportResults {
    param([psobject[]]$Duplicates)
    if (-not $Duplicates -or $Duplicates.Count -eq 0) { return }
    if (-not (Read-YesNo -Question "Resultate als CSV/JSON exportieren?" -DefaultYes $true)) {
        return
    }
    $files = Export-Results -Duplicates $Duplicates -OutputDir $resultsDir
    Write-Success "CSV  -> $($files.CsvPath)"
    Write-Success "JSON -> $($files.JsonPath)"
}

# Hilfsfunktion: ja/nein-Antwort vereinfachen.
function Read-YesNo {
    param([string]$Question, [bool]$DefaultYes = $false)
    $hint = if ($DefaultYes) { '(J/n)' } else { '(j/N)' }
    $yes  = @('j','y','ja','yes','1','true')
    $no   = @('n','nein','no','0','false')
    # Solange fragen, bis ein gueltiger Wert kommt (oder Enter = Default).
    while ($true) {
        $ans = (Read-Input -Question "$Question $hint").ToLower()
        if ([string]::IsNullOrWhiteSpace($ans)) { return $DefaultYes }
        if ($yes -contains $ans) { return $true }
        if ($no  -contains $ans) { return $false }
        Write-ErrorMsg "Ungueltige Eingabe: '$ans' - bitte 'j' oder 'n' (oder Enter fuer Default)."
    }
}

# ---- CSV-Befehl ----
function Invoke-CsvMode {
    Write-Section "CSV-Modus"

    $path = Read-Input -Question "Pfad zur CSV-Datei (Enter = Beispiel mit Duplikaten):"
    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = Join-Path $samplesDir 'songs-with-duplicates.csv'
        Write-Info "Verwende Beispiel: $path"
    }

    $useAlbum = Read-YesNo -Question "Album mitvergleichen?"

    try {
        $songs = Import-SongCsv -Path $path
        Write-Success "$($songs.Count) Songs eingelesen."

        $duplicates = Find-Duplicates -Songs $songs -IncludeAlbum:$useAlbum
        Show-DuplicateResults -Duplicates $duplicates -TotalSongs $songs.Count
        Confirm-ExportResults -Duplicates $duplicates
    } catch {
        Write-ErrorMsg $_.Exception.Message
    }
}

# ---- Config-Befehl ----
# Fragt interaktiv nach Client ID + Secret und schreibt sie nach config.json.
function Invoke-ConfigMode {
    [void](Save-SpotifyConfig -ConfigPath $configPath)
}

# ---- Spotify-Befehl: Untermenue (eigene Playlists vs. URL) ----
function Invoke-SpotifyMode {
    Write-Section "Spotify-Modus"

    # Wenn config.json fehlt: direkt Setup anbieten.
    if (-not (Test-Path -LiteralPath $configPath)) {
        Write-Warn "config.json fehlt - lass uns die Credentials jetzt einrichten."
        if (-not (Save-SpotifyConfig -ConfigPath $configPath)) {
            return
        }
    }

    Write-Host ""
    Write-Host "  Quelle waehlen:" -ForegroundColor Yellow
    Write-Host "    [1] " -ForegroundColor Cyan -NoNewline
    Write-Host "Eine meiner eigenen Playlists  " -NoNewline
    Write-Host "(Login mit Spotify-Account)" -ForegroundColor DarkGray
    Write-Host "    [2] " -ForegroundColor Cyan -NoNewline
    Write-Host "Eine oeffentliche Playlist per URL/ID"
    Write-Host ""
    Write-Host "  > " -ForegroundColor Magenta -NoNewline
    $choice = (Read-Host).Trim()

    switch ($choice) {
        '1' { Invoke-SpotifyMyPlaylists }
        '2' { Invoke-SpotifyByUrl }
        ''  { Write-Info "Abgebrochen." }
        default { Write-ErrorMsg "Ungueltige Auswahl: '$choice' (erwartet: 1 oder 2)" }
    }
}

# ---- Eigene Playlists ----
function Invoke-SpotifyMyPlaylists {
    # Token holen, falls noch nicht eingeloggt: Login anbieten.
    $token = $null
    try {
        $token = Get-SpotifyAccessToken -ConfigPath $configPath
    } catch {
        Write-Warn "Du bist noch nicht mit Spotify verbunden."
        $ans = Read-YesNo -Question "Jetzt einloggen? (Browser oeffnet sich)" -DefaultYes $true
        if (-not $ans) { return }
        try {
            Write-Info "Oeffne Browser fuer Login..."
            [void](Connect-Spotify -ConfigPath $configPath)
            Write-Success "Login erfolgreich."
            $token = Get-SpotifyAccessToken -ConfigPath $configPath
        } catch {
            Write-ErrorMsg $_.Exception.Message
            return
        }
    }

    # Playlists des Users abrufen.
    Write-Info "Hole deine Playlists..."
    try {
        $playlists = Get-MyPlaylists -AccessToken $token
    } catch {
        Write-ErrorMsg $_.Exception.Message
        return
    }
    if ($playlists.Count -eq 0) {
        Write-Warn "Keine Playlists gefunden."
        return
    }

    # User-ID einmalig holen, um zu markieren, was wirklich "deins" ist
    # (kann ich modifizieren) vs. "nur gefolgt" (kann ich nur lesen).
    $myId = $null
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $me = Invoke-RestMethod -Method GET -Uri 'https://api.spotify.com/v1/me' `
            -Headers @{ Authorization = "Bearer $token" }
        $myId = $me.id
    } catch { }

    Write-Host ""
    Write-Host "  Deine Playlists ($($playlists.Count)):" -ForegroundColor Yellow
    Write-Host "    (Symbol: " -ForegroundColor DarkGray -NoNewline
    Write-Host "* " -ForegroundColor Green -NoNewline
    Write-Host "= eigene Playlist (modifizierbar), " -ForegroundColor DarkGray -NoNewline
    Write-Host "  " -NoNewline
    Write-Host "= gefolgte Playlist (read-only))" -ForegroundColor DarkGray
    Write-Host ""
    for ($i = 0; $i -lt $playlists.Count; $i++) {
        $p     = $playlists[$i]
        $idx   = $i + 1
        $owned = ($null -ne $myId -and $p.OwnerId -eq $myId)
        $mark  = if ($owned) { '*' } else { ' ' }
        $markColor = if ($owned) { 'Green' } else { 'DarkGray' }

        Write-Host "  $mark " -ForegroundColor $markColor -NoNewline
        Write-Host ("[{0,2}] " -f $idx) -ForegroundColor Cyan -NoNewline
        Write-Host ("{0,-45}" -f $p.Name) -ForegroundColor White -NoNewline
        Write-Host ("  {0} Tracks" -f $p.TrackCount) -ForegroundColor DarkGray -NoNewline
        Write-Host ("  - {0}" -f $p.Owner) -ForegroundColor DarkGray
    }

    # Auswahl
    $sel = Read-Input -Question "Welche Playlist? (Nummer, Enter zum Abbrechen)"
    if ([string]::IsNullOrWhiteSpace($sel)) { Write-Info "Abgebrochen."; return }
    if ($sel -notmatch '^\d+$') { Write-ErrorMsg "Bitte eine Zahl eingeben."; return }
    $idx = [int]$sel - 1
    if ($idx -lt 0 -or $idx -ge $playlists.Count) {
        Write-ErrorMsg "Nummer ausserhalb des Bereichs (1-$($playlists.Count))."
        return
    }
    $chosen = $playlists[$idx]
    Write-Info "Gewaehlt: $($chosen.Name)"

    $useAlbum = Read-YesNo -Question "Album mitvergleichen?"

    # Tracks laden + Duplikate suchen.
    try {
        Write-Info "Lade Tracks der Playlist..."
        $songs = Get-PlaylistTracksUser -PlaylistId $chosen.Id -AccessToken $token
        Write-Success "$($songs.Count) Tracks geladen."

        $duplicates = Find-Duplicates -Songs $songs -IncludeAlbum:$useAlbum
        Show-DuplicateResults -Duplicates $duplicates -TotalSongs $songs.Count
        Confirm-ExportResults -Duplicates $duplicates

        # Hinweis: Spotify blockt die Track-Modify-API in Development Mode
        # mit HTTP 403, daher keine automatische Loeschung mehr im Tool.
        # Manueller Workaround: in Spotify-App Rechtsklick -> "Aus Playlist entfernen".
        if ($duplicates -and $duplicates.Count -gt 0) {
            Write-Host ""
            Write-Info "Hinweis: Duplikate manuell in der Spotify-App entfernen"
            Write-Info "         (Rechtsklick auf Song -> 'Aus Playlist entfernen')."
        }
    } catch {
        Write-ErrorMsg $_.Exception.Message
    }
}

# ---- Per URL (oeffentliche Playlist via Client Credentials) ----
function Invoke-SpotifyByUrl {
    $url = Read-Input -Question "Spotify-Playlist URL oder ID:"
    if ([string]::IsNullOrWhiteSpace($url)) {
        Write-ErrorMsg "Keine URL angegeben."
        return
    }

    $useAlbum = Read-YesNo -Question "Album mitvergleichen?"

    try {
        Write-Info "Hole Tracks von Spotify..."
        $songs = Get-SpotifyTracks -PlaylistUrlOrId $url -ConfigPath $configPath
        Write-Success "$($songs.Count) Tracks geladen."

        $duplicates = Find-Duplicates -Songs $songs -IncludeAlbum:$useAlbum
        Show-DuplicateResults -Duplicates $duplicates -TotalSongs $songs.Count
        Confirm-ExportResults -Duplicates $duplicates
    } catch {
        Write-ErrorMsg $_.Exception.Message
    }
}

# ---- Diagnose-Befehl: Spotify-API Schritt fuer Schritt durchtesten ----
# Zeigt rohe Antworten + Fehlermeldungen, damit wir sehen, welcher Endpoint
# blockiert wird. Sehr hilfreich, wenn 403er kommen ohne Klartext-Grund.
function Invoke-DiagMode {
    Write-Section "Spotify-Diagnose"

    if (-not (Test-Path -LiteralPath $configPath)) {
        Write-ErrorMsg "config.json fehlt. Erst 'config' und 'spotify' (Login) ausfuehren."
        return
    }

    try {
        $token = Get-SpotifyAccessToken -ConfigPath $configPath
        Write-Success "Access-Token vorhanden."
        # Aktuell gespeicherten Scope anzeigen - praktisch zum Debuggen.
        try {
            $cfg = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
            $sc = $cfg.Spotify.Scope
            if ([string]::IsNullOrEmpty($sc)) { $sc = '(nicht gespeichert)' }
            Write-Host "  Scopes: $sc" -ForegroundColor DarkGray
            if ($sc -notmatch 'playlist-modify') {
                Write-Warn "  -> Loeschen wird NICHT funktionieren (kein 'playlist-modify-*' Scope)."
            }
        } catch { }
    } catch {
        Write-ErrorMsg "Kein gueltiger Token: $($_.Exception.Message)"
        return
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $headers = @{ Authorization = "Bearer $token" }

    # --- Test 1: User-Profil ---
    Write-Host ""
    Write-Host "  === Test 1: GET /v1/me  (User-Profil) ===" -ForegroundColor Yellow
    $test1ok = $false
    try {
        $me = Invoke-RestMethod -Method GET -Uri 'https://api.spotify.com/v1/me' -Headers $headers
        Write-Host "    display_name : $($me.display_name)"
        Write-Host "    id           : $($me.id)"
        Write-Host "    country      : $($me.country)"
        Write-Host "    product      : $($me.product)"
        $test1ok = $true
    } catch {
        Write-ErrorMsg "Fehler: $(Get-SpotifyErrorDetail $_.Exception)"
    }

    # --- Test 2: erste 2 Playlists ROH ---
    Write-Host ""
    Write-Host "  === Test 2: GET /v1/me/playlists?limit=2  (rohe JSON) ===" -ForegroundColor Yellow
    $firstPid = $null
    $test2ok = $false
    try {
        $pls = Invoke-RestMethod -Method GET -Uri 'https://api.spotify.com/v1/me/playlists?limit=2' -Headers $headers
        Write-Host "    total: $($pls.total)"
        if ($pls.items -and $pls.items.Count -gt 0) {
            $firstPid = $pls.items[0].id
            Write-Host "    --- erste Playlist (raw) ---" -ForegroundColor DarkGray
            Write-Host ($pls.items[0] | ConvertTo-Json -Depth 5)
        }
        $test2ok = $true
    } catch {
        Write-ErrorMsg "Fehler: $(Get-SpotifyErrorDetail $_.Exception)"
    }

    if (-not $firstPid) {
        Write-Warn "Keine Playlist-ID - Test 3+4 uebersprungen."
        return
    }

    # --- Test 3: Playlist-Metadaten ---
    Write-Host ""
    Write-Host "  === Test 3: GET /v1/playlists/$firstPid  (Metadaten) ===" -ForegroundColor Yellow
    $test3ok = $false
    try {
        $meta = Invoke-RestMethod -Method GET -Uri "https://api.spotify.com/v1/playlists/$firstPid" -Headers $headers
        Write-Host "    name        : $($meta.name)"
        Write-Host "    owner.id    : $($meta.owner.id)"
        Write-Host "    tracks.total: $($meta.tracks.total)"
        $test3ok = $true
    } catch {
        Write-ErrorMsg "Fehler: $(Get-SpotifyErrorDetail $_.Exception)"
    }

    # --- Test 4: Playlist-Items (NEU: /items statt /tracks) ---
    Write-Host ""
    Write-Host "  === Test 4: GET /v1/playlists/$firstPid/items?limit=1&additional_types=track ===" -ForegroundColor Yellow
    $test4ok = $false
    try {
        $tr = Invoke-RestMethod -Method GET -Uri "https://api.spotify.com/v1/playlists/$firstPid/items?limit=1&additional_types=track" -Headers $headers
        Write-Host "    items count: $($tr.items.Count)"
        if ($tr.items.Count -gt 0) {
            Write-Host "    --- items[0] (raw JSON) ---" -ForegroundColor DarkGray
            Write-Host ($tr.items[0] | ConvertTo-Json -Depth 6)
            Write-Host ""
            $payload = ConvertTo-TrackPayload $tr.items[0]
            if ($payload) {
                Write-Host "    Parser-Resultat:" -ForegroundColor Green
                Write-Host "      Title : $($payload.Title)"
                Write-Host "      Artist: $($payload.Artist)"
                Write-Host "      Album : $($payload.Album)"
            } else {
                Write-Warn "  Parser konnte aus dem Item KEIN Track-Objekt bauen."
            }
        }
        $test4ok = $true
    } catch {
        Write-ErrorMsg "Fehler: $(Get-SpotifyErrorDetail $_.Exception)"
    }

    # --- Auswertung ---
    Write-Host ""
    Write-Section "Auswertung"
    Write-Host "    Test 1 (Profil)             : " -NoNewline; if ($test1ok) { Write-Host "OK" -ForegroundColor Green } else { Write-Host "FAIL" -ForegroundColor Red }
    Write-Host "    Test 2 (Playlists-Liste)    : " -NoNewline; if ($test2ok) { Write-Host "OK" -ForegroundColor Green } else { Write-Host "FAIL" -ForegroundColor Red }
    Write-Host "    Test 3 (Playlist-Metadaten) : " -NoNewline; if ($test3ok) { Write-Host "OK" -ForegroundColor Green } else { Write-Host "FAIL" -ForegroundColor Red }
    Write-Host "    Test 4 (Playlist-Tracks)    : " -NoNewline; if ($test4ok) { Write-Host "OK" -ForegroundColor Green } else { Write-Host "FAIL" -ForegroundColor Red }

    Write-Host ""
    if ($test1ok -and $test2ok -and -not $test4ok) {
        Write-Warn "Profil + Playlist-Liste OK, aber Tracks blockiert."
        Write-Info "Sehr wahrscheinlich App-Konfiguration:"
        Write-Info "  1. Spotify Dashboard -> deine App -> Edit"
        Write-Info "  2. 'Which API/SDKs are you planning to use?' -> Web API ankreuzen"
        Write-Info "  3. 'User Management' -> deine Spotify-Email als User eintragen"
        Write-Info "  4. config.json loeschen, 'spotify' neu starten"
    } elseif (-not $test1ok) {
        Write-Warn "Schon /v1/me schlaegt fehl - der Token ist vermutlich kaputt."
        Write-Info "  -> config.json loeschen und neu einloggen."
    }
}

# ---- Test-Modify: prueft, ob ueberhaupt eine Schreib-Op moeglich ist ----
# Aendert kurz die Description einer eigenen Playlist und setzt sie zurueck.
# Gibt eine klare Ja/Nein-Antwort, ob deine Spotify-App Modify-Ops darf.
function Invoke-TestModifyMode {
    Write-Section "Test: Modify-Operation"
    Write-Info "Versucht Description einer eigenen Playlist zu setzen (+ revert)."

    if (-not (Test-Path -LiteralPath $configPath)) {
        Write-ErrorMsg "config.json fehlt."
        return
    }
    try {
        $token = Get-SpotifyAccessToken -ConfigPath $configPath
    } catch {
        Write-ErrorMsg "Kein Token: $($_.Exception.Message)"
        return
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $headers = @{ Authorization = "Bearer $token" }

    try {
        $me = Invoke-RestMethod -Method GET -Uri 'https://api.spotify.com/v1/me' -Headers $headers
    } catch {
        Write-ErrorMsg "/v1/me fehlgeschlagen: $(Get-SpotifyErrorDetail $_.Exception)"
        return
    }

    # Erste eigene Playlist suchen (OwnerId == me.id).
    $pls = Get-MyPlaylists -AccessToken $token
    $ownedPl = $pls | Where-Object { $_.OwnerId -eq $me.id } | Select-Object -First 1
    if (-not $ownedPl) {
        Write-ErrorMsg "Keine eigene Playlist gefunden."
        return
    }
    try {
        $meta = Invoke-RestMethod -Method GET `
            -Uri "https://api.spotify.com/v1/playlists/$($ownedPl.Id)" -Headers $headers
    } catch {
        Write-ErrorMsg "Playlist-Metadaten: $(Get-SpotifyErrorDetail $_.Exception)"
        return
    }

    $orig = $meta.description
    $test = "duplichecker-test-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
    Write-Info "Test-Playlist: '$($ownedPl.Name)' (id: $($ownedPl.Id))"
    Write-Info "Original-Description: '$orig'"
    Write-Host ""

    $modifyWorks = $false
    try {
        $body = @{ description = $test } | ConvertTo-Json -Compress
        $null = Invoke-RestMethod -Method PUT `
            -Uri "https://api.spotify.com/v1/playlists/$($ownedPl.Id)" `
            -Headers $headers -ContentType 'application/json' -Body $body
        Write-Success "PUT /v1/playlists/{id} (Description-Update) erfolgreich!"
        $modifyWorks = $true
    } catch {
        Write-ErrorMsg "PUT (Description) fehlgeschlagen: $(Get-SpotifyErrorDetail $_.Exception)"
    }

    # Revert
    if ($modifyWorks) {
        try {
            $revertBody = @{ description = "$orig" } | ConvertTo-Json -Compress
            $null = Invoke-RestMethod -Method PUT `
                -Uri "https://api.spotify.com/v1/playlists/$($ownedPl.Id)" `
                -Headers $headers -ContentType 'application/json' -Body $revertBody
        } catch {
            Write-Warn "Revert fehlgeschlagen, Description ist: '$test'"
        }
    }

    Write-Host ""
    if ($modifyWorks) {
        Write-Success "Diagnose: deine App KANN Modify-Operationen ausfuehren."
        Write-Info "Wenn /tracks trotzdem 403 gibt -> dieser spezifische Endpoint ist gesperrt."
        Write-Info "Workaround: leg in Spotify eine NEUE Playlist an, kopiere Songs rein und"
        Write-Info "teste die Loeschung dort - manchmal sind nur einzelne Playlists betroffen."
    } else {
        Write-Warn "Diagnose: deine App kann GAR keine Modify-Operationen ausfuehren."
        Write-Info "Das ist eine Spotify-Restriktion, die nicht im Code zu beheben ist."
        Write-Info "Optionen:"
        Write-Info "  1. App im Spotify Dashboard loeschen + neu erstellen (frischer Status)"
        Write-Info "  2. Funktionalitaet auf 'Anzeigen-only' beschraenken (Loeschen manuell"
        Write-Info "     in der Spotify-App vornehmen)."
    }
}

# ---- End-to-End-Test fuer den /tracks-Endpoint ----
# Erstellt eine private Test-Playlist, fuegt 2x denselben Song hinzu,
# versucht den dedupliziert zu setzen, und loescht die Playlist wieder.
# Klares Ergebnis: funktioniert /tracks auf einer frischen Playlist?
function Invoke-TestTracksMode {
    Write-Section "Test: PUT /tracks Endpoint (End-to-End)"
    Write-Info "Erstellt kurzlebige Test-Playlist, prueft Dedup, raeumt selbst auf."

    if (-not (Test-Path -LiteralPath $configPath)) {
        Write-ErrorMsg "config.json fehlt."
        return
    }
    try {
        $token = Get-SpotifyAccessToken -ConfigPath $configPath
    } catch {
        Write-ErrorMsg "Kein Token: $($_.Exception.Message)"
        return
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $headers = @{ Authorization = "Bearer $token" }

    # User-ID holen.
    try {
        $me = Invoke-RestMethod -Method GET -Uri 'https://api.spotify.com/v1/me' -Headers $headers
    } catch {
        Write-ErrorMsg "/v1/me fehlgeschlagen: $(Get-SpotifyErrorDetail $_.Exception)"
        return
    }

    # ---- 1. Test-Playlist erstellen ----
    Write-Info "1. Erstelle private Test-Playlist..."
    $createBody = @{
        name        = "duplichecker-tracks-test"
        public      = $false
        description = "wird vom duplichecker gleich wieder geloescht"
    } | ConvertTo-Json
    try {
        $newPl = Invoke-RestMethod -Method POST `
            -Uri "https://api.spotify.com/v1/users/$($me.id)/playlists" `
            -Headers $headers -ContentType 'application/json' -Body $createBody
        Write-Success "Playlist erstellt: $($newPl.id)"
    } catch {
        Write-ErrorMsg "Erstellen fehlgeschlagen: $(Get-SpotifyErrorDetail $_.Exception)"
        return
    }
    $testPlId = $newPl.id

    $tracksWork = $false
    try {
        # ---- 2. 2x Billie Jean hinzufuegen (Track aus MJ-Playlist, kennen wir) ----
        Write-Info "2. Fuege 2x denselben Track hinzu..."
        $testUri = 'spotify:track:0Pta7osIb37yGqah9k3zOp'   # Billie Jean
        $addBody = @{ uris = @($testUri, $testUri) } | ConvertTo-Json -Compress
        $null = Invoke-RestMethod -Method POST `
            -Uri "https://api.spotify.com/v1/playlists/$testPlId/tracks" `
            -Headers $headers -ContentType 'application/json' -Body $addBody
        Write-Success "2 Tracks hinzugefuegt."

        # ---- 3. PUT /tracks mit dedup'ter Liste ----
        Write-Info "3. PUT /tracks mit dedup'ter Liste..."
        $dedupBody = @{ uris = @($testUri) } | ConvertTo-Json -Compress
        $null = Invoke-RestMethod -Method PUT `
            -Uri "https://api.spotify.com/v1/playlists/$testPlId/tracks" `
            -Headers $headers -ContentType 'application/json' -Body $dedupBody
        Write-Success "PUT /tracks (Dedup) hat geklappt!"

        # ---- 4. Verifikation: nur noch 1 Track? ----
        $verify = Invoke-RestMethod -Method GET `
            -Uri "https://api.spotify.com/v1/playlists/$testPlId/items?limit=10" `
            -Headers $headers
        if ($verify.items.Count -eq 1) {
            Write-Success "Verifikation: 1 Track in der Playlist (statt 2). Dedup hat funktioniert."
            $tracksWork = $true
        } else {
            Write-Warn "Verifikation unklar: $($verify.items.Count) Tracks (erwartet: 1)."
        }
    }
    catch {
        Write-ErrorMsg "Test fehlgeschlagen: $(Get-SpotifyErrorDetail $_.Exception)"
    }
    finally {
        # ---- 5. Aufraeumen ----
        Write-Info "5. Cleanup: Test-Playlist loeschen..."
        try {
            $null = Invoke-RestMethod -Method DELETE `
                -Uri "https://api.spotify.com/v1/playlists/$testPlId/followers" `
                -Headers $headers
            Write-Success "Test-Playlist entfernt."
        } catch {
            Write-Warn "Auto-Cleanup fehlgeschlagen - bitte 'duplichecker-tracks-test' manuell loeschen."
        }
    }

    Write-Host ""
    if ($tracksWork) {
        Write-Success "===> /tracks-Endpoint funktioniert auf frischen Playlists."
        Write-Info "Die 403 bei 'Dont think, do it' liegt also an der Playlist selbst."
        Write-Info "Workaround: in Spotify eine NEUE Playlist erstellen, Songs reinkopieren,"
        Write-Info "und auf der neuen Playlist im Tool 'play <nr>' + Loeschen ausfuehren."
    } else {
        Write-Warn "===> /tracks-Endpoint ist generell gesperrt fuer deine App."
        Write-Info "Loesung: App im Spotify Dashboard loeschen + neu erstellen."
        Write-Info "  (Settings -> ganz unten 'Delete app'. Dann neu erstellen mit Web API, User Management, Redirect URI.)"
    }
}

# ---- Web-Hinweis ----
function Invoke-WebMode {
    Write-Section "Web-Modus"
    Write-Info "Der Webserver laeuft als eigenes Skript:"
    Write-Host "    .\Start-WebServer.ps1" -ForegroundColor Cyan
    Write-Info "Danach im Browser oeffnen: http://localhost:8080/"
}

# ---- Hauptschleife ----
Show-Banner

$running = $true
while ($running) {
    $cmd = Read-Command -Prompt "duplichecker"

    switch ($cmd) {
        'csv'     { Invoke-CsvMode }
        'spotify' { Invoke-SpotifyMode }
        'config'  { Invoke-ConfigMode }
        'setup'   { Invoke-ConfigMode }
        'diag'    { Invoke-DiagMode }
        'test-modify' { Invoke-TestModifyMode }
        'tw'      { Invoke-TestModifyMode }
        'test-tracks' { Invoke-TestTracksMode }
        'tt'      { Invoke-TestTracksMode }
        'web'     { Invoke-WebMode }
        'samples' { Show-Samples -SamplesDir $samplesDir }
        'help'    { Show-Help }
        '?'       { Show-Help }
        'clear'   { Clear-Host; Show-Banner }
        'cls'     { Clear-Host; Show-Banner }
        'quit'    { $running = $false }
        'exit'    { $running = $false }
        'q'       { $running = $false }
        ''        { }   # leere Eingabe ignorieren (Enter ohne Befehl)
        default {
            Write-Host ""
            Write-Host "  unbekannter Befehl: '$cmd'" -ForegroundColor Red
            Write-Host "  tippe 'help' fuer eine Liste aller Befehle." -ForegroundColor Gray
        }
    }
}

Write-Host ""
Write-Host "  Tschuess!" -ForegroundColor Cyan
Write-Host ""
