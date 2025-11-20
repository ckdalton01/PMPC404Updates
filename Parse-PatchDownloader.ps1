<#
.SYNOPSIS
    Parse the SCCM PatchDownloader.log and cross-reference failed downloads with
    the Patch My PC publishing history.

.DESCRIPTION
    This tool analyzes the PatchDownloader.log (from SCCM/WSUS) and identifies updates
    that failed to download with HTTP 404 errors or related failure conditions.
    It then cross-references those UpdateIDs with Patch My PC's publishing history
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

.PARAMETER SMS
    Optional. Switch to automatically detect SCCM installation and use the
    appropriate log file path from the registry.

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

.EXAMPLE
    # Use SMS registry to auto-detect SCCM installation path
    .\Parse-PatchDownloader.ps1 -SMS

.NOTES
    Author: C. Dalton
    Date: 2025-11-06
#>

param(
    [string]$LogFile = "$env:ProgramFiles\SMS_CCM\Logs\PatchDownloader.log",
    [string]$CsvFile = "$env:ProgramFiles\Patch My PC\Patch My PC Publishing Service\PatchMyPC-PublishingHistory.csv",
    [string]$ZipFile,
    [string]$Output,
    [switch]$SMS
)

Write-Host ""
Write-Host "=== PatchDownloader Log Parser ==="

# Handle -SMS switch to auto-detect SCCM paths
$siteCode = $null
if ($SMS) {
    Write-Host "SMS mode enabled, detecting SCCM installation..."
    
    try {
        # Get site code - specify property name exactly as it appears in registry
        $siteCodeValue = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\SMS\Identification" -Name "Site Code" -ErrorAction Stop
        $siteCode = $siteCodeValue.'Site Code'
        
        if ($siteCode) {
            Write-Host "Site Code detected: $siteCode"
            
            # Get installation directory - specify property name exactly as it appears in registry
            $installDirValue = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\SMS\Identification" -Name "Installation Directory" -ErrorAction Stop
            $installDir = $installDirValue.'Installation Directory'
            
            if ($installDir) {
                Write-Host "Installation Directory: $installDir"
                
                # Remove "Microsoft Configuration Manager" and replace with "SMS_CCM\Logs\PatchDownloader.log"
                # Handle various possible path formats
                $basePath = $installDir -replace '\\Microsoft Configuration Manager\\?$', ''
                $basePath = $basePath.TrimEnd('\')
                $LogFile = Join-Path $basePath "SMS_CCM\Logs\PatchDownloader.log"
                
                Write-Host "Using SMS log path: $LogFile"
            }
            else {
                Write-Host "Warning: Installation Directory registry value is empty"
            }
        }
        else {
            Write-Host "Warning: Site Code registry value is empty"
        }
    }
    catch [System.Management.Automation.ItemNotFoundException] {
        Write-Host "Warning: SMS registry key not found. Ensure SCCM client is installed."
    }
    catch [System.Management.Automation.PSArgumentException] {
        Write-Host "Warning: SMS registry property not found. Registry structure may be different."
    }
    catch {
        Write-Host "Warning: Could not read SMS registry keys: $($_.Exception.Message)"
    }
    
    Write-Host ""
}
# Auto-locate Patch My PC PublishingHistory.csv when -SMS is used
if ($SMS) {
    Write-Host "Detecting Patch My PC Publishing Service path..."

    try {
        $pmpc = Get-ItemProperty -Path "HKLM:\SOFTWARE\Patch My PC Publishing Service" -Name "Path" -ErrorAction Stop
        $pmpcPath = $pmpc.Path

        if ($pmpcPath) {
            Write-Host "Patch My PC path detected: $pmpcPath"

            # Construct expected CSV path
            $autoCsv = Join-Path $pmpcPath "PatchMyPC-PublishingHistory.csv"

            if (Test-Path $autoCsv) {
                # Did the user also specify their own CSV?
                if ($PSBoundParameters.ContainsKey('CsvFile')) {
                    Write-Host "WARNING: Both -SMS and -CsvFile were specified. Using CsvFile parameter: $CsvFile"
                }
                else {
                    Write-Host "Using Patch My PC PublishingHistory CSV: $autoCsv"
                    $CsvFile = $autoCsv
                }
            }
            else {
                Write-Host "Warning: PublishingHistory.csv not found at detected path."
                Write-Host "Expected: $autoCsv"
            }
        }
        else {
            Write-Host "Warning: Patch My PC 'Path' registry value is empty."
        }
    }
    catch {
        Write-Host "Warning: Could not read Patch My PC Publishing Service registry key: $($_.Exception.Message)"
    }

    Write-Host ""
}

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
        
        # Try expected paths first
        $LogFile = Join-Path $tempExtractPath "Client\PatchDownloader.log"
        $CsvFile = Join-Path $tempExtractPath "PatchMyPC\PatchMyPC-PublishingHistory.csv"
        
        # If PatchDownloader.log not found in expected location, search recursively
        if (-not (Test-Path $LogFile)) {
            Write-Host "PatchDownloader.log not found in expected location, searching extracted files..."
            $foundLog = Get-ChildItem -Path $tempExtractPath -Filter "PatchDownloader.log" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            
            if ($foundLog) {
                $LogFile = $foundLog.FullName
                Write-Host "Found PatchDownloader.log at: $LogFile"
            }
            else {
                Write-Host "ERROR: PatchDownloader.log not found in the extracted zip file."
                Write-Host "Searched in: $tempExtractPath"
                # Cleanup before exit
                if (Test-Path $tempExtractPath) {
                    Remove-Item -Path $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
                }
                exit 1
            }
        }
        
        # If CSV not found in expected location, search recursively
        if (-not (Test-Path $CsvFile)) {
            Write-Host "PatchMyPC-PublishingHistory.csv not found in expected location, searching extracted files..."
            $foundCsv = Get-ChildItem -Path $tempExtractPath -Filter "PatchMyPC-PublishingHistory.csv" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            
            if ($foundCsv) {
                $CsvFile = $foundCsv.FullName
                Write-Host "Found PatchMyPC-PublishingHistory.csv at: $CsvFile"
            }
        }
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
    Write-Host "ERROR: Log file not found: $LogFile"
    Write-Host "If the log file is in another location, use -LogFile <path>"
    if ($SMS) {
        Write-Host "Note: -SMS flag was used but path detection may have failed"
    }
    exit 1
}
if (-not (Test-Path $CsvFile)) {
    if ($SMS) {
        $csvData = @()  # Empty array so later logic works
    } else {
        Write-Host "ERROR: CSV file not found: $CsvFile"
        Write-Host "If the CSV file is in another location, use -CsvFile <path>"
        exit 1
    }
}



