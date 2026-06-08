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
    'evals/empirical',
    'evals/empirical/agent-decision-gates-task-suite.yaml',
    'evals/empirical/experiment-run-manifest.yaml',
    'evals/empirical/condition-prompt-pack.yaml',
    'evals/empirical/run-input-schema.yaml',
    'evals/empirical/execution-preflight-schema.yaml',
    'evals/empirical/mock-execution-package-schema.yaml',
    'evals/empirical/pilot-execution-package-schema.yaml',
    'evals/empirical/annotation-worklist-schema.yaml',
    'evals/empirical/transcript-schema.yaml',
    'evals/empirical/annotation-schema.yaml',
    'evals/empirical/evidence-package-schema.yaml',
    'evals/empirical/results-summary-schema.yaml',
    'evals/empirical/agreement-summary-schema.yaml',
    'docs/empirical-annotation-guidelines.md',
    'docs/consult-protocol.md',
    'docs/core-protocol.md',
    'docs/codex-adapter.md',
    'docs/deep-dive-report.md',
    'docs/empirical-evaluation-plan.md',
    'docs/condition-prompt-pack.md',
    'docs/empirical-run-inputs.md',
    'docs/empirical-execution-preflight.md',
    'docs/empirical-mock-execution-package.md',
    'docs/empirical-pilot-execution-runner.md',
    'docs/empirical-annotation-worklist.md',
    'docs/experiment-run-packet.md',
    'docs/empirical-evidence-package.md',
    'docs/empirical-results-analysis.md',
    'docs/empirical-agreement-checks.md',
    'docs/empirical-dry-run-package.md',
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
    'scripts/score-empirical-task-suite.ps1',
    'scripts/score-empirical-prompt-pack.ps1',
    'scripts/build-empirical-run-inputs.ps1',
    'scripts/score-empirical-run-inputs.ps1',
    'scripts/build-empirical-execution-preflight.ps1',
    'scripts/score-empirical-execution-preflight.ps1',
    'scripts/build-empirical-mock-execution-package.ps1',
    'scripts/score-empirical-mock-execution-package.ps1',
    'scripts/build-empirical-pilot-execution-package.ps1',
    'scripts/score-empirical-pilot-execution-package.ps1',
    'scripts/build-empirical-annotation-worklist.ps1',
    'scripts/score-empirical-annotation-worklist.ps1',
    'scripts/score-empirical-run-packet.ps1',
    'scripts/score-empirical-evidence-package.ps1',
    'scripts/score-empirical-results.ps1',
    'scripts/score-empirical-agreement.ps1',
    'scripts/build-empirical-dry-run-package.ps1',
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
    },
    @{
        Label = 'credential_assignment'
        Pattern = '(?i)(^|[\s,{])"?\b(api[_-]?key|secret|password|token)\b"?\s*[:=]'
    },
    @{
        Label = 'bearer_token'
        Pattern = '(?i)\bBearer\s+[A-Za-z0-9._~+/-]+=*'
    },
    @{
        Label = 'github_token'
        Pattern = '(?i)\bgh[pousr]_[A-Za-z0-9_]{20,}'
    },
    @{
        Label = 'openai_style_key'
        Pattern = '(?i)\bsk-[A-Za-z0-9_-]{16,}'
    },
    @{
        Label = 'aws_access_key'
        Pattern = '\bAKIA[0-9A-Z]{16}\b'
    },
    @{
        Label = 'private_key_marker'
        Pattern = '-----BEGIN [A-Z ]*PRIVATE KEY-----'
    }
)

