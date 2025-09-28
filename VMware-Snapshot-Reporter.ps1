<#
===============================================================================
Title: VMware-Snapshot-Reporter.ps1
Description: Automated VMware snapshot monitoring and reporting tool with color-coded HTML email reports
Version: 2.0
Author: Canberk Kilicarslan
License: MIT
Repository: https://github.com/canberkys/VMware-Snapshot-Reporter/
Requirements: 
- Windows PowerShell 5.1 or later
- VMware PowerCLI module
- Read-only access to vCenter Server
- SMTP server access for email notifications
Usage: .\VMware-Snapshot-Reporter.ps1
===============================================================================

CONFIGURATION REQUIRED:
Before running this script, please update the following variables:
1. vCenter server details (lines 25-27)
2. SMTP server configuration (lines 32-36)
3. Email recipients (line 35)
4. Risk thresholds (optional, lines 138-142)

For installation and setup instructions, see README.md
#>

# Import required modules
Import-Module VMware.VimAutomation.Core

#region Configuration - UPDATE THESE VALUES FOR YOUR ENVIRONMENT
# ==================================================================================
# CONFIGURATION SECTION - MODIFY THESE VALUES
# ==================================================================================

# vCenter Server Configuration
# REQUIRED: Replace with your vCenter server FQDN or IP address
$VCenter = "your-vcenter-server.domain.com"
# REQUIRED: Replace with your service account credentials
$username = 'your-service-account@domain.com'
$password = 'your-secure-password'

# SMTP Configuration
# REQUIRED: Replace with your SMTP server details
$emailSmtpServer = "your-smtp-server.domain.com"
# REQUIRED: Replace with sender and recipient email addresses
$emailFrom = "vmware-reports@your-domain.com"
$emailTo = "it-team@your-domain.com"
# Email subject (automatically includes vCenter name and date)
$emailSubject = "$VCenter Daily Snapshot Report"

#endregion Configuration

# Initialize variables
$TotalSizeGB = 0
$OldestSnap = (Get-Date)
$NewestSnap = (Get-Date).AddDays(-1000)

# Set PowerCLI configuration to ignore certificate warnings
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false

# Initialize report array
$Report = @()

# Connect to vCenter Server
try {
    Write-Host "Connecting to vCenter: $VCenter" -ForegroundColor Green
    Connect-VIServer $VCenter -User $username -Password $password -ErrorAction Stop
    Write-Host "Successfully connected to vCenter" -ForegroundColor Green
}
catch {
    Write-Error "Failed to connect to vCenter: $($_.Exception.Message)"
    exit 1
}

# Collect snapshot data from powered-on VMs
Write-Host "Collecting snapshot data..." -ForegroundColor Yellow

Get-VM | Where-Object { $_.PowerState -eq "PoweredOn" } | Get-Snapshot | ForEach-Object {
    # Create snapshot object with required properties
    $Snap = New-Object PSObject -Property @{
        VM = $_.VM.Name
        Name = $_.Name
        Created = $_.Created
        Duration = -($_.Created - (Get-Date)).Days
        Description = if ($_.Description) { $_.Description } else { "No description" }
        SizeGB = [Math]::Floor($_.SizeGB)
        Username = "Unknown"
    }
    
    # Attempt to get snapshot creator from vCenter events
    try {
        $event = Get-VIEvent -Entity $_.VM.Name -MaxSamples 1000 | 
            Where-Object { $_.FullFormattedMessage -like "*Task: Create virtual machine snapshot*" } | 
            Select-Object -First 1
        if ($event) {
            $Snap.Username = $event.UserName
        }
    }
    catch {
        Write-Warning "Could not retrieve creator for snapshot: $($_.Name)"
    }
    
    # Update total size
    $TotalSizeGB += $_.SizeGB
    
    # Track oldest and newest snapshots
    if ($OldestSnap -gt $Snap.Created) {
        $OldestSnap = $Snap.Created
        $OldestSnapDays = -($OldestSnap - (Get-Date)).Days
    }
    
    if ($NewestSnap -lt $Snap.Created) {
        $NewestSnap = $Snap.Created
        $NewestSnapDays = -($NewestSnap - (Get-Date)).Days
    }
    
    # Add to report array
    $Report += $Snap
}

# Calculate statistics
$TotalSizeGB = [Math]::Round($TotalSizeGB, 2)
$Report = $Report | Sort-Object SizeGB -Descending

