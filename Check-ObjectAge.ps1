#############################################################################################
## Description: Check the age of files and directories and optionally export a CSV report
##
## Author: Matteo Z.
#############################################################################################

# nables advanced script behavior and common parameters such as -Verbose, -Debug, and -ErrorAction
[CmdletBinding()]
param(
    [Alias('P')]
    [string]$Path,

    [Alias('D')]
    [ValidateRange(1, 36500)]
    [int]$Day,

    [switch]$NoRecurse,
    [string]$OutputFile,
    [string]$LogFile,

    [Alias('-json')]
    [switch]$Json,

    [Alias('H')]
    [switch]$Help
)


function Show-Usage {
    Write-Output @'
Usage:
  .\Check-ObjectAge.ps1 -Path <DIRECTORY> -Day <DAYS> [-NoRecurse] [-OutputFile <CSV_PATH>] [-LogFile <LOG_PATH>] [-Json]
  .\Check-ObjectAge.ps1 -Help

Parameters:
  -Path, -P     Directory to inspect (required).
  -Day, -D      Age threshold in days, from 1 to 36500.
  -NoRecurse    Inspect immediate children only; recursive scanning is the default.
  -OutputFile   Export the full list of old objects and scan errors to CSV.
  -LogFile      Append scan diagnostics to the specified log file.
  --json        JSON output.
  -Help, -H     Display this usage without scanning or creating files.

Examples:
  .\Check-ObjectAge.ps1 -P 'C:\Exports' -D 2
  .\Check-ObjectAge.ps1 -P 'C:\Exports' -D 2 -NoRecurse
  .\Check-ObjectAge.ps1 -P 'C:\Exports' -D 2 -OutputFile 'C:\Reports\object-age.csv'
  .\Check-ObjectAge.ps1 -P 'C:\Exports' -D 2 -Json

Output and log parent directories must already exist.
Age is based on LastWriteTime. Junctions and symbolic links are not traversed.
'@
}


# A dictionary containing the parameters explicitly supplied by the caller and their values
if ($Help -or $PSBoundParameters.Count -eq 0) {
    Show-Usage
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Path) -or -not $PSBoundParameters.ContainsKey('Day')) {
    if ($Json) {
        [pscustomobject]@{
            Status   = 'UNKNOWN'
            ExitCode = 3
            Summary  = 'Both -Path and -Day are required.'
        } | ConvertTo-Json
    } else {
        Write-Output 'UNKNOWN - Both -Path and -Day are required.'
        Show-Usage
    }

    exit 3
}

$ErrorActionPreference = 'Stop'
$scanTime = Get-Date
# Creates an empty, growable list of objects
$oldObjects = [System.Collections.Generic.List[object]]::new()
$scanErrors = [System.Collections.Generic.List[object]]::new()
$scannedCount = 0
$exitCode = 3
$status = 'UNKNOWN'
$summary = ''

function Write-ScanLog {
    param([string]$Level, [string]$Message)

    if (-not $LogFile) {
        return
    }

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
}


