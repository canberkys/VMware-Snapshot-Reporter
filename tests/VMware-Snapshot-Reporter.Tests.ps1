Describe "VMware-Snapshot-Reporter" {

    Context "Configuration" {
        BeforeAll {
            $script:configPath = Join-Path $PSScriptRoot ".." "config.json"
        }

        It "config.json exists and is valid JSON" {
            Test-Path $script:configPath | Should -BeTrue
            { Get-Content $script:configPath -Raw | ConvertFrom-Json } | Should -Not -Throw
        }

        It "config.json has required keys" {
            $config = Get-Content $script:configPath -Raw | ConvertFrom-Json
            $config.PSObject.Properties.Name | Should -Contain "vcenterServers"
            $config.PSObject.Properties.Name | Should -Contain "riskThresholds"
            $config.PSObject.Properties.Name | Should -Contain "sizeThresholds"
            $config.PSObject.Properties.Name | Should -Contain "email"
        }

        It "riskThresholds has highRiskDays and mediumRiskDays" {
            $config = Get-Content $script:configPath -Raw | ConvertFrom-Json
            $config.riskThresholds.PSObject.Properties.Name | Should -Contain "highRiskDays"
            $config.riskThresholds.PSObject.Properties.Name | Should -Contain "mediumRiskDays"
        }

        It "sizeThresholds has largeGB and mediumGB" {
            $config = Get-Content $script:configPath -Raw | ConvertFrom-Json
            $config.sizeThresholds.PSObject.Properties.Name | Should -Contain "largeGB"
            $config.sizeThresholds.PSObject.Properties.Name | Should -Contain "mediumGB"
        }

        It "email config has required fields" {
            $config = Get-Content $script:configPath -Raw | ConvertFrom-Json
            $config.email.PSObject.Properties.Name | Should -Contain "smtpServer"
            $config.email.PSObject.Properties.Name | Should -Contain "from"
            $config.email.PSObject.Properties.Name | Should -Contain "to"
        }
    }

    Context "config.example.json" {
        BeforeAll {
            $script:examplePath = Join-Path $PSScriptRoot ".." "config.example.json"
        }

        It "config.example.json exists and is valid JSON" {
            Test-Path $script:examplePath | Should -BeTrue
            { Get-Content $script:examplePath -Raw | ConvertFrom-Json } | Should -Not -Throw
        }

        It "config.example.json has same structure as config.json" {
            $config  = Get-Content (Join-Path $PSScriptRoot ".." "config.json") -Raw | ConvertFrom-Json
            $example = Get-Content $script:examplePath -Raw | ConvertFrom-Json

            $configKeys  = $config.PSObject.Properties.Name | Sort-Object
            $exampleKeys = $example.PSObject.Properties.Name | Sort-Object

            $exampleKeys | Should -Be $configKeys
        }
    }

    Context "Module Files" {
        It "checks/Get-SnapshotCreator.ps1 exists" {
            Test-Path (Join-Path $PSScriptRoot ".." "checks" "Get-SnapshotCreator.ps1") | Should -BeTrue
        }

        It "checks/Get-SnapshotInventory.ps1 exists" {
            Test-Path (Join-Path $PSScriptRoot ".." "checks" "Get-SnapshotInventory.ps1") | Should -BeTrue
        }

        It "checks/Invoke-RiskAssessment.ps1 exists" {
            Test-Path (Join-Path $PSScriptRoot ".." "checks" "Invoke-RiskAssessment.ps1") | Should -BeTrue
        }

        It "report/New-HtmlReport.ps1 exists" {
            Test-Path (Join-Path $PSScriptRoot ".." "report" "New-HtmlReport.ps1") | Should -BeTrue
        }
    }

    Context "Main Script" {
        It "VMware-Snapshot-Reporter.ps1 has CmdletBinding attribute" {
            $content = Get-Content (Join-Path $PSScriptRoot ".." "VMware-Snapshot-Reporter.ps1") -Raw
            $content | Should -Match '\[CmdletBinding\(SupportsShouldProcess\)\]'
        }

        It "VMware-Snapshot-Reporter.ps1 has required parameters" {
            $content = Get-Content (Join-Path $PSScriptRoot ".." "VMware-Snapshot-Reporter.ps1") -Raw
            $content | Should -Match '\$VCenterServer'
            $content | Should -Match '\$Credential'
            $content | Should -Match '\$ConfigFile'
            $content | Should -Match '\$OutputPath'
            $content | Should -Match '\$ReportFormat'
            $content | Should -Match '\$SendEmail'
            $content | Should -Match '\$TestMode'
        }
    }
}
