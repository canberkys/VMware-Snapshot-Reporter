<#
.SYNOPSIS
    VMware-Snapshot-Reporter — Automated VMware snapshot monitoring and reporting tool.
.DESCRIPTION
    Connects to one or more vCenter Servers, collects all VM snapshots, performs risk
    assessment based on age and size, and produces color-coded HTML email reports with
    executive summaries. Supports CSV/JSON export. Read-only — makes no changes.
.PARAMETER VCenterServer
    FQDN or IP of target vCenter Server(s). Accepts multiple values for multi-vCenter
    reporting. Falls back to config.json vcenterServers.
.PARAMETER Credential
    PSCredential for vCenter authentication (read-only role sufficient).
    Falls back to saved credential file, environment variables, or interactive prompt.
.PARAMETER ConfigFile
    Path to config.json. Defaults to ./config.json.
.PARAMETER OutputPath
    Directory for report output. Defaults to ./output.
.PARAMETER ReportFormat
    Output format: HTML, JSON, CSV, or All.
.PARAMETER SendEmail
    Send HTML report via email using SMTP settings from config.json.
.PARAMETER SkipCreatorLookup
    Skip the expensive Get-VIEvent creator lookup for better performance.
.PARAMETER TestMode
    Run with mock data — no vCenter connection required. Useful for testing.
.EXAMPLE
    .\VMware-Snapshot-Reporter.ps1 -TestMode
.EXAMPLE
    .\VMware-Snapshot-Reporter.ps1 -VCenterServer vcsa.lab.local -Credential (Get-Credential)
.EXAMPLE
    .\VMware-Snapshot-Reporter.ps1 -TestMode -ReportFormat All -SendEmail
#>
#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$VCenterServer,

    [Parameter(Mandatory = $false)]
    [PSCredential]$Credential,

    [Parameter()]
    [string]$ConfigFile = (Join-Path $scriptRoot "config.json"),

    [Parameter()]
    [string]$OutputPath = (Join-Path $scriptRoot "output"),

    [Parameter()]
    [ValidateSet("HTML","JSON","CSV","All")]
    [string]$ReportFormat = "HTML",

    [Parameter()]
    [switch]$SendEmail,

    [Parameter()]
    [switch]$SkipCreatorLookup,

    [Parameter()]
    [switch]$TestMode
)

# ── Resolve script root reliably ──
$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) {
    $scriptRoot = Split-Path -Parent (Resolve-Path $MyInvocation.MyCommand.Path -ErrorAction SilentlyContinue) -ErrorAction SilentlyContinue
}
if (-not $scriptRoot) { $scriptRoot = $PWD.Path }

if (-not $ConfigFile -or -not (Test-Path $ConfigFile)) {
    $ConfigFile = Join-Path $scriptRoot "config.json"
}
if (-not $OutputPath) {
    $OutputPath = Join-Path $scriptRoot "output"
}

# ── Internals ──
$script:ToolVersion    = "3.0.0"
$script:CredentialFile = Join-Path $HOME ".snapshot-reporter-cred.xml"
$script:LogFile        = $null

# ══════════════════════════════════════════════════════════════
# Helper: Write-ReportLog
# ══════════════════════════════════════════════════════════════

function Write-ReportLog {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR","SUCCESS")]
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    $color = switch ($Level) {
        "ERROR"   { "Red" }
        "WARN"    { "Yellow" }
        "SUCCESS" { "Green" }
        default   { "White" }
    }
    Write-Host $line -ForegroundColor $color
    if ($script:LogFile) {
        $line | Out-File -FilePath $script:LogFile -Append -Encoding UTF8
    }
}

# ══════════════════════════════════════════════════════════════
# Mock Data Generator (for -TestMode)
# ══════════════════════════════════════════════════════════════

