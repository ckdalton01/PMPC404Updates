<#
.SYNOPSIS
    Parse the SCCM PatchDownloader.log and cross-reference failed downloads with the Patch My PC publishing history.

.DESCRIPTION
    This tool analyzes the PatchDownloader.log (used by SCCM/WSUS) and identifies updates that failed to download
    with HTTP 404 errors. It then cross-references those update IDs against Patch My PC's publishing history CSV file.

.PARAMETER LogFile
    (Optional) Path to PatchDownloader.log.
    Default: $env:WINDIR\CCM\Logs\PatchDownloader.log

.PARAMETER CsvFile
    (Optional) Path to Patch My PC publishing history CSV.
    Default: $env:ProgramFiles\PatchMyPC\Patch My PC Publishing Service\PatchMyPC-PublishingHistory.csv

.PARAMETER Output
    (Optional) Path to save results as CSV. 
    If not provided, results are printed to the console.

.EXAMPLE
    # Example 1 - Use defaults
    .\Parse-PatchDownloader.ps1

.EXAMPLE
    # Example 2 - Specify log file and CSV file
    .\Parse-PatchDownloader.ps1 -LogFile "D:\Temp\PatchDownloader.log" -CsvFile "D:\PMPC\PublishingHistory.csv"

.EXAMPLE
    # Example 3 - Export results to CSV
    .\Parse-PatchDownloader.ps1 -Output "C:\Temp\FailedUpdates.csv"

.NOTES
    Author: C. Dalton (2025)
    Tested on: PowerShell 5.1 / 7.x
    Description: Finds WSUS/SCCM PatchDownloader failures (HTTP 404) and matches them to published updates.
#>
