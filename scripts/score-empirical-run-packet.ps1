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

$paths = [ordered]@{
    Manifest = Join-Path $RepoRoot 'evals/empirical/experiment-run-manifest.yaml'
    TranscriptSchema = Join-Path $RepoRoot 'evals/empirical/transcript-schema.yaml'
    AnnotationSchema = Join-Path $RepoRoot 'evals/empirical/annotation-schema.yaml'
    EvidencePackageSchema = Join-Path $RepoRoot 'evals/empirical/evidence-package-schema.yaml'
    ResultsSummarySchema = Join-Path $RepoRoot 'evals/empirical/results-summary-schema.yaml'
    AgreementSummarySchema = Join-Path $RepoRoot 'evals/empirical/agreement-summary-schema.yaml'
    AnnotationGuidelines = Join-Path $RepoRoot 'docs/empirical-annotation-guidelines.md'
    RunPacketDoc = Join-Path $RepoRoot 'docs/experiment-run-packet.md'
}

$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$info = New-Object System.Collections.Generic.List[string]
$annotationRequiredFields = @()

foreach ($entry in $paths.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value)) {
        $failures.Add("Missing required run-packet artifact: $($entry.Value)")
    }
}

if (Test-Path -LiteralPath $paths.Manifest) {
    $manifest = Get-Content -LiteralPath $paths.Manifest -Raw
    if ((Get-Scalar -Text $manifest -Field 'claim_boundary') -ne 'run_packet_schema_only_no_execution_results') {
        $failures.Add('Experiment run manifest must declare run_packet_schema_only_no_execution_results.')
    }
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $manifest -Field 'conditions') -Required @(
        'no_gate',
        'checklist_only',
        'single_self_review',
        'same_context_critique',
        'separate_counter_review',
        'claim_ceiling_only',
        'counter_review_only',
        'full_consult_gate',
        'programmatic_gate_variant'
    ) -Label 'conditions'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $manifest -Field 'required_artifacts') -Required @(
        'raw_transcript',
        'annotation_record',
        'annotation_guidelines',
        'agreement_check_record',
        'model_runtime_record',
        'cost_latency_record',
        'prompt_version_record',
        'task_suite_hash_record',
        'scorer_version_record',
        'redaction_review_record'
    ) -Label 'required_artifacts'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $manifest -Field 'stop_gates') -Required @(
        'no_private_repository_material',
        'prompts_frozen_before_execution',
        'budget_recorded_before_execution',
        'annotation_guidelines_available',
        'agreement_checker_available',
        'no_paper_readiness_claim_before_results',
        'no_model_result_fields_in_planning_manifest'
    ) -Label 'stop_gates'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $manifest -Field 'current_nonclaims') -Required @(
        'no_model_api_eval_execution',
        'no_empirical_results',
        'no_cost_latency_results',
        'no_human_llm_judge_agreement_results',
        'no_transcripts',
        'no_annotations',
        'no_paper_readiness'
    ) -Label 'current_nonclaims'
    foreach ($schemaLink in @(
        'transcript_schema: evals/empirical/transcript-schema.yaml',
        'annotation_schema: evals/empirical/annotation-schema.yaml',
        'evidence_package_schema: evals/empirical/evidence-package-schema.yaml',
        'results_summary_schema: evals/empirical/results-summary-schema.yaml',
        'agreement_summary_schema: evals/empirical/agreement-summary-schema.yaml',
        'annotation_guidelines: docs/empirical-annotation-guidelines.md'
    )) {
        if (-not $manifest.Contains($schemaLink)) {
            $failures.Add("Experiment run manifest is missing schema link '$schemaLink'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.TranscriptSchema) {
    $transcript = Get-Content -LiteralPath $paths.TranscriptSchema -Raw
    if ((Get-Scalar -Text $transcript -Field 'claim_boundary') -ne 'transcript_schema_only_no_transcripts') {
        $failures.Add('Transcript schema must declare transcript_schema_only_no_transcripts.')
    }
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $transcript -Field 'required_fields') -Required @(
        'run_id',
        'task_id',
        'condition',
        'model_provider',
        'model_name_or_alias',
        'input_prompt',
        'transcript_messages',
        'final_claim',
        'checked_evidence',
        'selected_claim_ceiling',
        'cost_latency_record_id',
        'redaction_status'
    ) -Label 'transcript required_fields'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $transcript -Field 'privacy_requirements') -Required @(
        'synthetic_or_redacted_repository_fixture',
        'no_private_paths',
        'no_credentials',
        'no_unpublished_private_documents'
    ) -Label 'transcript privacy_requirements'
}