function Get-MockSnapshot {
    $now = Get-Date
    return @(
        [PSCustomObject]@{ VM = "PROD-DB-01";   Name = "Before Patching";       Created = $now.AddDays(-15); Duration = 15; Description = "Pre-patch snapshot before Windows updates";                SizeGB = 85;  Username = "admin@vsphere.local"; VCenter = "vcsa-mock.lab.local" }
        [PSCustomObject]@{ VM = "PROD-APP-02";  Name = "Upgrade Backup";        Created = $now.AddDays(-10); Duration = 10; Description = "Application upgrade rollback point";                       SizeGB = 42;  Username = "svc-backup@domain.com"; VCenter = "vcsa-mock.lab.local" }
        [PSCustomObject]@{ VM = "PROD-WEB-01";  Name = "Config Change";         Created = $now.AddDays(-8);  Duration = 8;  Description = "Before IIS configuration changes";                        SizeGB = 12;  Username = "john.doe@domain.com"; VCenter = "vcsa-mock.lab.local" }
        [PSCustomObject]@{ VM = "DEV-TEST-03";  Name = "Dev Snapshot";          Created = $now.AddDays(-5);  Duration = 5;  Description = "Development testing checkpoint";                          SizeGB = 28;  Username = "dev.team@domain.com"; VCenter = "vcsa-mock.lab.local" }
        [PSCustomObject]@{ VM = "STAGING-01";   Name = "Pre-Deploy";            Created = $now.AddDays(-4);  Duration = 4;  Description = "Before staging deployment v2.5.1";                        SizeGB = 18;  Username = "deploy-svc@domain.com"; VCenter = "vcsa-mock.lab.local" }
        [PSCustomObject]@{ VM = "PROD-SQL-01";  Name = "DB Migration";          Created = $now.AddDays(-2);  Duration = 2;  Description = "Before database schema migration";                        SizeGB = 120; Username = "dba@domain.com"; VCenter = "vcsa-mock.lab.local" }
        [PSCustomObject]@{ VM = "PROD-DC-01";   Name = "AD Changes";            Created = $now.AddDays(-1);  Duration = 1;  Description = "Before Active Directory Group Policy update";              SizeGB = 5;   Username = "ad.admin@domain.com"; VCenter = "vcsa-mock.lab.local" }
        [PSCustomObject]@{ VM = "DEV-BUILD-02"; Name = "Clean State";           Created = $now.AddHours(-6); Duration = 0;  Description = "Clean build environment snapshot";                        SizeGB = 3;   Username = "Unknown"; VCenter = "vcsa-mock.lab.local" }
    )
}

# ══════════════════════════════════════════════════════════════
# Banner
# ══════════════════════════════════════════════════════════════

Write-Host ""
Write-Host "  +====================================================+" -ForegroundColor Cyan
Write-Host "  |   VMware Snapshot Reporter v$script:ToolVersion                 |" -ForegroundColor Cyan
Write-Host "  |   Snapshot Monitoring & Risk Assessment             |" -ForegroundColor Cyan
Write-Host "  +====================================================+" -ForegroundColor Cyan
Write-Host ""

# ══════════════════════════════════════════════════════════════
# Load Configuration
# ══════════════════════════════════════════════════════════════

if (-not (Test-Path $ConfigFile)) {
    Write-Error "Config file not found: $ConfigFile"
    return
}
$config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
Write-ReportLog "Config loaded: $ConfigFile" -Level SUCCESS

# Ensure output directory exists
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

# Initialize log file
$script:LogFile = Join-Path $OutputPath "snapshot-reporter_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Write-ReportLog "Log file: $($script:LogFile)"

# ── Dot-source modules ──
Get-ChildItem -Path (Join-Path $scriptRoot "checks") -Filter "*.ps1" | ForEach-Object { . $_.FullName }
Get-ChildItem -Path (Join-Path $scriptRoot "report")  -Filter "*.ps1" | ForEach-Object { . $_.FullName }
Write-ReportLog "Modules loaded" -Level SUCCESS

# ══════════════════════════════════════════════════════════════
# Resolve vCenter Server(s)
# ══════════════════════════════════════════════════════════════

if (-not $VCenterServer -and -not $TestMode) {
    if ($config.vcenterServers -and $config.vcenterServers.Count -gt 0) {
        $VCenterServer = $config.vcenterServers
        Write-ReportLog "vCenter(s) from config: $($VCenterServer -join ', ')"
    } else {
        $inputVc = Read-Host "  [?] vCenter Server address"
        $VCenterServer = @($inputVc.Trim())
    }
}

# ══════════════════════════════════════════════════════════════
# Resolve Credential
# ══════════════════════════════════════════════════════════════

