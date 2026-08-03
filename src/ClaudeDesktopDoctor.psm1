Set-StrictMode -Version 2.0

$script:DoctorVersion = "0.1.0"
$script:ReportSchemaVersion = "1.0.0"
$script:AllowedNetworkHosts = @(
    "claude.ai",
    "docs.anthropic.com",
    "downloads.claude.ai"
)

function ConvertTo-DoctorSafeText {
    <#
    .SYNOPSIS
        Applies defense-in-depth redaction to a short diagnostic string.

    .DESCRIPTION
        Reports are constructed from an allowlist and should never receive raw
        external text. This function is a second boundary for fixed messages and
        future contributors. It must not be used to justify collecting more data.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Text
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return ""
    }

    $safe = $Text

    # URL credentials, authorization values, and sensitive query parameters.
    $safe = $safe -replace '(?i)(https?://)[^/@\s:]+:[^/@\s]+@', '$1[REDACTED]@'
    $safe = $safe -replace '(?i)(authorization\s*[:=]\s*(?:bearer|basic)\s+)[^\s,;]+', '$1[REDACTED]'
    $safe = $safe -replace '(?i)([?&](?:api[_-]?key|token|secret|password|credential|auth)\s*=)[^&\s]+', '$1[REDACTED]'

    # Common token shapes. Values are never needed for a Doctor finding.
    $safe = $safe -replace '(?i)\b(?:gh[pousr]_|sk-)[A-Za-z0-9_-]{12,}\b', '[REDACTED-TOKEN]'
    $safe = $safe -replace '\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b', '[REDACTED-TOKEN]'

    # Identity-bearing paths, UNC paths, and email addresses.
    $safe = $safe -replace '(?i)\b[A-Z]:\\Users\\[^\\\s]+(?:\\[^\s]*)?', '[PATH]'
    $safe = $safe -replace '(?i)\\\\[^\\\s]+\\[^\s]+', '[PATH]'
    $safe = $safe -replace '(?i)\b[A-Z]:\\[^\s]+', '[PATH]'
    $safe = $safe -replace '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b', '[REDACTED-EMAIL]'

    foreach ($identityValue in @($env:USERPROFILE, $env:USERNAME, $env:COMPUTERNAME)) {
        if (-not [string]::IsNullOrWhiteSpace([string] $identityValue)) {
            $safe = $safe -replace [regex]::Escape([string] $identityValue), '[REDACTED-IDENTITY]'
        }
    }

    # Keep report cells single-line and bounded.
    $safe = ($safe -replace '[\r\n\t]+', ' ').Trim()
    if ($safe.Length -gt 240) {
        $safe = $safe.Substring(0, 237) + "..."
    }

    return $safe
}

function New-DoctorCheck {
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-z0-9][a-z0-9.-]+$')]
        [string] $Id,

        [Parameter(Mandatory = $true)]
        [ValidateSet("PASS", "WARN", "FAIL", "UNKNOWN", "SKIPPED")]
        [string] $Status,

        [Parameter(Mandatory = $true)]
        [string] $Title,

        [Parameter(Mandatory = $true)]
        [string] $Message,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-z0-9][a-z0-9.-]+$')]
        [string] $RemediationId
    )

    return [PSCustomObject][ordered]@{
        id = $Id
        status = $Status
        title = ConvertTo-DoctorSafeText -Text $Title
        message = ConvertTo-DoctorSafeText -Text $Message
        remediationId = $RemediationId
    }
}

function Get-DoctorArchitecture {
    if (-not [string]::IsNullOrWhiteSpace([string] $env:PROCESSOR_ARCHITEW6432)) {
        $value = [string] $env:PROCESSOR_ARCHITEW6432
    }
    else {
        $value = [string] $env:PROCESSOR_ARCHITECTURE
    }

    switch -Regex ($value.ToUpperInvariant()) {
        'ARM64' { return "arm64" }
        'AMD64' { return "x64" }
        'X86' { return "x86" }
        default { return "unknown" }
    }
}

