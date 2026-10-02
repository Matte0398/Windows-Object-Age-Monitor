#######################################################################################################
## Description: Script that it verifies the existence of an object (file or directory) under a path
##              It goes in alarm when the object exists and it is more old than N day
##
## Author: Matteo Z.
#######################################################################################################

Param (
    [Parameter(Mandatory = $true) ] [Alias('D')] $day,
    [Parameter(Mandatory = $true) ] [Alias('P')] $path
)

function print_usage {
    Write-Host "`nScript that it verifies the existence of an object (file or directory) under a path. It goes in alarm when the object exists and it is more old than N day"
    Write-Host "`nUsage:"
    Write-Host "  $script_name -P <object_path> -D <N_day>"
    Write-Host "`nOptions:"
    Write-Host "  -P"
    Write-Host "     Path to verify"
    Write-Host "  -D"
    Write-Host "     N day (it must be a number!)`n"
    Exit 3
}


########## MAIN ##########

$script_name = $MyInvocation.MyCommand.Name
$i = 1

if ($day.Length -eq 0 -Or $path.Length -eq 0) {    # to verify if the variable is null or empty
    Write-Host "`nUnknown!! You have done something wrong!"
    print_usage
} else {
    if (Test-Path -LiteralPath $path -PathType Container) {
        if (-not ($day -as [int])) {
            Write-Host "Unknown!! The argument -D (days) must be an integer number!"
            Exit 3
        }
        
        # $file = $(Get-ChildItem $path -File | Measure-Object).count                         # count the file
        # $directory = $(Get-ChildItem $path -Directory | Measure-Object).count               # count the directory
        # Write-Host "File found = $file - Directory found = $directory"
        try {
            $threshold = (Get-Date).AddDays(-$day)
            $old_object = Get-ChildItem $path | Where-Object { $_.LastWriteTime -lt $threshold }      # save all file that are more old than N day
            # Write-Host "Old objects = $old_object"
        } catch {
            Write-Host "Unknown!! Error in data calculation: $_"
            Exit 3
        }

        if ($old_object.Length -eq 0) {
            Write-Host "OK!! There are no objects older than $day day!"
            Exit 0
        } else {
            $msg = "Critical!! Objects older than $day day: "

            foreach ($x in $old_object) {
                if ($x.PsIsContainer) {         # to verify if the object is a directory
                    $msg += " $i) $x (dir) "
                } else {
                    $msg += " $i) $x (file) "
                }

                $i += 1
            }

            Write-Host $msg
            Exit 2
        }
    } else {
        Write-Host "Critical!! This path doesn't exist!"
        Exit 2
    }
}