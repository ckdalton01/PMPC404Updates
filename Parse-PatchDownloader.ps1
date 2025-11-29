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

.EXAMPLE
    # Run with verbose output
    .\Parse-PatchDownloader.ps1 -Verbose

.NOTES
    Author: C. Dalton
    Date: 2025-11-06
    Log file location: $env:TEMP\Parse-PatchDownloader.log
#>

param(
    [string]$LogFile = "$env:ProgramFiles\SMS_CCM\Logs\PatchDownloader.log",
    [string]$CsvFile = "$env:ProgramFiles\Patch My PC\Patch My PC Publishing Service\PatchMyPC-PublishingHistory.csv",
    [string]$ZipFile,
    [string]$Output,
    [switch]$SMS
)

# Initialize log file
$ScriptLogFile = Join-Path $env:TEMP "Parse-PatchDownloader.log"
$ScriptStartTime = Get-Date

# Function to write to both console and log file in CMTrace format
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Verbose')]
        [string]$Level = 'Info'
    )
    
    # Map log levels to CMTrace severity
    # 1 = Informational, 2 = Warning, 3 = Error
    $severity = switch ($Level) {
        'Error'   { 3 }
        'Warning' { 2 }
        'Verbose' { 1 }
        'Info'    { 1 }
        default   { 1 }
    }
    
    # Get script context information
    $scriptName = Split-Path -Leaf $MyInvocation.ScriptName
    if (-not $scriptName) { $scriptName = "Parse-PatchDownloader.ps1" }
    
    # Get timestamp components
    $time = Get-Date -Format "HH:mm:ss.fff"
    $date = Get-Date -Format "MM-dd-yyyy"
    
    # Get timezone bias
    $tzBias = [System.TimeZoneInfo]::Local.GetUtcOffset((Get-Date)).TotalMinutes
    
    # Build CMTrace format log line
    # Format: <![LOG[Message]LOG]!><time="HH:mm:ss.fff+/-TZBias" date="MM-dd-yyyy" component="ComponentName" context="" type="Severity" thread="ThreadID" file="ScriptName">
    $cmTraceLog = "<![LOG[$Message]LOG]!><time=`"$time$($tzBias)`" date=`"$date`" component=`"$scriptName`" context=`"`" type=`"$severity`" thread=`"$PID`" file=`"$scriptName`">"
    
    # Write to log file
    try {
        Add-Content -Path $ScriptLogFile -Value $cmTraceLog -ErrorAction SilentlyContinue
    }
    catch {
        # Silently fail if we can't write to log
    }
    
    # Write to console based on level
    switch ($Level) {
        'Error'   { Write-Host $Message -ForegroundColor Red }
        'Warning' { Write-Host $Message -ForegroundColor Yellow }
        'Verbose' { Write-Verbose $Message }
        'Info'    { Write-Host $Message }
    }
}

# Initialize log file (append mode)
try {
    # Ensure log file exists, create if it doesn't, but don't overwrite
    if (-not (Test-Path $ScriptLogFile)) {
        "" | Set-Content -Path $ScriptLogFile -ErrorAction Stop
    }
    Write-Log "========== Script started at $ScriptStartTime ==========" -Level Verbose
}
catch {
    Write-Verbose "Warning: Could not initialize log file at $ScriptLogFile"
}

Write-Verbose ""
Write-Verbose "=== PatchDownloader Log Parser ===" -Verbose
Write-Log "PatchDownloader Log Parser started" -Level Verbose

# Handle -SMS switch to auto-detect SCCM paths
$siteCode = $null
if ($SMS) {
    Write-Verbose "SMS mode enabled, detecting SCCM installation..." -Verbose
    Write-Log "SMS mode enabled, detecting SCCM installation..." -Level Verbose
    
    try {
        # Get site code - specify property name exactly as it appears in registry
        $siteCodeValue = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\SMS\Identification" -Name "Site Code" -ErrorAction Stop
        $siteCode = $siteCodeValue.'Site Code'
        
        if ($siteCode) {
            Write-Verbose "Site Code detected: $siteCode" -Verbose
            Write-Log "Site Code detected: $siteCode" -Level Verbose
            
            # Get installation directory - specify property name exactly as it appears in registry
            $installDirValue = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\SMS\Identification" -Name "Installation Directory" -ErrorAction Stop
            $installDir = $installDirValue.'Installation Directory'
            
            if ($installDir) {
                Write-Log "Installation Directory: $installDir" -Level Verbose
                
                # Remove "Microsoft Configuration Manager" and replace with "SMS_CCM\Logs\PatchDownloader.log"
                # Handle various possible path formats
                $basePath = $installDir -replace '\\Microsoft Configuration Manager\\?$', ''
                $basePath = $basePath.TrimEnd('\')
                $LogFile = Join-Path $basePath "SMS_CCM\Logs\PatchDownloader.log"
                
                Write-Verbose "Using SMS log path: $LogFile" -Verbose
                Write-Log "Using SMS log path: $LogFile" -Level Verbose
            }
            else {
                Write-Log "Installation Directory registry value is empty" -Level Warning
            }
        }
        else {
            Write-Log "Site Code registry value is empty" -Level Warning
        }
    }
    catch [System.Management.Automation.ItemNotFoundException] {
        Write-Log "SMS registry key not found. Ensure SCCM client is installed." -Level Warning
    }
    catch [System.Management.Automation.PSArgumentException] {
        Write-Log "SMS registry property not found. Registry structure may be different." -Level Warning
    }
    catch {
        Write-Log "Could not read SMS registry keys: $($_.Exception.Message)" -Level Warning
    }
    
    Write-Verbose ""
}

# Auto-locate Patch My PC PublishingHistory.csv when -SMS is used
if ($SMS) {
    Write-Log "Detecting Patch My PC Publishing Service path..." -Level Verbose
    Write-Verbose "Detecting Patch My PC Publishing Service path..." -Verbose

    try {
        $pmpc = Get-ItemProperty -Path "HKLM:\SOFTWARE\Patch My PC Publishing Service" -Name "Path" -ErrorAction Stop
        $pmpcPath = $pmpc.Path

        if ($pmpcPath) {
            Write-Log "Patch My PC path detected: $pmpcPath" -Level Verbose

            # Construct expected CSV path
            $autoCsv = Join-Path $pmpcPath "PatchMyPC-PublishingHistory.csv"

            if (Test-Path $autoCsv) {
                # Did the user also specify their own CSV?
                if ($PSBoundParameters.ContainsKey('CsvFile')) {
                    Write-Log "Both -SMS and -CsvFile were specified. Using CsvFile parameter: $CsvFile" -Level Warning
                }
                else {
                    Write-Log "Using Patch My PC PublishingHistory CSV: $autoCsv" -Level Verbose
                    Write-Verbose "Using Patch My PC PublishingHistory CSV: $autoCsv" -Verbose
                    $CsvFile = $autoCsv
                }
            }
            else {
                Write-Log "PublishingHistory.csv not found at detected path. Expected: $autoCsv" -Level Warning
            }
        }
        else {
            Write-Log "Patch My PC 'Path' registry value is empty." -Level Warning
        }
    }
    catch {
        Write-Log "Could not read Patch My PC Publishing Service registry key: $($_.Exception.Message)" -Level Warning
    }

    Write-Verbose ""
}

# Handle zip file extraction
$tempExtractPath = $null
if ($ZipFile) {
    if (-not (Test-Path $ZipFile)) {
        Write-Log "Zip file not found: $ZipFile" -Level Error
        exit 1
    }
    
    Write-Log "ZipFile: $ZipFile" -Level Verbose
    Write-Log "Extracting zip file..." -Level Verbose
    Write-Verbose "Extracting zip file..." -Verbose
    
    $tempExtractPath = Join-Path $env:TEMP "PatchDownloaderParser_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    
    try {
        Expand-Archive -Path $ZipFile -DestinationPath $tempExtractPath -Force
        Write-Log "Extracted to: $tempExtractPath" -Level Verbose
        
        # Try expected paths first
        $LogFile = Join-Path $tempExtractPath "Client\PatchDownloader.log"
        $CsvFile = Join-Path $tempExtractPath "PatchMyPC\PatchMyPC-PublishingHistory.csv"
        
        # If PatchDownloader.log not found in expected location, search recursively
        if (-not (Test-Path $LogFile)) {
            Write-Log "PatchDownloader.log not found in expected location, searching extracted files..." -Level Verbose
            Write-Verbose "PatchDownloader.log not found in expected location, searching extracted files..." -Verbose
            
            $foundLog = Get-ChildItem -Path $tempExtractPath -Filter "PatchDownloader.log" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            
            if ($foundLog) {
                $LogFile = $foundLog.FullName
                Write-Log "Found PatchDownloader.log at: $LogFile" -Level Verbose
                Write-Verbose "Found PatchDownloader.log at: $LogFile" -Verbose
            }
            else {
                Write-Log "PatchDownloader.log not found in the extracted zip file. Searched in: $tempExtractPath" -Level Error
                Write-Verbose "PatchDownloader.log not found in the extracted zip file. Searched in: $tempExtractPath" -Verbose
                # Cleanup before exit
                if (Test-Path $tempExtractPath) {
                    Remove-Item -Path $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
                }
                exit 1
            }
        }
        
        # If CSV not found in expected location, search recursively
        if (-not (Test-Path $CsvFile)) {
            Write-Log "PatchMyPC-PublishingHistory.csv not found in expected location, searching extracted files..." -Level Verbose
            $foundCsv = Get-ChildItem -Path $tempExtractPath -Filter "PatchMyPC-PublishingHistory.csv" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            
            if ($foundCsv) {
                $CsvFile = $foundCsv.FullName
                Write-Log "Found PatchMyPC-PublishingHistory.csv at: $CsvFile" -Level Verbose
            }
        }
    }
    catch {
        Write-Log "Failed to extract zip file: $_" -Level Error
        exit 1
    }
}

Write-Log "LogFile: $LogFile" -Level Verbose
Write-Log "CsvFile: $CsvFile" -Level Verbose
if ($Output) { Write-Log "Output : $Output" -Level Verbose }
Write-Verbose ""

# Validate files
if (-not (Test-Path $LogFile)) {
    Write-Log "Log file not found: $LogFile" -Level Error
    Write-Host "If the log file is in another location, use -LogFile <path>"
    Write-Host "If running on SCCM Primary Site Server, use -SMS"
    if ($SMS) {
        Write-Host "Note: -SMS flag was used but path detection may have failed"
    }
    exit 1
}
if (-not (Test-Path $CsvFile)) {
    if ($SMS) {
        $csvData = @()  # Empty array so later logic works
    } else {
        Write-Log "CSV file not found: $CsvFile" -Level Error
        Write-Host "If the CSV file is in another location, use -CsvFile <path>"
        Write-Host "If running on Primary Site Server, use -SMS"
        exit 1
    }
}

# Import CSV if available
$csvData = @()  # Initialize as empty array
if (Test-Path $CsvFile) {
    try {
        Write-Log "Importing CSV file..." -Level Verbose
        $csvData = Import-Csv -Path $CsvFile -ErrorAction Stop
        if ($csvData.Count -eq 0) {
            Write-Log "CSV file is empty" -Level Warning
            if (-not $SMS) {
                Write-Host "CSV is required when -SMS is not used."
                exit 1
            }
        }
        else {
            Write-Log "CSV imported successfully. $($csvData.Count) records found." -Level Verbose
        }
    }
    catch {
        Write-Log "Failed to import CSV file: $($_.Exception.Message)" -Level Error
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
        Write-Log "CSV file not found: $CsvFile" -Level Error
        exit 1
    } else {
        Write-Log "CSV file not found, continuing with WMI only (SMS mode)." -Level Verbose
    }
}

try {
    Write-Log "Reading log file..." -Level Verbose
    $logLines = Get-Content -Path $LogFile -ErrorAction Stop
    if ($logLines.Count -eq 0) {
        Write-Log "Log file is empty" -Level Warning
    }
    else {
        Write-Log "Log file read successfully. $($logLines.Count) lines found." -Level Verbose
    }
}
catch {
    Write-Log "Failed to read log file: $($_.Exception.Message)" -Level Error
    exit 1
}

Write-Log "Parsing log file for failed downloads..." -Level Verbose
$updates = @{}
$updateIdPattern = 'Download destination\s*=\s*.*?\\(?<UpdateID>[0-9a-fA-F-]+)\.1\\'
$currentUpdateID = $null

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

        if ($currentUpdateID) {
            $updates[$currentUpdateID]['Failed'] = $true
            $updates[$currentUpdateID]['Lines'] += $line
        }
    }
}

$failedUpdates = $updates.GetEnumerator() | Where-Object { $_.Value.Failed -eq $true }
Write-Log "Found $($failedUpdates.Count) failed downloads" -Level Verbose

if ($failedUpdates.Count -eq 0) {
    Write-Host "No failed downloads found in log."
    Write-Log "No failed downloads found in log." -Level Info
    exit 0
}

Write-Host "Failed Downloads Found:`n"
Write-Log "Processing failed updates..." -Level Verbose
$results = @()   # Initialize as an empty array

