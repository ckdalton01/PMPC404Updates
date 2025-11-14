# PatchDownloader Log Parser

## Overview

`Parse-PatchDownloader.ps1` analyzes the **SCCM/WSUS PatchDownloader.log** file for failed update downloads (e.g. HTTP 404 errors) and cross-references those failures against the **Patch My PC Publishing History CSV** file.  

This tool helps identify updates that failed to download and maps them back to their published metadata for faster troubleshooting.

---

## Requirements

- **PowerShell 5.1 or higher** (PowerShell 7.x supported)
- Access to:
  - `PatchDownloader.log` (typically on the primary site server)
  - `PatchMyPC-PublishingHistory.csv` (from Patch My PC Publishing Service)

---


## **Default Paths**
- **Log file:**  
  `C:\Program Files\SMS_CCM\Logs\PatchDownloader.log`

- **Publishing history CSV:**  
  `C:\Program Files\Patch My PC\Patch My PC Publishing Service\PatchMyPC-PublishingHistory.csv`

Both can be overridden using command-line arguments.

---

## **Parameters**
| Parameter | Description |
|----------|-------------|
| `-LogFile` | Optional. Path to PatchDownloader.log |
| `-CsvFile` | Optional. Path to Patch My PC Publishing History |
| `-ZipFile` | Optional. ZIP file containing PatchDownloader.log |
| `-Output` | Optional. CSV path to export results |

If both `-LogFile` and `-ZipFile` are used, **ZipFile takes precedence**.

---

## **Examples**

### **Use default log + default CSV**
```powershell
.\Parse-PatchDownloader.ps1