# Risk assessment thresholds (in days)
$HighRiskThreshold = 7   # Snapshots older than 7 days = High risk (Red)
$MediumRiskThreshold = 3 # Snapshots 3-7 days old = Medium risk (Yellow)
                         # Snapshots < 3 days = Low risk (Green)

# Calculate risk statistics
$HighRiskCount = ($Report | Where-Object { $_.Duration -ge $HighRiskThreshold }).Count
$MediumRiskCount = ($Report | Where-Object { $_.Duration -ge $MediumRiskThreshold -and $_.Duration -lt $HighRiskThreshold }).Count
$LowRiskCount = ($Report | Where-Object { $_.Duration -lt $MediumRiskThreshold }).Count

Write-Host "Found $($Report.Count) snapshots totaling $TotalSizeGB GB" -ForegroundColor Yellow
Write-Host "Risk Distribution: High=$HighRiskCount, Medium=$MediumRiskCount, Low=$LowRiskCount" -ForegroundColor Yellow

# Generate timestamp for report
$ReportDate = Get-Date -Format 'MM/dd/yyyy HH:mm'
$ReportDateTime = Get-Date -Format 'MM/dd/yyyy HH:mm:ss'

# Generate HTML report with responsive design and text wrapping
$HTMLHeader = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$VCenter VMware Snapshot Report</title>
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
            <p style="margin: 8px 0 0 0; font-size: 14px; opacity: 0.9;">$VCenter - $ReportDate</p>
        </div>

        <!-- Statistics Cards -->
        <div style="padding: 20px; background-color: #f8f9fa;">
            <table style="width: 100%; border-collapse: collapse;">
                <tr>
                    <td style="width: 33.33%; padding: 10px; text-align: center;">
                        <div style="background: white; padding: 15px; border-radius: 8px; box-shadow: 0 1px 5px rgba(0,0,0,0.1); border-left: 4px solid #3498db;">
                            <div style="font-size: 24px; font-weight: bold; color: #2c3e50; margin-bottom: 5px;">$($Report.count)</div>
                            <div style="color: #7f8c8d; font-size: 12px; text-transform: uppercase; letter-spacing: 1px;">Active Snapshots</div>
                        </div>
                    </td>
                    <td style="width: 33.33%; padding: 10px; text-align: center;">
                        <div style="background: white; padding: 15px; border-radius: 8px; box-shadow: 0 1px 5px rgba(0,0,0,0.1); border-left: 4px solid #27ae60;">
                            <div style="font-size: 24px; font-weight: bold; color: #2c3e50; margin-bottom: 5px;">$TotalSizeGB GB</div>
                            <div style="color: #7f8c8d; font-size: 12px; text-transform: uppercase; letter-spacing: 1px;">Total Size</div>
                        </div>
                    </td>
                    <td style="width: 33.33%; padding: 10px; text-align: center;">
                        <div style="background: white; padding: 15px; border-radius: 8px; box-shadow: 0 1px 5px rgba(0,0,0,0.1); border-left: 4px solid #f39c12;">
                            <div style="font-size: 24px; font-weight: bold; color: #2c3e50; margin-bottom: 5px;">$OldestSnapDays Days</div>
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
                            Low Risk (&lt;$MediumRiskThreshold days): $LowRiskCount
                        </span>
                    </td>
                    <td style="width: 33.33%; padding: 5px; text-align: center;">
                        <span style="background-color: #fef3c7; color: #d97706; padding: 5px 10px; border-radius: 12px; font-weight: bold; font-size: 12px;">
                            Medium Risk ($MediumRiskThreshold-$(($HighRiskThreshold-1)) days): $MediumRiskCount
                        </span>
                    </td>
                    <td style="width: 33.33%; padding: 5px; text-align: center;">
                        <span style="background-color: #fee2e2; color: #dc2626; padding: 5px 10px; border-radius: 12px; font-weight: bold; font-size: 12px;">
                            High Risk ($HighRiskThreshold+ days): $HighRiskCount
                        </span>
                    </td>
                </tr>
            </table>
        </div>

        <!-- Table Header -->
        <div style="background-color: #34495e; color: white; padding: 15px 20px;">
            <h2 style="margin: 0; font-size: 18px; font-weight: normal;">Detailed Snapshot List</h2>
        </div>

        <!-- Responsive Table with Text Wrapping -->
        <div style="padding: 20px; overflow-x: auto;">
            <table class="main-table" style="width: 100%; border-collapse: collapse; background: white; margin: 0; font-size: 13px; table-layout: fixed;">
                <thead>
                    <tr style="background-color: #495057;">
                        <th style="color: white; padding: 12px 8px; text-align: left; font-weight: normal; font-size: 12px; border: none; width: 14%;">VM Name</th>
                        <th style="color: white; padding: 12px 8px; text-align: left; font-weight: normal; font-size: 12px; border: none; width: 14%;">Snapshot Name</th>
                        <th style="color: white; padding: 12px 8px; text-align: left; font-weight: normal; font-size: 12px; border: none; width: 11%;">Created</th>
                        <th style="color: white; padding: 12px 8px; text-align: center; font-weight: normal; font-size: 12px; border: none; width: 9%;">Duration</th>
                        <th style="color: white; padding: 12px 8px; text-align: left; font-weight: normal; font-size: 12px; border: none; width: 32%;">Description</th>
                        <th style="color: white; padding: 12px 8px; text-align: center; font-weight: normal; font-size: 12px; border: none; width: 8%;">Size (GB)</th>
                        <th style="color: white; padding: 12px 8px; text-align: left; font-weight: normal; font-size: 12px; border: none; width: 12%;">Created By</th>
                    </tr>
                </thead>
                <tbody>