if (-not $Credential -and -not $TestMode) {
    # Try saved credential file
    if (Test-Path $script:CredentialFile) {
        try {
            $savedCred = Import-Clixml -Path $script:CredentialFile
            $savedUser = $savedCred.UserName
            Write-Host ""
            $useSaved = Read-Host "  Saved credential found for [$savedUser], use it? [Y/N]"
            if ($useSaved -match '^[Yy]') {
                $Credential = $savedCred
                Write-ReportLog "Using saved credential: $savedUser" -Level SUCCESS
            }
        } catch {
            Write-ReportLog "Failed to load saved credential: $_" -Level WARN
        }
    }

    # Try environment variables
    if (-not $Credential -and $env:VCENTER_USERNAME -and $env:VCENTER_PASSWORD) {
        # PSScriptAnalyzer: suppress — env var is the intended source, not a hardcoded secret
        $secPass = $env:VCENTER_PASSWORD | ConvertTo-SecureString -AsPlainText -Force  # nosec
        $Credential = [System.Management.Automation.PSCredential]::new($env:VCENTER_USERNAME, $secPass)
        Write-ReportLog "Using credential from environment variables" -Level SUCCESS
    }

    # Interactive prompt
    if (-not $Credential) {
        Write-Host ""
        $Credential = Get-Credential -Message "Enter vCenter credentials (read-only role sufficient)"

        $saveCred = Read-Host "  Save credential for future runs? [Y/N]"
        if ($saveCred -match '^[Yy]') {
            $Credential | Export-Clixml -Path $script:CredentialFile
            Write-ReportLog "Credential saved to $($script:CredentialFile)" -Level SUCCESS
        }
    }
}

# ══════════════════════════════════════════════════════════════
# Collect Snapshots
# ══════════════════════════════════════════════════════════════

$allSnapshots = @()

if ($TestMode) {
    Write-ReportLog "TestMode active - using mock data" -Level WARN
    $allSnapshots = Get-MockSnapshot
    $reportVCenterName = "vcsa-mock.lab.local"
} else {
    # Import VMware PowerCLI
    try {
        Import-Module VMware.VimAutomation.Core -ErrorAction Stop
        Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
    } catch {
        Write-ReportLog "Failed to import VMware PowerCLI: $($_.Exception.Message)" -Level ERROR
        Write-Error "VMware PowerCLI is required. Install with: Install-Module VMware.PowerCLI"
        return
    }

    foreach ($vcServer in $VCenterServer) {
        Write-ReportLog "Connecting to vCenter: $vcServer"

        try {
            Connect-VIServer $vcServer -Credential $Credential -ErrorAction Stop | Out-Null
            Write-ReportLog "Connected to $vcServer" -Level SUCCESS
        } catch {
            Write-ReportLog "Failed to connect to $vcServer - $($_.Exception.Message)" -Level ERROR
            continue
        }

        try {
            Write-ReportLog "Collecting snapshots from $vcServer..."
            $snapshots = Get-SnapshotInventory `
                -PoweredOnOnly $config.poweredOnOnly `
                -MaxEventSamples $config.maxEventSamples `
                -SkipCreatorLookup:$SkipCreatorLookup `
                -VCenterName $vcServer

            $allSnapshots += $snapshots
            Write-ReportLog "Found $($snapshots.Count) snapshots on $vcServer" -Level SUCCESS
        } catch {
            Write-ReportLog "Error collecting snapshots from $vcServer - $($_.Exception.Message)" -Level ERROR
        } finally {
            try {
                Disconnect-VIServer $vcServer -Confirm:$false -ErrorAction SilentlyContinue
                Write-ReportLog "Disconnected from $vcServer"
            } catch {
                Write-ReportLog "Error disconnecting from $vcServer" -Level WARN
            }
        }
    }

    $reportVCenterName = $VCenterServer -join ", "
}

Write-ReportLog "Total snapshots collected: $($allSnapshots.Count)"

# ══════════════════════════════════════════════════════════════
# Risk Assessment
# ══════════════════════════════════════════════════════════════