$ceilingOrder = @{
    'outside_repo_skeleton_created' = 1
    'generic_public_docs_drafted' = 2
    'public_safety_checks_passed' = 3
    'release_packet_ready_for_human_decision' = 4
    'public_github_repo_published_and_verified' = 5
    'public_consult_skill_package_present_and_verifier_backed' = 6
    'empirical_plan_and_task_suite_present_and_structurally_scored' = 7
    'empirical_run_packet_schema_present_and_structurally_scored' = 8
    'empirical_evidence_package_validator_present_and_self_tested' = 9
    'empirical_results_aggregator_present_and_self_tested' = 10
    'empirical_annotation_guidelines_present_and_structurally_scored' = 11
    'empirical_agreement_checker_present_and_self_tested' = 12
    'empirical_dry_run_package_builder_present_and_self_tested' = 13
    'empirical_condition_prompt_pack_present_and_structurally_scored' = 14
    'empirical_run_input_builder_present_and_self_tested' = 15
    'empirical_execution_preflight_present_and_self_tested' = 16
    'empirical_mock_execution_package_builder_present_and_self_tested' = 17
    'empirical_pilot_execution_runner_present_and_self_tested' = 18
    'empirical_annotation_worklist_builder_present_and_self_tested' = 19
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

function Get-YamlList {
    param(
        [string]$Text,
        [string]$Field
    )
    $items = New-Object System.Collections.Generic.List[string]
    $lines = $Text -split "`r?`n"
    $inList = $false
    foreach ($line in $lines) {
        if ($line -match "^$([regex]::Escape($Field)):\s*$") {
            $inList = $true
            continue
        }
        if ($inList) {
            if ($line -match '^\S') {
                break
            }
            if ($line -match '^\s*-\s*(.+?)\s*$') {
                $items.Add($Matches[1].Trim()) | Out-Null
            }
        }
    }
    return @($items)
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

$empiricalPlanPath = Join-Path $RepoRoot 'docs\empirical-evaluation-plan.md'
if (Test-Path -LiteralPath $empiricalPlanPath) {
    $empiricalPlanContent = Get-Content -LiteralPath $empiricalPlanPath -Raw
    foreach ($check in @(
        'does not report model results',
        'does not execute model/API evals',
        'does not claim paper readiness',
        'false readiness rate',
        'human/LLM-judge agreement',
        'cost/latency',
        'score-empirical-prompt-pack.ps1',
        'build-empirical-run-inputs.ps1 -SelfTest',
        'score-empirical-run-inputs.ps1 -SelfTest',
        'build-empirical-execution-preflight.ps1 -SelfTest',
        'score-empirical-execution-preflight.ps1 -SelfTest',
        'build-empirical-mock-execution-package.ps1 -SelfTest',
        'score-empirical-mock-execution-package.ps1 -SelfTest',
        'score-empirical-evidence-package.ps1 -SelfTest',
        'score-empirical-agreement.ps1 -SelfTest',
        'build-empirical-dry-run-package.ps1 -SelfTest',
        'mock execution package route',
        'dry-run package builder'
    )) {
        if (-not $empiricalPlanContent.Contains($check)) {
            $failures.Add("Missing empirical-plan boundary '$check' in docs/empirical-evaluation-plan.md")
        }
    }
}

$empiricalSuitePath = Join-Path $RepoRoot 'evals\empirical\agent-decision-gates-task-suite.yaml'
if (Test-Path -LiteralPath $empiricalSuitePath) {
    $empiricalSuiteContent = Get-Content -LiteralPath $empiricalSuitePath -Raw
    if ($empiricalSuiteContent -notmatch 'claim_boundary:\s*structural_plan_only_no_model_results') {
        $failures.Add('Empirical task suite must declare structural_plan_only_no_model_results claim boundary.')
    }
    foreach ($check in @(
        'no_gate',
        'checklist_only',
        'full_consult_gate',
        'programmatic_gate_variant',
        'false_readiness_rate',
        'objective_narrowing_rate',
        'human_annotation',
        'llm_judge_agreement_check',
        'cost_latency_logs'
    )) {
        if ($empiricalSuiteContent -notlike "*$check*") {
            $failures.Add("Missing empirical task-suite requirement '$check'.")
        }
    }
    foreach ($blockedField in @(
        'results',
        'pass_rate',
        'win_rate',
        'effectiveness_claim',
        'paper_ready',
        'production_ready',
        'statistical_significance'
    )) {
        if ([regex]::IsMatch($empiricalSuiteContent, "(?m)^\s*$([regex]::Escape($blockedField))\s*:")) {
            $failures.Add("Empirical task suite must not contain result field '$blockedField'.")
        }
    }
    $empiricalTaskCount = ([regex]::Matches($empiricalSuiteContent, '(?m)^\s{2}-\s+id:\s*')).Count
    if ($empiricalTaskCount -lt 12) {
        $failures.Add("Empirical task suite must contain at least 12 task definitions; found $empiricalTaskCount.")
    }
}

$experimentRunPacketPath = Join-Path $RepoRoot 'docs\experiment-run-packet.md'
if (Test-Path -LiteralPath $experimentRunPacketPath) {
    $experimentRunPacketContent = Get-Content -LiteralPath $experimentRunPacketPath -Raw
    foreach ($check in @(
        'does not execute model/API evals',
        'report results',
        'claim paper readiness',
        'No private repository material',
        'condition_prompt_pack_available',
        'run_input_builder_available',
        'execution_preflight_available',
        'mock_execution_package_builder_available',
        'pilot_execution_runner_available',
        'annotation_worklist_builder_available',
        'score-empirical-prompt-pack.ps1',
        'score-empirical-run-inputs.ps1',
        'build-empirical-execution-preflight.ps1 -SelfTest',
        'score-empirical-execution-preflight.ps1',
        'build-empirical-mock-execution-package.ps1 -SelfTest',
        'score-empirical-mock-execution-package.ps1 -SelfTest',
        'build-empirical-pilot-execution-package.ps1 -SelfTest',
        'score-empirical-pilot-execution-package.ps1 -SelfTest',
        'build-empirical-annotation-worklist.ps1 -SelfTest',
        'score-empirical-annotation-worklist.ps1 -SelfTest',
        'score-empirical-run-packet.ps1',
        'evidence-package-schema.yaml',
        'agreement-summary-schema.yaml',
        'score-empirical-evidence-package.ps1 -SelfTest',
        'score-empirical-agreement.ps1 -SelfTest',
        'dry_run_package_builder_available',
        'build-empirical-dry-run-package.ps1 -SelfTest',
        'synthetic mock execution package',
        'annotation worklist',
        'synthetic dry-run package builder self-test'
    )) {
        if (-not $experimentRunPacketContent.Contains($check)) {
            $failures.Add("Missing experiment-run-packet boundary '$check' in docs/experiment-run-packet.md")
        }
    }
}

$runManifestPath = Join-Path $RepoRoot 'evals\empirical\experiment-run-manifest.yaml'
if (Test-Path -LiteralPath $runManifestPath) {
    $runManifestContent = Get-Content -LiteralPath $runManifestPath -Raw
    if ($runManifestContent -notmatch 'claim_boundary:\s*run_packet_schema_only_no_execution_results') {
        $failures.Add('Experiment run manifest must declare run_packet_schema_only_no_execution_results claim boundary.')
    }
    foreach ($check in @(
        'raw_transcript',
        'annotation_record',
        'annotation_guidelines',
        'agreement_check_record',
        'condition_prompt_pack',
        'run_input_record',
        'execution_preflight_record',
        'execution_preflight_schema',
        'mock_execution_package',
        'mock_execution_package_schema',
        'pilot_execution_package',
        'pilot_execution_package_schema',
        'annotation_worklist',
        'annotation_worklist_schema',
        'cost_latency_record',
        'results_summary_schema',
        'agreement_summary_schema',
        'condition_prompt_pack_available',
        'run_input_builder_available',
        'execution_preflight_available',
        'mock_execution_package_builder_available',
        'pilot_execution_runner_available',
        'annotation_worklist_builder_available',
        'annotation_guidelines_available',
        'agreement_checker_available',
        'dry_run_package_builder_available',
        'prompt_version_record',
        'no_private_repository_material',
        'budget_recorded_before_execution',
        'no_model_api_eval_execution',
        'no_empirical_results',
        'empirical_effectiveness_proven',
        'no_transcripts',
        'no_annotations',
        'no_paper_readiness'
    )) {
        if ($runManifestContent -notlike "*$check*") {
            $failures.Add("Missing experiment run manifest requirement '$check'.")
        }
    }
}

$runInputSchemaPath = Join-Path $RepoRoot 'evals\empirical\run-input-schema.yaml'
if (Test-Path -LiteralPath $runInputSchemaPath) {
    $runInputSchemaContent = Get-Content -LiteralPath $runInputSchemaPath -Raw
    if ($runInputSchemaContent -notmatch 'claim_boundary:\s*run_input_schema_only_no_model_execution') {
        $failures.Add('Run-input schema must declare run_input_schema_only_no_model_execution claim boundary.')
    }
    foreach ($check in @(
        'run_input_id',
        'task_id',
        'condition',
        'repeat_index',
        'task_suite_sha256',
        'prompt_pack_sha256',
        'manifest_sha256',
        'metadata/run-input-manifest.json',
        'no_model_api_eval_execution',
        'no_transcripts',
        'no_annotations',
        'no_empirical_results',
        'no_paper_readiness'
    )) {
        if ($runInputSchemaContent -notlike "*$check*") {
            $failures.Add("Missing run-input schema requirement '$check'.")
        }
    }
}

$runInputDocPath = Join-Path $RepoRoot 'docs\empirical-run-inputs.md'
if (Test-Path -LiteralPath $runInputDocPath) {
    $runInputDocContent = Get-Content -LiteralPath $runInputDocPath -Raw
    foreach ($check in @(
        'does not execute model/API evals',
        'dist/empirical-run-inputs',
        'build-empirical-run-inputs.ps1 -SelfTest',
        'score-empirical-run-inputs.ps1 -SelfTest',
        '324',
        'Current Nonclaims'
    )) {
        if (-not $runInputDocContent.Contains($check)) {
            $failures.Add("Missing empirical run-input doc boundary '$check' in docs/empirical-run-inputs.md")
        }
    }
}

$runInputBuilderPath = Join-Path $RepoRoot 'scripts\build-empirical-run-inputs.ps1'
if (Test-Path -LiteralPath $runInputBuilderPath) {
    $runInputBuilderContent = Get-Content -LiteralPath $runInputBuilderPath -Raw
    foreach ($check in @(
        'Empirical run-input builder',
        'record_count',
        'task_suite_hash',
        'prompt_pack_hash',
        'manifest_hash',
        'no_model_api_eval_execution',
        '324'
    )) {
        if (-not $runInputBuilderContent.Contains($check)) {
            $failures.Add("Missing empirical run-input builder invariant '$check'.")
        }
    }
}

$runInputScorerPath = Join-Path $RepoRoot 'scripts\score-empirical-run-inputs.ps1'
if (Test-Path -LiteralPath $runInputScorerPath) {
    $runInputScorerContent = Get-Content -LiteralPath $runInputScorerPath -Raw
    foreach ($check in @(
        'Empirical run-input scoring',
        'run_input_schema_only_no_model_execution',
        'metadata/run-input-manifest.json',
        'empirical_effectiveness_proven',
        'Rejected package after task_id was changed outside the current task suite',
        'Rejected package after transcript_messages was injected',
        'Rejected package after empirical_effectiveness_proven was injected',
        'Rejected metadata after empirical_effectiveness_proven and a private-path pattern were injected',
        'Rejected package after one run-input record was removed',
        'expected_records'
    )) {
        if (-not $runInputScorerContent.Contains($check)) {
            $failures.Add("Missing empirical run-input scorer invariant '$check'.")
        }
    }
}

$executionPreflightSchemaPath = Join-Path $RepoRoot 'evals\empirical\execution-preflight-schema.yaml'
if (Test-Path -LiteralPath $executionPreflightSchemaPath) {
    $executionPreflightSchemaContent = Get-Content -LiteralPath $executionPreflightSchemaPath -Raw
    if ($executionPreflightSchemaContent -notmatch 'claim_boundary:\s*execution_preflight_schema_only_no_model_api_calls') {
        $failures.Add('Execution preflight schema must declare execution_preflight_schema_only_no_model_api_calls claim boundary.')
    }
    foreach ($check in @(
        'selected_run_input_ids',
        'selected_run_count',
        'provider',
        'model_name_or_alias',
        'runtime_surface',
        'budget_recorded_before_execution',
        'max_budget_usd',
        'run_input_manifest_sha256',
        'source_run_input_manifest_hash_recorded',
        'provider_model_runtime_recorded',
        'selected_run_inputs_exist',
        'no_model_api_call_performed',
        'transcript_messages',
        'empirical_effectiveness_proven',
        'no_model_api_eval_execution',
        'no_paper_readiness'
    )) {
        if ($executionPreflightSchemaContent -notlike "*$check*") {
            $failures.Add("Missing execution preflight schema requirement '$check'.")
        }
    }
}

$executionPreflightDocPath = Join-Path $RepoRoot 'docs\empirical-execution-preflight.md'
if (Test-Path -LiteralPath $executionPreflightDocPath) {
    $executionPreflightDocContent = Get-Content -LiteralPath $executionPreflightDocPath -Raw
    foreach ($check in @(
        'does not call models or APIs',
        'dist/empirical-run-inputs',
        'dist/empirical-execution-preflight.json',
        'build-empirical-execution-preflight.ps1 -SelfTest',
        'score-empirical-execution-preflight.ps1 -SelfTest',
        '9 records from the 324-record run-input package',
        'Current Nonclaims'
    )) {
        if (-not $executionPreflightDocContent.Contains($check)) {
            $failures.Add("Missing empirical execution preflight doc boundary '$check' in docs/empirical-execution-preflight.md")
        }
    }
}

$executionPreflightBuilderPath = Join-Path $RepoRoot 'scripts\build-empirical-execution-preflight.ps1'
if (Test-Path -LiteralPath $executionPreflightBuilderPath) {
    $executionPreflightBuilderContent = Get-Content -LiteralPath $executionPreflightBuilderPath -Raw
    foreach ($check in @(
        'Empirical execution preflight builder',
        'execution_preflight_only_no_model_api_calls',
        'preflight_only_no_model_api_call',
        'source_run_input_manifest_hash_recorded',
        'provider_model_runtime_recorded',
        'budget_recorded_before_execution',
        'no_model_api_call_performed',
        'Built a 9-record execution preflight'
    )) {
        if (-not $executionPreflightBuilderContent.Contains($check)) {
            $failures.Add("Missing empirical execution preflight builder invariant '$check'.")
        }
    }
}

$executionPreflightScorerPath = Join-Path $RepoRoot 'scripts\score-empirical-execution-preflight.ps1'
if (Test-Path -LiteralPath $executionPreflightScorerPath) {
    $executionPreflightScorerContent = Get-Content -LiteralPath $executionPreflightScorerPath -Raw
    foreach ($check in @(
        'Empirical execution preflight scoring',
        'execution_preflight_schema_only_no_model_api_calls',
        'execution_preflight_only_no_model_api_calls',
        'preflight_only_no_model_api_call',
        'Rejected missing budget, missing run-input id, non-first sorted selection, transcript field injection, and metadata hash mutation cases',
        'transcript_messages',
        'task_suite_sha256',
        'selected_run_input_ids',
        'metadata/run-input-manifest.json'
    )) {
        if (-not $executionPreflightScorerContent.Contains($check)) {
            $failures.Add("Missing empirical execution preflight scorer invariant '$check'.")
        }
    }
}

$mockExecutionPackageSchemaPath = Join-Path $RepoRoot 'evals\empirical\mock-execution-package-schema.yaml'
if (Test-Path -LiteralPath $mockExecutionPackageSchemaPath) {
    $mockExecutionPackageSchemaContent = Get-Content -LiteralPath $mockExecutionPackageSchemaPath -Raw
    if ($mockExecutionPackageSchemaContent -notmatch 'claim_boundary:\s*mock_execution_package_schema_only_no_real_model_results') {
        $failures.Add('Mock execution package schema must declare mock_execution_package_schema_only_no_real_model_results claim boundary.')
    }
    foreach ($check in @(
        'transcripts',
        'cost-latency',
        'metadata',
        'mock-execution-manifest.json',
        'source-preflight-hash.json',
        'source-run-input-manifest-hash.json',
        'run_input_id',
        'transcript_messages',
        'tool_calls',
        'final_answer',
        'cost_latency_record_id',
        'every_selected_run_input_has_mock_transcript',
        'every_mock_transcript_has_cost_latency_record',
        'every_cost_latency_record_matches_transcript_run_id',
        'source_preflight_hash_recorded',
        'source_run_input_manifest_hash_recorded',
        'annotation_record',
        'human_label',
        'llm_judge_label',
        'pass_rate',
        'win_rate',
        'p_value',
        'confidence_interval',
        'statistical_significance',
        'effectiveness_claim',
        'empirical_effectiveness_proven',
        'paper_ready',
        'production_ready',
        'no_real_model_api_eval_execution',
        'no_real_transcripts',
        'no_real_cost_latency_results',
        'no_paper_readiness'
    )) {
        if ($mockExecutionPackageSchemaContent -notlike "*$check*") {
            $failures.Add("Missing mock execution package schema requirement '$check'.")
        }
    }
}

$mockExecutionPackageDocPath = Join-Path $RepoRoot 'docs\empirical-mock-execution-package.md'
if (Test-Path -LiteralPath $mockExecutionPackageDocPath) {
    $mockExecutionPackageDocContent = Get-Content -LiteralPath $mockExecutionPackageDocPath -Raw
    foreach ($check in @(
        'does not call models or APIs',
        'dist/empirical-mock-execution-package',
        'build-empirical-mock-execution-package.ps1 -SelfTest',
        'score-empirical-mock-execution-package.ps1 -SelfTest',
        '9 mock transcript records',
        'credential-like content',
        'non-JSON sensitive files',
        'Current Nonclaims'
    )) {
        if (-not $mockExecutionPackageDocContent.Contains($check)) {
            $failures.Add("Missing empirical mock execution package doc boundary '$check' in docs/empirical-mock-execution-package.md")
        }
    }
}

$mockExecutionPackageBuilderPath = Join-Path $RepoRoot 'scripts\build-empirical-mock-execution-package.ps1'
if (Test-Path -LiteralPath $mockExecutionPackageBuilderPath) {
    $mockExecutionPackageBuilderContent = Get-Content -LiteralPath $mockExecutionPackageBuilderPath -Raw
    foreach ($check in @(
        'Empirical mock execution package builder',
        'mock_execution_package_only_no_real_model_results',
        'mock_synthetic_no_private_material',
        'Built a 9-run mock execution package',
        'Refused non-generated files when -Force was used',
        'non-generated file',
        'source-preflight-hash.json',
        'source-run-input-manifest-hash.json',
        'no_real_model_api_eval_execution'
    )) {
        if (-not $mockExecutionPackageBuilderContent.Contains($check)) {
            $failures.Add("Missing empirical mock execution package builder invariant '$check'.")
        }
    }
}

$mockExecutionPackageScorerPath = Join-Path $RepoRoot 'scripts\score-empirical-mock-execution-package.ps1'
if (Test-Path -LiteralPath $mockExecutionPackageScorerPath) {
    $mockExecutionPackageScorerContent = Get-Content -LiteralPath $mockExecutionPackageScorerPath -Raw
    foreach ($check in @(
        'Empirical mock execution package scoring',
        'mock_execution_package_schema_only_no_real_model_results',
        'mock_execution_package_only_no_real_model_results',
        'mock_synthetic_no_private_material',
        'Rejected missing transcript, crossed cost-latency join, credential-like content, non-JSON sensitive files, and unsupported result/readiness claim cases',
        'unexpected non-JSON file',
        'source-preflight-hash.json',
        'source-run-input-manifest-hash.json',
        'transcript_messages',
        'cost_latency_record_id'
    )) {
        if (-not $mockExecutionPackageScorerContent.Contains($check)) {
            $failures.Add("Missing empirical mock execution package scorer invariant '$check'.")
        }
    }
}

$annotationWorklistSchemaPath = Join-Path $RepoRoot 'evals\empirical\annotation-worklist-schema.yaml'
if (Test-Path -LiteralPath $annotationWorklistSchemaPath) {
    $annotationWorklistSchemaContent = Get-Content -LiteralPath $annotationWorklistSchemaPath -Raw
    if ($annotationWorklistSchemaContent -notmatch 'claim_boundary:\s*annotation_worklist_schema_only_no_labels') {
        $failures.Add('Annotation worklist schema must declare annotation_worklist_schema_only_no_labels claim boundary.')
    }
    foreach ($check in @(
        'annotation-work-items',
        'annotation-worklist-manifest.json',
        'source-pilot-execution-manifest-hash.json',
        'annotation-guidelines-hash.json',
        'annotation_work_item_id',
        'transcript_message_count',
        'transcript_spans_source',
        'required_label_fields',
        'every_pilot_transcript_has_annotation_work_item',
        'work_item_contains_no_labels',
        'false_readiness_label',
        'llm_judge_label',
        'aggregate_metrics',
        'empirical_effectiveness_proven',
        'no_human_labels',
        'no_llm_judge_labels',
        'no_paper_readiness'
    )) {
        if ($annotationWorklistSchemaContent -notlike "*$check*") {
            $failures.Add("Missing annotation worklist schema requirement '$check'.")
        }
    }
}

$annotationWorklistDocPath = Join-Path $RepoRoot 'docs\empirical-annotation-worklist.md'
if (Test-Path -LiteralPath $annotationWorklistDocPath) {
    $annotationWorklistDocContent = Get-Content -LiteralPath $annotationWorklistDocPath -Raw
    foreach ($check in @(
        'does not create labels',
        'Run after producing a pilot execution package',
        'build-empirical-annotation-worklist.ps1 -SelfTest',
        'score-empirical-annotation-worklist.ps1 -SelfTest',
        'reject injected label',
        'metadata hash tampering',
        'non-JSON sensitive',
        'Current Nonclaims'
    )) {
        if (-not $annotationWorklistDocContent.Contains($check)) {
            $failures.Add("Missing empirical annotation worklist doc boundary '$check' in docs/empirical-annotation-worklist.md")
        }
    }
}

$annotationWorklistBuilderPath = Join-Path $RepoRoot 'scripts\build-empirical-annotation-worklist.ps1'
if (Test-Path -LiteralPath $annotationWorklistBuilderPath) {
    $annotationWorklistBuilderContent = Get-Content -LiteralPath $annotationWorklistBuilderPath -Raw
    foreach ($check in @(
        'Empirical annotation worklist builder',
        'annotation_worklist_unlabeled_no_annotations',
        'Built a 9-item annotation worklist',
        'Refused non-generated files when -Force was used',
        'annotation-guidelines-hash.json',
        'source-pilot-execution-manifest-hash.json'
    )) {
        if (-not $annotationWorklistBuilderContent.Contains($check)) {
            $failures.Add("Missing empirical annotation worklist builder invariant '$check'.")
        }
    }
}

$annotationWorklistScorerPath = Join-Path $RepoRoot 'scripts\score-empirical-annotation-worklist.ps1'
if (Test-Path -LiteralPath $annotationWorklistScorerPath) {
    $annotationWorklistScorerContent = Get-Content -LiteralPath $annotationWorklistScorerPath -Raw
    foreach ($check in @(
        'Empirical annotation worklist scoring',
        'annotation_worklist_schema_only_no_labels',
        'annotation_worklist_unlabeled_no_annotations',
        'Rejected missing work items, injected label fields, transcript mismatches, metadata hash tampering, and non-JSON sensitive files',
        'mismatched_checked_evidence',
        'must not contain forbidden field',
        'annotation-guidelines-hash.json',
        'source-pilot-execution-manifest-hash.json'
    )) {
        if (-not $annotationWorklistScorerContent.Contains($check)) {
            $failures.Add("Missing empirical annotation worklist scorer invariant '$check'.")
        }
    }
}

$conditionPromptPackPath = Join-Path $RepoRoot 'evals\empirical\condition-prompt-pack.yaml'
if (Test-Path -LiteralPath $conditionPromptPackPath) {
    $conditionPromptPackContent = Get-Content -LiteralPath $conditionPromptPackPath -Raw
    if ($conditionPromptPackContent -notmatch 'claim_boundary:\s*condition_prompt_pack_only_no_model_results') {
        $failures.Add('Condition prompt pack must declare condition_prompt_pack_only_no_model_results claim boundary.')
    }
    foreach ($check in @(
        'condition-prompts-v0.1.0',
        'no_gate',
        'checklist_only',
        'single_self_review',
        'same_context_critique',
        'separate_counter_review',
        'claim_ceiling_only',
        'counter_review_only',
        'full_consult_gate',
        'programmatic_gate_variant',
        'final_claim',
        'checked_evidence',
        'selected_claim_ceiling',
        'stop_or_continue_decision',
        'human_checkpoint_decision',
        'not a completely unprompted default interaction',
        'no_model_api_eval_execution',
        'no_empirical_results',
        'no_transcripts',
        'no_annotations',
        'no_paper_readiness'
    )) {
        if ($conditionPromptPackContent -notlike "*$check*") {
            $failures.Add("Missing condition prompt-pack requirement '$check'.")
        }
    }
    $conditionCount = ([regex]::Matches($conditionPromptPackContent, '(?m)^\s{2}-\s+condition:\s*')).Count
    if ($conditionCount -ne 9) {
        $failures.Add("Condition prompt pack must contain exactly 9 condition prompts; found $conditionCount.")
    }
    foreach ($blockedField in @(
        'pass_rate',
        'win_rate',
        'effectiveness_claim',
        'empirical_effectiveness_proven',
        'paper_ready',
        'production_ready',
        'statistical_significance'
    )) {
        if ([regex]::IsMatch($conditionPromptPackContent, "(?m)^\s*$([regex]::Escape($blockedField))\s*:")) {
            $failures.Add("Condition prompt pack must not contain result field '$blockedField'.")
        }
    }
}

$conditionPromptPackDocPath = Join-Path $RepoRoot 'docs\condition-prompt-pack.md'
if (Test-Path -LiteralPath $conditionPromptPackDocPath) {
    $conditionPromptPackDocContent = Get-Content -LiteralPath $conditionPromptPackDocPath -Raw
    foreach ($check in @(
        'does not execute model/API evals',
        'score-empirical-prompt-pack.ps1',
        'condition-prompts-v0.1.0',
        'Current Nonclaims',
        'real transcripts'
    )) {
        if (-not $conditionPromptPackDocContent.Contains($check)) {
            $failures.Add("Missing condition prompt-pack doc boundary '$check' in docs/condition-prompt-pack.md")
        }
    }
}

$conditionPromptPackScorerPath = Join-Path $RepoRoot 'scripts\score-empirical-prompt-pack.ps1'
if (Test-Path -LiteralPath $conditionPromptPackScorerPath) {
    $conditionPromptPackScorerContent = Get-Content -LiteralPath $conditionPromptPackScorerPath -Raw
    foreach ($check in @(
        'Empirical prompt-pack scoring',
        'condition_prompt_pack_only_no_model_results',
        'condition-prompts-v0.1.0',
        'condition_prompt_pack_available',
        'Condition prompt pack must contain exactly'
    )) {
        if (-not $conditionPromptPackScorerContent.Contains($check)) {
            $failures.Add("Missing condition prompt-pack scorer invariant '$check'.")
        }
    }
}

$transcriptSchemaPath = Join-Path $RepoRoot 'evals\empirical\transcript-schema.yaml'
if (Test-Path -LiteralPath $transcriptSchemaPath) {
    $transcriptSchemaContent = Get-Content -LiteralPath $transcriptSchemaPath -Raw
    if ($transcriptSchemaContent -notmatch 'claim_boundary:\s*transcript_schema_only_no_transcripts') {
        $failures.Add('Transcript schema must declare transcript_schema_only_no_transcripts claim boundary.')
    }
    foreach ($check in @(
        'run_id',
        'task_id',
        'condition',
        'model_provider',
        'transcript_messages',
        'final_claim',
        'checked_evidence',
        'selected_claim_ceiling',
        'cost_latency_record_id',
        'no_private_paths'
    )) {
        if ($transcriptSchemaContent -notlike "*$check*") {
            $failures.Add("Missing transcript schema requirement '$check'.")
        }
    }
}

$annotationSchemaPath = Join-Path $RepoRoot 'evals\empirical\annotation-schema.yaml'
$annotationRequiredFieldsForGuidelines = @()
if (Test-Path -LiteralPath $annotationSchemaPath) {
    $annotationSchemaContent = Get-Content -LiteralPath $annotationSchemaPath -Raw
    $annotationRequiredFieldsForGuidelines = Get-YamlList -Text $annotationSchemaContent -Field 'required_fields'
    if ($annotationSchemaContent -notmatch 'claim_boundary:\s*annotation_schema_only_no_labels') {
        $failures.Add('Annotation schema must declare annotation_schema_only_no_labels claim boundary.')
    }
    foreach ($check in @(
        'annotation_id',
        'run_id',
        'annotation_guideline_version',
        'false_readiness_label',
        'overclaim_label',
        'objective_narrowing_label',
        'human_checkpoint_recall_label',
        'unnecessary_stop_label',
        'nonlocal_route_violation_label',
        'stale_source_reliance_label',
        'counter_review_catch_label',
        'adjudication_override_quality_label',
        'final_claim_supported_label',
        'rationale_transcript_spans',
        'human_primary_labels',
        'llm_judge_labels_if_used',
        'agreement_metric_report',
        'judge_bias_limitations'
    )) {
        if ($annotationSchemaContent -notlike "*$check*") {
            $failures.Add("Missing annotation schema requirement '$check'.")
        }
    }
}

$evidencePackageSchemaPath = Join-Path $RepoRoot 'evals\empirical\evidence-package-schema.yaml'
if (Test-Path -LiteralPath $evidencePackageSchemaPath) {
    $evidencePackageSchemaContent = Get-Content -LiteralPath $evidencePackageSchemaPath -Raw
    if ($evidencePackageSchemaContent -notmatch 'claim_boundary:\s*evidence_package_schema_only_no_experiment_results') {
        $failures.Add('Evidence package schema must declare evidence_package_schema_only_no_experiment_results claim boundary.')
    }
    foreach ($check in @(
        'transcripts',
        'annotations',
        'cost-latency',
        'every_transcript_has_annotation',
        'every_transcript_has_cost_latency_record',
        'every_annotation_records_guideline_version',
        'annotation_rationales_include_transcript_spans',
        'crossed_cost_latency_join',
        'no_model_api_eval_execution',
        'no_transcripts',
        'no_annotations',
        'no_aggregate_metrics',
        'no_paper_readiness'
    )) {
        if ($evidencePackageSchemaContent -notlike "*$check*") {
            $failures.Add("Missing evidence package schema requirement '$check'.")
        }
    }
}

$evidencePackageDocPath = Join-Path $RepoRoot 'docs\empirical-evidence-package.md'
if (Test-Path -LiteralPath $evidencePackageDocPath) {
    $evidencePackageDocContent = Get-Content -LiteralPath $evidencePackageDocPath -Raw
    foreach ($check in @(
        'does not execute model/API evals',
        'include transcripts',
        'include labels',
        'report results',
        'claim paper readiness',
        'score-empirical-evidence-package.ps1 -SelfTest',
        'synthetic data',
        'not empirical effectiveness results'
    )) {
        if (-not $evidencePackageDocContent.Contains($check)) {
            $failures.Add("Missing empirical evidence-package boundary '$check' in docs/empirical-evidence-package.md")
        }
    }
}

$evidencePackageScorerPath = Join-Path $RepoRoot 'scripts\score-empirical-evidence-package.ps1'
if (Test-Path -LiteralPath $evidencePackageScorerPath) {
    $evidencePackageScorerContent = Get-Content -LiteralPath $evidencePackageScorerPath -Raw
    foreach ($check in @(
        'Empirical evidence-package scoring',
        'Synthetic positive evidence package',
        'Synthetic negative evidence package',
        'has no matching annotation record',
        'empty ids',
        'credential keys',
        'invalid labels',
        'invalid spans',
        'malformed costs',
        'missing or wrong guideline versions',
        'annotation-guidelines-v0.1.0',
        'crossed cost joins',
        'incomplete nested schema fields',
        'does not match transcript run_id',
        'Provide -PackageRoot for a real evidence package or -SelfTest'
    )) {
        if (-not $evidencePackageScorerContent.Contains($check)) {
            $failures.Add("Missing evidence-package scorer invariant '$check'.")
        }
    }
}

$annotationGuidelinesPath = Join-Path $RepoRoot 'docs\empirical-annotation-guidelines.md'
if (Test-Path -LiteralPath $annotationGuidelinesPath) {
    $annotationGuidelinesContent = Get-Content -LiteralPath $annotationGuidelinesPath -Raw
    foreach ($check in @(
        'annotation-guidelines-v0.1.0',
        'false_readiness_label',
        'overclaim_label',
        'objective_narrowing_label',
        'human_checkpoint_recall_label',
        'unnecessary_stop_label',
        'nonlocal_route_violation_label',
        'stale_source_reliance_label',
        'counter_review_catch_label',
        'adjudication_override_quality_label',
        'final_claim_supported_label',
        'Transcript Span Rules',
        'Agreement Route',
        'Current Nonclaims',
        'does not include real labels',
        'model/API results'
    )) {
        if (-not $annotationGuidelinesContent.Contains($check)) {
            $failures.Add("Missing empirical annotation-guidelines boundary '$check' in docs/empirical-annotation-guidelines.md")
        }
    }
    foreach ($labelField in @($annotationRequiredFieldsForGuidelines | Where-Object { $_ -like '*_label' })) {
        if (-not $annotationGuidelinesContent.Contains($labelField)) {
            $failures.Add("docs/empirical-annotation-guidelines.md is missing schema-required label rubric '$labelField'.")
        }
    }
}

$resultsSummarySchemaPath = Join-Path $RepoRoot 'evals\empirical\results-summary-schema.yaml'
if (Test-Path -LiteralPath $resultsSummarySchemaPath) {
    $resultsSummarySchemaContent = Get-Content -LiteralPath $resultsSummarySchemaPath -Raw
    if ($resultsSummarySchemaContent -notmatch 'claim_boundary:\s*results_summary_schema_only_no_empirical_results') {
        $failures.Add('Results summary schema must declare results_summary_schema_only_no_empirical_results claim boundary.')
    }
    foreach ($check in @(
        'primary_annotation_policy',
        'false_readiness_rate',
        'overclaim_rate',
        'objective_narrowing_rate',
        'unnecessary_stop_rate',
        'human_checkpoint_recall_rate',
        'cost_latency_summary',
        'pairwise_exact_label_agreement_rate',
        'pairwise_label_matches',
        'no_model_api_eval_execution',
        'no_human_llm_judge_agreement_results',
        'no_real_aggregate_metrics',
        'no_paper_readiness'
    )) {
        if ($resultsSummarySchemaContent -notlike "*$check*") {
            $failures.Add("Missing results summary schema requirement '$check'.")
        }
    }
}

$agreementSummarySchemaPath = Join-Path $RepoRoot 'evals\empirical\agreement-summary-schema.yaml'
if (Test-Path -LiteralPath $agreementSummarySchemaPath) {
    $agreementSummarySchemaContent = Get-Content -LiteralPath $agreementSummarySchemaPath -Raw
    if ($agreementSummarySchemaContent -notmatch 'claim_boundary:\s*agreement_summary_schema_only_no_real_agreement_results') {
        $failures.Add('Agreement summary schema must declare agreement_summary_schema_only_no_real_agreement_results claim boundary.')
    }
    foreach ($check in @(
        'human_llm_pairwise_exact_label_agreement_rate',
        'human_llm_label_comparisons',
        'human_llm_label_matches',
        'known_bias_limitations',
        'verbosity_bias',
        'position_bias',
        'self_enhancement_bias',
        'correlated_model_failure',
        'rubric_drift',
        'missing_human_ground_truth',
        'score-empirical-agreement.ps1 -SelfTest',
        'no_human_llm_judge_agreement_results',
        'no_judge_validity_claim',
        'no_paper_readiness'
    )) {
        if ($agreementSummarySchemaContent -notlike "*$check*") {
            $failures.Add("Missing agreement summary schema requirement '$check'.")
        }
    }
}

$empiricalResultsDocPath = Join-Path $RepoRoot 'docs\empirical-results-analysis.md'
if (Test-Path -LiteralPath $empiricalResultsDocPath) {
    $empiricalResultsDocContent = Get-Content -LiteralPath $empiricalResultsDocPath -Raw
    foreach ($check in @(
        'does not execute model/API evals',
        'real aggregate metrics',
        'score-empirical-results.ps1 -SelfTest',
        'Synthetic self-test metrics',
        'not empirical proof or paper readiness',
        'Current Nonclaims'
    )) {
        if (-not $empiricalResultsDocContent.Contains($check)) {
            $failures.Add("Missing empirical results-analysis boundary '$check' in docs/empirical-results-analysis.md")
        }
    }
}

$empiricalResultsScorerPath = Join-Path $RepoRoot 'scripts\score-empirical-results.ps1'
if (Test-Path -LiteralPath $empiricalResultsScorerPath) {
    $empiricalResultsScorerContent = Get-Content -LiteralPath $empiricalResultsScorerPath -Raw
    foreach ($check in @(
        'Empirical results aggregation',
        'Invoke-EvidencePackageValidator',
        'false_readiness_rate',
        'condition_metrics',
        'cost_latency_summary',
        'pairwise_exact_label_agreement_rate',
        'not referenced by any transcript',
        'conflicting same-priority primary annotations',
        'self_test_relative_package_id_status',
        'Rejected invalid package, duplicate cost records, and conflicting primary annotations before aggregation',
        'Provide -PackageRoot for a real evidence package or -SelfTest'
    )) {
        if (-not $empiricalResultsScorerContent.Contains($check)) {
            $failures.Add("Missing empirical results scorer invariant '$check'.")
        }
    }
}

$empiricalAgreementDocPath = Join-Path $RepoRoot 'docs\empirical-agreement-checks.md'
if (Test-Path -LiteralPath $empiricalAgreementDocPath) {
    $empiricalAgreementDocContent = Get-Content -LiteralPath $empiricalAgreementDocPath -Raw
    foreach ($check in @(
        'does not execute model/API evals',
        'score-empirical-agreement.ps1 -SelfTest',
        'RequireHumanLlmPairs',
        'MinimumAgreementRate',
        'Bias Limitations',
        'not prove',
        'Current Nonclaims'
    )) {
        if (-not $empiricalAgreementDocContent.Contains($check)) {
            $failures.Add("Missing empirical agreement-checks boundary '$check' in docs/empirical-agreement-checks.md")
        }
    }
}

$empiricalAgreementScorerPath = Join-Path $RepoRoot 'scripts\score-empirical-agreement.ps1'
if (Test-Path -LiteralPath $empiricalAgreementScorerPath) {
    $empiricalAgreementScorerContent = Get-Content -LiteralPath $empiricalAgreementScorerPath -Raw
    foreach ($check in @(
        'Empirical agreement checks',
        'Invoke-EvidencePackageValidator',
        'human_llm_pairwise_exact_label_agreement_rate',
        'Human/LLM-judge annotation pairs are required',
        'below required minimum',
        'known_bias_limitations',
        'self_test_path_redaction_status',
        'Rejected missing human/LLM pairs when required',
        'Rejected low agreement when a minimum threshold was required',
        'Provide -PackageRoot for a real evidence package or -SelfTest'
    )) {
        if (-not $empiricalAgreementScorerContent.Contains($check)) {
            $failures.Add("Missing empirical agreement scorer invariant '$check'.")
        }
    }
}

$empiricalDryRunDocPath = Join-Path $RepoRoot 'docs\empirical-dry-run-package.md'
if (Test-Path -LiteralPath $empiricalDryRunDocPath) {
    $empiricalDryRunDocContent = Get-Content -LiteralPath $empiricalDryRunDocPath -Raw
    foreach ($check in @(
        'does not execute model/API evals',
        'build-empirical-dry-run-package.ps1 -SelfTest',
        'RunValidators',
        'Current Nonclaims',
        'no real transcripts',
        'no empirical effectiveness claim',
        'synthetic evidence package'
    )) {
        if (-not $empiricalDryRunDocContent.Contains($check)) {
            $failures.Add("Missing empirical dry-run package boundary '$check' in docs/empirical-dry-run-package.md")
        }
    }
}

$empiricalDryRunBuilderPath = Join-Path $RepoRoot 'scripts\build-empirical-dry-run-package.ps1'
if (Test-Path -LiteralPath $empiricalDryRunBuilderPath) {
    $empiricalDryRunBuilderContent = Get-Content -LiteralPath $empiricalDryRunBuilderPath -Raw
    foreach ($check in @(
        'Empirical dry-run package builder',
        'score-empirical-evidence-package.ps1',
        'score-empirical-results.ps1',
        'score-empirical-agreement.ps1',
        'RequireHumanLlmPairs',
        'MinimumAgreementRate',
        'OutputRoot already exists and is not empty',
        'contains non-generated file',
        'no_model_api_eval_execution',
        'Generated synthetic dry-run evidence package'
    )) {
        if (-not $empiricalDryRunBuilderContent.Contains($check)) {
            $failures.Add("Missing empirical dry-run package builder invariant '$check'.")
        }
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
        },
        @{
            Path = Join-Path $RepoRoot 'docs\empirical-evaluation-plan.md'
            Label = 'docs/empirical-evaluation-plan.md'
        },
        @{
            Path = Join-Path $RepoRoot 'docs\condition-prompt-pack.md'
            Label = 'docs/condition-prompt-pack.md'
        },
        @{
            Path = Join-Path $RepoRoot 'docs\empirical-run-inputs.md'
            Label = 'docs/empirical-run-inputs.md'
        },
        @{
            Path = Join-Path $RepoRoot 'docs\empirical-execution-preflight.md'
            Label = 'docs/empirical-execution-preflight.md'
        },
        @{
            Path = Join-Path $RepoRoot 'docs\empirical-mock-execution-package.md'
            Label = 'docs/empirical-mock-execution-package.md'
        },
        @{
            Path = Join-Path $RepoRoot 'docs\empirical-pilot-execution-runner.md'
            Label = 'docs/empirical-pilot-execution-runner.md'
        },
        @{
            Path = Join-Path $RepoRoot 'docs\empirical-annotation-worklist.md'
            Label = 'docs/empirical-annotation-worklist.md'
        },
        @{
            Path = Join-Path $RepoRoot 'docs\experiment-run-packet.md'
            Label = 'docs/experiment-run-packet.md'
        },
        @{
            Path = Join-Path $RepoRoot 'docs\empirical-evidence-package.md'
            Label = 'docs/empirical-evidence-package.md'
        },
        @{
            Path = Join-Path $RepoRoot 'docs\empirical-results-analysis.md'
            Label = 'docs/empirical-results-analysis.md'
        },
        @{
            Path = Join-Path $RepoRoot 'docs\empirical-annotation-guidelines.md'
            Label = 'docs/empirical-annotation-guidelines.md'
        },
        @{
            Path = Join-Path $RepoRoot 'docs\empirical-agreement-checks.md'
            Label = 'docs/empirical-agreement-checks.md'
        },
        @{
            Path = Join-Path $RepoRoot 'docs\empirical-dry-run-package.md'
            Label = 'docs/empirical-dry-run-package.md'
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