# === UPDATED BLOCK WITH WMI INTEGRATION ===
foreach ($update in $failedUpdates) {
    $id = $update.Key
    $wmiData = $null

    if ($SMS -and $siteCode) {
        try {
            Write-Log "Querying WMI for UpdateID: $id" -Level Verbose
            $wmiData = Get-CimInstance -ClassName SMS_SoftwareUpdate `
                -Namespace "root\SMS\site_$siteCode" `
                -Filter "CI_UniqueID = '$id'" |
                Select-Object LocalizedDisplayName, DateCreated, CI_UniqueID
        } catch {
            Write-Log "WMI query failed for UpdateID $($id): $($_.Exception.Message)" -Level Warning
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
    
    Write-Log "Processed UpdateID: $id | Title: $($obj.Title) | Source: $($obj.Source)" -Level Verbose
}

# Export to file if requested
if ($Output) {
    $outputDir = Split-Path -Parent $Output
    if (-not (Test-Path $outputDir)) {
        try {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
            Write-Log "Created output directory: $outputDir" -Level Verbose
        } catch {
            Write-Log "Failed to create output directory: $_" -Level Error
        }
    }

    try {
        $results | Export-Csv -Path $Output -NoTypeInformation -Encoding UTF8
        Write-Host "Results exported to: $Output"
        Write-Log "Results exported to: $Output" -Level Verbose
    } catch {
        Write-Log "Failed to write output CSV: $_" -Level Error
    }
}

Write-Host ""
Write-Host "Consider republishing the updates above. See this KB for details:"
Write-Host "https://patchmypc.com/kb/when-how-republish-patch-my/"

# Cleanup temporary extraction folder
if ($tempExtractPath -and (Test-Path $tempExtractPath)) {
    try {
        Remove-Item -Path $tempExtractPath -Recurse -Force
        Write-Log "Cleaned up temporary files at: $tempExtractPath" -Level Verbose
        Write-Host ""
        Write-Host "Cleaned up temporary files."
    }
    catch {
        Write-Log "Could not clean up temporary folder: $tempExtractPath - $_" -Level Warning
        Write-Host ""
        Write-Host "Warning: Could not clean up temporary folder: $tempExtractPath"
    }
}

# Log script completion
$ScriptEndTime = Get-Date
$Duration = $ScriptEndTime - $ScriptStartTime
Write-Log "Script completed at $ScriptEndTime (Duration: $($Duration.TotalSeconds) seconds)" -Level Verbose
Write-Log "========== Script execution completed ==========" -Level Verbose
Write-Log "Log file location: $ScriptLogFile" -Level Verbose
Write-Host ""
Write-Host "Script log saved to: $ScriptLogFile" -ForegroundColor Cyan