<#
.SYNOPSIS
    Parse the SCCM PatchDownloader.log and cross-reference failed downloads with the Patch My PC publishing history.

.DESCRIPTION
    This tool analyzes the PatchDownloader.log (used by SCCM/WSUS) and identifies updates that failed to download
    with HTTP 404 errors. It then cross-references those update IDs against Patch My PC's publishing history CSV file.

.PARAMETER LogFile
    (Optional) Path to PatchDownloader.log.
    Default: $env:ProgramFiles\SMS_CCM\Logs\PatchDownloader.log

.PARAMETER CsvFile
    (Optional) Path to Patch My PC publishing history CSV.
    Default: $env:ProgramFiles\Patch My PC\Patch My PC Publishing Service\PatchMyPC-PublishingHistory.csv

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

param(
    [string]$LogFile = "$env:ProgramFiles\SMS_CCM\Logs\PatchDownloader.log",
    [string]$CsvFile = "$env:ProgramFiles\Patch My PC\Patch My PC Publishing Service\PatchMyPC-PublishingHistory.csv",
    [string]$Output
)

Write-Host ""
Write-Host "=== PatchDownloader Log Parser ==="
Write-Host "LogFile: $LogFile"
Write-Host "CsvFile: $CsvFile"
if ($Output) { Write-Host "Output : $Output" }
Write-Host ""

# Validate files
if (-not (Test-Path $LogFile)) {
    Write-Host "Log file not found: $LogFile"
    exit 1
}
if (-not (Test-Path $CsvFile)) {
    Write-Host "CSV file not found: $CsvFile"
    exit 1
}

# Import CSV
$csvData = Import-Csv -Path $CsvFile
$logLines = Get-Content -Path $LogFile

$updates = @{}
$updateIdPattern = 'Download destination\s*=\s*.*?\\(?<UpdateID>[0-9a-fA-F-]+)\.1\\'

for ($i = 0; $i -lt $logLines.Count; $i++) {
    $line = $logLines[$i]

    # Detect "Download destination" and extract UpdateID
    if ($line -match $updateIdPattern) {
        $currentUpdateID = $matches['UpdateID']
        if (-not $updates.ContainsKey($currentUpdateID)) {
            $updates[$currentUpdateID] = @{
                Failed = $false
                Lines  = @($line)
            }
        }
    }

    # Detect failure patterns
    if ($line -match 'HTTP_STATUS_NOT_FOUND' -or $line -match 'returns 404') {
        $lastUpdateKey = $updates.Keys | Select-Object -Last 1
        if ($lastUpdateKey) {
            $updates[$lastUpdateKey]['Failed'] = $true
            $updates[$lastUpdateKey]['Lines'] += $line
        }
    }
}

$failedUpdates = $updates.GetEnumerator() | Where-Object { $_.Value.Failed -eq $true }

if ($failedUpdates.Count -eq 0) {
    Write-Host "No failed downloads found in log."
    exit 0
}

Write-Host "Failed Downloads Found:`n"

# Prepare output collection
$results = @()

foreach ($update in $failedUpdates) {
    $id = $update.Key
    $match = $csvData | Where-Object { $_.UpdateID -eq $id }

    if ($match) {
        foreach ($m in $match) {
            $obj = [PSCustomObject]@{
                UpdateID = $id
                Title    = $m.Title
                Date     = $m.Date
                Version  = $m.Version
                Severity = $m.Severity
            }
            $results += $obj
            Write-Host "UpdateID: $id"
            Write-Host "  Title : $($m.Title)"
            Write-Host "  Date  : $($m.Date)"
            Write-Host "  Version: $($m.Version)"
            Write-Host "  Severity: $($m.Severity)"
            Write-Host ""
        }
    }
    else {
        Write-Host "UpdateID: $id (not found in CSV)"
        $results += [PSCustomObject]@{
            UpdateID = $id
            Title    = "Not found in CSV"
            Date     = ""
            Version  = ""
            Severity = ""
        }
        Write-Host ""
    }
}

# Export to file if requested
if ($Output) {
    $outputDir = Split-Path -Parent $Output
    if (-not (Test-Path $outputDir)) {
        try {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
            Write-Host "Created output directory: $outputDir"
        } catch {
            Write-Host "Failed to create output directory: $_"
        }
    }

    try {
        $results | Export-Csv -Path $Output -NoTypeInformation -Encoding UTF8
        Write-Host "Results exported to: $Output"
    } catch {
        Write-Host "Failed to write output CSV: $_"
    }
}

Write-Host ""
Write-Host "Consider republishing the updates above. See this KB for details:"
Write-Host "https://patchmypc.com/kb/when-how-republish-patch-my/"
