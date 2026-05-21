# Song-Duplikat-Checker (Modul 122)

PowerShell-Tool zur automatischen Erkennung doppelter Songs.
Datenquelle: **CSV-Datei** oder **Spotify-Playlist** (via Spotify Web API).
Optional mit einer einfachen Web-Oberfläche, die ebenfalls von PowerShell
bereitgestellt wird (kein Node.js, kein zusätzlicher Server nötig).

## Projektstruktur

```
M122-Projekt/
├── README.md                          Diese Datei
├── src/
│   ├── Start-DuplicateChecker.ps1     Interaktive Shell (Hauptprogramm)
│   ├── Find-DuplicateSongs.ps1        Parameter-Variante (für Skript-Aufruf)
│   ├── Start-WebServer.ps1            Optionaler Webserver für die UI
│   ├── config.example.json            Vorlage für Spotify-Credentials
│   ├── config.json                    (selbst anlegen, NICHT teilen)
│   ├── modules/
│   │   ├── Import-SongCsv.ps1         CSV einlesen + validieren
│   │   ├── Find-Duplicates.ps1        Duplikat-Logik (Kernfunktion)
│   │   ├── Export-Results.ps1         CSV-/JSON-Export der Resultate
│   │   ├── Get-SpotifyTracks.ps1      Spotify-API-Anbindung
│   │   └── Show-UI.ps1                Banner, Help, Prompts (Konsole)
│   └── web/
│       ├── index.html                 Web-Oberfläche im Terminal-Look
│       ├── style.css                  Styling
│       └── app.js                     Browser-Logik
└── data/
    ├── samples/                       Beispiel-CSVs zum Testen
    │   ├── songs-clean.csv
    │   ├── songs-with-duplicates.csv
    │   └── songs-broken.csv
    └── results/                       Hier landen exportierte Ergebnisse
```

## CSV-Format

| Spalte  | Pflicht | Beispiel                |
|---------|---------|-------------------------|
| Title   | ja      | Bohemian Rhapsody       |
| Artist  | ja      | Queen                   |
| Album   | nein    | A Night at the Opera    |

## Schnellstart

### 1. ExecutionPolicy für die aktuelle Sitzung erlauben

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
cd c:\School\M122\Projekt\src
```

### 2. Interaktive Shell (empfohlen)

```powershell
.\Start-DuplicateChecker.ps1
```

Du landest in einer Shell-artigen Oberfläche:

```
duplichecker$ help        # zeigt alle Befehle
duplichecker$ csv         # CSV-Modus starten
duplichecker$ spotify     # Spotify-Modus starten
duplichecker$ samples     # Beispiel-CSVs anzeigen
duplichecker$ clear       # Bildschirm leeren
duplichecker$ quit        # beenden
```

### 3. Parameter-Variante (für Demos / Automation)

```powershell
.\Find-DuplicateSongs.ps1 -Path ..\data\samples\songs-with-duplicates.csv
.\Find-DuplicateSongs.ps1 -Path ..\data\samples\songs-with-duplicates.csv -IncludeAlbum
```

### 4. Web-Oberfläche

```powershell
.\Start-WebServer.ps1
```

Browser: http://localhost:8080/ — Tab CSV oder Spotify wählen, Datei/URL eingeben, **run** klicken.
Server beenden: `Q` oder `Strg+C`.

## Spotify einrichten (einmalig, ca. 3 Minuten)

Damit der Spotify-Modus funktioniert, brauchst du einmalig kostenlose
Developer-Credentials. Schritte:

1. Öffne **https://developer.spotify.com/dashboard** und logge dich
   mit deinem normalen Spotify-Account ein (kostenlos reicht).
2. Klicke **"Create app"**.
   - App name: beliebig, z. B. *M122 Duplicate Checker*
   - App description: beliebig
   - Redirect URI: `http://localhost:8080` (Pflichtfeld, wird nicht genutzt)
   - APIs: **Web API** ankreuzen
