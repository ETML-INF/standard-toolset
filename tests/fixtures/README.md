# Test Fixtures

This directory contains pre-built test fixtures for integration testing.

## Directory Structure

```
fixtures/
├── mock-releases/         # Simulated GitHub releases (generated on-demand)
├── sample-apps/          # Sample application structures
└── README.md             # This file
```

## Generating Mock Releases

Mock releases are generated dynamically by test helper scripts. To manually create mock releases:

```powershell
# Import helper
. .\tests\helpers\New-MockReleaseRepository.ps1

# Create mock repository
$mockRepo = New-MockReleaseRepository -Releases @(
    @{
        Tag = "v1.9.0"
        Apps = @{git="2.40.0"; node="18.0.0"; python="3.11.0"}
    },
    @{
        Tag = "v1.9.1"
        Apps = @{git="2.40.0"; node="20.0.0"; python="3.11.0"}
        Delta = $true
    }
) -OutputPath ".\tests\fixtures\mock-releases"
```

## Mock Installation

To create a mock installation for testing:

```powershell
# Import helper
. .\tests\helpers\New-MockInstallation.ps1

# Create mock installation
$install = New-MockInstallation `
    -Version "v1.9.0" `
    -Apps @{git="2.40.0"; node="18.0.0"; python="3.11.0"} `
    -OutputPath "C:\temp\test-install"
```

## Usage in Tests

Tests automatically generate fixtures in `$env:TEMP` to avoid polluting the repository. Fixtures are cleaned up after test execution.

## Sample Apps

The `sample-apps/` directory contains minimal application structures used for testing delta generation and application.
