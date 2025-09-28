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
Before running this script, please update the following variables in the "User Configuration" section:
1. vCenter server details (server name, credentials)
2. SMTP server configuration
3. Email recipients
4. Risk thresholds (optional)

For detailed setup instructions, see: https://github.com/canberkys/VMware-Snapshot-Reporter/README.md
#>

param(
    [string]$ConfigFile = "",
    [switch]$TestMode,
    [switch]$SaveToFile,
    [string]$OutputPath = "C:\Reports\VMware-Snapshot-Report.html"
)

# Import required modules
try {
    Import-Module VMware.VimAutomation.Core -ErrorAction Stop
    Write-Host "✅ VMware PowerCLI module loaded successfully" -ForegroundColor Green
}
catch {
    Write-Error "❌ VMware PowerCLI module not found. Please install: Install-Module -Name VMware.PowerCLI"
    exit 1
}

#region User Configuration
# ==================================================================================
# CONFIGURATION SECTION - UPDATE THESE VALUES FOR YOUR ENVIRONMENT
# ==================================================================================

# vCenter Server Configuration
$VCenterConfig = @{
    # REQUIRED: Replace with your vCenter server FQDN or IP address
    Server = "your-vcenter-server.domain.com"
    
    # REQUIRED: Replace with your service account credentials
    # SECURITY NOTE: Consider using credential files instead of hardcoded passwords
    # To create credential file: Get-Credential | Export-CliXml -Path "C:\Secure\vcenter-creds.xml"
    Username = "your-service-account@domain.com"
    Password = "your-secure-password"
    
    # OPTIONAL: Path to credential file (recommended for production)
    # CredentialPath = "C:\Secure\vcenter-creds.xml"
}

# Email Configuration
$EmailConfig = @{
    # REQUIRED: Replace with your SMTP server details
    SmtpServer = "your-smtp-server.domain.com"
    SmtpPort = 25  # Common ports: 25, 587, 465
    
    # REQUIRED: Replace with your email addresses
    From = "vmware-reports@your-domain.com"
    To = @("it-team@your-domain.com", "infrastructure@your-domain.com")
    CC = @("manager@your-domain.com")  # Optional
    
    # Email subject template
    Subject = "$VCenterName VMware Snapshot Report - {0}"  # {0} will be replaced with vCenter name
    
    # OPTIONAL: SMTP Authentication (if required)
    # Username = "smtp-user@your-domain.com"
    # Password = "smtp-password"
    # UseSSL = $true
}

# Risk Thresholds (in days)
$RiskConfig = @{
    # Snapshots older than this are considered high risk (red)
    HighRiskDays = 3
    
    # Snapshots older than this are considered medium risk (yellow)  
    MediumRiskDays = 2
    
    # Snapshots newer than medium risk are low risk (green)
}

# Report Configuration
$ReportConfig = @{
    # Include only powered-on VMs
    PoweredOnOnly = $true
    
    # Maximum number of VI events to query per VM (affects performance)
    MaxEventSamples = 1000
    
    # Sort snapshots by size (largest first)
    SortBySize = $true
}

#endregion User Configuration

