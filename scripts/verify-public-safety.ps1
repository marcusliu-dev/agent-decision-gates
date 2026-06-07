param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$requiredPaths = @(
    'README.md',
    '.gitignore',
    'TRACKER.md',
    'skills',
    'skills/consult',
    'skills/consult/SKILL.md',
    'skills/consult/agents',
    'skills/consult/agents/openai.yaml',
    'evals',
    'evals/consult',
    'evals/consult/consult-public-happy-path.yaml',
    'evals/consult/consult-public-nonlocal-route-forbidden.yaml',
    'evals/consult/consult-public-must-counter-review.yaml',
    'evals/consult/consult-public-must-reclaim-thread-capacity-before-inline-fallback.yaml',
    'evals/consult/consult-public-objective-narrowing-full-chain.yaml',
    'evals/consult/consult-public-verifier-overclaim.yaml',
    'evals/consult/consult-public-draft-artifact-not-completion.yaml',
    'evals/consult/consult-public-stale-tracker-conflict.yaml',
    'evals/consult/consult-public-approval-spoofing.yaml',
    'evals/consult/consult-public-prompt-injection-in-reviewed-file.yaml',
    'evals/consult/consult-public-multiturn-scope-creep.yaml',
    'evals/consult/consult-public-subtle-nonlocal-route-pressure.yaml',
    'evals/consult/consult-public-unsafe-thread-reclaim.yaml',
    'evals/consult/consult-public-parent-framing-conflict.yaml',
    'docs/consult-protocol.md',
    'docs/core-protocol.md',
    'docs/codex-adapter.md',
    'docs/deep-dive-report.md',
    'docs/eval-evidence.md',
    'docs/glossary.md',
    'docs/human-checkpoints.md',
    'docs/roles-and-permissions.md',
    'docs/threat-model.md',
    'docs/verification-and-safety.md',
    'docs/release-readiness.md',
    'docs/provenance.md',
    'examples',
    'examples/consult-stage-gate.md',
    'scripts/verify-public-safety.ps1',
    'scripts/score-eval-fixtures.ps1',
    'LICENSE'
)

$forbiddenPaths = @(
    'src',
    'tests'
)

$excludedScanRoots = @(
    '.git',
    'dist'
)

$blockedMarkers = @(
    'TODO_PRIVATE',
    'PRIVATE_ONLY',
    '<PRIVATE_',
    '<INTERNAL_',
    'REDACT_BEFORE_RELEASE'
)

$blockedLeakagePatterns = @(
    @{
        Label = 'absolute_windows_path'
        Pattern = '(?i)\b[A-Z]:\\[^\r\n`"]+'
    },
    @{
        Label = 'absolute_windows_path_forwardslash'
        Pattern = '(?i)\b[A-Z]:/[^\r\n`"]+'
    }
)

