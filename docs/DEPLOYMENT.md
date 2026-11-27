# Installation ohne Mac (GitHub Actions + TestFlight)

Diese Anleitung bringt die App von diesem Repository auf deine Apple Watch – nur mit
Windows-PC (oder Handy-Browser), iPhone und Apple Watch. Gebaut und signiert wird auf einem
macOS-Runner von GitHub Actions, verteilt wird über TestFlight.

## Was du brauchst

| | |
|---|---|
| Apple Developer Program | 99 USD/Jahr. Ohne geht es von Windows aus nicht zuverlässig (siehe [unten](#geht-es-auch-ohne-developer-program)). |
| iPhone mit gekoppelter Apple Watch | watchOS 10 oder neuer. Für das Halten der Verbindung im Hintergrund Series 6 oder neuer. |
| Dieses Repository auf GitHub | Öffentliche Repos haben kostenlose macOS-Runner. |

Die Bundle-ID der App ist `io.github.dionho.pokitwatch` (Watch-App:
`io.github.dionho.pokitwatch.watchkitapp`). Wer das Projekt forkt, braucht eine eigene ID:
entweder `APP_BUNDLE_ID` in `project.yml` ändern oder im Repo eine Actions-Variable
`APP_BUNDLE_ID` anlegen.

## Einmalige Einrichtung

### 1. Apple Developer Program beitreten

Am einfachsten mit der App **Apple Developer** auf dem iPhone (Account › „Jetzt
registrieren"), alternativ auf <https://developer.apple.com/programs/enroll/>. Als
Privatperson („Individual") dauert die Freischaltung meist wenige Stunden bis zwei Tage.

### 2. Bundle-IDs registrieren

<https://developer.apple.com/account/resources/identifiers/list> › **+** › *App IDs* › *App*:

1. Description `Pokit Watch`, Bundle ID *Explicit*: `io.github.dionho.pokitwatch`
2. Noch einmal für die Watch-App: Description `Pokit Watch Watch App`, Bundle ID
   `io.github.dionho.pokitwatch.watchkitapp`

Capabilities müssen keine angehakt werden (Bluetooth braucht keine).

### 3. App in App Store Connect anlegen

<https://appstoreconnect.apple.com/apps> › **+** › *Neue App*:

- Plattform: **iOS**
- Name: frei wählbar, muss aber im ganzen App Store eindeutig sein, z. B. `Pokit Watch DionHo`
- Primäre Sprache: Deutsch oder Englisch
- Bundle-ID: `io.github.dionho.pokitwatch` auswählen
- SKU: beliebig, z. B. `pokitwatch`
- Benutzerzugriff: Uneingeschränkt

Die App wird nie im Store veröffentlicht; der Eintrag ist nur nötig, damit TestFlight die
Builds annimmt.

### 4. API-Schlüssel erstellen

<https://appstoreconnect.apple.com/access/integrations/api> (Benutzer und Zugriff ›
Integrationen › App Store Connect API › *Team-Schlüssel*):

1. Beim ersten Mal „Zugriff anfordern" bestätigen.
2. **+** › Name `GitHub Actions`, Zugriff **Admin** › Erstellen.
   (Admin ist nötig, damit der Runner Zertifikat und Profile selbst anlegen darf.)
3. Notieren: **Schlüssel-ID** (10 Zeichen) und oben auf der Seite die **Issuer-ID** (UUID).
4. **API-Schlüssel laden** – die Datei `AuthKey_XXXXXXXXXX.p8` gibt es nur dieses eine Mal.

Die **Team-ID** (10 Zeichen) steht unter <https://developer.apple.com/account> ›
*Mitgliedschaftsdetails*.

### 5. Secrets in GitHub hinterlegen

Im Repository: *Settings › Secrets and variables › Actions › New repository secret*.

| Name | Inhalt |
|---|---|
| `APPLE_TEAM_ID` | Team-ID |
| `APPSTORE_KEY_ID` | Schlüssel-ID |
| `APPSTORE_ISSUER_ID` | Issuer-ID |
| `APPSTORE_PRIVATE_KEY` | Kompletter Inhalt der `.p8`-Datei (mit Editor öffnen, alles kopieren, inklusive der Zeilen `-----BEGIN PRIVATE KEY-----` und `-----END PRIVATE KEY-----`) |

Die `.p8`-Datei gehört nicht ins Repository und nicht in einen Chat. Als Secret ist sie für
niemanden mehr lesbar, auch nicht für dich.

## Build auf die Uhr bringen

### 6. Workflow starten

*Actions › TestFlight › Run workflow* (Branch auswählen, „Upload" angehakt lassen). Der Lauf
dauert etwa 10 Minuten: Projekt generieren, archivieren, mit Apples Cloud-Zertifikat signieren,
hochladen. Danach verarbeitet Apple den Build noch 5–30 Minuten.

Tipp: Mit abgewähltem „Upload" prüft der Workflow nur, ob die Signierung klappt.

### 7. Dich als Tester eintragen

App Store Connect › deine App › **TestFlight** › *Interne Tests* › **+**: Gruppe anlegen
(z. B. `Ich`), „Automatische Verteilung" aktiviert lassen, dich selbst als Tester hinzufügen.
Interne Tests brauchen keine Prüfung durch Apple.

### 8. Installieren

1. **TestFlight** aus dem App Store auf dem iPhone installieren und mit deiner Apple-ID
   anmelden. „Pokit Watch" erscheint dort › *Installieren*.
2. Die Watch-App kommt mit, wenn auf dem iPhone *Watch › Allgemein › Automatische
   App-Installation* aktiv ist. Sonst: iPhone-App **Watch** › ganz unten *Verfügbare Apps* ›
   „Pokit" › *Installieren*. (Alternativ in TestFlight auf der Detailseite der App den Eintrag
   für die Apple Watch verwenden.)
3. Auf der Uhr **Pokit** öffnen, Bluetooth-Zugriff erlauben, Pokit einschalten und in der
   Liste antippen.

## Danach

- **Neue Version:** Änderungen pushen, Workflow erneut starten. TestFlight bietet das Update
  an (oder installiert es automatisch).
- **Ablauf nach 90 Tagen:** TestFlight-Builds laufen ab. Vorher einfach den Workflow noch
  einmal starten – das geht auch vom Handy aus (GitHub-App oder Browser).
- **Versionsnummer:** `MARKETING_VERSION` in `project.yml`. Die Build-Nummer vergibt der
  Workflow selbst (Zeitstempel).

## Wenn etwas schiefgeht

Das Log des fehlgeschlagenen Schritts in GitHub Actions zeigt die Ursache; bei Fehlern werden
die vollständigen Logs zusätzlich als Artefakt `testflight-logs` angehängt.

| Meldung | Ursache / Lösung |
|---|---|
| `Repository secret for … is missing` | Secret aus Schritt 5 fehlt oder ist falsch benannt. |
| `does not look like a .p8 key` | In `APPSTORE_PRIVATE_KEY` fehlt ein Teil der Datei. Komplett neu einfügen. |
| `No profiles for '…' were found` / `No signing certificate` | Der API-Schlüssel hat nicht die Rolle Admin, oder die Bundle-IDs aus Schritt 2 fehlen. |
| `No suitable application records were found` | Schritt 3 fehlt, oder die Bundle-ID der App passt nicht. |
| `The bundle version must be higher than the previously uploaded version` | Sollte durch den Zeitstempel nicht vorkommen; Workflow einfach neu starten. |
| Build erscheint nicht in TestFlight | Verarbeitung abwarten; Apple schickt bei Problemen eine E-Mail an die Apple-ID. |

Der Signier- und Upload-Schritt konnte ohne Apple-Konto nicht vorab getestet werden. Falls er
beim ersten Lauf hakt, hilft das Log aus `testflight-logs` beim Nachbessern des Workflows.

## Geht es auch ohne Developer Program?

Nicht verlässlich von Windows aus:

- **Sideloadly / AltStore** signieren iPhone-Apps mit einer kostenlosen Apple-ID, entfernen
  dabei aber eingebettete Watch-Apps bzw. installieren sie nicht auf der Uhr.
- **Mit einem geliehenen Mac** geht es kostenlos: Xcode installieren, `brew install xcodegen`,
  `xcodegen generate`, Projekt öffnen, eigenes „Personal Team" wählen, auf iPhone/Watch
  starten. Die App läuft dann 7 Tage und muss danach neu installiert werden.

Für eine App, die dauerhaft auf der Uhr bleiben soll, ist TestFlight der praktikable Weg.