$assessment = Invoke-RiskAssessment `
    -Snapshots $allSnapshots `
    -HighRiskDays $config.riskThresholds.highRiskDays `
    -MediumRiskDays $config.riskThresholds.mediumRiskDays `
    -LargeGB $config.sizeThresholds.largeGB `
    -MediumGB $config.sizeThresholds.mediumGB

$s = $assessment.Summary
Write-ReportLog "Risk Distribution: High=$($s.HighRiskCount), Medium=$($s.MediumRiskCount), Low=$($s.LowRiskCount)" -Level INFO
Write-ReportLog "Total Size: $($s.TotalSizeGB) GB | Oldest: $($s.OldestSnapDays) days" -Level INFO

# ══════════════════════════════════════════════════════════════
# Generate Reports
# ══════════════════════════════════════════════════════════════

$generatedFiles = @()

if ($ReportFormat -eq "HTML" -or $ReportFormat -eq "All") {
    $htmlReport = New-HtmlReport -AssessmentResult $assessment -VCenterName $reportVCenterName -Config $config
    $htmlFile = Join-Path $OutputPath "snapshot-report_$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
    $htmlReport | Out-File -FilePath $htmlFile -Encoding UTF8
    $generatedFiles += $htmlFile
    Write-ReportLog "HTML report saved: $htmlFile" -Level SUCCESS
}

if ($ReportFormat -eq "CSV" -or $ReportFormat -eq "All") {
    $csvFile = Export-SnapshotCsv -AssessmentResult $assessment -OutputPath $OutputPath
    $generatedFiles += $csvFile
    Write-ReportLog "CSV report saved: $csvFile" -Level SUCCESS
}

if ($ReportFormat -eq "JSON" -or $ReportFormat -eq "All") {
    $jsonFile = Export-SnapshotJson -AssessmentResult $assessment -OutputPath $OutputPath
    $generatedFiles += $jsonFile
    Write-ReportLog "JSON report saved: $jsonFile" -Level SUCCESS
}

# ══════════════════════════════════════════════════════════════
# Send Email
# ══════════════════════════════════════════════════════════════

if ($SendEmail -and $assessment.Summary.TotalCount -gt 0) {
    $emailConfig = $config.email

    if (-not $emailConfig.smtpServer) {
        Write-ReportLog "SMTP server not configured in config.json - skipping email" -Level WARN
    } else {
        $subject = ($emailConfig.subjectTemplate -f $reportVCenterName) + " - $(Get-Date -Format 'MM/dd/yyyy')"

        # Generate HTML for email if not already generated
        if (-not $htmlReport) {
            $htmlReport = New-HtmlReport -AssessmentResult $assessment -VCenterName $reportVCenterName -Config $config
        }

        $emailParams = @{
            SmtpServer = $emailConfig.smtpServer
            Port       = $emailConfig.smtpPort
            From       = $emailConfig.from
            To         = $emailConfig.to
            Subject    = $subject
            Body       = ($htmlReport | Out-String)
            BodyAsHtml = $true
        }

        if ($emailConfig.cc -and $emailConfig.cc.Count -gt 0) {
            $emailParams.Cc = $emailConfig.cc
        }
        if ($emailConfig.useSSL) {
            $emailParams.UseSsl = $true
        }

        try {
            Write-ReportLog "Sending email report..."
            Send-MailMessage @emailParams
            Write-ReportLog "Email sent to: $($emailConfig.to -join ', ')" -Level SUCCESS
        } catch {
            Write-ReportLog "Failed to send email: $($_.Exception.Message)" -Level ERROR

            # Save backup if HTML wasn't already saved
            if ($ReportFormat -ne "HTML" -and $ReportFormat -ne "All") {
                $backupFile = Join-Path $OutputPath "snapshot-report-backup_$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
                $htmlReport | Out-File -FilePath $backupFile -Encoding UTF8
                Write-ReportLog "Backup report saved: $backupFile" -Level WARN
            }
        }
    }
} elseif ($SendEmail -and $assessment.Summary.TotalCount -eq 0) {
    Write-ReportLog "No snapshots found - no email sent" -Level SUCCESS
}

# ══════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════

Write-Host ""
Write-Host "  +----------------------------------------------------+" -ForegroundColor Cyan
Write-Host "  |   Report Complete                                   |" -ForegroundColor Cyan
Write-Host "  +----------------------------------------------------+" -ForegroundColor Cyan
Write-Host ""

if ($generatedFiles.Count -gt 0) {
    Write-ReportLog "Generated files:"
    foreach ($f in $generatedFiles) {
        Write-Host "    $f" -ForegroundColor White
    }
}

Write-ReportLog "Script completed successfully" -Level SUCCESS
