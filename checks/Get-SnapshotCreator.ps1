function Get-SnapshotCreator {
    <#
    .SYNOPSIS
        Retrieves the username that created a VM snapshot from vCenter event logs.
    .PARAMETER VMName
        Name of the virtual machine to query events for.
    .PARAMETER MaxSamples
        Maximum number of events to search through. Default: 1000.
    .OUTPUTS
        [string] Username of the snapshot creator, or "Unknown" if not found.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VMName,

        [Parameter()]
        [int]$MaxSamples = 1000
    )

    try {
        $event = Get-VIEvent -Entity $VMName -MaxSamples $MaxSamples |
            Where-Object { $_.FullFormattedMessage -like "*Task: Create virtual machine snapshot*" } |
            Select-Object -First 1

        if ($event -and $event.UserName) {
            return $event.UserName
        }
    }
    catch {
        Write-Warning "Could not retrieve creator for VM: $VMName - $($_.Exception.Message)"
    }

    return "Unknown"
}
