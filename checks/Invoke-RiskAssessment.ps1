function Invoke-RiskAssessment {
    <#
    .SYNOPSIS
        Classifies snapshots by risk level and size, computes summary statistics.
    .PARAMETER Snapshots
        Array of snapshot objects from Get-SnapshotInventory.
    .PARAMETER HighRiskDays
        Threshold in days for high risk classification. Default: 7.
    .PARAMETER MediumRiskDays
        Threshold in days for medium risk classification. Default: 3.
    .PARAMETER LargeGB
        Size threshold in GB for large classification. Default: 50.
    .PARAMETER MediumGB
        Size threshold in GB for medium classification. Default: 10.
    .OUTPUTS
        [PSCustomObject] with .Snapshots (enriched array) and .Summary (statistics).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$Snapshots,

        [Parameter()]
        [int]$HighRiskDays = 7,

        [Parameter()]
        [int]$MediumRiskDays = 3,

        [Parameter()]
        [int]$LargeGB = 50,

        [Parameter()]
        [int]$MediumGB = 10
    )

    $enriched = @()

    foreach ($snap in $Snapshots) {
        $riskLevel = if ($snap.Duration -ge $HighRiskDays) {
            "High"
        } elseif ($snap.Duration -ge $MediumRiskDays) {
            "Medium"
        } else {
            "Low"
        }

        $sizeCategory = if ($snap.SizeGB -gt $LargeGB) {
            "Large"
        } elseif ($snap.SizeGB -gt $MediumGB) {
            "Medium"
        } else {
            "Normal"
        }

        $enrichedSnap = [PSCustomObject]@{
            VM           = $snap.VM
            Name         = $snap.Name
            Created      = $snap.Created
            Duration     = $snap.Duration
            Description  = $snap.Description
            SizeGB       = $snap.SizeGB
            Username     = $snap.Username
            VCenter      = $snap.VCenter
            RiskLevel    = $riskLevel
            SizeCategory = $sizeCategory
        }

        $enriched += $enrichedSnap
    }

    # Sort by size descending
    $enriched = $enriched | Sort-Object SizeGB -Descending

    # Compute summary
    $totalSizeGB = [Math]::Round(($enriched | Measure-Object -Property SizeGB -Sum).Sum, 2)
    if (-not $totalSizeGB) { $totalSizeGB = 0 }

    $highRiskCount   = ($enriched | Where-Object { $_.RiskLevel -eq "High" }).Count
    $mediumRiskCount = ($enriched | Where-Object { $_.RiskLevel -eq "Medium" }).Count
    $lowRiskCount    = ($enriched | Where-Object { $_.RiskLevel -eq "Low" }).Count

    $oldestSnapDays = 0
    $newestSnapDays = 0
    if ($enriched.Count -gt 0) {
        $oldestSnapDays = ($enriched | Measure-Object -Property Duration -Maximum).Maximum
        $newestSnapDays = ($enriched | Measure-Object -Property Duration -Minimum).Minimum
    }

    $summary = [PSCustomObject]@{
        TotalCount      = $enriched.Count
        TotalSizeGB     = $totalSizeGB
        HighRiskCount   = $highRiskCount
        MediumRiskCount = $mediumRiskCount
        LowRiskCount    = $lowRiskCount
        OldestSnapDays  = $oldestSnapDays
        NewestSnapDays  = $newestSnapDays
        HighRiskDays    = $HighRiskDays
        MediumRiskDays  = $MediumRiskDays
    }

    return [PSCustomObject]@{
        Snapshots = $enriched
        Summary   = $summary
    }
}
