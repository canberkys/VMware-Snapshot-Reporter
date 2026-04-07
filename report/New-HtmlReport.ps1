function New-HtmlReport {
    <#
    .SYNOPSIS
        Generates a color-coded HTML snapshot report from risk assessment results.
    .PARAMETER AssessmentResult
        Output from Invoke-RiskAssessment containing .Snapshots and .Summary.
    .PARAMETER VCenterName
        Name of the vCenter server for the report header.
    .PARAMETER Config
        Configuration object for thresholds and settings.
    .OUTPUTS
        [string] Complete HTML report.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $AssessmentResult,

        [Parameter(Mandatory)]
        [string]$VCenterName,

        [Parameter()]
        $Config = $null
    )

    $report  = $AssessmentResult.Snapshots
    $summary = $AssessmentResult.Summary

    $highRiskThreshold   = $summary.HighRiskDays
    $mediumRiskThreshold = $summary.MediumRiskDays

    $reportDate     = Get-Date -Format 'MM/dd/yyyy HH:mm'
    $reportDateTime = Get-Date -Format 'MM/dd/yyyy HH:mm:ss'

    # ── HTML Header ──
    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$VCenterName VMware Snapshot Report</title>
    <style>
        @media only screen and (max-width: 768px) {
            .container { width: 100% !important; margin: 0 !important; }
            .main-table { font-size: 10px !important; }
            .main-table th, .main-table td { padding: 4px 2px !important; }
            .description-cell { max-width: 100px !important; }
        }
    </style>
</head>
<body style="font-family: Arial, sans-serif; background-color: #f5f5f5; margin: 0; padding: 10px;">
    <div class="container" style="max-width: 1200px; margin: 0 auto; background: white; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); overflow: hidden;">

        <!-- Header -->
        <div style="background-color: #2c3e50; color: white; padding: 25px; text-align: center;">
            <h1 style="margin: 0; font-size: 24px; font-weight: normal;">VMware Snapshot Report</h1>
            <p style="margin: 8px 0 0 0; font-size: 14px; opacity: 0.9;">$VCenterName - $reportDate</p>
        </div>

        <!-- Statistics Cards -->
        <div style="padding: 20px; background-color: #f8f9fa;">
            <table style="width: 100%; border-collapse: collapse;">
                <tr>
                    <td style="width: 33.33%; padding: 10px; text-align: center;">
                        <div style="background: white; padding: 15px; border-radius: 8px; box-shadow: 0 1px 5px rgba(0,0,0,0.1); border-left: 4px solid #3498db;">
                            <div style="font-size: 24px; font-weight: bold; color: #2c3e50; margin-bottom: 5px;">$($summary.TotalCount)</div>
                            <div style="color: #7f8c8d; font-size: 12px; text-transform: uppercase; letter-spacing: 1px;">Active Snapshots</div>
                        </div>
                    </td>
                    <td style="width: 33.33%; padding: 10px; text-align: center;">
                        <div style="background: white; padding: 15px; border-radius: 8px; box-shadow: 0 1px 5px rgba(0,0,0,0.1); border-left: 4px solid #27ae60;">
                            <div style="font-size: 24px; font-weight: bold; color: #2c3e50; margin-bottom: 5px;">$($summary.TotalSizeGB) GB</div>
                            <div style="color: #7f8c8d; font-size: 12px; text-transform: uppercase; letter-spacing: 1px;">Total Size</div>
                        </div>
                    </td>
                    <td style="width: 33.33%; padding: 10px; text-align: center;">
                        <div style="background: white; padding: 15px; border-radius: 8px; box-shadow: 0 1px 5px rgba(0,0,0,0.1); border-left: 4px solid #f39c12;">
                            <div style="font-size: 24px; font-weight: bold; color: #2c3e50; margin-bottom: 5px;">$($summary.OldestSnapDays) Days</div>
                            <div style="color: #7f8c8d; font-size: 12px; text-transform: uppercase; letter-spacing: 1px;">Oldest Snapshot</div>
                        </div>
                    </td>
                </tr>
            </table>
        </div>

        <!-- Risk Summary -->
        <div style="padding: 20px; background-color: #fff;">
            <h3 style="margin: 0 0 15px 0; color: #2c3e50;">Risk Summary</h3>
            <table style="width: 100%; border-collapse: collapse;">
                <tr>
                    <td style="width: 33.33%; padding: 5px; text-align: center;">
                        <span style="background-color: #d1fae5; color: #16a34a; padding: 5px 10px; border-radius: 12px; font-weight: bold; font-size: 12px;">
                            Low Risk (&lt;$mediumRiskThreshold days): $($summary.LowRiskCount)
                        </span>
                    </td>
                    <td style="width: 33.33%; padding: 5px; text-align: center;">
                        <span style="background-color: #fef3c7; color: #d97706; padding: 5px 10px; border-radius: 12px; font-weight: bold; font-size: 12px;">
                            Medium Risk ($mediumRiskThreshold-$(($highRiskThreshold - 1)) days): $($summary.MediumRiskCount)
                        </span>
                    </td>
                    <td style="width: 33.33%; padding: 5px; text-align: center;">
                        <span style="background-color: #fee2e2; color: #dc2626; padding: 5px 10px; border-radius: 12px; font-weight: bold; font-size: 12px;">
                            High Risk ($highRiskThreshold+ days): $($summary.HighRiskCount)
                        </span>
                    </td>
                </tr>
            </table>
        </div>

        <!-- Table Header -->
        <div style="background-color: #34495e; color: white; padding: 15px 20px;">
            <h2 style="margin: 0; font-size: 18px; font-weight: normal;">Detailed Snapshot List</h2>
        </div>

        <!-- Responsive Table -->
        <div style="padding: 20px; overflow-x: auto;">
            <table class="main-table" style="width: 100%; border-collapse: collapse; background: white; margin: 0; font-size: 13px; table-layout: fixed;">
                <thead>
                    <tr style="background-color: #495057;">
                        <th style="color: white; padding: 12px 8px; text-align: left; font-weight: normal; font-size: 12px; border: none; width: 12%;">VM Name</th>
                        <th style="color: white; padding: 12px 8px; text-align: left; font-weight: normal; font-size: 12px; border: none; width: 12%;">Snapshot Name</th>
                        <th style="color: white; padding: 12px 8px; text-align: left; font-weight: normal; font-size: 12px; border: none; width: 11%;">Created</th>
                        <th style="color: white; padding: 12px 8px; text-align: center; font-weight: normal; font-size: 12px; border: none; width: 9%;">Duration</th>
                        <th style="color: white; padding: 12px 8px; text-align: left; font-weight: normal; font-size: 12px; border: none; width: 28%;">Description</th>
                        <th style="color: white; padding: 12px 8px; text-align: center; font-weight: normal; font-size: 12px; border: none; width: 8%;">Size (GB)</th>
                        <th style="color: white; padding: 12px 8px; text-align: left; font-weight: normal; font-size: 12px; border: none; width: 10%;">Created By</th>
                        <th style="color: white; padding: 12px 8px; text-align: left; font-weight: normal; font-size: 12px; border: none; width: 10%;">vCenter</th>
                    </tr>
                </thead>
                <tbody>
