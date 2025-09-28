# VMware Snapshot Reporter

A comprehensive PowerShell tool for automated VMware snapshot monitoring and reporting with color-coded HTML email notifications.

![VMware Snapshot Reporter](https://img.shields.io/badge/PowerShell-5.1%2B-blue)
![VMware PowerCLI](https://img.shields.io/badge/VMware-PowerCLI-green)
![License](https://img.shields.io/badge/License-MIT-yellow)

## 🚀 Features

- **📊 Comprehensive Reporting**: Detailed snapshot analysis with statistics and summaries
- **🎨 Color-Coded Risk Assessment**: 
  - 🟢 Green: Low risk (< 2 days old)
  - 🟡 Yellow: Medium risk (2-3 days old)  
  - 🔴 Red: High risk (3+ days old)
- **📧 HTML Email Reports**: Beautiful, responsive email notifications
- **⚙️ Configurable Thresholds**: Customize risk assessment criteria
- **📱 Mobile-Friendly**: Responsive design for all devices
- **🔒 Secure**: Support for credential files and encrypted passwords
- **🧪 Test Mode**: Validate configuration without sending emails
- **💾 Backup Reporting**: Automatic file backup when email fails

## 📋 Prerequisites

- **Windows PowerShell 5.1** or later
- **VMware PowerCLI** module
- **vCenter Server** access (read-only minimum)
- **SMTP Server** access for email notifications

## 🔧 Installation

1. **Install VMware PowerCLI** (if not already installed):
   ```powershell
   Install-Module -Name VMware.PowerCLI -Force -AllowClobber
   ```

2. **Download the script**:
   ```bash
   git clone https://github.com/canberkys/VMware-Snapshot-Reporter/git
   cd VMware-Snapshot-Reporter
   ```

3. **Configure the script** (see Configuration section below)

## ⚙️ Configuration

Before running the script, update the configuration section at the top of `VMware-Snapshot-Reporter.ps1`:

### vCenter Configuration
```powershell
$VCenterConfig = @{
    Server = "your-vcenter-server.domain.com"  # REQUIRED: Your vCenter FQDN/IP
    Username = "your-service-account@domain.com"  # REQUIRED: Service account
    Password = "your-secure-password"  # REQUIRED: Account password
    # CredentialPath = "C:\Secure\vcenter-creds.xml"  # OPTIONAL: Credential file
}
```

### Email Configuration
```powershell
$EmailConfig = @{
    SmtpServer = "your-smtp-server.domain.com"  # REQUIRED: SMTP server
    SmtpPort = 25  # OPTIONAL: SMTP port (25, 587, 465)
    From = "vmware-reports@your-domain.com"  # REQUIRED: Sender email
    To = @("it-team@your-domain.com")  # REQUIRED: Recipient emails
    CC = @("manager@your-domain.com")  # OPTIONAL: CC recipients
    Subject = "VMware Snapshot Report - {0}"  # Email subject template
}
```

### Risk Thresholds
```powershell
$RiskConfig = @{
    HighRiskDays = 3    # Snapshots older than 3 days = Red
    MediumRiskDays = 2  # Snapshots 2-3 days old = Yellow
    # Snapshots < 2 days = Green
}
```

## 🔐 Security Best Practices

### Option 1: Credential Files (Recommended)
```powershell
# Create encrypted credential file
Get-Credential | Export-CliXml -Path "C:\Secure\vcenter-creds.xml"

# Update configuration to use credential file
$VCenterConfig = @{
    Server = "your-vcenter-server.domain.com"
    CredentialPath = "C:\Secure\vcenter-creds.xml"
}
```

### Option 2: Environment Variables
```powershell
# Set environment variables
$env:VCENTER_USERNAME = "service-account@domain.com"
$env:VCENTER_PASSWORD = "secure-password"

# Update configuration
$VCenterConfig = @{
    Server = "your-vcenter-server.domain.com"
    Username = $env:VCENTER_USERNAME
    Password = $env:VCENTER_PASSWORD
}
```

## 🚀 Usage

### Basic Usage
```powershell
.\VMware-Snapshot-Reporter.ps1
```

### Test Mode (No Emails Sent)
```powershell
.\VMware-Snapshot-Reporter.ps1 -TestMode
```

### Save Report to File
```powershell
.\VMware-Snapshot-Reporter.ps1 -SaveToFile -OutputPath "C:\Reports\snapshot-report.html"
```

### Using External Configuration File
```powershell
.\VMware-Snapshot-Reporter.ps1 -ConfigFile "C:\Config\production-config.ps1"
```

### Combined Options
```powershell
.\VMware-Snapshot-Reporter.ps1 -TestMode -SaveToFile -OutputPath "C:\Reports\test-report.html"
```

## 📊 Sample Output

### Console Output
```
[2025-09-28 10:30:15] [INFO] VMware Snapshot Reporter v2.0 starting...
[2025-09-28 10:30:15] [INFO] vCenter: vcenter.company.com
[2025-09-28 10:30:16] [SUCCESS] Successfully connected to vCenter: vcenter.company.com
[2025-09-28 10:30:18] [SUCCESS] Successfully processed 5 snapshots
[2025-09-28 10:30:18] [SUCCESS] === SNAPSHOT REPORT SUMMARY ===
[2025-09-28 10:30:18] [SUCCESS] Total Snapshots: 5
[2025-09-28 10:30:18] [SUCCESS] Total Size: 125.6 GB
[2025-09-28 10:30:18] [SUCCESS] Risk Distribution: High=1, Medium=2, Low=2
[2025-09-28 10:30:19] [SUCCESS] Email report sent successfully
```

### Email Report Features
- **Executive Summary**: Total snapshots, size, and oldest snapshot age
- **Risk Assessment**: Color-coded breakdown of snapshot ages
- **Detailed Table**: Complete snapshot inventory with:
  - VM Name
  - Snapshot Name  
  - Creation Date
  - Age in Days (color-coded)
  - Description
  - Size (color-coded)
  - Creator Username

## 📅 Automation

### Task Scheduler (Windows)
Create a scheduled task to run daily:

```powershell
# Create scheduled task
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File C:\Scripts\VMware-Snapshot-Reporter.ps1"
$Trigger = New-ScheduledTaskTrigger -Daily -At "09:00AM"
$Settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 1)
$Principal = New-ScheduledTaskPrincipal -UserId "DOMAIN\ServiceAccount" -LogonType ServiceAccount

Register-ScheduledTask -TaskName "VMware Snapshot Report" -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal
```

### Cron Job (Linux with PowerShell Core)
```bash
# Add to crontab (run daily at 9 AM)
0 9 * * * /usr/bin/pwsh -File /opt/scripts/VMware-Snapshot-Reporter.ps1
```

## 🛠️ Troubleshooting

### Common Issues

#### PowerCLI Module Not Found
```powershell
Install-Module -Name VMware.PowerCLI -Force -AllowClobber -Scope CurrentUser
```

#### Certificate Errors
The script automatically ignores invalid certificates, but you can also:
```powershell
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
```

#### SMTP Authentication Required
Update email configuration:
```powershell
$EmailConfig = @{
    SmtpServer = "smtp.office365.com"
    SmtpPort = 587
    UseSSL = $true
    Username = "smtp-user@domain.com"
    Password = "app-password"
    # ... other settings
}
```

#### Firewall/Network Issues
Test connectivity:
```powershell
Test-NetConnection your-vcenter-server.domain.com -Port 443
Test-NetConnection your-smtp-server.domain.com -Port 25
```

### Debug Mode
Add verbose logging:
```powershell
$VerbosePreference = "Continue"
.\VMware-Snapshot-Reporter.ps1 -Verbose
```

## 🔧 Customization

### Custom Risk Thresholds
```powershell
$RiskConfig = @{
    HighRiskDays = 7     # Weekly cleanup cycle
    MediumRiskDays = 3   # 3-day warning period
}
```

### Additional Email Recipients
```powershell
$EmailConfig = @{
    To = @(
        "primary-admin@company.com",
        "backup-admin@company.com",
        "infrastructure-team@company.com"
    )
    CC = @(
        "manager@company.com",
        "director@company.com"
    )
}
```

### Custom Report Filters
```powershell
$ReportConfig = @{
    PoweredOnOnly = $false      # Include powered-off VMs
    MaxEventSamples = 2000      # Increase event history
    SortBySize = $false         # Sort by age instead of size
}
```

## 📈 Performance Considerations

- **Large Environments**: Increase `MaxEventSamples` carefully as it affects performance
- **Network Latency**: Consider running the script from a server close to vCenter
- **Concurrent Access**: Multiple scripts can run simultaneously against different vCenters
- **Memory Usage**: Large environments may require PowerShell memory optimization

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/new-feature`)
3. Commit your changes (`git commit -am 'Add new feature'`)
4. Push to the branch (`git push origin feature/new-feature`)
5. Create a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Issues**: [GitHub Issues](https://github.com/canberkys/VMware-Snapshot-Reporter/issues)
- **Discussions**: [GitHub Discussions](https://github.com/canberkys/VMware-Snapshot-Reporter/discussions)
- **Wiki**: [Project Wiki](https://github.com/canberkys/VMware-Snapshot-Reporter/wiki)

## 🙏 Acknowledgments

- VMware PowerCLI team for the excellent PowerShell module
- Community contributors for feedback and improvements
- IT Operations teams worldwide using this tool

## 📊 Statistics

- **Language**: PowerShell
- **Lines of Code**: ~500
- **File Size**: ~25KB
- **Tested On**: 
  - vCenter 6.7, 7.0, 8.0
  - PowerShell 5.1, 7.x
  - Exchange Server, Office 365, Gmail SMTP

---

⭐ **Star this repository if you find it useful!**

🐛 **Found a bug?** [Report it here](https://github.com/canberkys/VMware-Snapshot-Reporter/issues)

💡 **Have an idea?** [Share it with us](https://github.com/canberkys/VMware-Snapshot-Reporter/discussions)
