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
    a([User tippt csv]) --> b[Pfad eingeben]
    b --> c{Datei OK}
    c -->|nein| d[Fehlermeldung]
    c -->|ja| e[Datei einlesen]
    e --> f{Album mitvergleichen}
    f --> g[Duplikate finden]
    g --> h[Tabelle anzeigen]
    h --> i{Exportieren}
    i -->|ja| j[CSV und JSON speichern]
    i -->|nein| k([Ende])
    j --> k
    d --> k
```

---

## 3. Spotify-Modus — Datenfluss

Inklusive OAuth-Login und Auswahl-Menü (1 = eigene Playlist, 2 = öffentliche URL).

```mermaid
flowchart TD
    Begin([User tippt spotify]) --> Cfg{config.json vorhanden}
    Cfg -->|nein| Setup[Client ID und Secret eingeben]
    Cfg -->|ja| Choice[Quelle waehlen]
    Setup --> Choice

    Choice --> Q{Option 1 oder 2}
    Q -->|1 eigene| Token{Token gueltig}
    Q -->|2 URL| Url[URL eingeben]

    Token -->|nein| Login[OAuth Browser-Login]
    Login --> Mine
    Token -->|ja| Mine[Get-MyPlaylists]

    Mine --> Pick[Playlist-Nummer waehlen]
    Pick --> Fetch[Tracks der Playlist holen]
    Url --> FetchPublic[oeffentliche Tracks holen]

    Fetch --> Find[Find-Duplicates]
    FetchPublic --> Find
    Find --> Show[Tabelle anzeigen]
    Show --> Done([Ende])
```

---

## 4. OAuth-2.0-Login (Sequenz)

**Die vier Akteure:**

| Akteur | Rolle |
|---|---|
| **User** | Du, sitzt vor dem Computer |
| **duplichecker** | Unser PowerShell-Tool |
| **Browser** | Vermittelt zwischen User und Spotify |
| **Spotify** | Hat die Daten, gibt sie nur mit Erlaubnis raus |

**Die Idee in einem Satz:** duplichecker schickt dich kurz zu Spotify, du sagst dort „okay, das Tool darf meine Playlists lesen", und Spotify gibt dem Tool danach einen Schlüssel (Token) zurück, mit dem es deine Daten holen kann.

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant Tool as duplichecker
    participant Browser
    participant Spotify

    User->>Tool: moechte einloggen
    Tool->>Browser: oeffnet Spotify-Login-Seite
    User->>Browser: meldet sich an und erlaubt Zugriff
    Browser->>Spotify: User-Login durchfuehren
    Spotify->>Browser: schickt einen Code zurueck
    Browser->>Tool: Code weiterleiten
    Tool->>Spotify: Code gegen Token tauschen
    Spotify->>Tool: Access Token und Refresh Token
    Note over Tool: Token speichern
    Tool->>User: Login erfolgreich
```

**Warum ist das so umständlich?** Damit der User sein Spotify-Passwort **nie** beim Tool eingibt. Das Passwort bleibt zwischen User und Spotify. Das Tool bekommt nur einen Token — eine Art Stempelkarte, die Spotify jederzeit zurückziehen kann. Standard-Schutz seit ca. 2012.

---

## 5. Duplikat-Erkennung — Kernalgorithmus

Das Herz des Tools: aus einer rohen Songliste werden gruppierte Duplikate.

```mermaid
flowchart LR
    a[Liste von Songs] --> b[Title und Artist normalisieren]
    b --> c[Schluessel bilden]
    c --> d[Group-Object nach Key]
    d --> e{Anzahl groesser als 1}
    e -->|nein| f[verwerfen]
    e -->|ja| g[Duplikat-Gruppe aufnehmen]
    g --> h[nach Anzahl sortieren]
    h --> i[Duplikat-Gruppen]
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
    participant Server
    participant Modul

    User->>Browser: oeffnet die Webseite
    Browser->>Server: Anfrage Startseite
    Server->>Browser: HTML CSS und JS senden
    User->>Browser: waehlt CSV Datei aus
    Browser->>Server: sendet CSV als POST
    Server->>Modul: pruefe auf Duplikate
    Modul->>Server: Liste mit Duplikaten
    Server->>Browser: Antwort als JSON
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
