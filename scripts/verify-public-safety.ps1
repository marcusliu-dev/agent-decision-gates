param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$requiredPaths = @(
    'README.md',
    'TRACKER.md',
    'docs/consult-protocol.md',
    'docs/human-checkpoints.md',
    'docs/verification-and-safety.md',
    'docs/release-readiness.md',
    'docs/provenance.md',
    'examples',
    'examples/consult-stage-gate.md',
    'scripts/verify-public-safety.ps1',
    'LICENSE'
)

$forbiddenPaths = @(
    'src',
    'tests'
)

$blockedMarkers = @(
    'TODO_PRIVATE',
    'PRIVATE_ONLY',
    '<PRIVATE_',
    '<INTERNAL_',
    'REDACT_BEFORE_RELEASE'
)

$blockedLeakageTerms = @(
    'X:\ARD',
    'X:\ARD_backup',
    'X:\ARD_rebuild_prep_20260520',
    '.agents',
    'third_party',
    'vendored',
    'agent-migration'
)

$ceilingOrder = @{
    'outside_repo_skeleton_created' = 1
    'generic_public_docs_drafted' = 2
    'public_safety_checks_passed' = 3
    'release_packet_ready_for_human_decision' = 4
    'public_github_repo_published_and_verified' = 5
}

$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Get-RelativePath {
    param(
        [string]$BasePath,
        [string]$FullPath
    )

    return $FullPath.Substring($BasePath.Length).TrimStart('\')
}

function Get-MarkdownHeadingSlugs {
    param(
        [string]$Path
    )

    $slugs = New-Object System.Collections.Generic.HashSet[string]
    $lines = Get-Content -LiteralPath $Path
    foreach ($line in $lines) {
        if ($line -match '^\s{0,3}#{1,6}\s+(.+?)\s*$') {
            $heading = $Matches[1].ToLowerInvariant()
            $heading = [regex]::Replace($heading, '[^a-z0-9\s-]', '')
            $heading = [regex]::Replace($heading, '\s+', '-').Trim('-')
            if ($heading.Length -gt 0) {
                [void]$slugs.Add($heading)
            }
        }
    }
    return $slugs
}

foreach ($relativePath in $requiredPaths) {
    $fullPath = Join-Path $RepoRoot $relativePath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        $failures.Add("Missing required path: $relativePath")
    }
}

foreach ($relativePath in $forbiddenPaths) {
    $fullPath = Join-Path $RepoRoot $relativePath
    if (Test-Path -LiteralPath $fullPath) {
        $failures.Add("Forbidden path present for current doc-only surface: $relativePath")
    }
}

$selfPath = (Resolve-Path -LiteralPath $PSCommandPath).Path

$textFiles = Get-ChildItem -LiteralPath $RepoRoot -Recurse -File |
    Where-Object {
        $_.Extension -in '.md', '.ps1', '.txt' -and
        (Resolve-Path -LiteralPath $_.FullName).Path -ne $selfPath
    }

foreach ($file in $textFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    $relativeFile = Get-RelativePath -BasePath $RepoRoot -FullPath $file.FullName

    foreach ($marker in $blockedMarkers) {
        if ($content -like "*$marker*") {
            $failures.Add("Blocked marker '$marker' found in $relativeFile")
        }
    }

    foreach ($term in $blockedLeakageTerms) {
        if ($content -like "*$term*") {
            $failures.Add("Blocked leakage term '$term' found in $relativeFile")
        }
    }

    if ($file.Extension -eq '.md') {
        $matches = [regex]::Matches($content, '\[[^\]]+\]\(([^)]+)\)')
        foreach ($match in $matches) {
            $target = $match.Groups[1].Value.Trim()
            if (
                $target.StartsWith('http://') -or
                $target.StartsWith('https://') -or
                $target.StartsWith('mailto:') -or
                $target.StartsWith('#')
            ) {
                continue
            }

            $parts = $target.Split('#', 2)
            $targetPath = $parts[0]
            $anchor = if ($parts.Count -gt 1) { $parts[1] } else { $null }
            $resolvedTarget = Join-Path $file.DirectoryName $targetPath

            if (-not (Test-Path -LiteralPath $resolvedTarget)) {
                $failures.Add("Broken markdown link target '$target' in $relativeFile")
                continue
            }

            if ($anchor -and (Get-Item -LiteralPath $resolvedTarget).Extension -eq '.md') {
                $slugs = Get-MarkdownHeadingSlugs -Path $resolvedTarget
                if (-not $slugs.Contains($anchor.ToLowerInvariant())) {
                    $failures.Add("Broken markdown anchor '$target' in $relativeFile")
                }
            }
        }
    }
}

$trackerPath = Join-Path $RepoRoot 'TRACKER.md'
$trackerContent = Get-Content -LiteralPath $trackerPath -Raw
$trackerCeilingMatch = [regex]::Match($trackerContent, '## Current Claim Ceiling\s+`([^`]+)`')
if (-not $trackerCeilingMatch.Success) {
    $failures.Add('TRACKER.md is missing a parseable current claim ceiling.')
} else {
    $trackerCeiling = $trackerCeilingMatch.Groups[1].Value
    if (-not $ceilingOrder.ContainsKey($trackerCeiling)) {
        $failures.Add("TRACKER.md uses an unknown claim ceiling '$trackerCeiling'.")
    } else {
        $claimChecks = @(
            @{
                Path = Join-Path $RepoRoot 'README.md'
                Label = 'README.md'
                Pattern = 'current ceiling is no higher than `([^`]+)`'
            },
            @{
                Path = Join-Path $RepoRoot 'docs\release-readiness.md'
                Label = 'docs/release-readiness.md'
                Pattern = 'no higher than `([^`]+)`'
            }
        )

        foreach ($claimCheck in $claimChecks) {
            if (-not (Test-Path -LiteralPath $claimCheck.Path)) {
                continue
            }

            $claimContent = Get-Content -LiteralPath $claimCheck.Path -Raw
            $claimMatch = [regex]::Match($claimContent, $claimCheck.Pattern)
            if (-not $claimMatch.Success) {
                continue
            }

            $claimedCeiling = $claimMatch.Groups[1].Value
            if (-not $ceilingOrder.ContainsKey($claimedCeiling)) {
                $failures.Add("$($claimCheck.Label) uses an unknown claim ceiling '$claimedCeiling'.")
                continue
            }

            if ($ceilingOrder[$claimedCeiling] -gt $ceilingOrder[$trackerCeiling]) {
                $failures.Add("$($claimCheck.Label) claims a broader ceiling '$claimedCeiling' than TRACKER.md '$trackerCeiling'.")
            }
        }
    }
}

if ($failures.Count -eq 0) {
    Write-Host 'Public safety verification: pass'
} else {
    Write-Host 'Public safety verification: fail'
}

Write-Host ''
Write-Host 'Failures:'
if ($failures.Count -eq 0) {
    Write-Host '  none'
} else {
    foreach ($failure in $failures) {
        Write-Host "  - $failure"
    }
}

Write-Host ''
Write-Host 'Warnings:'
if ($warnings.Count -eq 0) {
    Write-Host '  none'
} else {
    foreach ($warning in $warnings) {
        Write-Host "  - $warning"
    }
}

if ($failures.Count -gt 0) {
    exit 1
}