#region Functions

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch($Level) {
        "ERROR" { "Red" }
        "WARN" { "Yellow" }
        "SUCCESS" { "Green" }
        default { "White" }
    }
    
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Connect-VCenterSafe {
    param($Config)
    
    try {
        Write-Log "Connecting to vCenter: $($Config.Server)"
        Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope Session | Out-Null
        
        if ($Config.CredentialPath -and (Test-Path $Config.CredentialPath)) {
            $credential = Import-CliXml -Path $Config.CredentialPath
            $connection = Connect-VIServer $Config.Server -Credential $credential -ErrorAction Stop
        } else {
            $connection = Connect-VIServer $Config.Server -User $Config.Username -Password $Config.Password -ErrorAction Stop
        }
        
        Write-Log "Successfully connected to vCenter: $($connection.Name)" -Level "SUCCESS"
        return $connection
    }
    catch {
        Write-Log "Failed to connect to vCenter: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
}

function Get-SnapshotData {
    param($ReportConfig)
    
    Write-Log "Collecting snapshot data..."
    
    try {
        $vmQuery = Get-VM
        if ($ReportConfig.PoweredOnOnly) {
            $vmQuery = $vmQuery | Where-Object { $_.PowerState -eq "PoweredOn" }
        }
        
        $snapshots = $vmQuery | Get-Snapshot
        
        if (-not $snapshots) {
            Write-Log "No snapshots found" -Level "WARN"
            return @()
        }
        
        $snapshotData = @()
        $totalProcessed = 0
        
        foreach ($snap in $snapshots) {
            $totalProcessed++
            Write-Progress -Activity "Processing snapshots" -Status "$totalProcessed/$($snapshots.Count)" -PercentComplete (($totalProcessed / $snapshots.Count) * 100)
            
            try {
                # Get snapshot creator
                $creator = "Unknown"
                try {
                    $events = Get-VIEvent -Entity $snap.VM.Name -MaxSamples $ReportConfig.MaxEventSamples | 
                        Where-Object { $_.FullFormattedMessage -like "*Task: Create virtual machine snapshot*" -and $_.ObjectName -eq $snap.Name } |
                        Select-Object -First 1
                    if ($events) {
                        $creator = $events.UserName
                    }
                }
                catch {
                    Write-Log "Could not retrieve creator for snapshot: $($snap.Name)" -Level "WARN"
                }
                
                $snapObj = [PSCustomObject]@{
                    VM = $snap.VM.Name
                    Name = $snap.Name
                    Created = $snap.Created
                    Duration = -($snap.Created - (Get-Date)).Days
                    Description = if ($snap.Description) { $snap.Description } else { "No description" }
                    SizeGB = [Math]::Round($snap.SizeGB, 2)
                    Username = $creator
                    PowerState = $snap.VM.PowerState
                }
                
                $snapshotData += $snapObj
            }
            catch {
                Write-Log "Error processing snapshot: $($snap.Name) - $($_.Exception.Message)" -Level "ERROR"
            }
        }
        
        Write-Progress -Activity "Processing snapshots" -Completed
        Write-Log "Successfully processed $($snapshotData.Count) snapshots" -Level "SUCCESS"
        
        if ($ReportConfig.SortBySize) {
            $snapshotData = $snapshotData | Sort-Object SizeGB -Descending
        }
        
        return $snapshotData
    }
    catch {
        Write-Log "Error collecting snapshot data: $($_.Exception.Message)" -Level "ERROR"
        throw
    }
}

function Get-SnapshotStatistics {
    param($SnapshotData, $RiskConfig)
    
    if (-not $SnapshotData -or $SnapshotData.Count -eq 0) {
        return @{
            TotalCount = 0
            TotalSizeGB = 0
            OldestSnapshotDays = 0
            AverageSizeGB = 0
            AverageAgeDays = 0
            HighRiskCount = 0
            MediumRiskCount = 0
            LowRiskCount = 0
        }
    }
    
    $totalSize = ($SnapshotData | Measure-Object SizeGB -Sum).Sum
    $oldestSnapshot = ($SnapshotData | Sort-Object Duration -Descending | Select-Object -First 1)
    $averageSize = ($SnapshotData | Measure-Object SizeGB -Average).Average
    $averageAge = ($SnapshotData | Measure-Object Duration -Average).Average
    
    $highRisk = ($SnapshotData | Where-Object { $_.Duration -ge $RiskConfig.HighRiskDays }).Count
    $mediumRisk = ($SnapshotData | Where-Object { $_.Duration -ge $RiskConfig.MediumRiskDays -and $_.Duration -lt $RiskConfig.HighRiskDays }).Count
    $lowRisk = ($SnapshotData | Where-Object { $_.Duration -lt $RiskConfig.MediumRiskDays }).Count
    
    return @{
        TotalCount = $SnapshotData.Count
        TotalSizeGB = [Math]::Round($totalSize, 2)
        OldestSnapshotDays = $oldestSnapshot.Duration
        AverageSizeGB = [Math]::Round($averageSize, 2)
        AverageAgeDays = [Math]::Round($averageAge, 1)
        HighRiskCount = $highRisk
        MediumRiskCount = $mediumRisk
        LowRiskCount = $lowRisk
    }
}

function Generate-HTMLReport {
    param($SnapshotData, $Statistics, $VCenterName, $RiskConfig)
    
    $reportDate = Get-Date -Format "MM/dd/yyyy HH:mm"
    $reportDateTime = Get-Date -Format "MM/dd/yyyy HH:mm:ss"
    
    # Email-compatible HTML with inline CSS
    $htmlHeader = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VMware Snapshot Report - $VCenterName</title>
    <style>
        @media only screen and (max-width: 600px) {
            .container { width: 100% !important; margin: 0 !important; }
            .stats-table { font-size: 12px !important; }
            .stats-cell { display: block !important; width: 100% !important; margin-bottom: 10px !important; }
            .main-table { font-size: 11px !important; }
            .main-table th, .main-table td { padding: 5px 3px !important; }
        }
    </style>
</head>
<body style="font-family: Arial, sans-serif; background-color: #f5f5f5; margin: 0; padding: 10px;">
    <div class="container" style="max-width: 900px; margin: 0 auto; background: white; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); overflow: hidden;">
        
        <!-- Header -->
        <div style="background-color: #2c3e50; color: white; padding: 25px; text-align: center;">
            <h1 style="margin: 0; font-size: 24px; font-weight: normal;">VMware Snapshot Report</h1>
            <p style="margin: 8px 0 0 0; font-size: 14px; opacity: 0.9;">$VCenterName - $reportDate</p>
        </div>

        <!-- Statistics Cards -->
        <div style="padding: 20px; background-color: #f8f9fa;">
            <table class="stats-table" style="width: 100%; border-collapse: collapse;">
                <tr>
                    <td class="stats-cell" style="width: 33.33%; padding: 10px; text-align: center;">
                        <div style="background: white; padding: 15px; border-radius: 8px; box-shadow: 0 1px 5px rgba(0,0,0,0.1); border-left: 4px solid #3498db;">
                            <div style="font-size: 24px; font-weight: bold; color: #2c3e50; margin-bottom: 5px;">$($Statistics.TotalCount)</div>
                            <div style="color: #7f8c8d; font-size: 12px; text-transform: uppercase; letter-spacing: 1px;">Active Snapshots</div>
                        </div>
                    </td>
                    <td class="stats-cell" style="width: 33.33%; padding: 10px; text-align: center;">
                        <div style="background: white; padding: 15px; border-radius: 8px; box-shadow: 0 1px 5px rgba(0,0,0,0.1); border-left: 4px solid #27ae60;">
                            <div style="font-size: 24px; font-weight: bold; color: #2c3e50; margin-bottom: 5px;">$($Statistics.TotalSizeGB) GB</div>
                            <div style="color: #7f8c8d; font-size: 12px; text-transform: uppercase; letter-spacing: 1px;">Total Size</div>
                        </div>
                    </td>
                    <td class="stats-cell" style="width: 33.33%; padding: 10px; text-align: center;">
                        <div style="background: white; padding: 15px; border-radius: 8px; box-shadow: 0 1px 5px rgba(0,0,0,0.1); border-left: 4px solid #f39c12;">
                            <div style="font-size: 24px; font-weight: bold; color: #2c3e50; margin-bottom: 5px;">$($Statistics.OldestSnapshotDays) Days</div>
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
                            Low Risk (&lt;$($RiskConfig.MediumRiskDays) days): $($Statistics.LowRiskCount)
                        </span>
                    </td>
                    <td style="width: 33.33%; padding: 5px; text-align: center;">
                        <span style="background-color: #fef3c7; color: #d97706; padding: 5px 10px; border-radius: 12px; font-weight: bold; font-size: 12px;">
                            Medium Risk ($($RiskConfig.MediumRiskDays)-$($RiskConfig.HighRiskDays-1) days): $($Statistics.MediumRiskCount)
                        </span>
                    </td>
                    <td style="width: 33.33%; padding: 5px; text-align: center;">
                        <span style="background-color: #fee2e2; color: #dc2626; padding: 5px 10px; border-radius: 12px; font-weight: bold; font-size: 12px;">
                            High Risk ($($RiskConfig.HighRiskDays)+ days): $($Statistics.HighRiskCount)
                        </span>
                    </td>
                </tr>
            </table>
        </div>

        <!-- Table Header -->
        <div style="background-color: #34495e; color: white; padding: 15px 20px;">
            <h2 style="margin: 0; font-size: 18px; font-weight: normal;">Detailed Snapshot List</h2>
        </div>

        <!-- Table -->
        <div style="padding: 20px; overflow-x: auto;">
"@

    # Generate table rows with color coding
    $tableHTML = @"
            <table class="main-table" style="width: 100%; border-collapse: collapse; background: white; margin: 0; min-width: 700px;">
                <thead>
                    <tr style="background-color: #495057;">
                        <th style="color: white; padding: 12px 8px; text-align: left; font-weight: normal; font-size: 13px; border: none; text-transform: uppercase;">VM Name</th>
                        <th style="color: white; padding: 12px 8px; text-align: left; font-weight: normal; font-size: 13px; border: none; text-transform: uppercase;">Snapshot Name</th>
                        <th style="color: white; padding: 12px 8px; text-align: left; font-weight: normal; font-size: 13px; border: none; text-transform: uppercase;">Created</th>
                        <th style="color: white; padding: 12px 8px; text-align: left; font-weight: normal; font-size: 13px; border: none; text-transform: uppercase;">Age (Days)</th>
                        <th style="color: white; padding: 12px 8px; text-align: left; font-weight: normal; font-size: 13px; border: none; text-transform: uppercase;">Description</th>
                        <th style="color: white; padding: 12px 8px; text-align: left; font-weight: normal; font-size: 13px; border: none; text-transform: uppercase;">Size (GB)</th>
                        <th style="color: white; padding: 12px 8px; text-align: left; font-weight: normal; font-size: 13px; border: none; text-transform: uppercase;">Created By</th>
                    </tr>
                </thead>
                <tbody>
"@

    # Add rows with color coding
    $rowCount = 0
    foreach ($snap in $SnapshotData) {
        $rowCount++
        
        # Determine color coding based on age
        $duration = $snap.Duration
        $rowStyle = ""
        $durationStyle = ""
        $leftBorder = ""
        
        if ($duration -ge $RiskConfig.HighRiskDays) {
            # High risk - Red
            $rowStyle = "background-color: #fef2f2;"
            $leftBorder = "border-left: 4px solid #ef4444;"
            $durationStyle = "background-color: #fee2e2; color: #dc2626; padding: 4px 8px; border-radius: 12px; font-weight: bold; font-size: 12px;"
        } elseif ($duration -ge $RiskConfig.MediumRiskDays) {
            # Medium risk - Yellow
            $rowStyle = "background-color: #fffbeb;"
            $leftBorder = "border-left: 4px solid #f59e0b;"
            $durationStyle = "background-color: #fef3c7; color: #d97706; padding: 4px 8px; border-radius: 12px; font-weight: bold; font-size: 12px;"
        } else {
            # Low risk - Green
            $rowStyle = "background-color: #f0fdf4;"
            $leftBorder = "border-left: 4px solid #22c55e;"
            $durationStyle = "background-color: #dcfce7; color: #16a34a; padding: 4px 8px; border-radius: 12px; font-weight: bold; font-size: 12px;"
        }
        
        # Size badge styling
        $sizeStyle = "background-color: #e3f2fd; color: #1976d2; padding: 3px 6px; border-radius: 8px; font-weight: bold; font-size: 11px;"
        if ($snap.SizeGB -gt 50) {
            $sizeStyle = "background-color: #ffebee; color: #d32f2f; padding: 3px 6px; border-radius: 8px; font-weight: bold; font-size: 11px;"
        } elseif ($snap.SizeGB -gt 10) {
            $sizeStyle = "background-color: #fff3e0; color: #f57c00; padding: 3px 6px; border-radius: 8px; font-weight: bold; font-size: 11px;"
        }
        
        $tableHTML += @"
                    <tr style="$rowStyle $leftBorder">
                        <td style="padding: 10px 8px; border-bottom: 1px solid #e9ecef; font-weight: bold; font-size: 13px;">$($snap.VM)</td>
                        <td style="padding: 10px 8px; border-bottom: 1px solid #e9ecef; font-size: 13px;">$($snap.Name)</td>
                        <td style="padding: 10px 8px; border-bottom: 1px solid #e9ecef; font-size: 12px;">$($snap.Created.ToString('MM/dd/yyyy HH:mm'))</td>
                        <td style="padding: 10px 8px; border-bottom: 1px solid #e9ecef;"><span style="$durationStyle">$($snap.Duration) days</span></td>
                        <td style="padding: 10px 8px; border-bottom: 1px solid #e9ecef; font-size: 12px;">$($snap.Description)</td>
                        <td style="padding: 10px 8px; border-bottom: 1px solid #e9ecef;"><span style="$sizeStyle">$($snap.SizeGB) GB</span></td>
                        <td style="padding: 10px 8px; border-bottom: 1px solid #e9ecef; font-size: 12px;">$($snap.Username)</td>
                    </tr>
"@
    }
    
    $tableHTML += @"
                </tbody>
            </table>
"@

    $htmlFooter = @"
        </div>
        
        <!-- Footer -->
        <div style="background-color: #f8f9fa; padding: 15px 20px; text-align: center; color: #6c757d; border-top: 1px solid #e9ecef;">
            <p style="margin: 0; font-size: 13px;">This report was generated automatically - $reportDateTime</p>
            <p style="margin: 8px 0 0 0; font-size: 12px;">
                <span style="display: inline-block; width: 10px; height: 10px; background-color: #22c55e; border-radius: 2px; margin-right: 5px; vertical-align: middle;"></span>&lt;$($RiskConfig.MediumRiskDays) Days (Low Risk)
                <span style="display: inline-block; width: 10px; height: 10px; background-color: #f59e0b; border-radius: 2px; margin: 0 5px 0 15px; vertical-align: middle;"></span>$($RiskConfig.MediumRiskDays)-$($RiskConfig.HighRiskDays-1) Days (Medium Risk)
                <span style="display: inline-block; width: 10px; height: 10px; background-color: #ef4444; border-radius: 2px; margin: 0 5px 0 15px; vertical-align: middle;"></span>$($RiskConfig.HighRiskDays)+ Days (High Risk)
            </p>
        </div>
    </div>
</body>
</html>
"@

    return $htmlHeader + $tableHTML + $htmlFooter
}

function Send-EmailReport {
    param($HTMLContent, $EmailConfig, $VCenterName, $Statistics)
    
    try {
        Write-Log "Sending email report..."
        
        $subject = $EmailConfig.Subject -f $VCenterName
        
        # Add priority indicator for high-risk situations
        if ($Statistics.HighRiskCount -gt 0) {
            $subject = "🔴 CRITICAL - $subject"
        } elseif ($Statistics.MediumRiskCount -gt 5) {
            $subject = "🟡 WARNING - $subject"
        }
        
        $emailParams = @{
            SmtpServer = $EmailConfig.SmtpServer
            From = $EmailConfig.From
            To = $EmailConfig.To
            Subject = $subject
            Body = $HTMLContent
            BodyAsHtml = $true
            Encoding = [System.Text.Encoding]::UTF8
            ErrorAction = "Stop"
        }
        
        # Add optional parameters
        if ($EmailConfig.CC -and $EmailConfig.CC.Count -gt 0) {
            $emailParams.CC = $EmailConfig.CC
        }
        
        if ($EmailConfig.SmtpPort -and $EmailConfig.SmtpPort -ne 25) {
            $emailParams.Port = $EmailConfig.SmtpPort
        }
        
        if ($EmailConfig.UseSSL) {
            $emailParams.UseSSL = $true
        }
        
        if ($EmailConfig.Username -and $EmailConfig.Password) {
            $credential = New-Object System.Management.Automation.PSCredential($EmailConfig.Username, ($EmailConfig.Password | ConvertTo-SecureString -AsPlainText -Force))
            $emailParams.Credential = $credential
        }
        
        Send-MailMessage @emailParams
        
        Write-Log "Email report sent successfully to: $($EmailConfig.To -join ', ')" -Level "SUCCESS"
        Write-Log "Report statistics: $($Statistics.TotalCount) snapshots, $($Statistics.TotalSizeGB) GB total" -Level "SUCCESS"
    }
    catch {
        Write-Log "Failed to send email report: $($_.Exception.Message)" -Level "ERROR"
        
        # Save to file as backup
        try {
            $backupPath = "C:\temp\vmware-snapshot-report-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
            New-Item -ItemType Directory -Path "C:\temp" -Force -ErrorAction SilentlyContinue | Out-Null
            $HTMLContent | Out-File -FilePath $backupPath -Encoding UTF8
            Write-Log "Report saved as backup: $backupPath" -Level "SUCCESS"
        }
        catch {
            Write-Log "Failed to save backup report: $($_.Exception.Message)" -Level "ERROR"
        }
        
        throw
    }
}

#endregion Functions

#region Main Execution

function Start-SnapshotReport {
    try {
        Write-Log "VMware Snapshot Reporter v2.0 starting..."
        Write-Log "vCenter: $($VCenterConfig.Server)"
        
        if ($TestMode) {
            Write-Log "Running in TEST MODE - no emails will be sent" -Level "WARN"
        }
        
        # Connect to vCenter
        $viConnection = Connect-VCenterSafe -Config $VCenterConfig
        
        # Collect snapshot data
        $snapshotData = Get-SnapshotData -ReportConfig $ReportConfig
        
        # Calculate statistics
        $statistics = Get-SnapshotStatistics -SnapshotData $snapshotData -RiskConfig $RiskConfig
        
        # Generate HTML report
        $htmlReport = Generate-HTMLReport -SnapshotData $snapshotData -Statistics $statistics -VCenterName $VCenterConfig.Server -RiskConfig $RiskConfig
        
        # Display summary
        Write-Log "=== SNAPSHOT REPORT SUMMARY ===" -Level "SUCCESS"
        Write-Log "Total Snapshots: $($statistics.TotalCount)" -Level "SUCCESS"
        Write-Log "Total Size: $($statistics.TotalSizeGB) GB" -Level "SUCCESS"
        Write-Log "Risk Distribution: High=$($statistics.HighRiskCount), Medium=$($statistics.MediumRiskCount), Low=$($statistics.LowRiskCount)" -Level "SUCCESS"
        
        # Save to file if requested
        if ($SaveToFile) {
            $directory = Split-Path $OutputPath -Parent
            if (!(Test-Path $directory)) {
                New-Item -ItemType Directory -Path $directory -Force | Out-Null
            }
            $htmlReport | Out-File -FilePath $OutputPath -Encoding UTF8
            Write-Log "Report saved to: $OutputPath" -Level "SUCCESS"
        }
        
        # Send email report (unless in test mode)
        if (-not $TestMode) {
            if ($statistics.TotalCount -gt 0 -or $statistics.HighRiskCount -gt 0) {
                Send-EmailReport -HTMLContent $htmlReport -EmailConfig $EmailConfig -VCenterName $VCenterConfig.Server -Statistics $statistics
            } else {
                Write-Log "No snapshots found - email not sent" -Level "INFO"
            }
        }
        
        Write-Log "Snapshot report completed successfully!" -Level "SUCCESS"
        
        # Disconnect from vCenter
        Disconnect-VIServer $viConnection -Confirm:$false
        
        return @{
            Success = $true
            SnapshotCount = $statistics.TotalCount
            TotalSizeGB = $statistics.TotalSizeGB
            HighRiskCount = $statistics.HighRiskCount
        }
    }
    catch {
        Write-Log "Snapshot report failed: $($_.Exception.Message)" -Level "ERROR"
        
        # Clean up connection
        try {
            if ($viConnection) {
                Disconnect-VIServer $viConnection -Confirm:$false
            }
        } catch {
            # Ignore disconnect errors
        }
        
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

# Script execution
try {
    # Validate configuration
    if ($VCenterConfig.Server -eq "your-vcenter-server.domain.com") {
        Write-Log "Please update the configuration section with your environment details" -Level "ERROR"
        Write-Log "See configuration section at the top of the script" -Level "ERROR"
        exit 1
    }
    
    if ($EmailConfig.SmtpServer -eq "your-smtp-server.domain.com") {
        Write-Log "Please update the email configuration with your SMTP server details" -Level "ERROR"
        exit 1
    }
    
    # Load configuration from file if specified
    if ($ConfigFile -and (Test-Path $ConfigFile)) {
        Write-Log "Loading configuration from: $ConfigFile"
        . $ConfigFile
    }
    
    # Execute main function
    $result = Start-SnapshotReport
    
    if ($result.Success) {
        Write-Host "✅ Snapshot report completed successfully!" -ForegroundColor Green
        if ($result.SnapshotCount -gt 0) {
            Write-Host "📊 Found $($result.SnapshotCount) snapshots totaling $($result.TotalSizeGB) GB" -ForegroundColor Yellow
            if ($result.HighRiskCount -gt 0) {
                Write-Host "🔴 $($result.HighRiskCount) snapshots require immediate attention!" -ForegroundColor Red
            }
        }
        exit 0
    } else {
        Write-Host "❌ Snapshot report failed: $($result.Error)" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Log "Unexpected error: $($_.Exception.Message)" -Level "ERROR"
    exit 1
}

#endregion Main Execution

<#
.SYNOPSIS
VMware Snapshot Reporter - Automated snapshot monitoring and reporting

.DESCRIPTION
This script connects to VMware vCenter Server to collect snapshot information 
from all virtual machines and generates a comprehensive HTML email report with 
color-coded risk indicators.

Features:
- Color-coded risk assessment (Green/Yellow/Red based on snapshot age)
- Responsive HTML email reports
- Detailed statistics and summaries
- Configurable risk thresholds
- Support for multiple email recipients
- Backup report saving
- Test mode for validation

.PARAMETER ConfigFile
Path to external configuration file (optional)

.PARAMETER TestMode
Run in test mode without sending emails

.PARAMETER SaveToFile
Save HTML report to file

.PARAMETER OutputPath
File path for saved report (default: C:\Reports\VMware-Snapshot-Report.html)

.EXAMPLE
.\VMware-Snapshot-Reporter.ps1
Run with default configuration

.EXAMPLE
.\VMware-Snapshot-Reporter.ps1 -TestMode -SaveToFile
Run in test mode and save report to file

.EXAMPLE
.\VMware-Snapshot-Reporter.ps1 -ConfigFile "C:\Config\prod-config.ps1"
Run with external configuration file

.NOTES
File Name      : VMware-Snapshot-Reporter.ps1
Version        : 2.0
Author         : IT Operations Team
Prerequisite   : VMware PowerCLI, vCenter access, SMTP server access
License        : MIT

.LINK
https://github.com/canberkys/VMware-Snapshot-Reporter/

#>
