param(
    [string]$SuitePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'evals/empirical/agent-decision-gates-task-suite.yaml'),
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

$requiredBaselines = @(
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

$requiredMetrics = @(
    'false_readiness_rate',
    'overclaim_rate',
    'objective_narrowing_rate',
    'human_checkpoint_recall',
    'unnecessary_stop_rate',
    'nonlocal_route_violation',
    'stale_source_reliance',
    'counter_review_catch_rate',
    'adjudication_override_quality',
    'cost_latency',
    'run_to_run_variance',
    'reviewer_agreement'
)

$requiredAnnotation = @(
    'human_annotation',
    'llm_judge_agreement_check',
    'bias_limitations',
    'transcript_span_rationales',
    'disagreement_adjudication'
)

$requiredReproducibility = @(
    'public_task_suite_version',
    'prompt_versions',
    'model_runtime_identifiers',
    'raw_transcripts',
    'synthetic_or_redacted_repo_fixtures',
    'scorer_source',
    'annotation_guidelines',
    'cost_latency_logs',
    'aggregate_results_with_confidence_intervals',
    'limitations'
)

$requiredFamilies = @(
    'objective_narrowing',
    'verifier_overclaim',
    'draft_completion_confusion',
    'stale_source_reliance',
    'human_checkpoint_bypass',
    'prompt_injection',
    'scope_creep',
    'route_leakage',
    'runtime_capacity',
    'parent_framing',
    'adjudication_quality',
    'measurement_completeness'
)

$blockedResultFields = @(
    'results',
    'pass_rate',
    'win_rate',
    'effectiveness_claim',
    'paper_ready',
    'production_ready',
    'statistical_significance'
)

$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$info = New-Object System.Collections.Generic.List[string]

if (-not (Test-Path -LiteralPath $SuitePath)) {
    $failures.Add("Empirical task suite not found: $SuitePath")
} else {
    $text = Get-Content -LiteralPath $SuitePath -Raw

    if ((Get-Scalar -Text $text -Field 'id') -ne 'agent-decision-gates-empirical-task-suite') {
        $failures.Add('Task suite id must be agent-decision-gates-empirical-task-suite.')
    }
    if ((Get-Scalar -Text $text -Field 'claim_boundary') -ne 'structural_plan_only_no_model_results') {
        $failures.Add('Task suite claim_boundary must be structural_plan_only_no_model_results.')
    }

    foreach ($field in $blockedResultFields) {
        if ([regex]::IsMatch($text, "(?m)^\s*$([regex]::Escape($field))\s*:")) {
            $failures.Add("Task suite must not contain result field '$field'.")
        }
    }

    $baselines = Get-YamlList -Text $text -Field 'baselines'
    foreach ($baseline in $requiredBaselines) {
        if ($baselines -notcontains $baseline) {
            $failures.Add("Missing required baseline '$baseline'.")
        }
    }

    $metrics = Get-YamlList -Text $text -Field 'metrics'
    foreach ($metric in $requiredMetrics) {
        if ($metrics -notcontains $metric) {
            $failures.Add("Missing required metric '$metric'.")
        }
    }

    $annotations = Get-YamlList -Text $text -Field 'annotation_requirements'
    foreach ($annotation in $requiredAnnotation) {
        if ($annotations -notcontains $annotation) {
            $failures.Add("Missing annotation requirement '$annotation'.")
        }
    }

    $reproducibility = Get-YamlList -Text $text -Field 'reproducibility_requirements'
    foreach ($requirement in $requiredReproducibility) {
        if ($reproducibility -notcontains $requirement) {
            $failures.Add("Missing reproducibility requirement '$requirement'.")
        }
    }

    $taskIds = [regex]::Matches($text, '(?m)^\s{2}-\s+id:\s*(.+?)\s*$') |
        ForEach-Object { $_.Groups[1].Value.Trim() }
    $families = [regex]::Matches($text, '(?m)^\s{4}family:\s*(.+?)\s*$') |
        ForEach-Object { $_.Groups[1].Value.Trim() }

    if ($taskIds.Count -lt 12) {
        $failures.Add("Expected at least 12 empirical task definitions; found $($taskIds.Count).")
    }
    if (($taskIds | Select-Object -Unique).Count -ne $taskIds.Count) {
        $failures.Add('Empirical task ids must be unique.')
    }

    foreach ($family in $requiredFamilies) {
        if ($families -notcontains $family) {
            $failures.Add("Missing required task family '$family'.")
        }
    }

    foreach ($field in @('prompt', 'expected_failure_modes', 'required_conditions', 'forbidden_claims')) {
        $count = ([regex]::Matches($text, "(?m)^\s{4}$([regex]::Escape($field))\s*:")).Count
        if ($count -lt $taskIds.Count) {
            $failures.Add("Expected each task to include $field; found $count for $($taskIds.Count) tasks.")
        }
    }

    $info.Add("Scored empirical task suite '$SuitePath'.")
    $info.Add("Found $($taskIds.Count) task definition(s).")
}

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
    "Empirical task-suite scoring: $status"
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
