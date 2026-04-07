# VMware Snapshot Reporter

[![CI](https://github.com/canberkys/VMware-Snapshot-Reporter/actions/workflows/ci.yml/badge.svg)](https://github.com/canberkys/VMware-Snapshot-Reporter/actions/workflows/ci.yml)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](license.txt)

Automated VMware snapshot monitoring and reporting tool. Connects to one or more vCenter Servers, inventories all VM snapshots, performs risk assessment based on age and size, and delivers color-coded HTML reports with executive summaries.

> **[Live Report Preview](https://canberkys.github.io/VMware-Snapshot-Reporter/)** — See a sample report with mock data.

---

## Features

| Feature | Description |
|---------|-------------|
| **Risk-Based Color Coding** | Green (<3 days), Yellow (3-7 days), Red (7+ days) with configurable thresholds |
| **Multi-vCenter** | Scan multiple vCenter Servers in a single run, consolidated into one report |
| **Multiple Exports** | HTML, CSV, JSON, or All — pick the format you need |
| **Secure Credentials** | 4-tier chain: parameter, encrypted XML, environment variables, interactive prompt |
| **TestMode** | Generate realistic sample reports without any vCenter connectivity |
| **Email Delivery** | Opt-in SMTP email with HTML body, CC support, and SSL |
| **Performance Mode** | `-SkipCreatorLookup` bypasses expensive `Get-VIEvent` queries |
| **CI/CD Ready** | Pester unit tests + GitHub Actions pipeline with PSScriptAnalyzer |

---

## Requirements

- **PowerShell** 5.1+ (PowerShell 7+ recommended)
- **[VMware PowerCLI](https://developer.vmware.com/powercli)** module
- **Read-only** access to vCenter Server
- SMTP server access *(optional, only for email delivery)*

---

## Quick Start

```powershell
# 1. Clone
git clone https://github.com/canberkys/VMware-Snapshot-Reporter.git
cd VMware-Snapshot-Reporter

# 2. Install PowerCLI (if needed)
Install-Module VMware.PowerCLI -Scope CurrentUser

# 3. Configure
Copy-Item config.example.json config.json
# Edit config.json with your vCenter and SMTP settings

# 4. Run in test mode (no vCenter required)
.\VMware-Snapshot-Reporter.ps1 -TestMode
```

### Usage Examples

```powershell
# Single vCenter with interactive credential prompt
.\VMware-Snapshot-Reporter.ps1 -VCenterServer vcsa.lab.local

# Multiple vCenters, all export formats
.\VMware-Snapshot-Reporter.ps1 -VCenterServer vcsa01.lab.local, vcsa02.lab.local -ReportFormat All

# Send email report
.\VMware-Snapshot-Reporter.ps1 -VCenterServer vcsa.lab.local -SendEmail

# Fast mode — skip creator lookup
.\VMware-Snapshot-Reporter.ps1 -VCenterServer vcsa.lab.local -SkipCreatorLookup

# Pass credentials directly
$cred = Get-Credential
.\VMware-Snapshot-Reporter.ps1 -VCenterServer vcsa.lab.local -Credential $cred -SendEmail -ReportFormat All
```

---

## Configuration

Copy `config.example.json` to `config.json` and edit:

```json
{
    "vcenterServers": ["vcsa01.lab.local", "vcsa02.lab.local"],
    "riskThresholds": { "highRiskDays": 7, "mediumRiskDays": 3 },
    "sizeThresholds": { "largeGB": 50, "mediumGB": 10 },
    "email": {
        "smtpServer": "smtp.domain.com",
        "smtpPort": 25,
        "useSSL": false,
        "from": "vmware-reports@domain.com",
        "to": ["it-team@domain.com"],
        "cc": [],
        "subjectTemplate": "{0} Daily Snapshot Report"
    },
    "poweredOnOnly": true,
    "maxEventSamples": 1000,
    "sortBy": "SizeGB"
}
```

> `config.json` is gitignored. Only `config.example.json` is committed.

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `-VCenterServer` | `string[]` | Target vCenter server(s). Falls back to `config.json`. |
| `-Credential` | `PSCredential` | vCenter credentials. Falls back to credential chain. |
| `-ConfigFile` | `string` | Path to config file. Default: `./config.json` |
| `-OutputPath` | `string` | Report output directory. Default: `./output` |
| `-ReportFormat` | `string` | `HTML`, `JSON`, `CSV`, or `All` |
| `-SendEmail` | `switch` | Send report via SMTP email |
| `-SkipCreatorLookup` | `switch` | Skip `Get-VIEvent` queries for faster execution |
| `-TestMode` | `switch` | Use mock data, no vCenter connection needed |

---

## Credential Management

Credentials are resolved in order:

| Priority | Method | Use Case |
|----------|--------|----------|
| 1 | `-Credential` parameter | Scripts, automation |
| 2 | Encrypted XML (`~/.snapshot-reporter-cred.xml`) | Recurring scheduled tasks |
| 3 | Environment variables (`VCENTER_USERNAME` / `VCENTER_PASSWORD`) | CI/CD pipelines |
| 4 | Interactive `Get-Credential` prompt | Ad-hoc manual runs |

```powershell
# Save credentials for scheduled tasks (encrypted, machine+user bound)
Get-Credential | Export-Clixml -Path ~/.snapshot-reporter-cred.xml
```

```bash
# CI/CD environment variables
export VCENTER_USERNAME="svc-snapshot@vsphere.local"
export VCENTER_PASSWORD="secure-password"
```

> **Note:** Encrypted XML files use DPAPI on Windows — they are bound to the machine and user that created them. Use environment variables for cross-machine or CI/CD scenarios.

---

## Project Structure

```
VMware-Snapshot-Reporter/
├── VMware-Snapshot-Reporter.ps1     # Main orchestrator script
├── config.example.json               # Configuration template
├── checks/
│   ├── Get-SnapshotCreator.ps1       # Event-based snapshot creator lookup
│   ├── Get-SnapshotInventory.ps1     # Snapshot data collection from vCenter
│   └── Invoke-RiskAssessment.ps1     # Risk/size classification engine
├── report/
│   └── New-HtmlReport.ps1            # HTML report generation + CSV/JSON export
├── tests/
│   ├── Invoke-RiskAssessment.Tests.ps1
│   ├── Get-SnapshotInventory.Tests.ps1
│   └── VMware-Snapshot-Reporter.Tests.ps1
├── docs/
│   └── index.html                     # Live report preview (GitHub Pages)
├── output/                            # Generated reports (gitignored)
├── .github/workflows/ci.yml          # CI pipeline (Pester + PSScriptAnalyzer)
├── CHANGELOG.md
└── license.txt
```

---

## Scheduling

### Windows Task Scheduler

```powershell
$action  = New-ScheduledTaskAction -Execute "pwsh.exe" `
    -Argument "-File C:\Scripts\VMware-Snapshot-Reporter\VMware-Snapshot-Reporter.ps1 -SendEmail"
$trigger = New-ScheduledTaskTrigger -Daily -At "08:00AM"
Register-ScheduledTask -TaskName "VMware Snapshot Report" -Action $action -Trigger $trigger -RunLevel Highest
```

### Linux Cron

```bash
0 8 * * * /usr/bin/pwsh -File /opt/scripts/VMware-Snapshot-Reporter/VMware-Snapshot-Reporter.ps1 -SendEmail
```

---

## Testing

```powershell
# Install Pester
Install-Module Pester -MinimumVersion 5.0 -Force

# Run all tests
Invoke-Pester ./tests -Output Detailed

# Run specific test
Invoke-Pester ./tests/Invoke-RiskAssessment.Tests.ps1 -Output Detailed
```

---

## Migration from v2.0

1. Pull the latest changes or clone fresh
2. `Copy-Item config.example.json config.json`
3. Move your vCenter, SMTP, and threshold settings into `config.json`
4. Remove hardcoded credentials from any old scripts
5. Add `-SendEmail` flag — email is now opt-in

---

## License

[MIT](license.txt)

## Author

**Canberk Kilicarslan** — [GitHub](https://github.com/canberkys)