function ConvertTo-DoctorVersion {
    param([AllowNull()][string] $Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $match = [regex]::Match($Value, '^\d+(?:\.\d+){0,3}(?:-[A-Za-z0-9.-]+)?$')
    if (-not $match.Success) {
        return $null
    }

    return $match.Value
}

function Get-DoctorSignatureStatus {
    param([AllowNull()][string] $ExecutablePath)

    if ([string]::IsNullOrWhiteSpace($ExecutablePath)) {
        return "not-checked"
    }

    if (-not (Test-Path -LiteralPath $ExecutablePath -PathType Leaf)) {
        return "not-checked"
    }

    $signatureCommand = Get-Command Get-AuthenticodeSignature -ErrorAction SilentlyContinue
    if ($null -eq $signatureCommand) {
        return "unavailable"
    }

    try {
        $status = [string] (Get-AuthenticodeSignature -FilePath $ExecutablePath -ErrorAction Stop).Status
        switch ($status) {
            "Valid" { return "valid" }
            "NotSigned" { return "not-signed" }
            "HashMismatch" { return "hash-mismatch" }
            "NotTrusted" { return "not-trusted" }
            default { return "unknown" }
        }
    }
    catch {
        return "unknown"
    }
}

function Get-ClaudeDesktopInstallation {
    $detected = $false
    $channel = "not-detected"
    $version = $null
    $executablePath = $null

    $getAppxPackage = Get-Command Get-AppxPackage -ErrorAction SilentlyContinue
    if ($null -ne $getAppxPackage) {
        foreach ($packageName in @("Claude", "Anthropic.Claude")) {
            try {
                $package = Get-AppxPackage -Name $packageName -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($null -ne $package) {
                    $detected = $true
                    $channel = "appx"
                    $version = ConvertTo-DoctorVersion -Value ([string] $package.Version)
                    break
                }
            }
            catch {
                # Detection remains best-effort; raw exception text is discarded.
            }
        }
    }

    if (-not $detected -and -not [string]::IsNullOrWhiteSpace([string] $env:LOCALAPPDATA)) {
        $candidateFiles = @(
            (Join-Path $env:LOCALAPPDATA "Programs\Claude\Claude.exe"),
            (Join-Path $env:LOCALAPPDATA "AnthropicClaude\Claude.exe")
        )

        $versionedRoot = Join-Path $env:LOCALAPPDATA "AnthropicClaude"
        if (Test-Path -LiteralPath $versionedRoot -PathType Container) {
            try {
                $versionedDirectories = Get-ChildItem -LiteralPath $versionedRoot -Directory -Filter "app-*" -ErrorAction SilentlyContinue |
                    Sort-Object -Property Name -Descending
                foreach ($directory in $versionedDirectories) {
                    $candidateFiles += Join-Path $directory.FullName "Claude.exe"
                }
            }
            catch {
                # The known location may be inaccessible. No path or exception is reported.
            }
        }

        foreach ($candidate in $candidateFiles) {
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                $detected = $true
                $channel = "classic"
                $executablePath = $candidate
                try {
                    $fileVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($candidate).FileVersion
                    $version = ConvertTo-DoctorVersion -Value ([string] $fileVersion)
                }
                catch {
                    $version = $null
                }
                break
            }
        }
    }

    $processRunning = $false
    try {
        $processRunning = ($null -ne (Get-Process -Name "Claude" -ErrorAction SilentlyContinue | Select-Object -First 1))
    }
    catch {
        $processRunning = $false
    }

    return [PSCustomObject][ordered]@{
        detected = [bool] $detected
        channel = $channel
        version = $version
        signatureStatus = Get-DoctorSignatureStatus -ExecutablePath $executablePath
        processRunning = [bool] $processRunning
    }
}

