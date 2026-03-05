# NinjaOne Asset Label Printer

Ein PowerShell-basiertes WPF-Tool zum Drucken von Asset-Etiketten für Geräte, die in [NinjaOne RMM](https://www.ninjarmm.com/) verwaltet werden.

---

## Inhaltsverzeichnis

- [Übersicht](#übersicht)
- [Voraussetzungen](#voraussetzungen)
- [Installation](#installation)
- [NinjaOne API einrichten](#ninjaone-api-einrichten)
- [Starten](#starten)
- [Benutzeroberfläche](#benutzeroberfläche)
  - [Linke Spalte – Verbindung & Organisationen](#linke-spalte--verbindung--organisationen)
  - [Mittlere Spalte – Geräteliste](#mittlere-spalte--geräteliste)
  - [Rechte Spalte – Etiketten-Designer](#rechte-spalte--etiketten-designer)
- [Etiketten konfigurieren](#etiketten-konfigurieren)
- [Drucken](#drucken)
- [Einstellungen & Konfigurationsdatei](#einstellungen--konfigurationsdatei)
- [Häufige Probleme](#häufige-probleme)

---

## Übersicht

Der **NinjaOne Asset Label Printer** verbindet sich über die NinjaOne REST API mit Ihrem NinjaOne-Account, listet alle Organisationen und deren Geräte auf und ermöglicht das direkte Drucken von professionellen Asset-Etiketten auf jedem lokal angebundenen Windows-Drucker.

**Funktionen auf einen Blick:**

- 🔌 OAuth2-Authentifizierung gegenüber der NinjaOne API
- 🏢 Browsen aller Organisationen und deren Geräte
- 🕐 Anzeige der 20 zuletzt hinzugefügten Geräte (organisationsübergreifend)
- 🏷 Live-Vorschau des Etiketts mit Organisationsname, Gerätename, Datum und Logo
- 🖨 Direktdruck auf beliebige Windows-Drucker (inkl. Etikettendrucker)
- 📐 Frei konfigurierbares Etikettenformat (Breite × Höhe in cm)
- 💾 Persistente Einstellungen (API-Credentials, Drucker, Maße, Logo)
- 🖼 Eigenes Firmenlogo auf dem Etikett

---

## Voraussetzungen

| Anforderung | Version / Hinweis |
|---|---|
| **Windows** | Windows 10 / Windows Server 2016 oder neuer |
| **PowerShell** | Version 5.1 oder neuer |
| **.NET Framework** | 4.5+ (WPF-Unterstützung) – bei Windows 10 bereits enthalten |
| **NinjaOne-Konto** | Zugang zum NinjaOne-Portal mit Berechtigung zur API-Nutzung |
| **Drucker** | Beliebiger lokal installierter Windows-Drucker (z. B. Brother QL-Serie, Zebra, etc.) |

> **Hinweis:** Das Skript benötigt eine Internetverbindung nur zum NinjaOne-API-Endpunkt.

---

## Installation

1. **Repository herunterladen** – entweder als ZIP oder per `git clone`:

   ```powershell
   git clone https://github.com/t2-schreiner/NinjaOneLabelPrinter.git
   ```

2. Das Skript benötigt **keine weiteren Abhängigkeiten** oder Installationsschritte. Alle verwendeten Assemblies (`PresentationFramework`, `System.Drawing`, `System.Windows.Forms`) sind Bestandteil von Windows / .NET Framework.

3. Optional: Stellen Sie sicher, dass die PowerShell-Ausführungsrichtlinie das Ausführen lokaler Skripte erlaubt:

   ```powershell
   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
   ```

---

## NinjaOne API einrichten

Das Tool nutzt OAuth2 mit dem **Client Credentials Grant** – Sie benötigen dafür eine **NinjaOne API-Applikation**:

1. Melden Sie sich im NinjaOne-Portal an.
2. Navigieren Sie zu **Administration → Apps → API** (oder **Configuration → Integrations → API**).
3. Legen Sie eine neue Applikation an:
   - **Name:** z. B. `LabelPrinter`
   - **Grant Type:** `Client Credentials`
   - **Scopes:** `monitoring`, `management`
4. Notieren Sie **Client ID** und **Client Secret**.
5. Wählen Sie den passenden API-Endpunkt:
   - EU-Instanz: `https://eu.ninjarmm.com`
   - US-Instanz: `https://app.ninjarmm.com`

---

## Starten

```powershell
.\NinjaOneLabelPrinter.ps1
```

Beim **ersten Start** erscheint nach Klick auf „Mit NinjaOne verbinden" automatisch ein Einstellungsdialog, in dem Sie folgende Angaben eintragen:

| Feld | Beschreibung |
|---|---|
| **Base URL** | API-Endpunkt Ihrer NinjaOne-Instanz (z. B. `https://eu.ninjarmm.com`) |
| **Client ID** | OAuth2 Client ID der angelegten API-Applikation |
| **Client Secret** | OAuth2 Client Secret der angelegten API-Applikation |

Die Zugangsdaten werden lokal in der [Konfigurationsdatei](#einstellungen--konfigurationsdatei) gespeichert.

---

## Benutzeroberfläche

Das Fenster ist in **drei Spalten** unterteilt:

```
┌─────────────────┬───────────────────────────────┬──────────────────────┐
│  Verbindung &   │     Geräteliste               │  Etiketten-Designer  │
│  Organisationen │     (Organisation)            │  & Vorschau          │
│                 ├───────────────────────────────│                      │
│                 │  Zuletzt hinzugefügte Geräte  │                      │
└─────────────────┴───────────────────────────────┴──────────────────────┘
```

### Linke Spalte – Verbindung & Organisationen

| Element | Funktion |
|---|---|
| **Mit NinjaOne verbinden** | Öffnet ggf. den Einstellungsdialog und verbindet sich mit der API. Nach erfolgreicher Verbindung werden alle Organisationen im Baum geladen. |
| **Organisationsbaum** | Listet alle NinjaOne-Organisationen auf. Ein Klick auf eine Organisation lädt deren Geräte in die mittlere Spalte. |

### Mittlere Spalte – Geräteliste

| Element | Funktion |
|---|---|
| **Geräteliste (oben)** | Zeigt alle Geräte der ausgewählten Organisation (Gerätename, Typ, Betriebssystem, Erstellungsdatum). Mehrfachauswahl per `Strg`+Klick oder `Shift`+Klick möglich. |
| **Zuletzt hinzugefügte Geräte (unten)** | Zeigt die 20 zuletzt in NinjaOne registrierten Geräte über alle Organisationen hinweg. |

### Rechte Spalte – Etiketten-Designer

| Element | Funktion |
|---|---|
| **Organisationsname** | Wird automatisch aus der ausgewählten Organisation übernommen – kann manuell überschrieben werden. |
| **Datum (Monat/Jahr)** | Standardmäßig das aktuelle Monat/Jahr – kann manuell angepasst werden. |
| **Etikettengröße** | Breite und Höhe des Etiketts in Zentimetern (z. B. `4,0 x 2,5 cm`). |
| **Logo** | Über das 📂-Symbol kann eine Bilddatei (PNG, JPG, BMP) als Logo ausgewählt werden. Es erscheint unten rechts auf dem Etikett. |
| **Drucker** | Dropdown mit allen installierten Windows-Druckern. Der zuletzt verwendete Drucker wird beim nächsten Start vorausgewählt. |
| **Vorschau** | Zeigt eine Live-Vorschau des Etiketts mit allen aktuellen Einstellungen. |
| **🔄 Vorschau aktualisieren** | Aktualisiert die Vorschau manuell. |
| **🖨 Etikett(en) drucken** | Druckt für jedes ausgewählte Gerät ein Etikett. |
| **💾 Einstellungen speichern** | Speichert Etikettengröße, Logo-Pfad und ausgewählten Drucker in der Konfigurationsdatei. |

---

## Etiketten konfigurieren

Ein Etikett enthält folgende Elemente:

```
┌──────────────────────────────────────┐
│         ORGANISATIONSNAME            │  ← Schwarzer Balken, weißer Text
├──────────────────────────────────────┤
│                                      │
│           GERÄTENAME                 │  ← Fett, zentriert
│                                      │
│  MM/YYYY              [Logo]         │  ← Datum links, Logo rechts
└──────────────────────────────────────┘
```

- **Etikettenformat:** Breite und Höhe in cm. Die Druckmaße werden automatisch in die passenden Druckereinheiten (1/100 Zoll) umgerechnet.
- **Schriften:** Alle Texte nutzen „Segoe UI". Die Schriftgröße skaliert automatisch mit der Etikettengröße.
- **Ränder:** Es werden keine Druckerränder verwendet (randlos).

### Empfohlene Etikettengrößen

| Etikettentyp | Breite | Höhe |
|---|---|---|
| Standard-Geräteetikett | 4,0 cm | 2,5 cm |
| Kleines Etikett | 3,5 cm | 1,5 cm |
| Großes Etikett | 6,0 cm | 4,0 cm |
| Brother DK-1201 | 9,0 cm | 2,9 cm |

---

## Drucken

1. Verbinden Sie sich mit NinjaOne (Schaltfläche **Mit NinjaOne verbinden**).
2. Klicken Sie im Organisationsbaum auf die gewünschte Organisation.
3. Wählen Sie ein oder mehrere Geräte in der Geräteliste aus (Mehrfachauswahl mit `Strg` oder `Shift`).
4. Wählen Sie im Dropdown den Zieldrucker aus.
5. Passen Sie Organisationsname, Datum, Etikettengröße und Logo nach Bedarf an.
6. Klicken Sie auf **🖨 Etikett(en) drucken**.

> Es wird pro ausgewähltem Gerät **ein separates Etikett** gedruckt.

---

## Einstellungen & Konfigurationsdatei

Die Einstellungen werden automatisch unter folgendem Pfad gespeichert:

```
%APPDATA%\NinjaOneLabelPrinter\config.json
```

Beispielinhalt der `config.json`:

```json
{
  "NinjaBaseUrl": "https://eu.ninjarmm.com",
  "ClientId": "your-client-id",
  "ClientSecret": "your-client-secret",
  "LastPrinter": "Brother QL-820NWB",
  "LabelWidthCm": 4.0,
  "LabelHeightCm": 2.5,
  "LogoPath": "C:\\Users\\User\\Pictures\\logo.png"
}
```

| Schlüssel | Beschreibung |
|---|---|
| `NinjaBaseUrl` | API-Basis-URL der NinjaOne-Instanz |
| `ClientId` | OAuth2 Client ID |
| `ClientSecret` | OAuth2 Client Secret |
| `LastPrinter` | Name des zuletzt verwendeten Druckers |
| `LabelWidthCm` | Etikettenbreite in cm |
| `LabelHeightCm` | Etikettenhöhe in cm |
| `LogoPath` | Absoluter Pfad zur Logo-Bilddatei |

> **Sicherheitshinweis:** Die Konfigurationsdatei enthält das Client Secret im Klartext. Stellen Sie sicher, dass der Zugriff auf `%APPDATA%\NinjaOneLabelPrinter\` auf den jeweiligen Benutzer beschränkt bleibt.

---

## Häufige Probleme

| Problem | Lösung |
|---|---|
| „Verbindung fehlgeschlagen" | Prüfen Sie Base URL, Client ID und Client Secret. Stellen Sie sicher, dass die API-App in NinjaOne aktiv ist und die Scopes `monitoring` und `management` hat. |
| Keine Drucker in der Liste | Stellen Sie sicher, dass Windows-Drucker lokal installiert (nicht nur als „Netzwerkfreigabe ohne Treiber") vorhanden sind. |
| Etikett wird nicht korrekt skaliert | Passen Sie die Etikettenmaße in cm genau an den physischen Etiketten Ihres Druckers an. |
| Skript startet nicht | Prüfen Sie die PowerShell-Ausführungsrichtlinie: `Get-ExecutionPolicy -Scope CurrentUser` – muss `RemoteSigned` oder `Unrestricted` sein. |
| Logo erscheint nicht | Stellen Sie sicher, dass der Dateipfad korrekt ist und das Bild ein unterstütztes Format hat (PNG, JPG, BMP). |

---

## Lizenz

Dieses Projekt steht unter der [MIT License](LICENSE).

---

*Entwickelt von [t2-schreiner](https://github.com/t2-schreiner)*