"@

# Generate table rows with color coding and text wrapping
$tableHTML = ""
$rowCount = 0

if ($Report.Count -gt 0) {
    foreach ($snap in $Report) {
        $rowCount++
        
        # Determine color coding based on duration
        $duration = $snap.Duration
        $rowStyle = ""
        $durationStyle = ""
        $leftBorder = ""
        
        if ($duration -ge $HighRiskThreshold) {
            # High risk - Red
            $rowStyle = "background-color: #fef2f2;"
            $leftBorder = "border-left: 4px solid #ef4444;"
            $durationStyle = "background-color: #fee2e2; color: #dc2626; padding: 4px 8px; border-radius: 12px; font-weight: bold; font-size: 11px; display: inline-block; white-space: nowrap;"
        } elseif ($duration -ge $MediumRiskThreshold) {
            # Medium risk - Yellow
            $rowStyle = "background-color: #fffbeb;"
            $leftBorder = "border-left: 4px solid #f59e0b;"
            $durationStyle = "background-color: #fef3c7; color: #d97706; padding: 4px 8px; border-radius: 12px; font-weight: bold; font-size: 11px; display: inline-block; white-space: nowrap;"
        } else {
            # Low risk - Green
            $rowStyle = "background-color: #f0fdf4;"
            $leftBorder = "border-left: 4px solid #22c55e;"
            $durationStyle = "background-color: #dcfce7; color: #16a34a; padding: 4px 8px; border-radius: 12px; font-weight: bold; font-size: 11px; display: inline-block; white-space: nowrap;"
        }
        
        # Alternating row colors for better readability
        if ($rowCount % 2 -eq 0 -and $duration -lt $MediumRiskThreshold) {
            $rowStyle = "background-color: #f8f9fa;"
        }
        
        # Size badge styling
        $sizeStyle = "background-color: #e3f2fd; color: #1976d2; padding: 4px 8px; border-radius: 8px; font-weight: bold; font-size: 11px; display: inline-block; white-space: nowrap;"
        if ($snap.SizeGB -gt 50) {
            $sizeStyle = "background-color: #ffebee; color: #d32f2f; padding: 4px 8px; border-radius: 8px; font-weight: bold; font-size: 11px; display: inline-block; white-space: nowrap;"
        } elseif ($snap.SizeGB -gt 10) {
            $sizeStyle = "background-color: #fff3e0; color: #f57c00; padding: 4px 8px; border-radius: 8px; font-weight: bold; font-size: 11px; display: inline-block; white-space: nowrap;"
        }
        
        # Clean up text data for display
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
        
        # Shorten username if it's an email (take part before @)
        if ($username -like "*@*") {
            $username = ($username -split "@")[0]
        }
        
        $tableHTML += @"
                    <tr style="$rowStyle $leftBorder">
                        <td style="padding: 10px 8px; border-bottom: 1px solid #e9ecef; font-weight: bold; font-size: 12px; word-wrap: break-word; overflow-wrap: break-word;">$($snap.VM)</td>
                        <td style="padding: 10px 8px; border-bottom: 1px solid #e9ecef; font-size: 12px; word-wrap: break-word; overflow-wrap: break-word;">$($snap.Name)</td>
                        <td style="padding: 10px 8px; border-bottom: 1px solid #e9ecef; font-size: 11px;">$($snap.Created.ToString('MM/dd/yyyy'))<br><small style="color: #666;">$($snap.Created.ToString('HH:mm'))</small></td>
                        <td style="padding: 10px 8px; border-bottom: 1px solid #e9ecef; text-align: center;"><span style="$durationStyle">$($snap.Duration) days</span></td>
                        <td class="description-cell" style="padding: 10px 8px; border-bottom: 1px solid #e9ecef; font-size: 11px; word-wrap: break-word; overflow-wrap: break-word; max-width: 300px;">$description</td>
                        <td style="padding: 10px 8px; border-bottom: 1px solid #e9ecef; text-align: center;"><span style="$sizeStyle">$($snap.SizeGB)</span></td>
                        <td style="padding: 10px 8px; border-bottom: 1px solid #e9ecef; font-size: 11px; word-wrap: break-word; overflow-wrap: break-word;">$username</td>
                    </tr>
"@
    }
} else {
    $tableHTML = @"
                    <tr>
                        <td colspan="7" style="padding: 30px; text-align: center; color: #27ae60; font-weight: bold; font-size: 16px;">
                            ✅ No snapshots found - System is clean!
                        </td>
                    </tr>
"@
}