# Import CSV if available
$csvData = @()  # Initialize as empty array
if (Test-Path $CsvFile) {
    try {
        $csvData = Import-Csv -Path $CsvFile -ErrorAction Stop
        if ($csvData.Count -eq 0) {
            Write-Host "WARNING: CSV file is empty"
            if (-not $SMS) {
                Write-Host "CSV is required when -SMS is not used."
                exit 1
            }
        }
    }
    catch {
        Write-Host "ERROR: Failed to import CSV file: $($_.Exception.Message)"
        if (-not $SMS) {
            exit 1
        } else {
            Write-Host "Continuing with WMI only (SMS mode)."
            $csvData = @()
        }
    }
}
else {
    if (-not $SMS) {
        Write-Host "ERROR: CSV file not found: $CsvFile"
        exit 1
    } else {
        Write-Host "CSV file not found, continuing with WMI only (SMS mode)."
    }
}


try {
    $logLines = Get-Content -Path $LogFile -ErrorAction Stop
    if ($logLines.Count -eq 0) {
        Write-Host "WARNING: Log file is empty"
    }
}
catch {
    Write-Host "ERROR: Failed to read log file: $($_.Exception.Message)"
    exit 1
}

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
$results = @()   # Initialize as an empty array

# === UPDATED BLOCK WITH WMI INTEGRATION ===
foreach ($update in $failedUpdates) {
    $id = $update.Key
    $wmiData = $null

    if ($SMS -and $siteCode) {
        try {
            $wmiData = Get-CimInstance -ClassName SMS_SoftwareUpdate `
                -Namespace "root\SMS\site_$siteCode" `
                -Filter "CI_UniqueID = '$id'" |
                Select-Object LocalizedDisplayName, DateCreated, CI_UniqueID
        } catch {
            Write-Host "Warning: WMI query failed for UpdateID $($id): $($_.Exception.Message)"
        }
    }

    $match = $csvData | Where-Object {
        $_.UpdateID -eq $id -and
        ($_.Operation -eq "Update Published" -or
         $_.Operation -eq "Update Revised" -or
         $_.Operation -eq "WSUS Update Published" -or
         $_.Operation -eq "WSUS Update Revised")
    } | Select-Object -First 1

    $obj = [PSCustomObject]@{
        UpdateID = $id
        Title    = if ($match) { $match.Title } elseif ($wmiData) { $wmiData.LocalizedDisplayName } else { "Not found" }
        Date     = if ($match) { $match.Date } elseif ($wmiData) { $wmiData.DateCreated } else { "" }
        Version  = if ($match) { $match.Version } else { "" }
        Severity = if ($match) { $match.Severity } else { "" }
        Source   = if ($match -and $wmiData) { "CSV + WMI" } elseif ($match) { "CSV" } elseif ($wmiData) { "WMI" } else { "None" }
    }

    $results += $obj

    Write-Host "UpdateID: $id"
    Write-Host "  Title : $($obj.Title)"
    Write-Host "  Date  : $($obj.Date)"
    Write-Host "  Version: $($obj.Version)"
    Write-Host "  Severity: $($obj.Severity)"
    Write-Host "  Source: $($obj.Source)"
    Write-Host ""
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