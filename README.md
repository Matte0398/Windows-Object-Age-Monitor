# Windows Object Count

PowerShell utility that checks whether a file or directory exists under a given path and verifies its age.

This script can be used for monitoring purposes, for example as a Zabbix custom check, to detect files or directories older than a defined number of days.

## Features

- Checks files and directories
- Supports custom paths
- Verifies object age
- Useful for monitoring stale files, old exports or delayed jobs
- Can be integrated with Zabbix UserParameters

## Usage

```powershell
powershell.exe .\objectCount.ps1 -P [object_path] -D [days]
```

## Example

```powershell
powershell.exe .\objectCount.ps1 -P "C:\Exports\report.csv" -D 2
```

## Output

```powershell
.\objectCount.ps1 -D 2 -P C:\

Critical!! Objects older than 2 day: 1) cygwin64 (dir)  2) inetpub (dir)  3) Intel (dir)  4) PerfLogs (dir) 5) Program Files (x86) (dir) 6) trac_msi.log (file)
```

```powershell
.\objectCount.ps1 -D 200 -P C:\temp

OK!! There are no objects older than 200 day!
```