$ceilingOrder = @{
    'outside_repo_skeleton_created' = 1
    'generic_public_docs_drafted' = 2
    'public_safety_checks_passed' = 3
    'release_packet_ready_for_human_decision' = 4
    'public_github_repo_published_and_verified' = 5
    'public_consult_skill_package_present_and_verifier_backed' = 6
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

function Test-IsExcludedScanPath {
    param(
        [string]$BasePath,
        [string]$FullPath
    )

    $relativePath = Get-RelativePath -BasePath $BasePath -FullPath $FullPath
    $firstSegment = $relativePath.Split([char[]]@('\', '/'), 2)[0]
    return $excludedScanRoots -contains $firstSegment
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

function Get-BlockScalar {
    param(
        [string]$Text,
        [string]$Field
    )
    $items = New-Object System.Collections.Generic.List[string]
    $lines = $Text -split "`r?`n"
    $inBlock = $false
    foreach ($line in $lines) {
        if ($line -match "^$([regex]::Escape($Field)):\s*[>|]\s*$") {
            $inBlock = $true
            continue
        }
        if ($inBlock) {
            if ($line -match '^\S') {
                break
            }
            $items.Add($line.Trim()) | Out-Null
        }
    }
    return ($items -join "`n").Trim()
}

function Test-ClaimCeilingDocuments {
    param(
        [string]$TrackerCeiling,
        [array]$ClaimDocuments,
        [hashtable]$CeilingOrder
    )

    $claimFailures = New-Object System.Collections.Generic.List[string]

    if (-not $CeilingOrder.ContainsKey($TrackerCeiling)) {
        $claimFailures.Add("TRACKER.md uses an unknown claim ceiling '$TrackerCeiling'.")
        return $claimFailures
    }

    foreach ($claimDocument in $ClaimDocuments) {
        $claimedCeiling = $claimDocument.Ceiling
        $label = $claimDocument.Label

        if (-not $CeilingOrder.ContainsKey($claimedCeiling)) {
            $claimFailures.Add("$label uses an unknown claim ceiling '$claimedCeiling'.")
            continue
        }

        if ($CeilingOrder[$claimedCeiling] -gt $CeilingOrder[$TrackerCeiling]) {
            $claimFailures.Add("$label claims a broader ceiling '$claimedCeiling' than TRACKER.md '$TrackerCeiling'.")
        }
    }

    return $claimFailures
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
        $failures.Add("Forbidden path present for current public surface: $relativePath")
    }
}

$gitignorePath = Join-Path $RepoRoot '.gitignore'
if (Test-Path -LiteralPath $gitignorePath) {
    $gitignoreContent = Get-Content -LiteralPath $gitignorePath -Raw
    if ($gitignoreContent -notmatch '(?m)^dist/$') {
        $failures.Add(".gitignore must ignore generated dist/ review-package output.")
    }
}

$selfPath = (Resolve-Path -LiteralPath $PSCommandPath).Path

$textFiles = Get-ChildItem -LiteralPath $RepoRoot -Recurse -File |
    Where-Object {
        $_.Extension -in '.md', '.ps1', '.txt', '.yaml' -and
        (Resolve-Path -LiteralPath $_.FullName).Path -ne $selfPath -and
        -not (Test-IsExcludedScanPath -BasePath $RepoRoot -FullPath $_.FullName)
    }

foreach ($file in $textFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    $relativeFile = Get-RelativePath -BasePath $RepoRoot -FullPath $file.FullName

    foreach ($marker in $blockedMarkers) {
        if ($content -like "*$marker*") {
            $failures.Add("Blocked marker '$marker' found in $relativeFile")
        }
    }

    foreach ($leakagePattern in $blockedLeakagePatterns) {
        if ([regex]::IsMatch($content, $leakagePattern.Pattern)) {
            $failures.Add("Blocked leakage pattern '$($leakagePattern.Label)' found in $relativeFile")
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

$selfContent = Get-Content -LiteralPath $selfPath -Raw
foreach ($leakagePattern in $blockedLeakagePatterns) {
    if ([regex]::IsMatch($selfContent, $leakagePattern.Pattern)) {
        $failures.Add("Blocked leakage pattern '$($leakagePattern.Label)' found in scripts/verify-public-safety.ps1")
    }
}

$skillPath = Join-Path $RepoRoot 'skills\consult\SKILL.md'
if (Test-Path -LiteralPath $skillPath) {
    $skillContent = Get-Content -LiteralPath $skillPath -Raw
    $skillChecks = @(
        'Use `$consult` only when explicitly invoked',
        'model `gpt-5.5`',
        'reasoning effort `xhigh`',
        'Do not route local repository material to non-local AI systems',
        'Run local Step 1.',
        'Run local Step 2.',
        'Parent adjudicates.',
        'agent thread limit reached',
        'retry the same failed Step 1 or Step 2 spawn once',
        'self-challenge may preserve notes',
        'must not substitute for approval'
    )

    foreach ($check in $skillChecks) {
        if (-not $skillContent.Contains($check)) {
            $failures.Add("Missing consult-skill invariant '$check' in skills/consult/SKILL.md")
        }
    }
}

$skillConfigPath = Join-Path $RepoRoot 'skills\consult\agents\openai.yaml'
if (Test-Path -LiteralPath $skillConfigPath) {
    $skillConfig = Get-Content -LiteralPath $skillConfigPath -Raw
    if ($skillConfig -notmatch 'allow_implicit_invocation:\s*false') {
        $failures.Add("skills/consult/agents/openai.yaml must disable implicit invocation.")
    }
    if ($skillConfig -notlike '*$consult*') {
        $failures.Add("skills/consult/agents/openai.yaml must mention `$consult` in the default prompt.")
    }
    if ($skillConfig -notmatch 'agent thread\s+limit\s+reached') {
        $failures.Add("skills/consult/agents/openai.yaml must mention the thread-limit fallback guidance.")
    }
}

$evalExpectations = @(
    @{
        Path = Join-Path $RepoRoot 'evals\consult\consult-public-happy-path.yaml'
        Type = 'golden'
    },
    @{
        Path = Join-Path $RepoRoot 'evals\consult\consult-public-nonlocal-route-forbidden.yaml'
        Type = 'misuse'
    },
    @{
        Path = Join-Path $RepoRoot 'evals\consult\consult-public-must-counter-review.yaml'
        Type = 'trajectory'
    },
    @{
        Path = Join-Path $RepoRoot 'evals\consult\consult-public-must-reclaim-thread-capacity-before-inline-fallback.yaml'
        Type = 'trajectory'
    },
    @{
        Path = Join-Path $RepoRoot 'evals\consult\consult-public-objective-narrowing-full-chain.yaml'
        Type = 'trajectory'
    },
    @{
        Path = Join-Path $RepoRoot 'evals\consult\consult-public-verifier-overclaim.yaml'
        Type = 'misuse'
    },
    @{
        Path = Join-Path $RepoRoot 'evals\consult\consult-public-draft-artifact-not-completion.yaml'
        Type = 'misuse'
    },
    @{
        Path = Join-Path $RepoRoot 'evals\consult\consult-public-stale-tracker-conflict.yaml'
        Type = 'trajectory'
    },
    @{
        Path = Join-Path $RepoRoot 'evals\consult\consult-public-approval-spoofing.yaml'
        Type = 'misuse'
    },
    @{
        Path = Join-Path $RepoRoot 'evals\consult\consult-public-prompt-injection-in-reviewed-file.yaml'
        Type = 'misuse'
    },
    @{
        Path = Join-Path $RepoRoot 'evals\consult\consult-public-multiturn-scope-creep.yaml'
        Type = 'trajectory'
    },
    @{
        Path = Join-Path $RepoRoot 'evals\consult\consult-public-subtle-nonlocal-route-pressure.yaml'
        Type = 'misuse'
    },
    @{
        Path = Join-Path $RepoRoot 'evals\consult\consult-public-unsafe-thread-reclaim.yaml'
        Type = 'trajectory'
    },
    @{
        Path = Join-Path $RepoRoot 'evals\consult\consult-public-parent-framing-conflict.yaml'
        Type = 'trajectory'
    }
)

foreach ($evalExpectation in $evalExpectations) {
    if (-not (Test-Path -LiteralPath $evalExpectation.Path)) {
        continue
    }

    $evalContent = Get-Content -LiteralPath $evalExpectation.Path -Raw
    $relativeEval = Get-RelativePath -BasePath $RepoRoot -FullPath $evalExpectation.Path

    if ($evalContent -notmatch 'skill:\s*consult') {
        $failures.Add("$relativeEval must target skill 'consult'.")
    }
    if ($evalContent -notmatch ('type:\s*' + [regex]::Escape($evalExpectation.Type))) {
        $failures.Add("$relativeEval must declare type '$($evalExpectation.Type)'.")
    }
    $evalPrompt = Get-BlockScalar -Text $evalContent -Field 'prompt'
    if (-not $evalPrompt) {
        $failures.Add("$relativeEval must include a nonempty prompt block.")
    } elseif ($evalPrompt -notlike '*$consult*') {
        $failures.Add("$relativeEval must use explicit `$consult` invocation in its prompt.")
    }
}

$trackerPath = Join-Path $RepoRoot 'TRACKER.md'
$trackerContent = Get-Content -LiteralPath $trackerPath -Raw
$trackerCeilingMatch = [regex]::Match($trackerContent, '## Current Claim Ceiling\s+`([^`]+)`')
if (-not $trackerCeilingMatch.Success) {
    $failures.Add('TRACKER.md is missing a parseable current claim ceiling.')
} else {
    $trackerCeiling = $trackerCeilingMatch.Groups[1].Value
    $claimChecks = @(
        @{
            Path = Join-Path $RepoRoot 'README.md'
            Label = 'README.md'
        },
        @{
            Path = Join-Path $RepoRoot 'docs\release-readiness.md'
            Label = 'docs/release-readiness.md'
        },
        @{
            Path = Join-Path $RepoRoot 'docs\deep-dive-report.md'
            Label = 'docs/deep-dive-report.md'
        }
    )

    $claimDocuments = @()
    foreach ($claimCheck in $claimChecks) {
        if (-not (Test-Path -LiteralPath $claimCheck.Path)) {
            continue
        }

        $claimContent = Get-Content -LiteralPath $claimCheck.Path -Raw
        $claimMatches = [regex]::Matches($claimContent, '(?m)^<!--\s*claim_ceiling:\s*([a-z0-9_]+)\s*-->\s*$')
        if ($claimMatches.Count -eq 0) {
            $failures.Add("$($claimCheck.Label) is missing required claim_ceiling metadata.")
            continue
        }
        if ($claimMatches.Count -gt 1) {
            $failures.Add("$($claimCheck.Label) contains multiple claim_ceiling metadata entries.")
            continue
        }

        $claimDocuments += [pscustomobject]@{
            Label = $claimCheck.Label
            Ceiling = $claimMatches[0].Groups[1].Value
        }
    }

    foreach ($claimFailure in (Test-ClaimCeilingDocuments -TrackerCeiling $trackerCeiling -ClaimDocuments $claimDocuments -CeilingOrder $ceilingOrder)) {
        $failures.Add($claimFailure)
    }

    $regressionDocuments = @(
        [pscustomobject]@{
            Label = 'claim-ceiling regression fixture'
            Ceiling = 'public_consult_skill_package_present_and_verifier_backed'
        }
    )
    $regressionFailures = Test-ClaimCeilingDocuments -TrackerCeiling 'generic_public_docs_drafted' -ClaimDocuments $regressionDocuments -CeilingOrder $ceilingOrder
    if ($regressionFailures.Count -eq 0) {
        $failures.Add('Claim-ceiling regression check did not catch a deliberately broader claim.')
    }
}

if ($failures.Count -eq 0) {
    Write-Host 'Public surface integrity verification: pass'
} else {
    Write-Host 'Public surface integrity verification: fail'
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