function Get-DoctorConfigurationPresence {
    $items = @()

    $knownFiles = @()
    if (-not [string]::IsNullOrWhiteSpace([string] $env:APPDATA)) {
        $knownFiles += [PSCustomObject]@{
            id = "roaming-claude-desktop-config"
            path = Join-Path $env:APPDATA "Claude\claude_desktop_config.json"
        }
    }
    if (-not [string]::IsNullOrWhiteSpace([string] $env:LOCALAPPDATA)) {
        $knownFiles += [PSCustomObject]@{
            id = "local-claude-desktop-config"
            path = Join-Path $env:LOCALAPPDATA "Claude\claude_desktop_config.json"
        }
    }

    foreach ($knownFile in $knownFiles) {
        $items += [PSCustomObject][ordered]@{
            id = [string] $knownFile.id
            present = [bool] (Test-Path -LiteralPath $knownFile.path -PathType Leaf)
        }
    }

    return @($items)
}

function Get-DoctorSystemProxyEnabled {
    $proxyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    try {
        $value = Get-ItemProperty -LiteralPath $proxyPath -Name ProxyEnable -ErrorAction SilentlyContinue
        if ($null -eq $value) {
            return $false
        }
        return ([int] $value.ProxyEnable -eq 1)
    }
    catch {
        return $false
    }
}

function Invoke-DoctorNetworkProbe {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("claude.ai", "docs.anthropic.com", "downloads.claude.ai")]
        [string] $HostName,

        [ValidateRange(500, 15000)]
        [int] $TimeoutMilliseconds = 5000
    )

    $dnsSucceeded = $false
    $tcpSucceeded = $false
    $tlsSucceeded = $false
    $tlsProtocol = $null

    try {
        $addresses = [System.Net.Dns]::GetHostAddresses($HostName)
        $dnsSucceeded = ($null -ne $addresses -and $addresses.Count -gt 0)
    }
    catch {
        $dnsSucceeded = $false
    }

    if ($dnsSucceeded) {
        $client = $null
        $sslStream = $null
        try {
            $client = New-Object System.Net.Sockets.TcpClient
            $connectResult = $client.BeginConnect($HostName, 443, $null, $null)
            if ($connectResult.AsyncWaitHandle.WaitOne($TimeoutMilliseconds, $false)) {
                $client.EndConnect($connectResult)
                $tcpSucceeded = $client.Connected
            }

            if ($tcpSucceeded) {
                $sslStream = New-Object System.Net.Security.SslStream($client.GetStream(), $false)
                $authResult = $sslStream.BeginAuthenticateAsClient($HostName, $null, $null)
                if ($authResult.AsyncWaitHandle.WaitOne($TimeoutMilliseconds, $false)) {
                    $sslStream.EndAuthenticateAsClient($authResult)
                    $tlsSucceeded = $sslStream.IsAuthenticated -and $sslStream.IsEncrypted
                    if ($tlsSucceeded) {
                        $protocolCandidate = [string] $sslStream.SslProtocol
                        if ($protocolCandidate -match '^Tls(?:11|12|13)?$') {
                            $tlsProtocol = $protocolCandidate
                        }
                        else {
                            $tlsProtocol = "other"
                        }
                    }
                }
            }
        }
        catch {
            # Fail closed and discard exception text, addresses, and certificate details.
        }
        finally {
            if ($null -ne $sslStream) {
                $sslStream.Dispose()
            }
            if ($null -ne $client) {
                $client.Close()
            }
        }
    }

    return [PSCustomObject][ordered]@{
        host = $HostName
        dnsSucceeded = [bool] $dnsSucceeded
        tcp443Succeeded = [bool] $tcpSucceeded
        tlsSucceeded = [bool] $tlsSucceeded
        tlsProtocol = $tlsProtocol
    }
}

