# Flowcharts
## Song-Duplikat-Checker — Modul 122

> Diagramme im **Mermaid**-Format. GitHub, GitLab und VS Code (Extension *„Markdown Preview Mermaid Support"*) rendern sie automatisch. Zum Export als PNG/SVG/PDF: Code-Block auf [mermaid.live](https://mermaid.live) einfügen → Actions → Download.

---

## 1. System-Architektur (Komponenten-Übersicht)

Die wichtigsten Bausteine und wie sie miteinander reden. Bewusst minimal gehalten — jede Box ist eine echte Datei oder ein klarer Verantwortungsbereich.

```mermaid
flowchart TD
    User([Anwender])

    User -->|tippt Befehle| CLI[PowerShell-Shell]
    User -->|Browser| Web[Web-Oberflaeche]

    Web <-->|HTTP / JSON| Server[PowerShell Webserver]

    CLI --> Modules[Logik-Module]
    Server --> Modules

    Modules --> CSV[(CSV-Dateien)]
    Modules -->|OAuth + REST| Spotify[Spotify Web API]
```

**Vier saubere Ebenen:** Anwender → Präsentation (CLI **oder** Web) → Logik-Module → externe Datenquellen.

---

## 2. CSV-Modus — Datenfluss

Der einfachste Pfad: Datei einlesen, prüfen, gruppieren, anzeigen.

```mermaid
flowchart TD
    Start([User tippt 'csv']) --> Path[Pfad eingeben]
    Path --> Check{Datei + Spalten OK?}
    Check -->|nein| Err[Fehlermeldung]
    Check -->|ja| Import[Import-SongCsv]
    Import --> Album{Album mitvergleichen?}
    Album --> Find[Find-Duplicates]
    Find --> Show[Tabelle anzeigen]
    Show --> Export{Export?}
    Export -->|ja| Save[CSV + JSON speichern]
    Export -->|nein| End([Ende])
    Save --> End
    Err --> End
```

---

## 3. Spotify-Modus — Datenfluss

Inklusive OAuth-Login und Auswahl-Menü (1 = eigene Playlist, 2 = öffentliche URL).

```mermaid
flowchart TD
    Start([User tippt 'spotify']) --> Cfg{config.json da?}
    Cfg -->|nein| Setup[Client ID + Secret eingeben]
    Cfg -->|ja| Choice[Quelle waehlen]
    Setup --> Choice

    Choice --> Q{1 oder 2?}
    Q -->|1: eigene| Token{gueltiger Token?}
    Q -->|2: URL| Url[URL eingeben]

    Token -->|nein| Login[OAuth Browser-Login]
    Login --> Mine
    Token -->|ja| Mine[Get-MyPlaylists]

    Mine --> Pick[Playlist-Nummer waehlen]
    Pick --> Fetch[Tracks der Playlist holen]
    Url --> FetchPublic[oeffentliche Tracks holen]

    Fetch --> Find[Find-Duplicates]
    FetchPublic --> Find
    Find --> Show[Tabelle + Hinweis<br>manuell loeschen]
    Show --> End([Ende])
```

---

## 4. OAuth-2.0-Login (Sequenz)

Der genaue Ablauf zwischen vier Akteuren: User, PowerShell-Skript, lokaler `TcpListener` (für den Callback) und Spotify.

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant CLI as duplichecker
    participant Listener as TcpListener<br>127.0.0.1:8888
    participant Browser
    participant Spotify

    User->>CLI: spotify -> 1
    CLI->>CLI: Random State generieren
    CLI->>Listener: starten
    CLI->>Browser: spotify.com/authorize<br>(client_id, scope, state)
    User->>Browser: einloggen + zustimmen
    Browser->>Spotify: Login
    Spotify->>Browser: Redirect zu 127.0.0.1:8888/callback
    Browser->>Listener: GET /callback?code=...&state=...
    Listener->>Listener: State pruefen (CSRF)
    Listener->>Browser: HTML "Login erfolgreich"
    Listener->>CLI: Authorization Code
    CLI->>Spotify: POST /api/token (Code + Basic Auth)
    Spotify->>CLI: access_token + refresh_token
    CLI->>CLI: Tokens speichern
    CLI->>User: "Login erfolgreich"
```

---

## 5. Duplikat-Erkennung — Kernalgorithmus

Das Herz des Tools: aus einer rohen Songliste werden gruppierte Duplikate.

```mermaid
flowchart LR
    A[Liste von Songs] --> B[fuer jeden Song:<br>Title + Artist normalisieren]
    B --> C[Schluessel bilden]
    C --> D[Group-Object nach Key]
    D --> E{Count > 1?}
    E -->|nein| F[verwerfen]
    E -->|ja| G[als Duplikat-Gruppe<br>aufnehmen]
    G --> H[nach Count absteigend<br>sortieren]
    H --> I[Duplikat-Gruppen]
```

**Beispiel-Durchlauf** (ohne Album-Vergleich):

| Roh-Eingabe | Normalisierter Schlüssel |
|---|---|
| `"Imagine"` — `"John Lennon"` | `imagine\|john lennon` |
| `"  IMAGINE "` — `"John Lennon"` | `imagine\|john lennon` ← **gleich!** |
| `"Imagine - Remastered"` — `"John Lennon"` | `imagine - remastered\|john lennon` |
| `"Hey Jude"` — `"The Beatles"` | `hey jude\|the beatles` |

→ `Group-Object` findet 2 Treffer für `imagine|john lennon` → eine Duplikat-Gruppe (Count = 2). Die Remastered-Variante zählt nicht dazu, weil der Titel anders ist.

---

## 6. Web-Anfrage (Sequenz)

Wie eine Aktion im Browser (z. B. „CSV hochladen") als HTTP-Request beim PowerShell-Server landet und zurückkommt.

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant Browser
    participant Server as PowerShell Server
    participant Mod as Module

    User->>Browser: oeffnet localhost:8080
    Browser->>Server: GET / (index.html)
    Server->>Browser: HTML + CSS + JS
    User->>Browser: waehlt CSV, klickt 'run'
    Browser->>Server: POST /api/check (CSV-Body)
    Server->>Mod: Import-SongCsv + Find-Duplicates
    Mod->>Server: Duplikat-Liste
    Server->>Browser: JSON Response
    Browser->>User: Tabelle anzeigen
```

---

## Export-Hinweis

So bekommst du die Diagramme als Bild/PDF in deine Schulpräsentation:

| Methode | Vorgehen |
|---|---|
| **mermaid.live** (am schnellsten) | Code-Block kopieren → [mermaid.live](https://mermaid.live) → Actions → PNG/SVG |
| **VS Code** | Extension *„Markdown Preview Mermaid Support"* → Preview öffnen → über Markdown-PDF-Extension exportieren |
| **GitHub** | rendert direkt beim Hochladen — Screenshots vom Browser nehmen |
