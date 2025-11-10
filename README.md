# PatchDownloader Log Parser

## Overview

`Parse-PatchDownloader.ps1` analyzes the **SCCM/WSUS PatchDownloader.log** file for failed update downloads (such as HTTP 404 errors) and cross-references those failures against the **Patch My PC Publishing History CSV** file.  

This tool helps identify which updates failed to download and maps them back to their published metadata, allowing for faster remediation and troubleshooting.

---

## Requirements

- **PowerShell 5.1 or higher** (works with 7.x)
- Access to:
  - `PatchDownloader.log` (typically located at `C:\Windows\CCM\Logs`)
  - `PatchMyPC-PublishingHistory.csv` (from the Patch My PC Publishing Service)

---

## Default Paths

If not specified, the script uses the following default paths:

| Argument | Default Path |
|-----------|---------------|
| `-LogFile` | `%WINDIR%\CCM\Logs\PatchDownloader.log` |
| `-CsvFile` | `%ProgramFiles%\PatchMyPC\Patch My PC Publishing Service\PatchMyPC-PublishingHistory.csv` |

---

## Usage

```powershell
.\Parse-PatchDownloader.ps1 [-LogFile <path>] [-CsvFile <path>] [-Output <path>]