"@

    # ── Table Rows ──
    if ($report.Count -gt 0) {
        $rowCount = 0
        foreach ($snap in $report) {
            $rowCount++
            $duration = $snap.Duration

            # Color coding based on risk level
            switch ($snap.RiskLevel) {
                "High" {
                    $rowStyle      = "background-color: #fef2f2;"
                    $leftBorder    = "border-left: 4px solid #ef4444;"
                    $durationStyle = "background-color: #fee2e2; color: #dc2626; padding: 4px 8px; border-radius: 12px; font-weight: bold; font-size: 11px; display: inline-block; white-space: nowrap;"
                }
                "Medium" {
                    $rowStyle      = "background-color: #fffbeb;"
                    $leftBorder    = "border-left: 4px solid #f59e0b;"
                    $durationStyle = "background-color: #fef3c7; color: #d97706; padding: 4px 8px; border-radius: 12px; font-weight: bold; font-size: 11px; display: inline-block; white-space: nowrap;"
                }
                default {
                    $rowStyle      = "background-color: #f0fdf4;"
                    $leftBorder    = "border-left: 4px solid #22c55e;"
                    $durationStyle = "background-color: #dcfce7; color: #16a34a; padding: 4px 8px; border-radius: 12px; font-weight: bold; font-size: 11px; display: inline-block; white-space: nowrap;"
                }
            }

            # Alternating row colors for low risk
            if ($rowCount % 2 -eq 0 -and $snap.RiskLevel -eq "Low") {
                $rowStyle = "background-color: #f8f9fa;"
            }

            # Size badge styling
            switch ($snap.SizeCategory) {
                "Large"  { $sizeStyle = "background-color: #ffebee; color: #d32f2f; padding: 4px 8px; border-radius: 8px; font-weight: bold; font-size: 11px; display: inline-block; white-space: nowrap;" }
                "Medium" { $sizeStyle = "background-color: #fff3e0; color: #f57c00; padding: 4px 8px; border-radius: 8px; font-weight: bold; font-size: 11px; display: inline-block; white-space: nowrap;" }
                default  { $sizeStyle = "background-color: #e3f2fd; color: #1976d2; padding: 4px 8px; border-radius: 8px; font-weight: bold; font-size: 11px; display: inline-block; white-space: nowrap;" }
            }

            $description = if ($snap.Description -and $snap.Description.Trim() -ne "") {
                $snap.Description.Trim()
            } else {
                "No description available"
            }

            $username = if ($snap.Username -and $snap.Username.Trim() -ne "") {
                $snap.Username.Trim()
            } else {
                "Unknown"
            }

            # Shorten email usernames
            if ($username -like "*@*") {
                $username = ($username -split "@")[0]
            }

            $vcenterDisplay = if ($snap.VCenter) { $snap.VCenter } else { $VCenterName }

            $html += @"
                    <tr style="$rowStyle $leftBorder">
                        <td style="padding: 10px 8px; border-bottom: 1px solid #e9ecef; font-weight: bold; font-size: 12px; word-wrap: break-word; overflow-wrap: break-word;">$($snap.VM)</td>
                        <td style="padding: 10px 8px; border-bottom: 1px solid #e9ecef; font-size: 12px; word-wrap: break-word; overflow-wrap: break-word;">$($snap.Name)</td>
                        <td style="padding: 10px 8px; border-bottom: 1px solid #e9ecef; font-size: 11px;">$($snap.Created.ToString('MM/dd/yyyy'))<br><small style="color: #666;">$($snap.Created.ToString('HH:mm'))</small></td>
                        <td style="padding: 10px 8px; border-bottom: 1px solid #e9ecef; text-align: center;"><span style="$durationStyle">$($snap.Duration) days</span></td>
                        <td class="description-cell" style="padding: 10px 8px; border-bottom: 1px solid #e9ecef; font-size: 11px; word-wrap: break-word; overflow-wrap: break-word; max-width: 300px;">$description</td>
                        <td style="padding: 10px 8px; border-bottom: 1px solid #e9ecef; text-align: center;"><span style="$sizeStyle">$($snap.SizeGB)</span></td>
                        <td style="padding: 10px 8px; border-bottom: 1px solid #e9ecef; font-size: 11px; word-wrap: break-word; overflow-wrap: break-word;">$username</td>
                        <td style="padding: 10px 8px; border-bottom: 1px solid #e9ecef; font-size: 11px; word-wrap: break-word; overflow-wrap: break-word;">$vcenterDisplay</td>
                    </tr>
"@
        }
    } else {
        $html += @"
                    <tr>
                        <td colspan="8" style="padding: 30px; text-align: center; color: #27ae60; font-weight: bold; font-size: 16px;">
                            No snapshots found - System is clean!
                        </td>
                    </tr>
"@
    }

    # ── Footer ──
    $html += @"
                </tbody>
            </table>
        </div>

        <!-- Footer -->
        <div style="background-color: #f8f9fa; padding: 15px 20px; text-align: center; color: #6c757d; border-top: 1px solid #e9ecef;">
            <p style="margin: 0; font-size: 13px;">This report was generated automatically - $reportDateTime</p>
            <p style="margin: 5px 0 0 0; font-size: 11px;">
                <a href="https://github.com/canberkys/VMware-Snapshot-Reporter" target="_blank" style="color: #3498db; text-decoration: none;">VMware Snapshot Reporter</a> |
                Canberkys
            </p>
            <p style="margin: 8px 0 0 0; font-size: 12px;">
                <span style="display: inline-block; width: 10px; height: 10px; background-color: #22c55e; border-radius: 2px; margin-right: 5px; vertical-align: middle;"></span>&lt;$mediumRiskThreshold Days (Low Risk)
                <span style="display: inline-block; width: 10px; height: 10px; background-color: #f59e0b; border-radius: 2px; margin: 0 5px 0 15px; vertical-align: middle;"></span>$mediumRiskThreshold-$(($highRiskThreshold - 1)) Days (Medium Risk)
                <span style="display: inline-block; width: 10px; height: 10px; background-color: #ef4444; border-radius: 2px; margin: 0 5px 0 15px; vertical-align: middle;"></span>$highRiskThreshold+ Days (High Risk)
            </p>
        </div>
    </div>
</body>
</html>
"@

    return $html
}

function Export-SnapshotCsv {
    <#
    .SYNOPSIS
        Exports snapshot assessment results to CSV format.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $AssessmentResult,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    $fileName = "snapshot-report_$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
    $filePath = Join-Path $OutputPath $fileName

    $AssessmentResult.Snapshots | Select-Object VM, Name, Created, Duration, Description, SizeGB, Username, VCenter, RiskLevel, SizeCategory |
        Export-Csv -Path $filePath -NoTypeInformation -Encoding UTF8

    return $filePath
}

function Export-SnapshotJson {
    <#
    .SYNOPSIS
        Exports snapshot assessment results to JSON format.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $AssessmentResult,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    $fileName = "snapshot-report_$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $filePath = Join-Path $OutputPath $fileName

    $exportData = @{
        GeneratedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
        Summary     = $AssessmentResult.Summary
        Snapshots   = $AssessmentResult.Snapshots
    }

    $exportData | ConvertTo-Json -Depth 5 | Set-Content -Path $filePath -Encoding UTF8

    return $filePath
}
