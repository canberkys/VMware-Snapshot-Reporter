BeforeAll {
    . (Join-Path $PSScriptRoot ".." "checks" "Get-SnapshotCreator.ps1")
    . (Join-Path $PSScriptRoot ".." "checks" "Get-SnapshotInventory.ps1")
}

Describe "Get-SnapshotInventory" {

    Context "With mocked VMware cmdlets" {

        BeforeAll {
            # Mock VMware cmdlets
            function Get-VM { }
            function Get-Snapshot { }
            function Get-VIEvent { }

            $mockDate = (Get-Date).AddDays(-5)

            Mock Get-VM {
                return @(
                    [PSCustomObject]@{ Name = "VM-01"; PowerState = "PoweredOn" }
                    [PSCustomObject]@{ Name = "VM-02"; PowerState = "PoweredOff" }
                )
            }

            Mock Get-Snapshot {
                return @(
                    [PSCustomObject]@{
                        VM          = [PSCustomObject]@{ Name = "VM-01" }
                        Name        = "Test Snapshot"
                        Created     = $mockDate
                        Description = "Test description"
                        SizeGB      = 10.7
                    }
                )
            }

            Mock Get-VIEvent { return $null }
        }

        It "Returns snapshot objects with required properties" {
            $result = Get-SnapshotInventory -SkipCreatorLookup -VCenterName "test-vc"
            $result | Should -Not -BeNullOrEmpty
            $result[0].PSObject.Properties.Name | Should -Contain "VM"
            $result[0].PSObject.Properties.Name | Should -Contain "Name"
            $result[0].PSObject.Properties.Name | Should -Contain "Created"
            $result[0].PSObject.Properties.Name | Should -Contain "Duration"
            $result[0].PSObject.Properties.Name | Should -Contain "Description"
            $result[0].PSObject.Properties.Name | Should -Contain "SizeGB"
            $result[0].PSObject.Properties.Name | Should -Contain "Username"
            $result[0].PSObject.Properties.Name | Should -Contain "VCenter"
        }

        It "Sets VCenter property from parameter" {
            $result = Get-SnapshotInventory -SkipCreatorLookup -VCenterName "my-vcenter"
            $result[0].VCenter | Should -Be "my-vcenter"
        }

        It "Sets Username to Unknown when SkipCreatorLookup is used" {
            $result = Get-SnapshotInventory -SkipCreatorLookup
            $result[0].Username | Should -Be "Unknown"
        }

        It "Floors SizeGB value" {
            $result = Get-SnapshotInventory -SkipCreatorLookup
            $result[0].SizeGB | Should -Be 10
        }

        It "Calculates Duration correctly" {
            $result = Get-SnapshotInventory -SkipCreatorLookup
            $result[0].Duration | Should -Be 5
        }
    }

    Context "Empty results" {
        BeforeAll {
            function Get-VM { }
            function Get-Snapshot { }

            Mock Get-VM { return @() }
            Mock Get-Snapshot { return @() }
        }

        It "Returns empty array when no VMs exist" {
            $result = Get-SnapshotInventory -SkipCreatorLookup
            $result.Count | Should -Be 0
        }
    }
}
