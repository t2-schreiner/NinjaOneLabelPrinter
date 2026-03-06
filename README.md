# NinjaOne Asset Label Printer

A PowerShell-based WPF tool for printing asset labels for devices managed in [NinjaOne RMM](https://www.ninjarmm.com/).

Tested on small mobile Printers and industrial Printers for higher volumes.

<img width="629" height="838" alt="image" src="https://github.com/user-attachments/assets/bfb1979f-51ae-4a54-bc8d-fdfe44f6dc30" />
<img width="1156" height="1536" alt="image" src="https://github.com/user-attachments/assets/f70fd519-bc66-4d75-8ba8-103c3d13c748" />


---

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [NinjaOne API Setup](#ninjaone-api-setup)
- [Getting Started](#getting-started)
- [User Interface](#user-interface)
  - [Left Column – Connection & Organizations](#left-column--connection--organizations)
  - [Middle Column – Device List](#middle-column--device-list)
  - [Right Column – Label Designer](#right-column--label-designer)
- [Configuring Labels](#configuring-labels)
- [Printing](#printing)
- [Settings & Configuration File](#settings--configuration-file)
- [Security Concept](#security-concept)
- [Troubleshooting](#troubleshooting)

---

## Overview

The **NinjaOne Asset Label Printer** connects to your NinjaOne account via the NinjaOne REST API, lists all organizations and their devices, and enables direct printing of professional asset labels on any locally connected Windows printer.

**Features at a Glance:**

- 🔌 OAuth2 authentication against the NinjaOne API
- 🏢 Browse all organizations and their devices
- 🕐 Display the 20 most recently added devices (across all organizations)
- 🏷 Live label preview with organization name, device name, date, and logo
- 🖨 Direct printing on any Windows printer (including label printers)
- 📐 Fully configurable label format (width × height in cm)
- 🔧 Adjustable inner padding, header height, and logo height (as percentage of label size)
- 🏷 Per-organization name overrides (custom display names)
- 💾 Persistent settings (API credentials, printer, dimensions, logo)
- 🔐 AES-256 encryption of API credentials with a master password
- 🔑 PBKDF2-SHA256 key derivation (100,000 iterations)
- 🔄 Reset function for forgotten master passwords
- 🖼 Custom company logo on the label

---

## Prerequisites

| Requirement | Version / Notes |
|---|---|
| **Windows** | Windows 10 / Windows Server 2016 or newer |
| **PowerShell** | Version 7 or newer |
| **.NET Framework** | 4.7.2+ (WPF support + modern cryptography) – included with Windows 10 (1803+) |
| **NinjaOne Account** | Access to the NinjaOne portal with API permissions |
| **Printer** | Any locally installed Windows printer (e.g. Brother QL series, Zebra, etc.) |

> **Note:** The script only requires an internet connection to the NinjaOne API endpoint.

---

## Installation

1. **Download the repository** – either as a ZIP or via `git clone`:

   ```powershell
   git clone https://github.com/t2-schreiner/NinjaOneLabelPrinter.git
   ```

2. The script requires **no additional dependencies** or installation steps. All assemblies used (`PresentationFramework`, `System.Drawing`, `System.Windows.Forms`) are part of Windows / .NET Framework.

3. **Launch:** Double-click **`Start-NinjaOneLabelPrinter.bat`** to start the application directly. No further steps are required.

---

## NinjaOne API Setup

The tool uses OAuth2 with the **Client Credentials Grant** – you need a **NinjaOne API application** for this:

1. Log in to the NinjaOne portal.
2. Navigate to **Administration → Apps → API** (or **Configuration → Integrations → API**).
3. Create a new application:
   - **Name:** e.g. `LabelPrinter`
   - **Grant Type:** `Client Credentials`
   - **Scopes:** `monitoring`, `management`
4. Note down the **Client ID** and **Client Secret**.
5. Select the appropriate API endpoint:
   - EU instance: `https://eu.ninjarmm.com`
   - US instance: `https://app.ninjarmm.com`

---

## Getting Started

### Recommended: Double-click the batch file

Simply double-click **`Start-NinjaOneLabelPrinter.bat`** in the project folder. The batch file starts the application automatically – there is no need to open PowerShell manually or change the execution policy.

> **Note:** The ExecutionPolicy is only set to `Bypass` for this single session. The system-wide policy remains unchanged.

### Alternative: Run manually in PowerShell

```powershell
.\NinjaOneLabelPrinter.ps1
```

On **first launch**, after clicking "Connect to NinjaOne", a setup dialog appears where you enter the following:

| Field | Description |
|---|---|
| **Master Password** | A freely chosen password (min. 8 characters) used to encrypt API credentials. |
| **Base URL** | API endpoint of your NinjaOne instance (e.g. `https://eu.ninjarmm.com`) |
| **Client ID** | OAuth2 Client ID of the created API application |
| **Client Secret** | OAuth2 Client Secret of the created API application |

The credentials are stored **AES-256 encrypted** in the [configuration file](#settings--configuration-file).

On every subsequent launch, you will be prompted for the **master password** when connecting, to decrypt the credentials.

---

## User Interface

The window is divided into **three columns**:

<img width="2879" height="1714" alt="image" src="https://github.com/user-attachments/assets/f66f3705-285b-4d27-ae53-604dd1264bf4" />


### Left Column – Connection & Organizations

| Element | Function |
|---|---|
| **Connect to NinjaOne** | Opens the setup dialog if needed and connects to the API. After a successful connection, all organizations are loaded into the tree. |
| **Organization Tree** | Lists all NinjaOne organizations. Clicking an organization loads its devices into the middle column. |

### Middle Column – Device List

| Element | Function |
|---|---|
| **Device List (top)** | Shows all devices of the selected organization (device name, type, asset ID). Multi-select via `Ctrl`+Click or `Shift`+Click is supported. |
| **Recently Added Devices (bottom)** | Shows the 20 most recently registered devices in NinjaOne across all organizations. |

### Right Column – Label Designer

| Element | Function |
|---|---|
| **Organization name** | Automatically populated from the selected organization – can be manually overridden. Overrides are saved per organization. |
| **Date (month/year)** | Defaults to the current month/year – can be manually adjusted. |
| **Label size** | Width and height of the label in centimeters (e.g. `4.0 × 2.5 cm`). |
| **Inner padding** | Padding in millimeters applied on all sides of the label content. |
| **Header / Logo height** | Percentage of the label height used for the header bar and logo area respectively. |
| **Logo** | Use the 📂 button to select an image file (PNG, JPG, BMP) as a logo. It appears in the bottom-right of the label. |
| **Printer** | Dropdown with all installed Windows printers. The last used printer is pre-selected on the next launch. |
| **Preview** | Shows a live preview of the label with all current settings. |
| **🖨 Print label(s)** | Prints one label for each selected device. |
| **💾 Save settings** | Saves label size, padding, header/logo percentages, logo path, and selected printer to the configuration file. |
| **🔑 Change master password** | Allows changing the master password. The credentials are re-encrypted with the new password. |
| **🔄 Reset credentials** | Deletes all stored API credentials and the master password. Useful when the master password has been forgotten. |

---

## Configuring Labels

The Label design looks like this but many elements are configureable.

<img width="243" height="165" alt="image" src="https://github.com/user-attachments/assets/99b6c4fc-fe11-4053-993a-f47fed0a62a8" />


- **Label format:** Width and height in cm. Print dimensions are automatically converted to the appropriate printer units (1/100 inch).
- **Fonts:** All text uses "Segoe UI". Font sizes scale automatically with the label size, with auto-shrink for long device names.
- **Margins:** No printer margins are used (borderless). An optional inner padding (in mm) can be configured.
- **Header & Logo height:** Configurable as a percentage of the total label height (default: 22% each).

### Recommended Label Sizes

| Label Type | Width | Height |
|---|---|---|
| Standard device label | 4.0 cm | 2.5 cm |
| Small label | 3.5 cm | 2.0 cm |
| Large label | 6.0 cm | 4.0 cm |
| Brother DK-1201 | 9.0 cm | 2.9 cm |

---

## Printing

1. Connect to NinjaOne (button **Connect to NinjaOne**).
2. Click on the desired organization in the organization tree.
3. Select one or more devices in the device list (multi-select with `Ctrl` or `Shift`).
4. Select the target printer from the dropdown.
5. Adjust the organization name, date, label size, and logo as needed.
6. Click **🖨 Print label(s)**.

> One **separate label** is printed for each selected device.

---

## Settings & Configuration File

Settings are automatically saved at the following path:

```
%APPDATA%\NinjaOneLabelPrinter\config.json
```

Example contents of `config.json`:

```json
{
  "NinjaBaseUrl": "https://eu.ninjarmm.com",
  "LastPrinter": "Brother QL-820NWB",
  "LabelWidthCm": 4.0,
  "LabelHeightCm": 2.5,
  "PaddingMm": 0.0,
  "HeaderHeightPercent": 22,
  "LogoHeightPercent": 22,
  "LogoPath": "C:\\Users\\User\\Pictures\\logo.png",
  "OrgNameOverrides": {},
  "EncryptedClientId": "base64-encrypted-value...",
  "EncryptedClientSecret": "base64-encrypted-value...",
  "MasterPasswordVerifier": "base64-verifier..."
}
```

| Key | Description |
|---|---|
| `NinjaBaseUrl` | API base URL of the NinjaOne instance |
| `EncryptedClientId` | AES-256-encrypted OAuth2 Client ID (Base64-encoded: Salt + IV + Ciphertext) |
| `EncryptedClientSecret` | AES-256-encrypted OAuth2 Client Secret (Base64-encoded: Salt + IV + Ciphertext) |
| `MasterPasswordVerifier` | PBKDF2-SHA256 hash for verifying the master password (Base64-encoded: Salt + Hash) |
| `LastPrinter` | Name of the last used printer |
| `LabelWidthCm` | Label width in cm |
| `LabelHeightCm` | Label height in cm |
| `PaddingMm` | Inner padding in mm (applied on all sides) |
| `HeaderHeightPercent` | Header bar height as a percentage of label height |
| `LogoHeightPercent` | Logo area height as a percentage of label height |
| `LogoPath` | Absolute path to the logo image file |
| `OrgNameOverrides` | Custom display names per organization (maps org ID → name) |

> **Security note:** API credentials (Client ID and Client Secret) are stored **AES-256-CBC encrypted**. The encryption key is derived from the master password via **PBKDF2-HMAC-SHA256** (100,000 iterations). Each save operation uses a random salt and IV.

---

## Security Concept

### Encryption

API credentials are **never stored in plaintext** on disk. They are protected by the following methods:

| Component | Method |
|---|---|
| **Encryption** | AES-256-CBC with random IV per save operation |
| **Key Derivation** | PBKDF2-HMAC-SHA256, 100,000 iterations, 32-byte salt |
| **Password Verifier** | PBKDF2-HMAC-SHA256 hash (separate from encryption key) |
| **Comparison** | Constant-time comparison to protect against timing attacks |

### Master Password

- The master password must be **at least 8 characters** long.
- It is **not** stored – only a cryptographic verifier (PBKDF2 hash).
- To change the master password: **🔑 Change master password** in the right column.

### Reset on Forgotten Master Password

If the master password is forgotten, the credentials **cannot** be recovered (this is by design). Instead:

1. Click **🔄 Reset credentials** (right column) or **🔄 Reset** in the unlock dialog.
2. All encrypted credentials are permanently deleted.
3. Enter a new master password and your API credentials the next time you connect.

### Legacy Migration

If you are upgrading from an older version without encryption, the tool automatically detects the unencrypted credentials and prompts you to set a master password the next time you connect. The existing credentials are then encrypted and stored.

---

## Troubleshooting

| Problem | Solution |
|---|---|
| "Connection failed" | Check Base URL, Client ID, and Client Secret. Make sure the API app in NinjaOne is active and has the scopes `monitoring` and `management`. |
| Forgotten master password | Click **🔄 Reset** in the unlock dialog or use the **🔄 Reset credentials** button in the right column. All stored credentials will be deleted and must be re-entered. |
| No printers in the list | Make sure Windows printers are locally installed (not just shared network printers without drivers). |
| Label is not scaled correctly | Adjust the label dimensions in cm to match the physical labels of your printer exactly. |
| Script does not start | Use the batch file `Start-NinjaOneLabelPrinter.bat` – it bypasses the execution policy automatically. Alternatively: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`. |
| Logo does not appear | Make sure the file path is correct and the image is in a supported format (PNG, JPG, BMP). |

---

## License

This project is licensed under the [MIT License](LICENSE).

---

*Developed by [t2-schreiner](https://github.com/t2-schreiner)*
