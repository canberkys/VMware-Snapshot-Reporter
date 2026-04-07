BeforeAll {
    . (Join-Path $PSScriptRoot ".." "checks" "Invoke-RiskAssessment.ps1")

    function New-TestSnapshot {
        param([int]$Duration, [int]$SizeGB, [string]$VM = "TEST-VM")
        return [PSCustomObject]@{
            VM          = $VM
            Name        = "Snapshot-$Duration"
            Created     = (Get-Date).AddDays(-$Duration)
            Duration    = $Duration
            Description = "Test snapshot"
            SizeGB      = $SizeGB
            Username    = "testuser"
            VCenter     = "vcsa-test"
        }
    }
}

Describe "Invoke-RiskAssessment" {

    Context "Risk Classification" {
        It "Classifies snapshot older than 7 days as High risk" {
            $snap = New-TestSnapshot -Duration 10 -SizeGB 5
            $result = Invoke-RiskAssessment -Snapshots @($snap)
            $result.Snapshots[0].RiskLevel | Should -Be "High"
        }

        It "Classifies snapshot between 3 and 7 days as Medium risk" {
            $snap = New-TestSnapshot -Duration 5 -SizeGB 5
            $result = Invoke-RiskAssessment -Snapshots @($snap)
            $result.Snapshots[0].RiskLevel | Should -Be "Medium"
        }

        It "Classifies snapshot younger than 3 days as Low risk" {
            $snap = New-TestSnapshot -Duration 1 -SizeGB 5
            $result = Invoke-RiskAssessment -Snapshots @($snap)
            $result.Snapshots[0].RiskLevel | Should -Be "Low"
        }

        It "Classifies 0-day snapshot as Low risk" {
            $snap = New-TestSnapshot -Duration 0 -SizeGB 1
            $result = Invoke-RiskAssessment -Snapshots @($snap)
            $result.Snapshots[0].RiskLevel | Should -Be "Low"
        }

        It "Classifies exactly 7-day boundary as High risk" {
            $snap = New-TestSnapshot -Duration 7 -SizeGB 5
            $result = Invoke-RiskAssessment -Snapshots @($snap)
            $result.Snapshots[0].RiskLevel | Should -Be "High"
        }

        It "Classifies exactly 3-day boundary as Medium risk" {
            $snap = New-TestSnapshot -Duration 3 -SizeGB 5
            $result = Invoke-RiskAssessment -Snapshots @($snap)
            $result.Snapshots[0].RiskLevel | Should -Be "Medium"
        }
    }

    Context "Size Classification" {
        It "Classifies snapshot larger than 50 GB as Large" {
            $snap = New-TestSnapshot -Duration 1 -SizeGB 100
            $result = Invoke-RiskAssessment -Snapshots @($snap)
            $result.Snapshots[0].SizeCategory | Should -Be "Large"
        }

        It "Classifies snapshot between 10-50 GB as Medium" {
            $snap = New-TestSnapshot -Duration 1 -SizeGB 25
            $result = Invoke-RiskAssessment -Snapshots @($snap)
            $result.Snapshots[0].SizeCategory | Should -Be "Medium"
        }

        It "Classifies snapshot smaller than 10 GB as Normal" {
            $snap = New-TestSnapshot -Duration 1 -SizeGB 5
            $result = Invoke-RiskAssessment -Snapshots @($snap)
            $result.Snapshots[0].SizeCategory | Should -Be "Normal"
        }

        It "Classifies 0 GB snapshot as Normal" {
            $snap = New-TestSnapshot -Duration 1 -SizeGB 0
            $result = Invoke-RiskAssessment -Snapshots @($snap)
            $result.Snapshots[0].SizeCategory | Should -Be "Normal"
        }
    }

    Context "Custom Thresholds" {
        It "Respects custom risk thresholds" {
            $snap = New-TestSnapshot -Duration 5 -SizeGB 5
            $result = Invoke-RiskAssessment -Snapshots @($snap) -HighRiskDays 4 -MediumRiskDays 2
            $result.Snapshots[0].RiskLevel | Should -Be "High"
        }

        It "Respects custom size thresholds" {
            $snap = New-TestSnapshot -Duration 1 -SizeGB 15
            $result = Invoke-RiskAssessment -Snapshots @($snap) -LargeGB 20 -MediumGB 5
            $result.Snapshots[0].SizeCategory | Should -Be "Medium"
        }
    }

    Context "Summary Statistics" {
        BeforeAll {
            $snaps = @(
                (New-TestSnapshot -Duration 10 -SizeGB 50 -VM "VM-1")
                (New-TestSnapshot -Duration 5  -SizeGB 20 -VM "VM-2")
                (New-TestSnapshot -Duration 1  -SizeGB 5  -VM "VM-3")
                (New-TestSnapshot -Duration 8  -SizeGB 30 -VM "VM-4")
            )
            $script:result = Invoke-RiskAssessment -Snapshots $snaps
        }

        It "Calculates correct total count" {
            $script:result.Summary.TotalCount | Should -Be 4
        }

        It "Calculates correct total size" {
            $script:result.Summary.TotalSizeGB | Should -Be 105
        }

        It "Counts high risk snapshots correctly" {
            $script:result.Summary.HighRiskCount | Should -Be 2
        }

        It "Counts medium risk snapshots correctly" {
            $script:result.Summary.MediumRiskCount | Should -Be 1
        }

        It "Counts low risk snapshots correctly" {
            $script:result.Summary.LowRiskCount | Should -Be 1
        }

        It "Identifies oldest snapshot days" {
            $script:result.Summary.OldestSnapDays | Should -Be 10
        }

        It "Identifies newest snapshot days" {
            $script:result.Summary.NewestSnapDays | Should -Be 1
        }

        It "Sorts snapshots by size descending" {
            $script:result.Snapshots[0].SizeGB | Should -BeGreaterOrEqual $script:result.Snapshots[-1].SizeGB
        }
    }

    Context "Edge Cases" {
        It "Handles empty snapshot array" {
            $result = Invoke-RiskAssessment -Snapshots @()
            $result.Summary.TotalCount | Should -Be 0
            $result.Summary.TotalSizeGB | Should -Be 0
            $result.Snapshots.Count | Should -Be 0
        }

        It "Handles single snapshot" {
            $snap = New-TestSnapshot -Duration 3 -SizeGB 10
            $result = Invoke-RiskAssessment -Snapshots @($snap)
            $result.Summary.TotalCount | Should -Be 1
        }
    }
}