if (Test-Path -LiteralPath $paths.AnnotationSchema) {
    $annotation = Get-Content -LiteralPath $paths.AnnotationSchema -Raw
    $annotationRequiredFields = Get-YamlList -Text $annotation -Field 'required_fields'
    if ((Get-Scalar -Text $annotation -Field 'claim_boundary') -ne 'annotation_schema_only_no_labels') {
        $failures.Add('Annotation schema must declare annotation_schema_only_no_labels.')
    }
    Assert-ListContains -Failures $failures -Items $annotationRequiredFields -Required @(
        'annotation_id',
        'run_id',
        'task_id',
        'condition',
        'annotation_guideline_version',
        'annotator_type',
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
        'confidence'
    ) -Label 'annotation required_fields'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $annotation -Field 'agreement_requirements') -Required @(
        'human_primary_labels',
        'llm_judge_labels_if_used',
        'disagreement_adjudication',
        'agreement_metric_report',
        'judge_bias_limitations'
    ) -Label 'agreement_requirements'
    if (-not $annotation.Contains('required_guideline_version: annotation-guidelines-v0.1.0')) {
        $failures.Add('Annotation schema must declare required_guideline_version: annotation-guidelines-v0.1.0.')
    }
}

if (Test-Path -LiteralPath $paths.EvidencePackageSchema) {
    $evidencePackage = Get-Content -LiteralPath $paths.EvidencePackageSchema -Raw
    if ((Get-Scalar -Text $evidencePackage -Field 'claim_boundary') -ne 'evidence_package_schema_only_no_experiment_results') {
        $failures.Add('Evidence package schema must declare evidence_package_schema_only_no_experiment_results.')
    }
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $evidencePackage -Field 'required_directories') -Required @(
        'transcripts',
        'annotations',
        'cost-latency'
    ) -Label 'evidence package required_directories'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $evidencePackage -Field 'join_requirements') -Required @(
        'every_transcript_has_annotation',
        'every_transcript_has_cost_latency_record',
        'every_annotation_records_guideline_version',
        'every_annotation_run_id_matches_transcript',
        'every_cost_latency_run_id_matches_transcript',
        'every_transcript_cost_latency_record_id_matches_cost_record',
        'annotation_rationales_include_transcript_spans'
    ) -Label 'evidence package join_requirements'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $evidencePackage -Field 'current_nonclaims') -Required @(
        'no_model_api_eval_execution',
        'no_transcripts',
        'no_annotations',
        'no_cost_latency_results',
        'no_human_llm_judge_agreement_results',
        'no_aggregate_metrics',
        'no_statistical_results',
        'no_empirical_effectiveness_claim',
        'no_paper_readiness'
    ) -Label 'evidence package current_nonclaims'
}

