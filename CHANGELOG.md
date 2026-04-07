# Changelog

## [3.0.1] - 2026-04-08

### Removed
- `config.json` from repository (user-specific, now gitignored — use `config.example.json` as template)
- `mail-example-output.png` (outdated v2.0 screenshot, replaced with live HTML preview)

### Added
- Live report preview via GitHub Pages (`docs/sample-report.html`)

### Fixed
- `.gitignore` now properly excludes `config.json`
- README references to removed files cleaned up

---

## [3.0.0] - 2026-04-08

### Added
- **Modular architecture**: Split monolithic script into `checks/` and `report/` modules
- **Multi-vCenter support**: Scan multiple vCenter servers in a single run with `-VCenterServer` array parameter
- **External configuration**: `config.json` for all settings (thresholds, SMTP, vCenter servers)
- **Secure credential handling**: Credential chain — parameter, encrypted XML file, environment variables, interactive prompt
- **CSV export**: `-ReportFormat CSV` for spreadsheet-compatible output
- **JSON export**: `-ReportFormat JSON` for programmatic consumption
- **TestMode**: `-TestMode` flag generates reports with realistic mock data (no vCenter required)
- **SkipCreatorLookup**: `-SkipCreatorLookup` flag to skip expensive `Get-VIEvent` queries
- **Logging**: Automatic log file generation in output directory
- **Pester tests**: Unit tests for risk assessment, snapshot inventory, and configuration validation
- **GitHub Actions CI**: Automated testing and PSScriptAnalyzer linting
- **vCenter column**: HTML report now shows source vCenter for multi-server environments
- **CmdletBinding**: Full PowerShell parameter validation with `SupportsShouldProcess`

### Changed
- **Configuration**: Moved from hardcoded variables to `config.json`
- **Email sending**: Now opt-in via `-SendEmail` flag instead of automatic
- **Backup path**: Cross-platform output directory instead of hardcoded `C:\temp`
- **Report output**: Reports saved to `./output/` directory by default

### Security
- **Removed plain-text password**: Replaced with PSCredential, encrypted XML, and environment variable support
- **Credential file**: Machine+user-bound encryption via `Export-Clixml`

### Removed
- Hardcoded vCenter, SMTP, and credential configuration from main script

## [2.0.0] - 2025-09-28

### Initial release
- Single-file snapshot reporting script
- Color-coded HTML email reports
- Risk assessment based on snapshot age
- Responsive email design with mobile support