3. In der App-Übersicht: **"Settings"** → **Client ID** und
   **Client Secret** kopieren.
   **Wichtig:** Bei **Redirect URIs** muss eingetragen sein:
   - `http://127.0.0.1:8888/callback` (für den Login der eigenen Playlists)

   > Spotify akzeptiert seit 2025 **kein `http://localhost...`** mehr —
   > nur HTTPS oder die Loopback-IP `http://127.0.0.1...`. Wenn du
   > `localhost` einträgst, kommt der rote Hinweis *„This redirect URI
   > is not secure"*.
4. Im Projekt: `config.example.json` zu `config.json` kopieren und
   die zwei Werte einsetzen:

```json
{
    "Spotify": {
        "ClientId": "abc123...",
        "ClientSecret": "xyz789..."
    }
}
```

5. Im Spotify-Modus eine **öffentliche** Playlist-URL angeben, z. B.
   `https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M`.

> **Wichtig:** `config.json` gehört nicht in eine öffentliche Veröffentlichung
> (GitHub o.ä.). Nur `config.example.json` weitergeben.

## Bekannte Einschränkung: automatisches Löschen via Spotify-API

Das Tool **erkennt** Duplikate in einer Spotify-Playlist zuverlässig. Es kann sie
auch automatisch entfernen — **wenn Spotify es erlaubt**.

Seit Ende 2024 hat Spotify für Apps im *Development Mode* (kostenlos, ohne
Spotify-Review) die folgenden API-Operationen weitgehend eingeschränkt:

- `POST /v1/users/{id}/playlists` — Neue Playlist erstellen
- `PUT /v1/playlists/{id}/tracks` — Tracks einer Playlist ersetzen
- `DELETE /v1/playlists/{id}/tracks` — Tracks einzeln löschen

Alle drei antworten mit `HTTP 403 Forbidden`, obwohl Scopes und Owner-ID stimmen.
**Lese-Operationen** und das **Ändern der Playlist-Metadaten** (Name, Beschreibung)
sind nicht betroffen.

Die Architektur des Tools ist **vollständig vorbereitet** — der OAuth-Flow,
die PUT-Logik und die Fehlerbehandlung sind alle implementiert. Sobald Spotify
einer App **Extended Quota Mode** gewährt (Antrag mit Review), funktioniert
die Lösch-Funktion sofort, ohne Code-Änderung.

**Workaround für Endnutzer:** Duplikate manuell in der Spotify-App entfernen
(Rechtsklick auf den Song → *„Aus Playlist entfernen"*). Das Tool zeigt einem
sauber, welche Songs es sind.

### Diagnose-Befehle

| Befehl im Tool | Was er macht |
|---|---|
| `diag` | Testet `/v1/me`, `/v1/me/playlists`, `/v1/playlists/{id}` und `/items` |
| `test-modify` | Versucht *eine* Playlist-Metadaten-Änderung (sollte klappen) |
| `test-tracks` | Versucht eine End-to-End-Track-Modifikation (zeigt die Sperre) |

## Fehlerbehandlung

Klare Fehlermeldungen, z. B.:
- `Datei nicht gefunden: ...`
- `Datei ist keine CSV-Datei (.csv erwartet): ...`
- `Fehlende Pflichtspalten: Artist. Vorhandene Spalten: Title, Album`
- `Spotify-Authentifizierung fehlgeschlagen. Pruefe Client ID/Secret.`
- `Ungueltige Playlist-ID: ... Format erwartet: 22 alphanumerische Zeichen.`

## Spätere Erweiterungen

- **Fuzzy-Matching:** Tippfehler erkennen (z. B. Levenshtein-Distanz).
- **Pester-Tests:** Unit-Tests für die Module unter `tests/`.
- **Verlauf:** JSON-Datei mit allen bisherigen Läufen.
- **Bash-Variante:** dasselbe Tool in Bash für Linux/macOS, als
  Vergleichsobjekt für die Modul-122-Präsentation.
- **Spotify – eigene private Playlists:** statt Client Credentials den
  Authorization Code Flow implementieren (komplexer, lokaler OAuth-Login nötig).