function Invoke-ClaudeDesktopDoctor {
    [CmdletBinding()]
    param(
        [switch] $IncludeNetwork,

        [ValidateSet("claude.ai", "docs.anthropic.com", "downloads.claude.ai")]
        [string[]] $NetworkHosts = @("claude.ai")
    )

    $checks = New-Object System.Collections.ArrayList

    $platform = [Environment]::OSVersion.Platform
    $isWindows = ($platform -eq [PlatformID]::Win32NT)
    $osBuild = if ($isWindows) { [int] [Environment]::OSVersion.Version.Build } else { 0 }
    $architecture = Get-DoctorArchitecture
    $powerShellVersion = "{0}.{1}" -f $PSVersionTable.PSVersion.Major, $PSVersionTable.PSVersion.Minor
    $wingetAvailable = ($null -ne (Get-Command winget -ErrorAction SilentlyContinue))
    $systemProxyEnabled = Get-DoctorSystemProxyEnabled

    if ($isWindows) {
        [void] $checks.Add((New-DoctorCheck -Id "platform.windows" -Status "PASS" -Title "Windows detected" -Message "The Doctor is running on Windows." -RemediationId "none"))
    }
    else {
        [void] $checks.Add((New-DoctorCheck -Id "platform.windows" -Status "FAIL" -Title "Windows not detected" -Message "This Doctor supports Windows only." -RemediationId "run-on-windows"))
    }

    if ($PSVersionTable.PSVersion -ge [version] "5.1") {
        [void] $checks.Add((New-DoctorCheck -Id "runtime.powershell" -Status "PASS" -Title "PowerShell version" -Message "PowerShell 5.1 or newer is available." -RemediationId "none"))
    }
    else {
        [void] $checks.Add((New-DoctorCheck -Id "runtime.powershell" -Status "FAIL" -Title "PowerShell version" -Message "PowerShell 5.1 or newer is required." -RemediationId "upgrade-powershell"))
    }

    if ($architecture -in @("x64", "arm64")) {
        [void] $checks.Add((New-DoctorCheck -Id "platform.architecture" -Status "PASS" -Title "Processor architecture" -Message "A modern 64-bit architecture was detected." -RemediationId "none"))
    }
    else {
        [void] $checks.Add((New-DoctorCheck -Id "platform.architecture" -Status "WARN" -Title "Processor architecture" -Message "The detected architecture may require separate compatibility review." -RemediationId "review-architecture"))
    }

    $installation = Get-ClaudeDesktopInstallation
    if ($installation.detected) {
        [void] $checks.Add((New-DoctorCheck -Id "desktop.installation" -Status "PASS" -Title "Claude Desktop installation" -Message "Claude Desktop was detected in a known Windows installation channel." -RemediationId "none"))
    }
    else {
        [void] $checks.Add((New-DoctorCheck -Id "desktop.installation" -Status "WARN" -Title "Claude Desktop installation" -Message "Claude Desktop was not detected in the known Windows installation channels." -RemediationId "review-installation"))
    }

    if (-not $installation.detected) {
        [void] $checks.Add((New-DoctorCheck -Id "desktop.signature" -Status "SKIPPED" -Title "Executable signature" -Message "Signature inspection was skipped because no classic executable was detected." -RemediationId "review-installation"))
    }
    elseif ($installation.channel -eq "appx") {
        [void] $checks.Add((New-DoctorCheck -Id "desktop.signature" -Status "SKIPPED" -Title "Executable signature" -Message "Package installation was detected; individual executable signature inspection was not required." -RemediationId "none"))
    }
    elseif ($installation.signatureStatus -eq "valid") {
        [void] $checks.Add((New-DoctorCheck -Id "desktop.signature" -Status "PASS" -Title "Executable signature" -Message "The detected classic executable has a valid Authenticode signature." -RemediationId "none"))
    }
    elseif ($installation.signatureStatus -eq "hash-mismatch") {
        [void] $checks.Add((New-DoctorCheck -Id "desktop.signature" -Status "FAIL" -Title "Executable signature" -Message "The detected classic executable reports a signature hash mismatch." -RemediationId "reinstall-from-trusted-source"))
    }
    else {
        [void] $checks.Add((New-DoctorCheck -Id "desktop.signature" -Status "WARN" -Title "Executable signature" -Message "The detected classic executable signature could not be confirmed as valid." -RemediationId "reinstall-from-trusted-source"))
    }

    [void] $checks.Add((New-DoctorCheck -Id "desktop.process" -Status "PASS" -Title "Desktop process state" -Message $(if ($installation.processRunning) { "A Claude process is running." } else { "No Claude process is currently running; this is not an error." }) -RemediationId "none"))

    $configurationFiles = @(Get-DoctorConfigurationPresence)
    $presentConfigCount = @($configurationFiles | Where-Object { $_.present }).Count
    [void] $checks.Add((New-DoctorCheck -Id "configuration.presence" -Status "PASS" -Title "Configuration presence" -Message $(if ($presentConfigCount -gt 0) { "A known configuration filename is present; its content was not opened." } else { "No known custom configuration filename was found; this can be a valid default state." }) -RemediationId "none"))

    [void] $checks.Add((New-DoctorCheck -Id "network.proxy-state" -Status "PASS" -Title "System proxy state" -Message $(if ($systemProxyEnabled) { "The Windows system proxy switch is enabled; the proxy address was not read." } else { "The Windows system proxy switch is not enabled." }) -RemediationId "none"))

    $networkEndpoints = @()
    if ($IncludeNetwork) {
        $uniqueHosts = @($NetworkHosts | Select-Object -Unique)
        foreach ($hostName in $uniqueHosts) {
            if ($script:AllowedNetworkHosts -notcontains $hostName) {
                throw "Network host is outside the allowlist."
            }

            $endpoint = Invoke-DoctorNetworkProbe -HostName $hostName
            $networkEndpoints += $endpoint
            if ($endpoint.dnsSucceeded -and $endpoint.tcp443Succeeded -and $endpoint.tlsSucceeded) {
                [void] $checks.Add((New-DoctorCheck -Id ("network.{0}" -f ($hostName -replace '\.', '-')) -Status "PASS" -Title "Explicit network probe" -Message "DNS, TCP 443, and certificate-validating TLS checks succeeded for an allowlisted public host." -RemediationId "none"))
            }
            else {
                [void] $checks.Add((New-DoctorCheck -Id ("network.{0}" -f ($hostName -replace '\.', '-')) -Status "FAIL" -Title "Explicit network probe" -Message "One or more DNS, TCP 443, or certificate-validating TLS checks failed for an allowlisted public host." -RemediationId "review-network"))
            }
        }
    }
    else {
        [void] $checks.Add((New-DoctorCheck -Id "network.offline" -Status "SKIPPED" -Title "Network checks" -Message "Network checks were not requested; this run stayed offline." -RemediationId "none"))
    }

    $passCount = @($checks | Where-Object { $_.status -eq "PASS" }).Count
    $warnCount = @($checks | Where-Object { $_.status -eq "WARN" }).Count
    $failCount = @($checks | Where-Object { $_.status -eq "FAIL" }).Count
    $unknownCount = @($checks | Where-Object { $_.status -eq "UNKNOWN" }).Count
    $skippedCount = @($checks | Where-Object { $_.status -eq "SKIPPED" }).Count
    $exitCode = if ($failCount -gt 0) { 2 } elseif ($warnCount -gt 0) { 1 } else { 0 }

    return [PSCustomObject][ordered]@{
        schemaVersion = $script:ReportSchemaVersion
        tool = [PSCustomObject][ordered]@{
            name = "claude-desktop-doctor"
            version = $script:DoctorVersion
        }
        generatedAtUtc = [DateTime]::UtcNow.ToString("o")
        privacy = [PSCustomObject][ordered]@{
            mode = "strict-allowlist"
            configContentRead = $false
            rawLogsRead = $false
            secretValuesRead = $false
            containsSensitiveData = $false
        }
        system = [PSCustomObject][ordered]@{
            osFamily = if ($isWindows) { "windows" } else { "other" }
            osBuild = $osBuild
            architecture = $architecture
            powershellVersion = $powerShellVersion
            wingetAvailable = [bool] $wingetAvailable
            systemProxyEnabled = [bool] $systemProxyEnabled
        }
        installation = $installation
        configuration = [PSCustomObject][ordered]@{
            files = @($configurationFiles)
            contentInspected = $false
        }
        network = [PSCustomObject][ordered]@{
            mode = if ($IncludeNetwork) { "explicit" } else { "offline" }
            endpoints = @($networkEndpoints)
        }
        checks = @($checks)
        summary = [PSCustomObject][ordered]@{
            pass = $passCount
            warn = $warnCount
            fail = $failCount
            unknown = $unknownCount
            skipped = $skippedCount
            exitCode = $exitCode
        }
    }
}

