param(
    [Parameter(Mandatory=$true)]
    [string]$LogFile,

    [Parameter(Mandatory=$true)]
    [string]$CsvFile
)

# Import CSV data
$csvData = Import-Csv -Path $CsvFile

# Read log file
$logLines = Get-Content -Path $LogFile

# Hashtable to store UpdateIDs and failure status
$updates = @{}

# Regex to extract UpdateID from log line
$updateIdPattern = 'Download destination\s*=\s*.*?\\(?<UpdateID>[0-9a-fA-F-]+)\.1\\'

for ($i = 0; $i -lt $logLines.Count; $i++) {
    $line = $logLines[$i]

    # Check for "Download destination" lines to extract UpdateID
    if ($line -match $updateIdPattern) {
        $currentUpdateID = $matches['UpdateID']
        if (-not $updates.ContainsKey($currentUpdateID)) {
            $updates[$currentUpdateID] = @{
                Failed = $false
                Lines  = @($line)
            }
        }
    }

    # If current line indicates HTTP 404, mark most recent UpdateID as failed
    if ($line -match 'HTTP_STATUS_NOT_FOUND' -or $line -match 'returns 404') {
        # Try to backtrack to the most recent UpdateID
        $lastUpdateKey = $updates.Keys | Select-Object -Last 1
        if ($lastUpdateKey) {
            $updates[$lastUpdateKey]['Failed'] = $true
            $updates[$lastUpdateKey]['Lines'] += $line
        }
    }
}

# Filter failed updates
$failedUpdates = $updates.GetEnumerator() | Where-Object { $_.Value.Failed -eq $true }

if ($failedUpdates.Count -eq 0) {
    Write-Host "No failed downloads found in log."
    exit
}

Write-Host "Failed Downloads Found:`n"

# Loop through failed update IDs and match against CSV
foreach ($update in $failedUpdates) {
    $id = $update.Key

    $match = $csvData | Where-Object { $_.UpdateID -eq $id }

    if ($match) {
        Write-Host "UpdateID: $id"
        Write-Host "  Title : $($match.Title)"
        Write-Host "  Date  : $($match.Date)"
        Write-Host "  Version: $($match.Version)"
        Write-Host "  Severity: $($match.Severity)"
        Write-Host ""
    } else {
        Write-Host "UpdateID: $id (not found in CSV)"
        Write-Host ""
    }
}