$HTMLFooter = @"
                </tbody>
            </table>
        </div>
        
        <!-- Footer -->
        <div style="background-color: #f8f9fa; padding: 15px 20px; text-align: center; color: #6c757d; border-top: 1px solid #e9ecef;">
            <p style="margin: 0; font-size: 13px;">This report was generated automatically - $ReportDateTime</p>
            <p style="margin: 5px 0 0 0; font-size: 11px;">
                <a href="https://github.com/canberkys/VMware-Snapshot-Reporter" target="_blank" style="color: #3498db; text-decoration: none;">VMware Snapshot Reporter</a> | 
                Canberkys
            </p>
            <p style="margin: 8px 0 0 0; font-size: 12px;">
                <span style="display: inline-block; width: 10px; height: 10px; background-color: #22c55e; border-radius: 2px; margin-right: 5px; vertical-align: middle;"></span>&lt;$MediumRiskThreshold Days (Low Risk)
                <span style="display: inline-block; width: 10px; height: 10px; background-color: #f59e0b; border-radius: 2px; margin: 0 5px 0 15px; vertical-align: middle;"></span>$MediumRiskThreshold-$(($HighRiskThreshold-1)) Days (Medium Risk)
                <span style="display: inline-block; width: 10px; height: 10px; background-color: #ef4444; border-radius: 2px; margin: 0 5px 0 15px; vertical-align: middle;"></span>$HighRiskThreshold+ Days (High Risk)
            </p>
        </div>
    </div>
</body>
</html>
"@

# Combine HTML components
$HTMLReport = $HTMLHeader + $tableHTML + $HTMLFooter

# Send email report if snapshots exist
if ($Report.Count -gt 0) {
    try {
        Write-Host "Sending email report..." -ForegroundColor Green
        $emailBody = $HTMLReport | Out-String
        Send-MailMessage -SmtpServer $emailSmtpServer -To $emailTo -From $emailFrom -Subject $emailSubject -Body $emailBody -BodyAsHtml
        Write-Host "Email report sent successfully to: $emailTo" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to send email: $($_.Exception.Message)"
        
        # Save report to file as backup
        $backupPath = "C:\temp\VMware-Snapshot-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
        try {
            New-Item -ItemType Directory -Path "C:\temp" -Force -ErrorAction SilentlyContinue | Out-Null
            $HTMLReport | Out-File -FilePath $backupPath -Encoding UTF8
            Write-Host "Report saved as backup: $backupPath" -ForegroundColor Yellow
        }
        catch {
            Write-Error "Failed to save backup report: $($_.Exception.Message)"
        }
    }
} else {
    Write-Host "No snapshots found - no email sent" -ForegroundColor Green
}

# Disconnect from vCenter
try {
    Disconnect-VIServer $VCenter -Confirm:$false
    Write-Host "Disconnected from vCenter" -ForegroundColor Green
}
catch {
    Write-Warning "Error disconnecting from vCenter: $($_.Exception.Message)"
}

Write-Host "Script completed successfully!" -ForegroundColor Green