function ConvertTo-DoctorMarkdown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Report
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Claude Desktop Doctor Report")
    $lines.Add("")
    $lines.Add("> This report contains allowlisted metadata only. Configuration contents, raw logs, secrets, identities, IP addresses, and complete paths were not collected.")
    $lines.Add("")
    $lines.Add("- Tool version: ``$($Report.tool.version)``")
    $lines.Add("- Generated at (UTC): ``$($Report.generatedAtUtc)``")
    $lines.Add("- Network mode: ``$($Report.network.mode)``")
    $lines.Add("- Exit code: ``$($Report.summary.exitCode)``")
    $lines.Add("")
    $lines.Add("## Summary")
    $lines.Add("")
    $lines.Add("| PASS | WARN | FAIL | UNKNOWN | SKIPPED |")
    $lines.Add("| ---: | ---: | ---: | ---: | ---: |")
    $lines.Add("| $($Report.summary.pass) | $($Report.summary.warn) | $($Report.summary.fail) | $($Report.summary.unknown) | $($Report.summary.skipped) |")
    $lines.Add("")
    $lines.Add("## Checks")
    $lines.Add("")
    $lines.Add("| Status | Check | Result | Remediation |")
    $lines.Add("| --- | --- | --- | --- |")

    foreach ($check in $Report.checks) {
        $title = (ConvertTo-DoctorSafeText -Text ([string] $check.title)) -replace '\|', '\|'
        $message = (ConvertTo-DoctorSafeText -Text ([string] $check.message)) -replace '\|', '\|'
        $remediation = (ConvertTo-DoctorSafeText -Text ([string] $check.remediationId)) -replace '\|', '\|'
        $lines.Add("| $($check.status) | $title | $message | ``$remediation`` |")
    }

    $lines.Add("")
    $lines.Add("## Safe next steps")
    $lines.Add("")
    $lines.Add("Use each remediation ID to find the matching guidance in the project README. Do not attach raw configuration files or logs to a public issue.")
    $lines.Add("")
    $lines.Add("This independent project is not affiliated with, endorsed by, sponsored by, or supported by Anthropic.")

    return ($lines -join [Environment]::NewLine)
}

function Write-DoctorReports {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Report,

        [Parameter(Mandatory = $true)]
        [string] $OutputDirectory
    )

    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        throw "Output directory is required."
    }

    if (Test-Path -LiteralPath $OutputDirectory -PathType Leaf) {
        throw "Output directory points to a file."
    }

    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

    $jsonPath = Join-Path $OutputDirectory "diagnostic-report.json"
    $markdownPath = Join-Path $OutputDirectory "diagnostic-report.md"

    $json = $Report | ConvertTo-Json -Depth 8
    $markdown = ConvertTo-DoctorMarkdown -Report $Report

    Set-Content -LiteralPath $jsonPath -Value $json -Encoding UTF8
    Set-Content -LiteralPath $markdownPath -Value $markdown -Encoding UTF8

    return [PSCustomObject][ordered]@{
        jsonFileName = "diagnostic-report.json"
        markdownFileName = "diagnostic-report.md"
    }
}

Export-ModuleMember -Function @(
    "ConvertTo-DoctorSafeText",
    "Invoke-ClaudeDesktopDoctor",
    "ConvertTo-DoctorMarkdown",
    "Write-DoctorReports"
)
