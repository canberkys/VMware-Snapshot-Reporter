function Get-SnapshotInventory {
    <#
    .SYNOPSIS
        Collects snapshot inventory from a connected vCenter Server.
    .PARAMETER PoweredOnOnly
        If true, only collects snapshots from powered-on VMs. Default: true.
    .PARAMETER MaxEventSamples
        Maximum event samples for creator lookup. Default: 1000.
    .PARAMETER SkipCreatorLookup
        Skip the expensive Get-VIEvent creator lookup for better performance.
    .PARAMETER VCenterName
        Name of the vCenter server (for multi-vCenter identification).
    .OUTPUTS
        [PSCustomObject[]] Array of snapshot objects with properties:
        VM, Name, Created, Duration, Description, SizeGB, Username, VCenter
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [bool]$PoweredOnOnly = $true,

        [Parameter()]
        [int]$MaxEventSamples = 1000,

        [Parameter()]
        [switch]$SkipCreatorLookup,

        [Parameter()]
        [string]$VCenterName = ""
    )

    $snapshots = @()

    $vmFilter = if ($PoweredOnOnly) {
        Get-VM | Where-Object { $_.PowerState -eq "PoweredOn" }
    } else {
        Get-VM
    }

    $vmFilter | Get-Snapshot | ForEach-Object {
        $duration = -($_.Created - (Get-Date)).Days

        $username = "Unknown"
        if (-not $SkipCreatorLookup) {
            $username = Get-SnapshotCreator -VMName $_.VM.Name -MaxSamples $MaxEventSamples
        }

        $description = if ($_.Description -and $_.Description.Trim() -ne "") {
            $_.Description.Trim()
        } else {
            "No description"
        }

        $snapshots += [PSCustomObject]@{
            VM          = $_.VM.Name
            Name        = $_.Name
            Created     = $_.Created
            Duration    = $duration
            Description = $description
            SizeGB      = [Math]::Floor($_.SizeGB)
            Username    = $username
            VCenter     = $VCenterName
        }
    }

    return $snapshots
}
