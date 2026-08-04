[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$modulePath = Join-Path $repoRoot "src\ClaudeDesktopDoctor.psm1"
$schemaPath = Join-Path $repoRoot "schemas\diagnostic-report.schema.json"

function Assert-True {
    param(
        [Parameter(Mandatory = $true)]
        [bool] $Condition,

        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    if (-not $Condition) {
        throw "ASSERTION_FAILED: $Message"
    }
}

function Assert-Equal {
    param(
        [AllowNull()] $Actual,
        [AllowNull()] $Expected,
        [Parameter(Mandatory = $true)][string] $Message
    )

    if ($Actual -ne $Expected) {
        throw "ASSERTION_FAILED: $Message. Expected='$Expected' Actual='$Actual'."
    }
}

function Assert-PropertyNames {
    param(
        [Parameter(Mandatory = $true)] $Object,
        [Parameter(Mandatory = $true)][string[]] $Expected,
        [Parameter(Mandatory = $true)][string] $Context
    )

    $actual = @($Object.PSObject.Properties.Name | Sort-Object)
    $wanted = @($Expected | Sort-Object)
    Assert-Equal -Actual ($actual -join "|") -Expected ($wanted -join "|") -Message "$Context uses the strict property allowlist"
}

# Parse every PowerShell file before importing the module. This uses the parser
# built into both Windows PowerShell 5.1 and PowerShell 7.
$parseErrors = New-Object System.Collections.Generic.List[object]
foreach ($powerShellFile in Get-ChildItem -LiteralPath $repoRoot -Recurse -File | Where-Object { $_.Extension -in @(".ps1", ".psm1") }) {
    $tokens = $null
    $errors = $null
    [void] [System.Management.Automation.Language.Parser]::ParseFile(
        $powerShellFile.FullName,
        [ref] $tokens,
        [ref] $errors
    )
    foreach ($parseError in @($errors)) {
        $parseErrors.Add($parseError)
    }
}
Assert-Equal -Actual $parseErrors.Count -Expected 0 -Message "All PowerShell files parse"

Import-Module $modulePath -Force

$schema = Get-Content -Raw -Encoding UTF8 -LiteralPath $schemaPath | ConvertFrom-Json
Assert-Equal -Actual $schema.title -Expected "Claude Desktop Doctor diagnostic report" -Message "Schema parses"
Assert-Equal -Actual $schema.additionalProperties -Expected $false -Message "Top-level schema rejects extra properties"

$report = Invoke-ClaudeDesktopDoctor

Assert-Equal -Actual $report.schemaVersion -Expected "1.0.0" -Message "Report schema version"
Assert-Equal -Actual $report.network.mode -Expected "offline" -Message "Default run is offline"
Assert-Equal -Actual @($report.network.endpoints).Count -Expected 0 -Message "Default run creates no network endpoint result"
Assert-Equal -Actual $report.privacy.mode -Expected "strict-allowlist" -Message "Privacy mode"
Assert-Equal -Actual $report.privacy.configContentRead -Expected $false -Message "Configuration content is not read"
Assert-Equal -Actual $report.privacy.rawLogsRead -Expected $false -Message "Raw logs are not read"
Assert-Equal -Actual $report.privacy.secretValuesRead -Expected $false -Message "Secret values are not read"
Assert-Equal -Actual $report.configuration.contentInspected -Expected $false -Message "Configuration inspection remains metadata-only"
Assert-True -Condition (@($report.checks | Where-Object { $_.id -eq "network.offline" -and $_.status -eq "SKIPPED" }).Count -eq 1) -Message "Offline network check is explicit"

Assert-PropertyNames -Object $report -Expected @(
    "schemaVersion", "tool", "generatedAtUtc", "privacy", "system",
    "installation", "configuration", "network", "checks", "summary"
) -Context "Report root"
Assert-PropertyNames -Object $report.privacy -Expected @(
    "mode", "configContentRead", "rawLogsRead", "secretValuesRead", "containsSensitiveData"
) -Context "Privacy object"
Assert-PropertyNames -Object $report.system -Expected @(
    "osFamily", "osBuild", "architecture", "powershellVersion", "wingetAvailable", "systemProxyEnabled"
) -Context "System object"
Assert-PropertyNames -Object $report.installation -Expected @(
    "detected", "channel", "version", "signatureStatus", "processRunning"
) -Context "Installation object"

foreach ($item in @($report.configuration.files)) {
    Assert-PropertyNames -Object $item -Expected @("id", "present") -Context "Configuration item"
    Assert-True -Condition (-not ($item.PSObject.Properties.Name -contains "path")) -Message "Configuration paths are absent"
}

$checkTotal = $report.summary.pass + $report.summary.warn + $report.summary.fail + $report.summary.unknown + $report.summary.skipped
Assert-Equal -Actual $checkTotal -Expected @($report.checks).Count -Message "Summary count matches checks"
$expectedExitCode = if ($report.summary.fail -gt 0) { 2 } elseif ($report.summary.warn -gt 0) { 1 } else { 0 }
Assert-Equal -Actual $report.summary.exitCode -Expected $expectedExitCode -Message "Exit code follows severity"

# Build synthetic sensitive strings at runtime so the repository contains no
# credential-shaped fixture literal.
$syntheticToken = ("gh" + "p_" + ("x" * 20))
$syntheticJwt = ("eyJ" + ("a" * 10) + "." + ("b" * 10) + "." + ("c" * 10))
$credentialUrl = ("https://person" + ":pass@example.invalid/path")
$unsafe = "$credentialUrl`?token=$syntheticToken C:\Users\Example\private.json person@example.invalid $syntheticJwt"
$redacted = ConvertTo-DoctorSafeText -Text $unsafe
Assert-True -Condition (-not $redacted.Contains("person:pass")) -Message "URL credentials are redacted"
Assert-True -Condition (-not $redacted.Contains($syntheticToken)) -Message "Query tokens are redacted"
Assert-True -Condition (-not $redacted.Contains("C:\Users\Example")) -Message "User paths are redacted"
Assert-True -Condition (-not $redacted.Contains("person@example.invalid")) -Message "Email addresses are redacted"
Assert-True -Condition (-not $redacted.Contains($syntheticJwt)) -Message "JWT-shaped values are redacted"

$invalidHostRejected = $false
try {
    Invoke-ClaudeDesktopDoctor -IncludeNetwork -NetworkHosts @("localhost") | Out-Null
}
catch {
    $invalidHostRejected = $true
}
Assert-True -Condition $invalidHostRejected -Message "Non-allowlisted network hosts are rejected before probing"

$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("claude-desktop-doctor-tests-" + [Guid]::NewGuid().ToString("N"))
try {
    $written = Write-DoctorReports -Report $report -OutputDirectory $temporaryRoot
    Assert-Equal -Actual $written.jsonFileName -Expected "diagnostic-report.json" -Message "JSON filename is fixed"
    Assert-Equal -Actual $written.markdownFileName -Expected "diagnostic-report.md" -Message "Markdown filename is fixed"

    $jsonPath = Join-Path $temporaryRoot $written.jsonFileName
    $markdownPath = Join-Path $temporaryRoot $written.markdownFileName
    Assert-True -Condition (Test-Path -LiteralPath $jsonPath -PathType Leaf) -Message "JSON report is written"
    Assert-True -Condition (Test-Path -LiteralPath $markdownPath -PathType Leaf) -Message "Markdown report is written"

    $roundTrip = Get-Content -Raw -Encoding UTF8 -LiteralPath $jsonPath | ConvertFrom-Json
    Assert-Equal -Actual $roundTrip.schemaVersion -Expected "1.0.0" -Message "JSON report round trip"

    $serialized = Get-Content -Raw -Encoding UTF8 -LiteralPath $jsonPath
    foreach ($forbiddenText in @(
        [string] $env:USERPROFILE,
        [string] $env:USERNAME,
        [string] $env:COMPUTERNAME,
        "ProxyServer",
        "PackageFullName",
        "InstallLocation",
        "commandLine",
        "configurationContent"
    )) {
        if (-not [string]::IsNullOrWhiteSpace($forbiddenText)) {
            Assert-True -Condition (-not $serialized.Contains($forbiddenText)) -Message "Serialized report omits forbidden identity or raw metadata"
        }
    }

    $markdown = Get-Content -Raw -Encoding UTF8 -LiteralPath $markdownPath
    Assert-True -Condition $markdown.Contains("# Claude Desktop Doctor Report") -Message "Markdown report has a stable title"
    Assert-True -Condition $markdown.Contains("Configuration contents") -Message "Markdown report states its privacy boundary"
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}

$requiredFiles = @(
    "README.md",
    "LICENSE",
    "PRIVACY.md",
    "SECURITY.md",
    "CONTRIBUTING.md",
    "CHANGELOG.md",
    "docs\diagnostic-decision-tree.md",
    "docs\compatibility-and-maintenance.md",
    "schemas\diagnostic-report.schema.json",
    ".github\workflows\test.yml",
    ".github\ISSUE_TEMPLATE\bug-report.yml",
    ".github\ISSUE_TEMPLATE\environment-report.yml"
)
foreach ($requiredFile in $requiredFiles) {
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $repoRoot $requiredFile) -PathType Leaf) -Message "Required repository file exists: $requiredFile"
}

