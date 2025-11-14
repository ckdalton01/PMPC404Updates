<#
.SYNOPSIS
    Parse the SCCM PatchDownloader.log and cross-reference failed downloads with
    the Patch My PC publishing history.

.DESCRIPTION
    This tool analyzes the PatchDownloader.log (from SCCM/WSUS) and identifies updates
    that failed to download with HTTP 404 errors or related failure conditions.
    It then cross-references those UpdateIDs with Patch My PC’s publishing history
    to produce a detailed failure report.

    Defaults:
      - LogFile: C:\Program Files\SMS_CCM\Logs\PatchDownloader.log
      - CsvFile: C:\Program Files\Patch My PC\Patch My PC Publishing Service\PatchMyPC-PublishingHistory.csv

.PARAMETER LogFile
    Optional. Path to PatchDownloader.log.

.PARAMETER CsvFile
    Optional. Path to Patch My PC Publishing History CSV.

.PARAMETER ZipFile
    Optional. A ZIP file containing a PatchDownloader.log. If provided, the ZIP
    will be extracted and the log parsed automatically.

.PARAMETER Output
    Optional. Path to export the final results as a CSV.

.EXAMPLE
    # Use default log and CSV paths
    .\Parse-PatchDownloader.ps1

.EXAMPLE
    # Provide explicit log and CSV paths
    .\Parse-PatchDownloader.ps1 -LogFile "D:\Logs\PatchDownloader.log" -CsvFile "D:\PMPC\PublishingHistory.csv"

.EXAMPLE
    # Export results to CSV
    .\Parse-PatchDownloader.ps1 -Output "C:\Reports\FailedUpdates.csv"

.EXAMPLE
    # Use a ZIP file
    .\Parse-PatchDownloader.ps1 -ZipFile "C:\Temp\logs.zip"

.EXAMPLE
    # Use a ZIP file and export results
    .\Parse-PatchDownloader.ps1 -ZipFile "C:\Temp\logs.zip" -Output "C:\Results\failed.csv"

.NOTES
    Author: C. Dalton
    Date: 2025-11-06
#>

param(
    [string]$LogFile = "$env:ProgramFiles\SMS_CCM\Logs\PatchDownloader.log",
    [string]$CsvFile = "$env:ProgramFiles\Patch My PC\Patch My PC Publishing Service\PatchMyPC-PublishingHistory.csv",
    [string]$ZipFile,
    [string]$Output
)

Write-Host ""
Write-Host "=== PatchDownloader Log Parser ==="

# Handle zip file extraction
$tempExtractPath = $null
if ($ZipFile) {
    if (-not (Test-Path $ZipFile)) {
        Write-Host "Zip file not found: $ZipFile"
        exit 1
    }
    
    Write-Host "ZipFile: $ZipFile"
    Write-Host "Extracting zip file..."
    
    $tempExtractPath = Join-Path $env:TEMP "PatchDownloaderParser_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    
    try {
        Expand-Archive -Path $ZipFile -DestinationPath $tempExtractPath -Force
        Write-Host "Extracted to: $tempExtractPath"
        
        # Override LogFile and CsvFile paths
        $LogFile = Join-Path $tempExtractPath "Client\PatchDownloader.log"
        $CsvFile = Join-Path $tempExtractPath "PatchMyPC\PatchMyPC-PublishingHistory.csv"
    }
    catch {
        Write-Host "Failed to extract zip file: $_"
        exit 1
    }
}

Write-Host "LogFile: $LogFile"
Write-Host "CsvFile: $CsvFile"
if ($Output) { Write-Host "Output : $Output" }
Write-Host ""

# Validate files
if (-not (Test-Path $LogFile)) {
    Write-Host "Log file not found: $LogFile"
	Write-Host "If the log file is in another location, use -LogFile"
    exit 1
}
if (-not (Test-Path $CsvFile)) {
    Write-Host "CSV file not found: $CsvFile"
	Write-Host "If the CSV file is in another location, use -CsvFile"
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
    $match = $csvData | Where-Object { 
        $_.UpdateID -eq $id -and 
        ($_.Operation -eq "Update Published" -or 
         $_.Operation -eq "Update Revised" -or 
         $_.Operation -eq "WSUS Update Published" -or 
         $_.Operation -eq "WSUS Update Revised")
    } | Select-Object -First 1

    if ($match) {
        $obj = [PSCustomObject]@{
            UpdateID = $id
            Title    = $match.Title
            Date     = $match.Date
            Version  = $match.Version
            Severity = $match.Severity
        }
        $results += $obj
        Write-Host "UpdateID: $id"
        Write-Host "  Title : $($match.Title)"
        Write-Host "  Date  : $($match.Date)"
        Write-Host "  Version: $($match.Version)"
        Write-Host "  Severity: $($match.Severity)"
        Write-Host ""
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

# Cleanup temporary extraction folder
if ($tempExtractPath -and (Test-Path $tempExtractPath)) {
    try {
        Remove-Item -Path $tempExtractPath -Recurse -Force
        Write-Host ""
        Write-Host "Cleaned up temporary files."
    }
    catch {
        Write-Host ""
        Write-Host "Warning: Could not clean up temporary folder: $tempExtractPath"
    }
}
