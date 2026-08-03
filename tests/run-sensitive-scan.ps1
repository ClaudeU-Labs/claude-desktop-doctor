[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$violations = New-Object System.Collections.Generic.List[string]

$excludedDirectories = @(".git", "doctor-output")
$textExtensions = @(".md", ".ps1", ".psm1", ".json", ".yml", ".yaml", ".gitignore")

$patterns = [ordered]@{
    "private-key-material" = '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'
    "github-token" = '\bgh[pousr]_[A-Za-z0-9]{20,}\b'
    "api-token" = '\bsk-[A-Za-z0-9_-]{20,}\b'
    "bearer-credential" = '(?i)authorization\s*[:=]\s*bearer\s+[A-Za-z0-9._-]{12,}'
    "credential-url" = '(?i)https?://[^/\s:@]+:[^/\s@]+@'
    "real-user-path" = '(?i)\b[A-Z]:\\Users\\(?!Example(?:\\|\b))[^\\\s]+'
    "private-implementation" = ('(?i)OpenClaude\.' + '(?:RuntimeState|Gateway|Patcher)|app' + '\.asar|Claude-' + '3p|/v1/' + 'messages')
}

$files = Get-ChildItem -LiteralPath $repoRoot -Recurse -File | Where-Object {
    $relative = $_.FullName.Substring($repoRoot.Length).TrimStart('\', '/')
    $firstSegment = ($relative -split '[\\/]')[0]
    ($excludedDirectories -notcontains $firstSegment) -and
    (($textExtensions -contains $_.Extension) -or $_.Name -eq ".gitignore")
}

foreach ($file in $files) {
    $relativePath = $file.FullName.Substring($repoRoot.Length).TrimStart('\', '/')
    $content = Get-Content -Raw -Encoding UTF8 -LiteralPath $file.FullName
    foreach ($pattern in $patterns.GetEnumerator()) {
        if ($content -match $pattern.Value) {
            $violations.Add("$($pattern.Key):$relativePath")
        }
    }
}

$binaryAssets = Get-ChildItem -LiteralPath $repoRoot -Recurse -File | Where-Object {
    $_.Extension -match '^\.(exe|dll|msix|appx|asar|pfx|pem|key)$'
}
foreach ($binaryAsset in $binaryAssets) {
    $relativePath = $binaryAsset.FullName.Substring($repoRoot.Length).TrimStart('\', '/')
    $violations.Add("forbidden-binary:$relativePath")
}

if ($violations.Count -gt 0) {
    $violations | Sort-Object | ForEach-Object { Write-Error $_ }
    throw "Sensitive-data scan found $($violations.Count) violation(s)."
}

Write-Host "PASS: sensitive-data and private-implementation scan"
