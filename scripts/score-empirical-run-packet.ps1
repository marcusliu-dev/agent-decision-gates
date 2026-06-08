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
    ConditionPromptPack = Join-Path $RepoRoot 'evals/empirical/condition-prompt-pack.yaml'
    RunInputSchema = Join-Path $RepoRoot 'evals/empirical/run-input-schema.yaml'
    ExecutionPreflightSchema = Join-Path $RepoRoot 'evals/empirical/execution-preflight-schema.yaml'
    AnnotationGuidelines = Join-Path $RepoRoot 'docs/empirical-annotation-guidelines.md'
    ConditionPromptDoc = Join-Path $RepoRoot 'docs/condition-prompt-pack.md'
    RunInputDoc = Join-Path $RepoRoot 'docs/empirical-run-inputs.md'
    ExecutionPreflightDoc = Join-Path $RepoRoot 'docs/empirical-execution-preflight.md'
    EmpiricalPlan = Join-Path $RepoRoot 'docs/empirical-evaluation-plan.md'
    RunPacketDoc = Join-Path $RepoRoot 'docs/experiment-run-packet.md'
    DryRunDoc = Join-Path $RepoRoot 'docs/empirical-dry-run-package.md'
    PromptPackScorer = Join-Path $RepoRoot 'scripts/score-empirical-prompt-pack.ps1'
    RunInputBuilder = Join-Path $RepoRoot 'scripts/build-empirical-run-inputs.ps1'
    RunInputScorer = Join-Path $RepoRoot 'scripts/score-empirical-run-inputs.ps1'
    ExecutionPreflightBuilder = Join-Path $RepoRoot 'scripts/build-empirical-execution-preflight.ps1'
    ExecutionPreflightScorer = Join-Path $RepoRoot 'scripts/score-empirical-execution-preflight.ps1'
    DryRunBuilder = Join-Path $RepoRoot 'scripts/build-empirical-dry-run-package.ps1'
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
        'execution_preflight_record',
        'raw_transcript',
        'annotation_record',
        'annotation_guidelines',
        'agreement_check_record',
        'condition_prompt_pack',
        'run_input_record',
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
        'condition_prompt_pack_available',
        'run_input_builder_available',
        'execution_preflight_available',
        'budget_recorded_before_execution',
        'annotation_guidelines_available',
        'agreement_checker_available',
        'dry_run_package_builder_available',
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
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $manifest -Field 'forbidden_result_fields') -Required @(
        'effectiveness_claim',
        'empirical_effectiveness_proven',
        'paper_ready',
        'production_ready'
    ) -Label 'manifest forbidden_result_fields'
    foreach ($schemaLink in @(
        'transcript_schema: evals/empirical/transcript-schema.yaml',
        'annotation_schema: evals/empirical/annotation-schema.yaml',
        'evidence_package_schema: evals/empirical/evidence-package-schema.yaml',
        'results_summary_schema: evals/empirical/results-summary-schema.yaml',
        'agreement_summary_schema: evals/empirical/agreement-summary-schema.yaml',
        'annotation_guidelines: docs/empirical-annotation-guidelines.md',
        'condition_prompt_pack: evals/empirical/condition-prompt-pack.yaml',
        'run_input_schema: evals/empirical/run-input-schema.yaml',
        'execution_preflight_schema: evals/empirical/execution-preflight-schema.yaml'
    )) {
        if (-not $manifest.Contains($schemaLink)) {
            $failures.Add("Experiment run manifest is missing schema link '$schemaLink'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.ConditionPromptPack) {
    $promptPack = Get-Content -LiteralPath $paths.ConditionPromptPack -Raw
    if ((Get-Scalar -Text $promptPack -Field 'claim_boundary') -ne 'condition_prompt_pack_only_no_model_results') {
        $failures.Add('Condition prompt pack must declare condition_prompt_pack_only_no_model_results.')
    }
    if ((Get-Scalar -Text $promptPack -Field 'prompt_pack_version') -ne 'condition-prompts-v0.1.0') {
        $failures.Add('Condition prompt pack must declare prompt_pack_version: condition-prompts-v0.1.0.')
    }
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $promptPack -Field 'required_record_fields') -Required @(
        'final_claim',
        'checked_evidence',
        'selected_claim_ceiling',
        'stop_or_continue_decision',
        'human_checkpoint_decision'
    ) -Label 'condition prompt pack required_record_fields'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $promptPack -Field 'forbidden_result_fields') -Required @(
        'effectiveness_claim',
        'empirical_effectiveness_proven',
        'paper_ready',
        'production_ready'
    ) -Label 'condition prompt pack forbidden_result_fields'
    foreach ($condition in @(
        'no_gate',
        'checklist_only',
        'single_self_review',
        'same_context_critique',
        'separate_counter_review',
        'claim_ceiling_only',
        'counter_review_only',
        'full_consult_gate',
        'programmatic_gate_variant'
    )) {
        if (-not [regex]::IsMatch($promptPack, "(?m)^\s{2}-\s+condition:\s*$([regex]::Escape($condition))\s*$")) {
            $failures.Add("Condition prompt pack is missing condition '$condition'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.ConditionPromptDoc) {
    $doc = Get-Content -LiteralPath $paths.ConditionPromptDoc -Raw
    foreach ($check in @(
        'does not execute model/API evals',
        'score-empirical-prompt-pack.ps1',
        'condition-prompts-v0.1.0',
        'Current Nonclaims',
        'real transcripts'
    )) {
        if (-not $doc.Contains($check)) {
            $failures.Add("Condition prompt-pack doc is missing boundary '$check'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.PromptPackScorer) {
    $promptPackScorer = Get-Content -LiteralPath $paths.PromptPackScorer -Raw
    foreach ($check in @(
        'Empirical prompt-pack scoring',
        'condition_prompt_pack_only_no_model_results',
        'condition-prompts-v0.1.0',
        'condition_prompt_pack_available',
        'Condition prompt pack must contain exactly'
    )) {
        if (-not $promptPackScorer.Contains($check)) {
            $failures.Add("Empirical prompt-pack scorer is missing invariant '$check'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.RunInputSchema) {
    $schema = Get-Content -LiteralPath $paths.RunInputSchema -Raw
    if ((Get-Scalar -Text $schema -Field 'claim_boundary') -ne 'run_input_schema_only_no_model_execution') {
        $failures.Add('Run-input schema must declare run_input_schema_only_no_model_execution.')
    }
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'required_fields') -Required @(
        'run_input_id',
        'task_id',
        'condition',
        'repeat_index',
        'task_suite_version',
        'prompt_pack_version',
        'manifest_version',
        'task_prompt',
        'condition_instruction',
        'input_prompt',
        'task_suite_sha256',
        'prompt_pack_sha256',
        'manifest_sha256',
        'redaction_status'
    ) -Label 'run-input schema required_fields'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'current_nonclaims') -Required @(
        'no_model_api_eval_execution',
        'no_transcripts',
        'no_annotations',
        'no_cost_latency_results',
        'no_human_llm_judge_agreement_results',
        'no_empirical_results',
        'no_paper_readiness'
    ) -Label 'run-input schema current_nonclaims'
}

if (Test-Path -LiteralPath $paths.RunInputDoc) {
    $doc = Get-Content -LiteralPath $paths.RunInputDoc -Raw
    foreach ($check in @(
        'does not execute model/API evals',
        'dist/empirical-run-inputs',
        'build-empirical-run-inputs.ps1 -SelfTest',
        'score-empirical-run-inputs.ps1 -SelfTest',
        '324',
        'Current Nonclaims'
    )) {
        if (-not $doc.Contains($check)) {
            $failures.Add("Empirical run-input doc is missing boundary '$check'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.RunInputBuilder) {
    $builder = Get-Content -LiteralPath $paths.RunInputBuilder -Raw
    foreach ($check in @(
        'Empirical run-input builder',
        'record_count',
        'task_suite_hash',
        'prompt_pack_hash',
        'manifest_hash',
        'no_model_api_eval_execution',
        '324'
    )) {
        if (-not $builder.Contains($check)) {
            $failures.Add("Empirical run-input builder is missing invariant '$check'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.RunInputScorer) {
    $scorer = Get-Content -LiteralPath $paths.RunInputScorer -Raw
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
        if (-not $scorer.Contains($check)) {
            $failures.Add("Empirical run-input scorer is missing invariant '$check'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.ExecutionPreflightSchema) {
    $schema = Get-Content -LiteralPath $paths.ExecutionPreflightSchema -Raw
    if ((Get-Scalar -Text $schema -Field 'claim_boundary') -ne 'execution_preflight_schema_only_no_model_api_calls') {
        $failures.Add('Execution preflight schema must declare execution_preflight_schema_only_no_model_api_calls.')
    }
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'required_fields') -Required @(
        'selected_run_input_ids',
        'selected_run_count',
        'selected_conditions',
        'selected_task_ids',
        'provider',
        'model_name_or_alias',
        'runtime_surface',
        'budget_recorded_before_execution',
        'max_budget_usd',
        'run_input_manifest_sha256',
        'stop_gates_satisfied',
        'current_nonclaims'
    ) -Label 'execution preflight schema required_fields'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'metadata_requirements') -Required @(
        'source_run_input_manifest_hash_recorded',
        'provider_model_runtime_recorded',
        'budget_recorded_before_execution',
        'selected_run_inputs_exist',
        'no_model_api_call_performed'
    ) -Label 'execution preflight schema metadata_requirements'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'forbidden_fields') -Required @(
        'transcript_messages',
        'model_output',
        'annotation_record',
        'cost_latency_result',
        'empirical_effectiveness_proven',
        'paper_ready'
    ) -Label 'execution preflight schema forbidden_fields'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'current_nonclaims') -Required @(
        'no_model_api_eval_execution',
        'no_transcripts',
        'no_annotations',
        'no_cost_latency_results',
        'no_human_llm_judge_agreement_results',
        'no_aggregate_metrics',
        'no_statistical_results',
        'no_empirical_effectiveness_claim',
        'no_paper_readiness'
    ) -Label 'execution preflight schema current_nonclaims'
}

if (Test-Path -LiteralPath $paths.ExecutionPreflightDoc) {
    $doc = Get-Content -LiteralPath $paths.ExecutionPreflightDoc -Raw
    foreach ($check in @(
        'does not call models or APIs',
        'dist/empirical-run-inputs',
        'dist/empirical-execution-preflight.json',
        'build-empirical-execution-preflight.ps1 -SelfTest',
        'score-empirical-execution-preflight.ps1 -SelfTest',
        '9 records from the 324-record run-input package',
        'Current Nonclaims'
    )) {
        if (-not $doc.Contains($check)) {
            $failures.Add("Empirical execution preflight doc is missing boundary '$check'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.ExecutionPreflightBuilder) {
    $builder = Get-Content -LiteralPath $paths.ExecutionPreflightBuilder -Raw
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
        if (-not $builder.Contains($check)) {
            $failures.Add("Empirical execution preflight builder is missing invariant '$check'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.ExecutionPreflightScorer) {
    $scorer = Get-Content -LiteralPath $paths.ExecutionPreflightScorer -Raw
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
        if (-not $scorer.Contains($check)) {
            $failures.Add("Empirical execution preflight scorer is missing invariant '$check'.")
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
        'condition_prompt_pack_available',
        'run_input_builder_available',
        'execution_preflight_available',
        'score-empirical-prompt-pack.ps1',
        'score-empirical-run-inputs.ps1',
        'score-empirical-execution-preflight.ps1',
        'score-empirical-run-packet.ps1',
        'dry_run_package_builder_available',
        'build-empirical-dry-run-package.ps1 -SelfTest',
        'synthetic dry-run package builder self-test'
    )) {
        if (-not $doc.Contains($check)) {
            $failures.Add("Experiment run packet doc is missing boundary '$check'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.EmpiricalPlan) {
    $plan = Get-Content -LiteralPath $paths.EmpiricalPlan -Raw
    foreach ($check in @(
        'score-empirical-task-suite.ps1',
        'score-empirical-prompt-pack.ps1',
        'build-empirical-run-inputs.ps1 -SelfTest',
        'score-empirical-run-inputs.ps1 -SelfTest',
        'build-empirical-execution-preflight.ps1 -SelfTest',
        'score-empirical-execution-preflight.ps1 -SelfTest',
        'score-empirical-run-packet.ps1',
        'score-empirical-evidence-package.ps1 -SelfTest',
        'score-empirical-results.ps1 -SelfTest',
        'score-empirical-agreement.ps1 -SelfTest',
        'build-empirical-dry-run-package.ps1 -SelfTest',
        'dry-run package builder',
        'They do not execute model/API evals'
    )) {
        if (-not $plan.Contains($check)) {
            $failures.Add("Empirical evaluation plan is missing verification sync text '$check'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.DryRunDoc) {
    $doc = Get-Content -LiteralPath $paths.DryRunDoc -Raw
    foreach ($check in @(
        'build-empirical-dry-run-package.ps1 -SelfTest',
        'RunValidators',
        'does not execute model/API evals',
        'Current Nonclaims',
        'no real transcripts',
        'no empirical effectiveness claim'
    )) {
        if (-not $doc.Contains($check)) {
            $failures.Add("Empirical dry-run package doc is missing boundary '$check'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.DryRunBuilder) {
    $builder = Get-Content -LiteralPath $paths.DryRunBuilder -Raw
    foreach ($check in @(
        'Empirical dry-run package builder',
        'score-empirical-evidence-package.ps1',
        'score-empirical-results.ps1',
        'score-empirical-agreement.ps1',
        'RequireHumanLlmPairs',
        'MinimumAgreementRate',
        'OutputRoot already exists and is not empty',
        'contains non-generated file',
        'no_model_api_eval_execution'
    )) {
        if (-not $builder.Contains($check)) {
            $failures.Add("Empirical dry-run package builder is missing invariant '$check'.")
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
