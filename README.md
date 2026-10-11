# Windows Object Age Monitor

[Check-ObjectAge.ps1](Check-ObjectAge.ps1) scans a Windows directory for files and directories whose last modification time is older than a configured number of days. It scans recursively by default and supports text or JSON output, an optional CSV report and a diagnostic log.

Use it to identify stale exports or accumulated objects. It does not delete or modify the objects being inspected.

## Contents

- [Requirements](#requirements)
- [Usage and parameters](#usage-and-parameters)
- [Scan behavior](#scan-behavior)
- [Output formats](#output-formats)
- [Example files](#example-files)
- [Status and exit codes](#status-and-exit-codes)
- [Limitations and troubleshooting](#limitations-and-troubleshooting)
- [License](#license)

## Requirements

- Windows PowerShell 5.1 or later with standard filesystem cmdlets.
- Read/list permissions on the target directory and its selected subdirectories.
- Write permissions for optional CSV and log files; their parent directories must already exist.

For scheduled or monitoring execution, check permissions using the account that will run the program. Execution must be allowed by the applicable PowerShell execution policy.

## Usage and parameters

Run from the directory containing the program:

```powershell
# Recursive scan with text output
.\Check-ObjectAge.ps1 -P 'C:\Exports' -D 2

# Immediate children only
.\Check-ObjectAge.ps1 -P 'C:\Exports' -D 2 -NoRecurse

# JSON output
.\Check-ObjectAge.ps1 -P 'C:\Exports' -D 2 -Json

# CSV report and diagnostic log
.\Check-ObjectAge.ps1 -P 'C:\Exports' -D 2 -OutputFile 'C:\Reports\object-age.csv' -LogFile 'C:\Reports\object-age.log'

# Built-in usage
.\Check-ObjectAge.ps1 -Help
```

The paths above are examples to replace with your own. Quote paths containing spaces. JSON output can be combined with CSV export and logging.

| Parameter     | Alias | Purpose                                                                                                           |
| ------------- | ----- | ----------------------------------------------------------------------------------------------------------------- |
| `-Path`       | `-P`  | Required directory to scan. A single file is not a valid target.                                                  |
| `-Day`        | `-D`  | Required integer threshold from `1` to `36500` days; the date calculation must also fit the supported date range. |
| `-NoRecurse`  | —     | Inspect immediate children only.                                                                                  |
| `-Json`       | —     | Print JSON instead of the default text report.                                                                    |
| `-OutputFile` | —     | Write the complete CSV report, overwriting an existing file.                                                      |
| `-LogFile`    | —     | Append timestamped `INFO` and `ERROR` diagnostic messages.                                                        |
| `-Help`       | `-H`  | Show usage without scanning or writing reports.                                                                   |

Running without arguments also shows usage.

## Scan behavior

The cutoff is calculated once using `(Get-Date).AddDays(-$Day)`. An object is old when its `LastWriteTime` is strictly earlier than that cutoff. Creation time is not used; an object exactly at the cutoff is not selected.

The scan includes hidden/system objects through `Get-ChildItem -Force`. It evaluates each child directory's own timestamp, then scans its children unless `-NoRecurse` is set. The target directory itself is not evaluated as an old object.

Child directories with the `ReparsePoint` attribute, including junctions and symbolic links, are not traversed to avoid loops. Their own metadata can still appear in the results. A reparse point supplied as the root path is not explicitly excluded.

Directory-listing errors are recorded and scanning continues where possible. Any such error makes the overall status `UNKNOWN`, even if old objects were also found.

## Output formats

### Text

Default output includes a summary, up to ten old objects and all recorded directory-listing errors. If more old objects exist, a message indicates the remaining count.

Illustrative output:

```text
CRITICAL - 1 old object(s); 5 scanned; 0 inaccessible directories; threshold 2 day(s)
  [File] C:\Exports\report.csv | modified 2026-10-01 09:00:00 | 10 days
```

### JSON

`-Json` returns the full list of old objects without the text report's ten-object limit. The following example illustrates the normal report structure:

```json
{
  "Status": "CRITICAL",
  "ExitCode": 2,
  "Summary": "CRITICAL - 1 old object(s); 5 scanned; 0 inaccessible directories; threshold 2 day(s)",
  "Path": "C:\\Exports",
  "ThresholdDays": 2,
  "Recursive": true,
  "ScannedCount": 5,
  "OldObjects": [
    {
      "Status": "CRITICAL",
      "Type": "File",
      "Path": "C:\\Exports\\report.csv",
      "LastWriteTime": "2026-10-01 09:00:00",
      "AgeDays": 10,
      "Details": ""
    }
  ],
  "ScanErrors": []
}
```

`OldObjects` contains files/directories older than the threshold. `AgeDays` is rounded to two decimal places, and `Details` is empty for these objects.

`ScanErrors` contains directory-listing failures, each with `Path` and `Message`. For example:

```json
{
  "Path": "C:\\Exports\\Restricted",
  "Message": "Access to the path is denied."
}
```

Both arrays are empty when there are no corresponding records. General execution failures, such as CSV or log write errors, are reported in `Summary` rather than added to `ScanErrors`.

Missing required parameters produce a shorter JSON object with `Status`, `ExitCode` and `Summary`.

### CSV and log

`-OutputFile` exports a comma-separated UTF-8 CSV with these columns:

| Column          | Contents                                                                                            |
| --------------- | --------------------------------------------------------------------------------------------------- |
| `Status`        | `CRITICAL` for old objects, `UNKNOWN` for scan-error rows, or the overall status for a summary row. |
| `Type`          | `File`, `Directory`, `Error` or `Summary`.                                                          |
| `Path`          | Object path, inaccessible directory or target path.                                                 |
| `LastWriteTime` | Modification timestamp for old objects; otherwise empty.                                            |
| `AgeDays`       | Age for old objects; otherwise empty.                                                               |
| `Details`       | Empty for old objects; error message for error rows; report summary for a summary row.              |

A summary row is written when there are no old objects or scan errors. CSV output is a result report, not an inventory of every scanned object.

## Example files

The [examples](examples/) folder contains illustrative files for the same scenario: one old file and one inaccessible directory.

| File                                        | Contents                                                        |
| ------------------------------------------- | --------------------------------------------------------------- |
| [object-age.csv](examples/object-age.csv)   | Old-object and scan-error rows, including the `Details` column. |
| [object-age.json](examples/object-age.json) | Complete structured report with `OldObjects` and `ScanErrors`.  |
| [object-age.log](examples/object-age.log)   | Scan start, directory access error and final summary.           |

To produce equivalent output files for your own directory, first create the report directory, then run:

```powershell
.\Check-ObjectAge.ps1 -P 'C:\Exports' -D 2 -OutputFile 'C:\Reports\object-age.csv' -LogFile 'C:\Reports\object-age.log' -Json |
```

## Status and exit codes

| Code | Status     | Meaning                                                                    |
| ---- | ---------- | -------------------------------------------------------------------------- |
| `0`  | `OK`       | Scan completed with no old objects; also used when displaying help.        |
| `2`  | `CRITICAL` | Old objects found, or the target did not pass the directory check.         |
| `3`  | `UNKNOWN`  | Missing required parameters, incomplete scan or a handled execution error. |

## Limitations and troubleshooting

- An empty directory returns `OK`; the program does not verify that a particular expected file exists.
- A missing directory or file supplied as the target produces `CRITICAL - Directory not found`. Access-check exceptions can instead produce `UNKNOWN`.
- For incomplete scans, inspect `ScanErrors` or the diagnostic log and verify the execution account's permissions.
- Large trees can produce large JSON/CSV reports. Use `-NoRecurse` when only immediate children are relevant.
- Store output/log files outside the scanned tree when possible, so previous reports and log updates do not affect later checks.
- Review paths and error messages before sharing reports; they may expose environment details.

## License

Released under the MIT License. See [LICENSE](LICENSE).