try {
    $cutoff = $scanTime.AddDays(-$Day)

    if (-not (Test-Path -LiteralPath $Path -PathType Container -ErrorAction Stop)) {
        $summary = "CRITICAL - Directory not found: $Path"
        $exitCode = 2
        $status = 'CRITICAL'
    } else {
        $rootPath = (Get-Item -LiteralPath $Path -ErrorAction Stop).FullName
        Write-ScanLog -Level 'INFO' -Message "Starting scan: $rootPath; threshold: $Day day(s); recursive: $(-not $NoRecurse)"

        # Creates an empty stack of strings, where the last item added is the first removed
        $pendingDirectories = [System.Collections.Generic.Stack[string]]::new()
        $pendingDirectories.Push($rootPath)

        while ($pendingDirectories.Count -gt 0) {
            $directory = $pendingDirectories.Pop()

            try {
                $children = @(Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop)
            } catch {
                $message = $_.Exception.Message
                # Creates an object with custom properties, useful for structured results and CSV exports
                $scanErrors.Add([pscustomobject]@{ Path = $directory; Message = $message })
                Write-ScanLog -Level 'ERROR' -Message "Cannot list '$directory': $message"
                continue
            }

            foreach ($child in $children) {
                $scannedCount++

                if ($child.LastWriteTime -lt $cutoff) {
                    $oldObjects.Add([pscustomobject]@{
                        Status = 'CRITICAL'
                        Type = if ($child.PSIsContainer) { 'Directory' } else { 'File' }
                        Path = $child.FullName
                        LastWriteTime = $child.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
                        AgeDays = [math]::Round(($scanTime - $child.LastWriteTime).TotalDays, 2)
                        Details = ''
                    })
                }

                # Do not follow junctions or symbolic links: they can create loops
                if (-not $NoRecurse -and $child.PSIsContainer -and
                    -not ($child.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                    $pendingDirectories.Push($child.FullName)
                }
            }
        }

        if ($scanErrors.Count -gt 0) {
            $status = 'UNKNOWN'
            $exitCode = 3
        } elseif ($oldObjects.Count -gt 0) {
            $status = 'CRITICAL'
            $exitCode = 2
        } else {
            $status = 'OK'
            $exitCode = 0
        }

        $summary = "$status - $($oldObjects.Count) old object(s); $scannedCount scanned; $($scanErrors.Count) inaccessible directories; threshold $Day day(s)"
    }

    if (-not $json) {
        Write-Output $summary

        foreach ($item in ($oldObjects | Select-Object -First 10)) {
            Write-Output ("  [{0}] {1} | modified {2} | {3} days" -f $item.Type, $item.Path, $item.LastWriteTime, $item.AgeDays)
        }

        if ($oldObjects.Count -gt 10) {
            Write-Output "  ... and $($oldObjects.Count - 10) more old object(s). Use -OutputFile for the full list."
        }

        foreach ($scanError in $scanErrors) {
            Write-Output "  [ERROR] $($scanError.Path): $($scanError.Message)"
        }
    }

    if ($OutputFile) {
        $report = [System.Collections.Generic.List[object]]::new()

        foreach ($item in $oldObjects) {
            $report.Add($item)
        }

        foreach ($scanError in $scanErrors) {
            $report.Add([pscustomobject]@{
                Status = 'UNKNOWN'
                Type = 'Error'
                Path = $scanError.Path
                LastWriteTime = ''
                AgeDays = ''
                Details = $scanError.Message
            })
        }

        if ($report.Count -eq 0) {
            $report.Add([pscustomobject]@{
                Status = $status
                Type = 'Summary'
                Path = $Path
                LastWriteTime = ''
                AgeDays = ''
                Details = $summary
            })
        }

        $report | Export-Csv -LiteralPath $OutputFile -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
    }

    Write-ScanLog -Level 'INFO' -Message $summary
} catch {
    $exitCode = 3
    $status = 'UNKNOWN'
    $summary = "UNKNOWN - Execution error: $($_.Exception.Message)"

    if (-not $Json) {
        Write-Output $summary
    }

    if ($LogFile) {
        try {
            Write-ScanLog -Level 'ERROR' -Message $_.Exception.Message
        } catch {
            if (-not $Json) {
                Write-Output "UNKNOWN - Unable to write log: $($_.Exception.Message)"
            }
        }
    }
}

if ($Json) {
    $scanReport = [pscustomobject]@{
        Status        = $status
        ExitCode      = $exitCode
        Summary       = $summary
        Path          = $Path
        ThresholdDays = $Day
        Recursive     = -not $NoRecurse
        ScannedCount  = $scannedCount
        OldObjects    = @($oldObjects.ToArray())
        ScanErrors    = @($scanErrors.ToArray())
    }

    $scanReport | ConvertTo-Json -Depth 5
}

exit $exitCode