param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

function Get-Scalar {
    param(
        [string]$Text,
        [string]$Field
    )
    $match = [regex]::Match($Text, "(?m)^$([regex]::Escape($Field)):\s*(.+?)\s*$")
    if ($match.Success) {
        return $match.Groups[1].Value.Trim('"').Trim("'").Trim()
    }
    return $null
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

function Assert-ListContains {
    param(
        [System.Collections.Generic.List[string]]$Failures,
        [string[]]$Items,
        [string[]]$Required,
        [string]$Label
    )
    foreach ($requiredItem in $Required) {
        if ($Items -notcontains $requiredItem) {
            $Failures.Add("$Label is missing '$requiredItem'.")
        }
    }
}

$expectedConditions = @(
    'no_gate',
    'checklist_only',
    'single_self_review',
    'same_context_critique',
    'separate_counter_review',
    'claim_ceiling_only',
    'counter_review_only',
    'full_consult_gate',
    'programmatic_gate_variant'
)

$paths = [ordered]@{
    PromptPack = Join-Path $RepoRoot 'evals/empirical/condition-prompt-pack.yaml'
    Manifest = Join-Path $RepoRoot 'evals/empirical/experiment-run-manifest.yaml'
    TaskSuite = Join-Path $RepoRoot 'evals/empirical/agent-decision-gates-task-suite.yaml'
    PromptPackDoc = Join-Path $RepoRoot 'docs/condition-prompt-pack.md'
}

$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$info = New-Object System.Collections.Generic.List[string]

foreach ($entry in $paths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value)) {
        $failures.Add("Missing required prompt-pack artifact: $($entry.Value)")
    }
}

if (Test-Path -LiteralPath $paths.PromptPack) {
    $promptPack = Get-Content -LiteralPath $paths.PromptPack -Raw
    if ((Get-Scalar -Text $promptPack -Field 'claim_boundary') -ne 'condition_prompt_pack_only_no_model_results') {
        $failures.Add('Condition prompt pack must declare condition_prompt_pack_only_no_model_results.')
    }
    if ((Get-Scalar -Text $promptPack -Field 'version') -ne '0.1.0') {
        $failures.Add('Condition prompt pack must declare version: 0.1.0.')
    }
    if ((Get-Scalar -Text $promptPack -Field 'prompt_pack_version') -ne 'condition-prompts-v0.1.0') {
        $failures.Add('Condition prompt pack must declare prompt_pack_version: condition-prompts-v0.1.0.')
    }

    $conditionMatches = [regex]::Matches($promptPack, '(?m)^\s{2}-\s+condition:\s*(\S+)\s*$')
    $conditions = @($conditionMatches | ForEach-Object { $_.Groups[1].Value })
    foreach ($condition in $expectedConditions) {
        if ($conditions -notcontains $condition) {
            $failures.Add("Condition prompt pack is missing condition '$condition'.")
        }
    }
    foreach ($condition in $conditions) {
        if ($expectedConditions -notcontains $condition) {
            $failures.Add("Condition prompt pack contains unexpected condition '$condition'.")
        }
    }
    if ($conditions.Count -ne $expectedConditions.Count) {
        $failures.Add("Condition prompt pack must contain exactly $($expectedConditions.Count) conditions; found $($conditions.Count).")
    }

    $promptVersionCount = ([regex]::Matches($promptPack, '(?m)^\s+prompt_version:\s*condition-prompts-v0\.1\.0\s*$')).Count
    if ($promptVersionCount -ne $expectedConditions.Count) {
        $failures.Add("Condition prompt pack must repeat prompt_version for each condition; found $promptVersionCount.")
    }

    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $promptPack -Field 'required_record_fields') -Required @(
        'final_claim',
        'checked_evidence',
        'selected_claim_ceiling',
        'stop_or_continue_decision',
        'human_checkpoint_decision'
    ) -Label 'required_record_fields'

    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $promptPack -Field 'current_nonclaims') -Required @(
        'no_model_api_eval_execution',
        'no_empirical_results',
        'no_cost_latency_results',
        'no_human_llm_judge_agreement_results',
        'no_transcripts',
        'no_annotations',
        'no_paper_readiness'
    ) -Label 'current_nonclaims'

    foreach ($requiredText in @(
        'use_only_public_synthetic_or_redacted_fixtures',
        'no_private_repository_material',
        'held_constant_prompt_components',
        'paper_ready',
        'production_ready',
        'empirical_effectiveness_proven',
        'not a completely unprompted default interaction',
        'do not claim independent review',
        'deterministic blocker or permission check'
    )) {
        if (-not $promptPack.Contains($requiredText)) {
            $failures.Add("Condition prompt pack is missing invariant '$requiredText'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.Manifest) {
    $manifest = Get-Content -LiteralPath $paths.Manifest -Raw
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $manifest -Field 'conditions') -Required $expectedConditions -Label 'manifest conditions'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $manifest -Field 'required_artifacts') -Required @(
        'condition_prompt_pack',
        'prompt_version_record'
    ) -Label 'manifest required_artifacts'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $manifest -Field 'stop_gates') -Required @(
        'prompts_frozen_before_execution',
        'condition_prompt_pack_available',
        'no_model_result_fields_in_planning_manifest'
    ) -Label 'manifest stop_gates'
    if (-not $manifest.Contains('condition_prompt_pack: evals/empirical/condition-prompt-pack.yaml')) {
        $failures.Add('Experiment run manifest is missing condition_prompt_pack schema link.')
    }
}