$readme = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $repoRoot "README.md")
Assert-True -Condition ($readme.Contains("https://claudeu.com/?utm_source=github&utm_medium=organic&utm_campaign=claude_desktop_doctor&utm_content=readme_recommendation_card")) -Message "README recommendation card uses the product homepage and scoped campaign"
Assert-True -Condition ($readme.Contains("provider API key")) -Message "README recommendation card describes the provider-key boundary"
Assert-True -Condition ($readme.Contains("40%")) -Message "README recommendation card qualifies the current discount"
Assert-True -Condition (-not ($readme -match 'https://claudeu\.com/(?:zh-CN|en-US)/(?:download|guide|support)')) -Message "README has no deprecated GitHub-specific ClaudeU destination"
Assert-True -Condition ($readme.Contains("not affiliated with")) -Message "README contains the independence disclaimer"

Assert-True -Condition (@([regex]::Matches($readme, '(?m)^### ')).Count -ge 10) -Message "README contains a complete professional section hierarchy"
foreach ($requiredReference in @(
    "docs/diagnostic-decision-tree.md",
    "docs/compatibility-and-maintenance.md",
    "PRIVACY.md",
    "SECURITY.md",
    "CONTRIBUTING.md",
    "schemas/diagnostic-report.schema.json"
)) {
    Assert-True -Condition ($readme.Contains($requiredReference)) -Message "README links required reader guidance: $requiredReference"
}

$allMarkdown = Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Filter "*.md"
foreach ($markdownFile in $allMarkdown) {
    $markdownText = Get-Content -Raw -Encoding UTF8 -LiteralPath $markdownFile.FullName
    Assert-True -Condition (-not ($markdownText -match 'https://claudeu\.com/(?:zh-CN|en-US)/(?:download|guide|support)')) -Message "Markdown uses no deprecated ClaudeU destination: $($markdownFile.Name)"
}

Write-Host "PASS: dependency-free Doctor tests"
