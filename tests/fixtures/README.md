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

Mock releases are generated dynamically by test helper scripts and Pester tests. In normal
development and CI runs you do not need to create anything manually in `mock-releases/` —
the tests will create and clean up their own fixtures under `$env:TEMP`.

If you want to explore how mock releases are built, inspect the helper scripts under the `tests/`
directory (for example `tests/New-FakePack.ps1`) and the integration test suites in
`tests/integration/`. Those scripts document the supported parameters and how mock release
fixtures are laid out on disk.

## Mock Installation

Mock installations used in tests are created programmatically by the integration test suites,
usually in unique, temporary directories under `$env:TEMP` to avoid polluting the repository
or any real installation.

To experiment manually, follow the patterns used in the existing test helpers and create a
temporary directory (for example `Join-Path $env:TEMP ([guid]::NewGuid().ToString())`) that
mimics the expected installation structure. The exact layout and required files are described
in the tests under `tests/integration/`.

## Usage in Tests

Tests automatically generate fixtures in `$env:TEMP` to avoid polluting the repository. Fixtures are cleaned up after test execution.

## Sample Apps

The `sample-apps/` directory contains minimal application structures used for testing delta generation and application.