if (Test-Path -LiteralPath $paths.ResultsSummarySchema) {
    $resultsSummary = Get-Content -LiteralPath $paths.ResultsSummarySchema -Raw
    if ((Get-Scalar -Text $resultsSummary -Field 'claim_boundary') -ne 'results_summary_schema_only_no_empirical_results') {
        $failures.Add('Results summary schema must declare results_summary_schema_only_no_empirical_results.')
    }
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $resultsSummary -Field 'required_summary_fields') -Required @(
        'package_id',
        'primary_annotation_policy',
        'total_runs',
        'analyzed_runs',
        'condition_count',
        'metrics',
        'condition_metrics',
        'cost_latency_summary',
        'annotator_agreement',
        'analyzer_version'
    ) -Label 'results summary required_summary_fields'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $resultsSummary -Field 'defect_rates') -Required @(
        'false_readiness_rate',
        'overclaim_rate',
        'objective_narrowing_rate',
        'unnecessary_stop_rate',
        'nonlocal_route_violation_rate',
        'stale_source_reliance_rate'
    ) -Label 'results summary defect_rates'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $resultsSummary -Field 'positive_rates') -Required @(
        'human_checkpoint_recall_rate',
        'counter_review_catch_rate',
        'adjudication_override_quality_rate',
        'final_claim_supported_rate'
    ) -Label 'results summary positive_rates'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $resultsSummary -Field 'current_nonclaims') -Required @(
        'no_model_api_eval_execution',
        'no_real_transcripts',
        'no_real_annotations',
        'no_real_cost_latency_results',
        'no_human_llm_judge_agreement_results',
        'no_real_aggregate_metrics',
        'no_statistical_results',
        'no_empirical_effectiveness_claim',
        'no_paper_readiness'
    ) -Label 'results summary current_nonclaims'
}

if (Test-Path -LiteralPath $paths.AgreementSummarySchema) {
    $agreementSummary = Get-Content -LiteralPath $paths.AgreementSummarySchema -Raw
    if ((Get-Scalar -Text $agreementSummary -Field 'claim_boundary') -ne 'agreement_summary_schema_only_no_real_agreement_results') {
        $failures.Add('Agreement summary schema must declare agreement_summary_schema_only_no_real_agreement_results.')
    }
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $agreementSummary -Field 'required_summary_fields') -Required @(
        'package_id',
        'compared_runs',
        'human_llm_pairwise_exact_label_agreement_rate',
        'human_llm_label_comparisons',
        'human_llm_label_matches',
        'human_annotation_count',
        'llm_judge_annotation_count',
        'agreement_unavailable_reason',
        'known_bias_limitations',
        'analyzer_version'
    ) -Label 'agreement summary required_summary_fields'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $agreementSummary -Field 'known_bias_limitations') -Required @(
        'verbosity_bias',
        'position_bias',
        'self_enhancement_bias',
        'correlated_model_failure',
        'rubric_drift',
        'missing_human_ground_truth'
    ) -Label 'agreement summary known_bias_limitations'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $agreementSummary -Field 'current_nonclaims') -Required @(
        'no_model_api_eval_execution',
        'no_real_human_labels',
        'no_real_llm_judge_labels',
        'no_human_llm_judge_agreement_results',
        'no_judge_validity_claim',
        'no_paper_readiness'
    ) -Label 'agreement summary current_nonclaims'
}

if (Test-Path -LiteralPath $paths.AnnotationGuidelines) {
    $guidelines = Get-Content -LiteralPath $paths.AnnotationGuidelines -Raw
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
        if (-not $guidelines.Contains($check)) {
            $failures.Add("Annotation guidelines are missing required rubric text '$check'.")
        }
    }
    foreach ($labelField in @($annotationRequiredFields | Where-Object { $_ -like '*_label' })) {
        if (-not $guidelines.Contains($labelField)) {
            $failures.Add("Annotation guidelines are missing schema-required label rubric '$labelField'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.RunPacketDoc) {
    $doc = Get-Content -LiteralPath $paths.RunPacketDoc -Raw
    foreach ($check in @(
        'does not execute model/API evals',
        'report results',
        'claim paper readiness',
        'No private repository material',
        'score-empirical-run-packet.ps1'
    )) {
        if (-not $doc.Contains($check)) {
            $failures.Add("Experiment run packet doc is missing boundary '$check'.")
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

$info.Add('Scored empirical run-packet structure.')
$info.Add("Checked $($paths.Count) run-packet artifact(s).")

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
    "Empirical run-packet scoring: $status"
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
