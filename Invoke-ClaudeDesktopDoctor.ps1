<#
.SYNOPSIS
    Runs the read-only, offline-by-default Claude Desktop Doctor for Windows.

.DESCRIPTION
    Collects allowlisted system metadata and writes JSON and Markdown reports.
    The command never changes Windows or Claude Desktop state. Network checks run
    only when -IncludeNetwork is explicitly supplied.

.PARAMETER OutputDirectory
    Directory that receives diagnostic-report.json and diagnostic-report.md.

.PARAMETER IncludeNetwork
    Enables DNS, TCP 443, and TLS checks for the selected allowlisted hosts.

.PARAMETER NetworkHosts
    One or more public hosts from the fixed allowlist.

.OUTPUTS
    Process exit code 0 (pass), 1 (warning), 2 (failed check), or 3 (internal error).
#>
[CmdletBinding()]
param(
    [string] $OutputDirectory = (Join-Path (Get-Location).Path "doctor-output"),

    [switch] $IncludeNetwork,

    [ValidateSet("claude.ai", "docs.anthropic.com", "downloads.claude.ai")]
    [string[]] $NetworkHosts = @("claude.ai")
)

$ErrorActionPreference = "Stop"

try {
    $modulePath = Join-Path $PSScriptRoot "src\ClaudeDesktopDoctor.psm1"
    Import-Module $modulePath -Force -ErrorAction Stop

    $report = Invoke-ClaudeDesktopDoctor `
        -IncludeNetwork:$IncludeNetwork `
        -NetworkHosts $NetworkHosts

    Write-DoctorReports -Report $report -OutputDirectory $OutputDirectory | Out-Null

    Write-Host "Claude Desktop Doctor completed."
    Write-Host "JSON and Markdown reports were written to the requested output directory."
    Write-Host ("Result: {0} pass, {1} warning, {2} fail, {3} skipped." -f `
        $report.summary.pass, `
        $report.summary.warn, `
        $report.summary.fail, `
        $report.summary.skipped)

    exit ([int] $report.summary.exitCode)
}
catch {
    # Deliberately do not print the exception. Exception text can contain paths,
    # network addresses, or other workstation-specific data.
    Write-Error "DOCTOR_INTERNAL_ERROR: The diagnostic run could not be completed safely."
    exit 3
}