if (Test-Path -LiteralPath $paths.TaskSuite) {
    $taskSuite = Get-Content -LiteralPath $paths.TaskSuite -Raw
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $taskSuite -Field 'baselines') -Required $expectedConditions -Label 'task-suite baselines'
    if (-not $taskSuite.Contains('prompt_versions')) {
        $failures.Add('Task suite must require prompt_versions for reproducibility.')
    }
}

if (Test-Path -LiteralPath $paths.PromptPackDoc) {
    $doc = Get-Content -LiteralPath $paths.PromptPackDoc -Raw
    foreach ($check in @(
        'does not execute model/API evals',
        'score-empirical-prompt-pack.ps1',
        'condition-prompts-v0.1.0',
        'Current Nonclaims',
        'real transcripts',
        'no model/API evals'
    )) {
        if (-not $doc.Contains($check)) {
            $failures.Add("Condition prompt-pack doc is missing boundary '$check'.")
        }
    }
}

$blockedResultFields = @(
    'pass_rate',
    'win_rate',
    'p_value',
    'confidence_interval',
    'statistical_significance',
    'effectiveness_claim',
    'empirical_effectiveness_proven',
    'paper_ready',
    'production_ready'
)

foreach ($entry in $paths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value)) {
        continue
    }
    $text = Get-Content -LiteralPath $entry.Value -Raw
    foreach ($blockedField in $blockedResultFields) {
        if ([regex]::IsMatch($text, "(?m)^\s*$([regex]::Escape($blockedField))\s*:")) {
            $failures.Add("$($entry.Key) must not contain result field '$blockedField'.")
        }
    }
}

$info.Add('Scored empirical condition prompt-pack structure.')
$info.Add("Checked $($paths.Count) prompt-pack artifact(s).")

$status = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
$result = [ordered]@{
    status = $status
    failures = @($failures)
    warnings = @($warnings)
    info = @($info)
}

if ($Json) {
    $result | ConvertTo-Json -Depth 5
} else {
    "Empirical prompt-pack scoring: $status"
    ''
    'Failures:'
    if ($failures.Count -eq 0) { '  none' } else { $failures | ForEach-Object { "  - $_" } }
    ''
    'Warnings:'
    if ($warnings.Count -eq 0) { '  none' } else { $warnings | ForEach-Object { "  - $_" } }
    ''
    'Info:'
    if ($info.Count -eq 0) { '  none' } else { $info | ForEach-Object { "  - $_" } }
}

if ($failures.Count -gt 0) {
    exit 1
}
