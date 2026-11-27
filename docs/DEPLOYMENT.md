# Installation ohne Mac (GitHub Actions + TestFlight)

Diese Anleitung bringt die App von diesem Repository auf deine Apple Watch – nur mit
Windows-PC (oder Handy-Browser), iPhone und Apple Watch. Gebaut und signiert wird auf einem
macOS-Runner von GitHub Actions, verteilt wird über TestFlight.

## Was du brauchst

| | |
|---|---|
| Apple Developer Program | 99 USD/Jahr. Zum Ausprobieren gibt es einen experimentellen Weg ohne (siehe [unten](#geht-es-auch-ohne-developer-program)). |
| iPhone mit gekoppelter Apple Watch | watchOS 10 oder neuer. Für das Halten der Verbindung im Hintergrund Series 6 oder neuer. |
| Dieses Repository auf GitHub | Öffentliche Repos haben kostenlose macOS-Runner. |

Die Bundle-ID der App ist `io.github.dionho.pokitwatch` (Watch-App:
`io.github.dionho.pokitwatch.watchkitapp`, deren Komplikationen:
`io.github.dionho.pokitwatch.watchkitapp.widgets`). Wer das Projekt forkt, braucht eine eigene ID:
entweder `APP_BUNDLE_ID` in `project.yml` ändern oder im Repo eine Actions-Variable
`APP_BUNDLE_ID` anlegen.

## Einmalige Einrichtung

### 1. Apple Developer Program beitreten

Am einfachsten mit der App **Apple Developer** auf dem iPhone (Account › „Jetzt
registrieren"), alternativ auf <https://developer.apple.com/programs/enroll/>. Als
Privatperson („Individual") dauert die Freischaltung meist wenige Stunden bis zwei Tage.

### 2. Bundle-IDs registrieren

<https://developer.apple.com/account/resources/identifiers/list> › **+** › *App IDs* › *App*:

1. Description `Wristmeter`, Bundle ID *Explicit*: `io.github.dionho.pokitwatch`
2. Noch einmal für die Watch-App: Description `Wristmeter Watch App`, Bundle ID
   `io.github.dionho.pokitwatch.watchkitapp`
3. Und für die Komplikationen: Description `Wristmeter Widgets`, Bundle ID
   `io.github.dionho.pokitwatch.watchkitapp.widgets`

Capabilities müssen keine angehakt werden (Bluetooth braucht keine).

### 3. App in App Store Connect anlegen

<https://appstoreconnect.apple.com/apps> › **+** › *Neue App*:

- Plattform: **iOS**
- Name: frei wählbar, muss aber im ganzen App Store eindeutig sein. `Wristmeter` ist durch
  dieses Projekt belegt; wer forkt, nimmt z. B. `Wristmeter <dein Name>`. „Pokit“ gehört als
  Marke von Pokit Innovations nicht in den App-Namen.
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
dauert etwa 3 Minuten: Projekt generieren, archivieren, mit Apples Cloud-Zertifikat signieren,
hochladen. Danach verarbeitet Apple den Build noch 5–30 Minuten.

Hinweis: GitHub zeigt „Run workflow" nur für Workflows an, die im Standard-Branch (`main`)
liegen. Solange der Code nur in einem Feature-Branch steckt, diesen zuerst nach `main` mergen.

Tipp: Mit abgewähltem „Upload" prüft der Workflow nur, ob die Signierung klappt.

### 7. Dich als Tester eintragen

App Store Connect › deine App › **TestFlight** › *Interne Tests* › **+**: Gruppe anlegen
(z. B. `Ich`), „Automatische Verteilung" aktiviert lassen, dich selbst als Tester hinzufügen.
Interne Tests brauchen keine Prüfung durch Apple.

### 8. Installieren

1. **TestFlight** aus dem App Store auf dem iPhone installieren und mit deiner Apple-ID
   anmelden. „Wristmeter" erscheint dort › *Installieren*.
2. Die Watch-App kommt mit, wenn auf dem iPhone *Watch › Allgemein › Automatische
   App-Installation* aktiv ist. Sonst: iPhone-App **Watch** › ganz unten *Verfügbare Apps* ›
   „Wristmeter" › *Installieren*. (Alternativ in TestFlight auf der Detailseite der App den Eintrag
   für die Apple Watch verwenden.)
3. Auf der Uhr **Wristmeter** öffnen, Bluetooth-Zugriff erlauben, Pokit einschalten und in der
   Liste antippen.
4. Damit die App schnell zur Hand ist: Zifferblatt gedrückt halten › *Bearbeiten* ›
   *Komplikationen* › Platz antippen › *Wristmeter*. Oder im Smart-Stapel (Krone auf dem
   Zifferblatt nach oben drehen) ganz unten *Bearbeiten* › **+** › *Wristmeter*.

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
| `No profiles for '…' were found` / `No signing certificate` | Der API-Schlüssel hat nicht die Rolle Admin, oder eine der drei Bundle-IDs aus Schritt 2 fehlt. |
| `No suitable application records were found` | Schritt 3 fehlt, oder die Bundle-ID der App passt nicht. |
| `The bundle version must be higher than the previously uploaded version` | Sollte durch den Zeitstempel nicht vorkommen; Workflow einfach neu starten. |
| Build erscheint nicht in TestFlight | Verarbeitung abwarten; Apple schickt bei Problemen eine E-Mail an die Apple-ID. |

App Store Connect meldet beim Hochladen eine Warnung zur SDK-Version (ab April 2027 wird das
iOS-27-SDK verlangt). Sie verhindert den Upload nicht; bis dahin muss der Workflow auf ein
neueres Xcode umgestellt werden.

## Geht es auch ohne Developer Program?

Vielleicht – als Experiment für 7 Tage. Mit einer kostenlosen Apple-ID signierte Apps laufen
7 Tage und müssen danach neu signiert werden. Das Problem ist die Uhr: Die üblichen
Windows-Werkzeuge installieren nur iPhone-Apps.

**Dieser Weg ist mit dieser App noch nicht erprobt.** Er stützt sich auf die Angaben der
genannten Projekte; ob er mit deiner iOS-/watchOS-Version funktioniert, zeigt nur der Versuch.

### Variante A: WatchBridge (Windows)

[WatchBridge](https://github.com/AdminZachary/WatchBridge) ist ein quelloffenes
Community-Werkzeug (Alpha-Stand), das nach eigener Beschreibung genau diese Lücke füllt:
Entwicklermodus der Uhr vorbereiten, ein IPA mit iPhone-Hülle und eingebetteter Watch-App mit
der Apple-ID signieren, erst aufs iPhone und dann auf die Uhr installieren. Es kann die
Signatur vor Ablauf der 7 Tage erneuern, solange der PC läuft.

1. **IPA holen:** GitHub › *Actions* › *Build* › letzter erfolgreicher Lauf › *Artifacts* ›
   `PokitWatch-unsigned-ipa`. Das ZIP entpacken, darin liegt `PokitWatch-unsigned.ipa`.
   (Die App darin hat die eigene Bundle-ID `io.github.dionho.pokitwatch.sideload`, damit sie
   einer späteren TestFlight-Version nicht in die Quere kommt.)
2. **Apple-Treiber:** iTunes oder die App „Apple-Geräte" aus dem Microsoft Store installieren.
3. **WatchBridge** von der Releases-Seite laden, entpacken, `WatchBridge.exe` starten. Die
   Datei ist nicht signiert, Windows SmartScreen warnt beim ersten Start.
4. iPhone per USB anschließen und in WatchBridge auswählen. Die Uhr koppeln, auf der Uhr dem
   Computer vertrauen und den Schalter für den Entwicklermodus anfordern. Dann auf der Uhr:
   *Einstellungen › Datenschutz & Sicherheit › Entwicklermodus* einschalten, neu starten,
   bestätigen. Zurück in WatchBridge „Erneut prüfen".
5. Mit der Apple-ID anmelden, das IPA auswählen, signieren und installieren lassen.
6. Auf dem iPhone ggf. *Einstellungen › Allgemein › VPN & Geräteverwaltung* das
   Entwicklerzertifikat als vertrauenswürdig markieren und den Entwicklermodus einschalten.
7. **Wristmeter** auf der Uhr öffnen.

Zu beachten:

- Du gibst deine Apple-ID in ein Programm eines Drittanbieters ein. Wer das nicht mit der
  Haupt-ID tun möchte, legt dafür eine zweite Apple-ID an; sie muss nicht die des iPhones sein.
- Kostenlose Apple-IDs erlauben nur wenige gleichzeitig installierte Apps und App-IDs pro Woche.
- WatchBridge unterstützt nur ein iPhone mit genau einer gekoppelten Uhr.

### Variante B: Sideloadly

[Sideloadly](https://sideloadly.io) installiert das IPA aufs iPhone; die Watch-App wird danach
in der iPhone-App *Watch* unter „Verfügbare Apps" installiert. In den erweiterten Optionen
„Use automatic bundle ID" abschalten. Steht im Sideloadly-Log
`Watch apps will be stripped from the IPA`, wurde die Watch-App entfernt – dann führt dieser
Weg nicht zum Ziel.

### Variante C: geliehener Mac

Xcode installieren, `brew install xcodegen`, `xcodegen generate`, Projekt öffnen, eigenes
„Personal Team" wählen, auf iPhone/Watch starten. Auch hier gilt die 7-Tage-Grenze.

Für eine App, die dauerhaft und ohne PC auf der Uhr bleiben soll, ist TestFlight der
praktikable Weg.
