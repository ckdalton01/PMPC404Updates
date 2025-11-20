# PatchDownloader Log Parser

## Overview
`Parse-PatchDownloader.ps1` is a PowerShell script designed to analyze SCCM/WSUS PatchDownloader logs and identify updates that failed to download (e.g., HTTP 404 errors). It cross-references these failed UpdateIDs with Patch My PC's publishing history and optionally enriches data using SCCM WMI queries when `-SMS` mode is enabled.

## Features
- Detects failed downloads in `PatchDownloader.log`.
- Matches UpdateIDs against Patch My PC publishing history CSV.
- Supports ZIP extraction for logs and CSV.
- **SMS Mode**: Auto-detects SCCM installation paths and uses WMI (`Get-CimInstance`) to retrieve update details if CSV is missing.
- Exports results to CSV with combined data from CSV and WMI.

## Requirements
- Windows PowerShell 5.1 or PowerShell 7.x
- Run on SCCM Primary Site Server for `-SMS` mode
- Access to PatchDownloader.log and optionally Patch My PC PublishingHistory.csv

## Parameters
- `-LogFile <string>`: Path to PatchDownloader.log (default: `C:\Program Files\SMS_CCM\Logs\PatchDownloader.log`).
- `-CsvFile <string>`: Path to Patch My PC PublishingHistory.csv (default: `C:\Program Files\Patch My PC\Patch My PC Publishing Service\PatchMyPC-PublishingHistory.csv`).
- `-ZipFile <string>`: Path to a ZIP file containing PatchDownloader.log and optionally CSV.
- `-Output <string>`: Path to export results as CSV.
- `-SMS`: Switch to enable SCCM detection and WMI enrichment.

## Usage Examples
```powershell
# Use default paths
.\Parse-PatchDownloader.ps1

# Specify log and CSV paths
.\Parse-PatchDownloader.ps1 -LogFile "D:\Logs\PatchDownloader.log" -CsvFile "D:\PMPC\PublishingHistory.csv"

# Use ZIP file and export results
.\Parse-PatchDownloader.ps1 -ZipFile "C:\Temp\logs.zip" -Output "C:\Reports\FailedUpdates.csv"

# Enable SMS mode (auto-detect SCCM paths and use WMI)
.\Parse-PatchDownloader.ps1 -SMS
```

## Behavior Details
- If both `-LogFile` and `-ZipFile` are provided, `-ZipFile` takes precedence.
- In SMS mode:
  - Reads SCCM registry keys for Site Code and Installation Directory.
  - Attempts WMI query for each failed UpdateID using:
    ```powershell
    Get-CimInstance -ClassName SMS_SoftwareUpdate -Namespace "root\SMS\site_$SiteCode" -Filter "CI_UniqueID = '$UpdateID'"
    ```
  - If CSV is missing, script continues with WMI data only.
- Failure detection is based on `HTTP_STATUS_NOT_FOUND` or `returns 404` in log lines.

## Output
- Console summary of failed updates.
- Optional CSV export with columns:
  - `UpdateID`, `Title`, `Date`, `Version`, `Severity`, `Source` (CSV, WMI, or both).

## Notes
- When SMS mode is enabled, WMI data is merged with CSV if available.
- If CSV is missing in SMS mode, WMI-only data is used.
- Ensure proper permissions for registry and WMI queries.

---
Author: C. Dalton  
Date: 2025-11-20
