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
    MockExecutionPackageSchema = Join-Path $RepoRoot 'evals/empirical/mock-execution-package-schema.yaml'
    RunnerResponseSchema = Join-Path $RepoRoot 'evals/empirical/runner-response-schema.yaml'
    PilotExecutionPackageSchema = Join-Path $RepoRoot 'evals/empirical/pilot-execution-package-schema.yaml'
    PilotExecutionReadinessSchema = Join-Path $RepoRoot 'evals/empirical/pilot-execution-readiness-schema.yaml'
    PilotRunnerRequestSchema = Join-Path $RepoRoot 'evals/empirical/pilot-runner-request-schema.yaml'
    AnnotationWorklistSchema = Join-Path $RepoRoot 'evals/empirical/annotation-worklist-schema.yaml'
    LabelTemplatePackageSchema = Join-Path $RepoRoot 'evals/empirical/label-template-package-schema.yaml'
    AnnotationIntakeSchema = Join-Path $RepoRoot 'evals/empirical/annotation-intake-schema.yaml'
    AnnotationGuidelines = Join-Path $RepoRoot 'docs/empirical-annotation-guidelines.md'
    ConditionPromptDoc = Join-Path $RepoRoot 'docs/condition-prompt-pack.md'
    RunInputDoc = Join-Path $RepoRoot 'docs/empirical-run-inputs.md'
    ExecutionPreflightDoc = Join-Path $RepoRoot 'docs/empirical-execution-preflight.md'
    MockExecutionPackageDoc = Join-Path $RepoRoot 'docs/empirical-mock-execution-package.md'
    RunnerContractDoc = Join-Path $RepoRoot 'docs/empirical-runner-contract.md'
    PilotExecutionRunnerDoc = Join-Path $RepoRoot 'docs/empirical-pilot-execution-runner.md'
    PilotRunChainDoc = Join-Path $RepoRoot 'docs/empirical-pilot-run-chain.md'
    PilotExecutionReadinessDoc = Join-Path $RepoRoot 'docs/empirical-pilot-execution-readiness.md'
    PilotRunnerRequestDoc = Join-Path $RepoRoot 'docs/empirical-pilot-runner-requests.md'
    AnnotationWorklistDoc = Join-Path $RepoRoot 'docs/empirical-annotation-worklist.md'
    LabelTemplatePackageDoc = Join-Path $RepoRoot 'docs/empirical-label-template-package.md'
    AnnotationIntakeDoc = Join-Path $RepoRoot 'docs/empirical-annotation-intake.md'
    EvidencePackageBuilderDoc = Join-Path $RepoRoot 'docs/empirical-evidence-package-builder.md'
    EmpiricalPlan = Join-Path $RepoRoot 'docs/empirical-evaluation-plan.md'
    RunPacketDoc = Join-Path $RepoRoot 'docs/experiment-run-packet.md'
    DryRunDoc = Join-Path $RepoRoot 'docs/empirical-dry-run-package.md'
    PromptPackScorer = Join-Path $RepoRoot 'scripts/score-empirical-prompt-pack.ps1'
    RunInputBuilder = Join-Path $RepoRoot 'scripts/build-empirical-run-inputs.ps1'
    RunInputScorer = Join-Path $RepoRoot 'scripts/score-empirical-run-inputs.ps1'
    ExecutionPreflightBuilder = Join-Path $RepoRoot 'scripts/build-empirical-execution-preflight.ps1'
    ExecutionPreflightScorer = Join-Path $RepoRoot 'scripts/score-empirical-execution-preflight.ps1'
    MockExecutionPackageBuilder = Join-Path $RepoRoot 'scripts/build-empirical-mock-execution-package.ps1'
    MockExecutionPackageScorer = Join-Path $RepoRoot 'scripts/score-empirical-mock-execution-package.ps1'
    RunnerResponseScorer = Join-Path $RepoRoot 'scripts/score-empirical-runner-response.ps1'
    PilotExecutionPackageBuilder = Join-Path $RepoRoot 'scripts/build-empirical-pilot-execution-package.ps1'
    PilotExecutionPackageScorer = Join-Path $RepoRoot 'scripts/score-empirical-pilot-execution-package.ps1'
    PilotRunChainBuilder = Join-Path $RepoRoot 'scripts/build-empirical-pilot-run-chain.ps1'
    PilotExecutionReadinessChecker = Join-Path $RepoRoot 'scripts/check-empirical-pilot-execution-readiness.ps1'
    PilotRunnerRequestBuilder = Join-Path $RepoRoot 'scripts/build-empirical-pilot-runner-requests.ps1'
    PilotRunnerRequestScorer = Join-Path $RepoRoot 'scripts/score-empirical-pilot-runner-requests.ps1'
    AnnotationWorklistBuilder = Join-Path $RepoRoot 'scripts/build-empirical-annotation-worklist.ps1'
    AnnotationWorklistScorer = Join-Path $RepoRoot 'scripts/score-empirical-annotation-worklist.ps1'
    LabelTemplatePackageBuilder = Join-Path $RepoRoot 'scripts/build-empirical-label-template-package.ps1'
    LabelTemplatePackageScorer = Join-Path $RepoRoot 'scripts/score-empirical-label-template-package.ps1'
    AnnotationIntakeScorer = Join-Path $RepoRoot 'scripts/score-empirical-annotation-intake.ps1'
    EvidencePackageBuilder = Join-Path $RepoRoot 'scripts/build-empirical-evidence-package.ps1'
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
        'mock_execution_package',
        'runner_response_contract',
        'pilot_execution_package',
        'pilot_run_chain',
        'pilot_execution_readiness_record',
        'pilot_runner_request_package',
        'annotation_worklist',
        'label_template_package',
        'annotation_intake_package',
        'evidence_package',
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
        'mock_execution_package_builder_available',
        'runner_response_contract_available',
        'pilot_execution_runner_available',
        'pilot_run_chain_builder_available',
        'pilot_execution_readiness_checker_available',
        'required_environment_variables_checked_before_execution',
        'pilot_runner_request_package_builder_available',
        'pilot_runner_request_package_scorer_available',
        'annotation_worklist_builder_available',
        'label_template_package_builder_available',
        'annotation_intake_validator_available',
        'evidence_package_builder_available',
        'evidence_package_validator_available',
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
        'no_completed_annotations',
        'no_validated_real_runner_responses',
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
        'execution_preflight_schema: evals/empirical/execution-preflight-schema.yaml',
        'mock_execution_package_schema: evals/empirical/mock-execution-package-schema.yaml',
        'runner_response_schema: evals/empirical/runner-response-schema.yaml',
        'runner_response_contract: docs/empirical-runner-contract.md',
        'pilot_execution_package_schema: evals/empirical/pilot-execution-package-schema.yaml',
        'pilot_run_chain_builder: docs/empirical-pilot-run-chain.md',
        'pilot_execution_readiness_schema: evals/empirical/pilot-execution-readiness-schema.yaml',
        'pilot_execution_readiness_checker: docs/empirical-pilot-execution-readiness.md',
        'pilot_runner_request_schema: evals/empirical/pilot-runner-request-schema.yaml',
        'pilot_runner_request_builder: docs/empirical-pilot-runner-requests.md',
        'pilot_runner_request_scorer: scripts/score-empirical-pilot-runner-requests.ps1',
        'annotation_worklist_schema: evals/empirical/annotation-worklist-schema.yaml',
        'label_template_package_schema: evals/empirical/label-template-package-schema.yaml',
        'annotation_intake_schema: evals/empirical/annotation-intake-schema.yaml',
        'evidence_package_builder: docs/empirical-evidence-package-builder.md'
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

if (Test-Path -LiteralPath $paths.MockExecutionPackageSchema) {
    $schema = Get-Content -LiteralPath $paths.MockExecutionPackageSchema -Raw
    if ((Get-Scalar -Text $schema -Field 'claim_boundary') -ne 'mock_execution_package_schema_only_no_real_model_results') {
        $failures.Add('Mock execution package schema must declare mock_execution_package_schema_only_no_real_model_results.')
    }
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'required_directories') -Required @(
        'transcripts',
        'cost-latency',
        'metadata'
    ) -Label 'mock execution package required_directories'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'required_metadata_files') -Required @(
        'mock-execution-manifest.json',
        'source-preflight-hash.json',
        'source-run-input-manifest-hash.json'
    ) -Label 'mock execution package required_metadata_files'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'required_transcript_fields') -Required @(
        'run_id',
        'run_input_id',
        'task_id',
        'condition',
        'model_provider',
        'model_name_or_alias',
        'runtime_surface',
        'input_prompt',
        'transcript_messages',
        'tool_calls',
        'final_answer',
        'final_claim',
        'checked_evidence',
        'selected_claim_ceiling',
        'cost_latency_record_id',
        'redaction_status'
    ) -Label 'mock execution package required_transcript_fields'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'required_cost_latency_fields') -Required @(
        'cost_latency_record_id',
        'run_id',
        'input_tokens',
        'output_tokens',
        'tool_call_count',
        'wall_time_ms',
        'api_cost_usd',
        'retry_count'
    ) -Label 'mock execution package required_cost_latency_fields'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'join_requirements') -Required @(
        'every_selected_run_input_has_mock_transcript',
        'every_mock_transcript_has_cost_latency_record',
        'every_cost_latency_record_matches_transcript_run_id',
        'every_mock_transcript_input_prompt_matches_run_input',
        'source_preflight_hash_recorded',
        'source_run_input_manifest_hash_recorded'
    ) -Label 'mock execution package join_requirements'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'forbidden_fields') -Required @(
        'annotation_record',
        'human_label',
        'llm_judge_label',
        'pass_rate',
        'win_rate',
        'p_value',
        'confidence_interval',
        'statistical_significance',
        'model_api_eval_results',
        'model_api_results',
        'model_quality',
        'aggregate_metrics',
        'real_aggregate_metrics',
        'runner_quality',
        'runner_quality_claim',
        'effectiveness_claim',
        'empirical_effectiveness_proven',
        'paper_ready',
        'paper_readiness',
        'production_ready'
    ) -Label 'mock execution package forbidden_fields'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'current_nonclaims') -Required @(
        'no_real_model_api_eval_execution',
        'no_real_transcripts',
        'no_real_annotations',
        'no_real_cost_latency_results',
        'no_human_llm_judge_agreement_results',
        'no_aggregate_metrics',
        'no_statistical_results',
        'no_empirical_effectiveness_claim',
        'no_paper_readiness'
    ) -Label 'mock execution package current_nonclaims'
}

if (Test-Path -LiteralPath $paths.MockExecutionPackageDoc) {
    $doc = Get-Content -LiteralPath $paths.MockExecutionPackageDoc -Raw
    foreach ($check in @(
        'does not call models or APIs',
        'dist/empirical-mock-execution-package',
        'build-empirical-mock-execution-package.ps1 -SelfTest',
        'score-empirical-mock-execution-package.ps1 -SelfTest',
        '9 mock transcript records',
        'credential-like content',
        'non-JSON sensitive',
        'Current Nonclaims'
    )) {
        if (-not $doc.Contains($check)) {
            $failures.Add("Empirical mock execution package doc is missing boundary '$check'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.MockExecutionPackageBuilder) {
    $builder = Get-Content -LiteralPath $paths.MockExecutionPackageBuilder -Raw
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
        if (-not $builder.Contains($check)) {
            $failures.Add("Empirical mock execution package builder is missing invariant '$check'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.MockExecutionPackageScorer) {
    $scorer = Get-Content -LiteralPath $paths.MockExecutionPackageScorer -Raw
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
        if (-not $scorer.Contains($check)) {
            $failures.Add("Empirical mock execution package scorer is missing invariant '$check'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.RunnerResponseSchema) {
    $schema = Get-Content -LiteralPath $paths.RunnerResponseSchema -Raw
    if ((Get-Scalar -Text $schema -Field 'claim_boundary') -ne 'runner_response_contract_schema_only_no_execution_results') {
        $failures.Add('Runner response schema must declare runner_response_contract_schema_only_no_execution_results.')
    }
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'required_response_fields') -Required @(
        'final_answer'
    ) -Label 'runner response required_response_fields'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'optional_response_fields') -Required @(
        'run_input_id',
        'transcript_messages',
        'final_claim',
        'checked_evidence',
        'selected_claim_ceiling',
        'stop_or_continue_decision',
        'human_checkpoint_decision',
        'input_tokens',
        'output_tokens',
        'wall_time_ms',
        'api_cost_usd',
        'retry_count'
    ) -Label 'runner response optional_response_fields'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'required_for_pilot_package_fields') -Required @(
        'final_answer',
        'input_tokens',
        'output_tokens',
        'api_cost_usd',
        'retry_count'
    ) -Label 'runner response required_for_pilot_package_fields'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'join_checks') -Required @(
        'optional_run_input_id_matches_request',
        'response_json_parseable_before_package_wrapping',
        'final_answer_nonempty_before_transcript_generation'
    ) -Label 'runner response join_checks'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'privacy_requirements') -Required @(
        'no_credentials_in_response',
        'no_absolute_private_paths_in_response',
        'no_private_key_material_in_response'
    ) -Label 'runner response privacy_requirements'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'forbidden_fields') -Required @(
        'pass_rate',
        'aggregate_metrics',
        'runner_quality_claim',
        'empirical_effectiveness_proven',
        'paper_ready',
        'paper_readiness',
        'production_ready'
    ) -Label 'runner response forbidden_fields'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'current_nonclaims') -Required @(
        'no_model_api_eval_execution',
        'no_validated_real_runner_responses',
        'no_pilot_transcripts',
        'no_aggregate_metrics',
        'no_empirical_effectiveness_claim',
        'no_paper_readiness'
    ) -Label 'runner response current_nonclaims'
}

if (Test-Path -LiteralPath $paths.RunnerContractDoc) {
    $doc = Get-Content -LiteralPath $paths.RunnerContractDoc -Raw
    foreach ($check in @(
        'score-empirical-runner-response.ps1 -SelfTest',
        'Response Contract',
        'does not call hosted model APIs',
        'does not prove runner quality',
        'credential-like content',
        'forbidden result/readiness fields',
        'request/run-input mismatches',
        'Current Nonclaims'
    )) {
        if (-not $doc.Contains($check)) {
            $failures.Add("Empirical runner contract doc is missing boundary '$check'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.RunnerResponseScorer) {
    $scorer = Get-Content -LiteralPath $paths.RunnerResponseScorer -Raw
    foreach ($check in @(
        'Empirical runner response scoring',
        'runner_response_contract_schema_only_no_execution_results',
        'Validated runner response contract self-test',
        'Rejected missing final_answer, credential-like content, forbidden result/readiness fields, unsupported result/readiness claim text, null, blank, boolean, or negative numeric fields, and request/run_input mismatches',
        'No hosted model/API calls are made by this scorer',
        'does not match request run_input_id',
        'blocked sensitive pattern',
        'unsupported result/readiness claim text'
    )) {
        if (-not $scorer.Contains($check)) {
            $failures.Add("Empirical runner response scorer is missing invariant '$check'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.PilotExecutionPackageSchema) {
    $schema = Get-Content -LiteralPath $paths.PilotExecutionPackageSchema -Raw
    if ((Get-Scalar -Text $schema -Field 'claim_boundary') -ne 'pilot_execution_package_schema_only_no_empirical_results') {
        $failures.Add('Pilot execution package schema must declare pilot_execution_package_schema_only_no_empirical_results.')
    }
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'required_directories') -Required @(
        'transcripts',
        'cost-latency',
        'metadata'
    ) -Label 'pilot execution package required_directories'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'required_metadata_files') -Required @(
        'pilot-execution-manifest.json',
        'source-preflight-hash.json',
        'source-run-input-manifest-hash.json',
        'runner-script-hash.json'
    ) -Label 'pilot execution package required_metadata_files'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'required_transcript_fields') -Required @(
        'run_id',
        'run_input_id',
        'task_id',
        'condition',
        'model_provider',
        'model_name_or_alias',
        'runtime_surface',
        'input_prompt',
        'transcript_messages',
        'tool_calls',
        'final_answer',
        'final_claim',
        'checked_evidence',
        'selected_claim_ceiling',
        'cost_latency_record_id',
        'redaction_status'
    ) -Label 'pilot execution package required_transcript_fields'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'required_cost_latency_fields') -Required @(
        'cost_latency_record_id',
        'run_id',
        'input_tokens',
        'output_tokens',
        'tool_call_count',
        'wall_time_ms',
        'api_cost_usd',
        'retry_count'
    ) -Label 'pilot execution package required_cost_latency_fields'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'join_requirements') -Required @(
        'every_selected_run_input_has_pilot_transcript',
        'every_pilot_transcript_has_cost_latency_record',
        'every_cost_latency_record_matches_transcript_run_id',
        'every_pilot_transcript_input_prompt_matches_run_input',
        'every_pilot_transcript_provider_model_runtime_matches_preflight',
        'total_api_cost_usd_does_not_exceed_preflight_max_budget_usd',
        'source_preflight_hash_recorded',
        'source_run_input_manifest_hash_recorded',
        'runner_script_hash_recorded'
    ) -Label 'pilot execution package join_requirements'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'runner_requirements') -Required @(
        'local_runner_script_explicitly_allowed',
        'runner_script_hash_recorded',
        'runner_outputs_json_response',
        'runner_reports_input_tokens_before_package_wrapping',
        'runner_reports_output_tokens_before_package_wrapping',
        'runner_reports_api_cost_usd_before_package_wrapping',
        'runner_reports_retry_count_before_package_wrapping',
        'no_credentials_in_package',
        'no_private_paths_in_package'
    ) -Label 'pilot execution package runner_requirements'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'forbidden_fields') -Required @(
        'annotation_record',
        'human_label',
        'llm_judge_label',
        'pass_rate',
        'win_rate',
        'p_value',
        'confidence_interval',
        'statistical_significance',
        'model_api_eval_results',
        'model_api_results',
        'model_quality',
        'aggregate_metrics',
        'real_aggregate_metrics',
        'runner_quality',
        'runner_quality_claim',
        'effectiveness_claim',
        'empirical_effectiveness_proven',
        'paper_ready',
        'paper_readiness',
        'production_ready'
    ) -Label 'pilot execution package forbidden_fields'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'current_nonclaims') -Required @(
        'no_annotations',
        'no_human_llm_judge_agreement_results',
        'no_aggregate_metrics',
        'no_statistical_results',
        'no_empirical_effectiveness_claim',
        'no_paper_readiness',
        'no_runner_quality_claim'
    ) -Label 'pilot execution package current_nonclaims'
}

if (Test-Path -LiteralPath $paths.PilotExecutionRunnerDoc) {
    $doc = Get-Content -LiteralPath $paths.PilotExecutionRunnerDoc -Raw
    foreach ($check in @(
        'does not call hosted model APIs',
        'Runner Contract',
        'does not silently convert missing API cost into zero cost',
        'score-empirical-runner-response.ps1 -SelfTest',
        'dist/empirical-pilot-execution-package',
        'build-empirical-pilot-execution-package.ps1 -SelfTest',
        'score-empirical-pilot-execution-package.ps1 -SelfTest',
        'rejects credentials',
        'provider/model/runtime mismatches',
        'metadata hash tampering',
        'non-JSON sensitive',
        'Current Nonclaims'
    )) {
        if (-not $doc.Contains($check)) {
            $failures.Add("Empirical pilot execution runner doc is missing boundary '$check'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.PilotExecutionPackageBuilder) {
    $builder = Get-Content -LiteralPath $paths.PilotExecutionPackageBuilder -Raw
    foreach ($check in @(
        'Empirical pilot execution package builder',
        'pilot_execution_package_unlabeled_no_empirical_results',
        'pilot_execution_transcripts_present_unlabeled_no_results',
        'Pass -AllowRunnerScript',
        'score-empirical-runner-response.ps1',
        'Built a 9-run pilot execution package',
        'Required explicit runner token, API cost, and retry telemetry before package wrapping',
        'missing required telemetry field',
        'refused non-generated files when -Force was used',
        'runner-script-hash.json',
        'source-run-input-manifest-hash.json',
        'no_runner_quality_claim'
    )) {
        if (-not $builder.Contains($check)) {
            $failures.Add("Empirical pilot execution package builder is missing invariant '$check'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.PilotExecutionPackageScorer) {
    $scorer = Get-Content -LiteralPath $paths.PilotExecutionPackageScorer -Raw
    foreach ($check in @(
        'Empirical pilot execution package scoring',
        'pilot_execution_package_schema_only_no_empirical_results',
        'pilot_execution_package_unlabeled_no_empirical_results',
        'public_synthetic_task_no_private_material',
        'Rejected missing transcript, crossed cost-latency join, budget overrun, credential-like content, provider/model/runtime mismatches, metadata hash tampering, non-JSON sensitive files, and unsupported result/readiness claim cases',
        'aggregate_budget_exceeded',
        'micro_budget_exceeded',
        'unexpected non-JSON file',
        'runner-script-hash.json',
        'source-run-input-manifest-hash.json',
        'transcript_messages',
        'cost_latency_record_id'
    )) {
        if (-not $scorer.Contains($check)) {
            $failures.Add("Empirical pilot execution package scorer is missing invariant '$check'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.PilotExecutionReadinessSchema) {
    $schema = Get-Content -LiteralPath $paths.PilotExecutionReadinessSchema -Raw
    if ((Get-Scalar -Text $schema -Field 'claim_boundary') -ne 'pilot_execution_readiness_schema_only_no_model_api_calls') {
        $failures.Add('Pilot execution readiness schema must declare pilot_execution_readiness_schema_only_no_model_api_calls.')
    }
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'required_inputs') -Required @(
        'run_input_root',
        'execution_preflight_path',
        'runner_script_path',
        'runner_label',
        'required_environment_variable_names'
    ) -Label 'pilot execution readiness required_inputs'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'readiness_requirements') -Required @(
        'run_input_package_scores_before_execution',
        'execution_preflight_scores_before_execution',
        'runner_script_exists_before_execution',
        'runner_script_stays_outside_public_repo',
        'runner_label_has_no_path_separator',
        'at_least_one_required_environment_variable_name_is_provided',
        'required_environment_variable_names_are_valid',
        'required_environment_variables_are_present_without_value_logging',
        'readiness_checker_does_not_execute_runner',
        'readiness_checker_does_not_call_model_api'
    ) -Label 'pilot execution readiness readiness_requirements'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'forbidden_outputs') -Required @(
        'environment_variable_values',
        'credential_values',
        'raw_runner_response',
        'transcript_record',
        'cost_latency_record',
        'aggregate_metrics',
        'paper_ready',
        'production_ready'
    ) -Label 'pilot execution readiness forbidden_outputs'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'current_nonclaims') -Required @(
        'no_runner_execution',
        'no_model_api_eval_execution',
        'no_secret_values_reported',
        'no_real_transcripts',
        'no_real_cost_latency_results',
        'no_empirical_effectiveness_claim',
        'no_paper_readiness'
    ) -Label 'pilot execution readiness current_nonclaims'
}

if (Test-Path -LiteralPath $paths.PilotExecutionReadinessDoc) {
    $doc = Get-Content -LiteralPath $paths.PilotExecutionReadinessDoc -Raw
    foreach ($check in @(
        'check-empirical-pilot-execution-readiness.ps1 -SelfTest',
        'does not execute the runner',
        'requires at least one required environment variable name',
        'print environment variable values',
        'does not execute model/API evals',
        'Current Nonclaims',
        'paper readiness'
    )) {
        if (-not $doc.Contains($check)) {
            $failures.Add("Empirical pilot execution readiness doc is missing boundary '$check'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.PilotExecutionReadinessChecker) {
    $checker = Get-Content -LiteralPath $paths.PilotExecutionReadinessChecker -Raw
    foreach ($check in @(
        'Empirical pilot execution readiness',
        'Validated empirical pilot execution readiness self-test',
        'Rejected missing required environment variable lists, missing required environment variables, invalid environment variable names, repo-local runner scripts, and bad runner labels',
        'Did not execute the fixture runner or call model/API routes',
        'RunnerScriptPath must stay outside the public repository',
        'At least one required environment variable name must be provided',
        'Environment variable values were not printed or written',
        'Invalid required environment variable name',
        'Required environment variable'
    )) {
        if (-not $checker.Contains($check)) {
            $failures.Add("Empirical pilot execution readiness checker is missing invariant '$check'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.PilotRunnerRequestSchema) {
    $schema = Get-Content -LiteralPath $paths.PilotRunnerRequestSchema -Raw
    if ((Get-Scalar -Text $schema -Field 'claim_boundary') -ne 'pilot_runner_request_package_schema_only_no_runner_execution') {
        $failures.Add('Pilot runner request schema must declare pilot_runner_request_package_schema_only_no_runner_execution.')
    }
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'required_inputs') -Required @(
        'run_input_root',
        'execution_preflight_path',
        'runner_label'
    ) -Label 'pilot runner request required_inputs'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'required_directories') -Required @(
        'requests',
        'metadata'
    ) -Label 'pilot runner request required_directories'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'required_metadata_files') -Required @(
        'pilot-runner-request-manifest.json',
        'source-preflight-hash.json',
        'source-run-input-manifest-hash.json'
    ) -Label 'pilot runner request required_metadata_files'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'required_request_fields') -Required @(
        'request_id',
        'run_id',
        'run_input_id',
        'task_id',
        'condition',
        'input_prompt',
        'preflight_id',
        'model_provider',
        'model_name_or_alias',
        'runtime_surface',
        'runner_label'
    ) -Label 'pilot runner request required_request_fields'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'request_requirements') -Required @(
        'one_request_per_selected_run_input_id',
        'selected_run_input_ids_exist_in_run_input_package',
        'requests_match_source_run_input_prompts',
        'requests_match_execution_preflight_runtime',
        'source_preflight_hash_recorded',
        'source_run_input_manifest_hash_recorded',
        'runner_label_has_no_path_separator',
        'request_package_does_not_execute_runner',
        'request_package_does_not_call_model_api'
    ) -Label 'pilot runner request request_requirements'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'scorer_requirements') -Required @(
        'scorer_validates_manifest_request_hashes',
        'scorer_validates_request_source_alignment',
        'scorer_validates_request_preflight_alignment',
        'scorer_rejects_forbidden_response_fields',
        'scorer_rejects_unexpected_request_fields',
        'scorer_rejects_malformed_metadata_json',
        'scorer_rejects_sensitive_non_json_files',
        'scorer_does_not_execute_runner',
        'scorer_does_not_call_model_api'
    ) -Label 'pilot runner request scorer_requirements'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'forbidden_outputs') -Required @(
        'raw_runner_response',
        'transcript_record',
        'cost_latency_record',
        'environment_variable_values',
        'credential_values',
        'aggregate_metrics',
        'paper_ready',
        'production_ready'
    ) -Label 'pilot runner request forbidden_outputs'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'current_nonclaims') -Required @(
        'no_runner_execution',
        'no_model_api_eval_execution',
        'no_runner_responses',
        'no_real_transcripts',
        'no_real_cost_latency_results',
        'no_annotations',
        'no_aggregate_metrics',
        'no_empirical_effectiveness_claim',
        'no_paper_readiness'
    ) -Label 'pilot runner request current_nonclaims'
}

if (Test-Path -LiteralPath $paths.PilotRunnerRequestDoc) {
    $doc = Get-Content -LiteralPath $paths.PilotRunnerRequestDoc -Raw
    foreach ($check in @(
        'build-empirical-pilot-runner-requests.ps1 -SelfTest',
        'score-empirical-pilot-runner-requests.ps1 -SelfTest',
        'does not execute the runner',
        'request package',
        'No runner script was executed by this scorer',
        'Current Nonclaims',
        'credential validity',
        'paper readiness'
    )) {
        if (-not $doc.Contains($check)) {
            $failures.Add("Empirical pilot runner request doc is missing boundary '$check'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.PilotRunnerRequestBuilder) {
    $builder = Get-Content -LiteralPath $paths.PilotRunnerRequestBuilder -Raw
    foreach ($check in @(
        'Empirical pilot runner request package builder',
        'pilot_runner_request_package_no_runner_execution',
        'Built a 9-request pilot runner request package',
        'Rejected missing selected run inputs, bad runner labels, and non-generated overwrite attempts',
        'No runner script was executed and no model/API calls were made by this request builder',
        'requests/pilot-request-',
        'source-run-input-manifest-hash.json',
        'source-preflight-hash.json'
    )) {
        if (-not $builder.Contains($check)) {
            $failures.Add("Empirical pilot runner request builder is missing invariant '$check'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.PilotRunnerRequestScorer) {
    $scorer = Get-Content -LiteralPath $paths.PilotRunnerRequestScorer -Raw
    foreach ($check in @(
        'Empirical pilot runner request package scorer',
        'Validated a 9-request pilot runner request package',
        'Rejected missing request files, request/source mismatches, metadata hash tampering, forbidden response fields, and sensitive non-JSON files',
        'Rejected rehashed unexpected request fields and malformed metadata JSON',
        'No runner script was executed and no model/API calls were made by this request scorer',
        'source-preflight-hash.json value',
        'does not match source run input field',
        'unexpected field',
        'Could not parse JSON file',
        'forbidden field',
        'blocked sensitive pattern'
    )) {
        if (-not $scorer.Contains($check)) {
            $failures.Add("Empirical pilot runner request scorer is missing invariant '$check'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.PilotRunChainDoc) {
    $doc = Get-Content -LiteralPath $paths.PilotRunChainDoc -Raw
    foreach ($check in @(
        'build-empirical-pilot-run-chain.ps1 -SelfTest',
        'AllowRunnerScript',
        'explicitly allowed local runner',
        'does not embed provider API code',
        'does not prove',
        'Current Nonclaims'
    )) {
        if (-not $doc.Contains($check)) {
            $failures.Add("Empirical pilot run chain doc is missing boundary '$check'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.PilotRunChainBuilder) {
    $builder = Get-Content -LiteralPath $paths.PilotRunChainBuilder -Raw
    foreach ($check in @(
        'Empirical pilot run chain builder',
        'pilot_run_chain_executed_no_labels_no_metrics',
        'pilot-run-chain-manifest.json',
        'score-empirical-pilot-execution-package.ps1',
        'score-empirical-annotation-worklist.ps1',
        'score-empirical-label-template-package.ps1',
        'Required -AllowRunnerScript and refused non-generated files when -Force was used',
        'Rejected root-level and nested non-generated files when -Force was used',
        'Generated no completed labels, agreement metrics, aggregate metrics, or paper-readiness claim'
    )) {
        if (-not $builder.Contains($check)) {
            $failures.Add("Empirical pilot run chain builder is missing invariant '$check'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.AnnotationWorklistSchema) {
    $schema = Get-Content -LiteralPath $paths.AnnotationWorklistSchema -Raw
    if ((Get-Scalar -Text $schema -Field 'claim_boundary') -ne 'annotation_worklist_schema_only_no_labels') {
        $failures.Add('Annotation worklist schema must declare annotation_worklist_schema_only_no_labels.')
    }
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'required_directories') -Required @(
        'annotation-work-items',
        'metadata'
    ) -Label 'annotation worklist required_directories'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'required_metadata_files') -Required @(
        'annotation-worklist-manifest.json',
        'source-pilot-execution-manifest-hash.json',
        'annotation-guidelines-hash.json'
    ) -Label 'annotation worklist required_metadata_files'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'required_work_item_fields') -Required @(
        'annotation_work_item_id',
        'run_id',
        'run_input_id',
        'task_id',
        'condition',
        'repeat_index',
        'task_suite_version',
        'prompt_version',
        'model_provider',
        'model_name_or_alias',
        'runtime_surface',
        'input_prompt',
        'final_answer',
        'final_claim',
        'checked_evidence',
        'selected_claim_ceiling',
        'stop_or_continue_decision',
        'human_checkpoint_decision',
        'transcript_message_count',
        'transcript_spans_source',
        'annotation_guideline_version',
        'required_label_fields',
        'redaction_status'
    ) -Label 'annotation worklist required_work_item_fields'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'join_requirements') -Required @(
        'every_pilot_transcript_has_annotation_work_item',
        'every_annotation_work_item_matches_pilot_transcript',
        'every_annotation_work_item_records_guideline_version',
        'source_pilot_execution_manifest_hash_recorded',
        'annotation_guidelines_hash_recorded',
        'work_item_contains_no_labels'
    ) -Label 'annotation worklist join_requirements'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'forbidden_fields') -Required @(
        'annotation_record',
        'false_readiness_label',
        'overclaim_label',
        'objective_narrowing_label',
        'human_checkpoint_recall_label',
        'human_label',
        'llm_judge_label',
        'pass_rate',
        'win_rate',
        'p_value',
        'confidence_interval',
        'statistical_significance',
        'aggregate_metrics',
        'effectiveness_claim',
        'empirical_effectiveness_proven',
        'paper_ready',
        'paper_readiness',
        'production_ready'
    ) -Label 'annotation worklist forbidden_fields'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'current_nonclaims') -Required @(
        'no_annotations',
        'no_human_labels',
        'no_llm_judge_labels',
        'no_agreement_results',
        'no_aggregate_metrics',
        'no_statistical_results',
        'no_empirical_effectiveness_claim',
        'no_paper_readiness'
    ) -Label 'annotation worklist current_nonclaims'
}

if (Test-Path -LiteralPath $paths.AnnotationWorklistDoc) {
    $doc = Get-Content -LiteralPath $paths.AnnotationWorklistDoc -Raw
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
        if (-not $doc.Contains($check)) {
            $failures.Add("Empirical annotation worklist doc is missing boundary '$check'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.AnnotationWorklistBuilder) {
    $builder = Get-Content -LiteralPath $paths.AnnotationWorklistBuilder -Raw
    foreach ($check in @(
        'Empirical annotation worklist builder',
        'annotation_worklist_unlabeled_no_annotations',
        'Built a 9-item annotation worklist',
        'Refused non-generated files when -Force was used',
        'annotation-guidelines-hash.json',
        'source-pilot-execution-manifest-hash.json'
    )) {
        if (-not $builder.Contains($check)) {
            $failures.Add("Empirical annotation worklist builder is missing invariant '$check'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.AnnotationWorklistScorer) {
    $scorer = Get-Content -LiteralPath $paths.AnnotationWorklistScorer -Raw
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
        if (-not $scorer.Contains($check)) {
            $failures.Add("Empirical annotation worklist scorer is missing invariant '$check'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.LabelTemplatePackageSchema) {
    $schema = Get-Content -LiteralPath $paths.LabelTemplatePackageSchema -Raw
    if ((Get-Scalar -Text $schema -Field 'claim_boundary') -ne 'label_template_package_schema_only_no_real_labels') {
        $failures.Add('Label-template package schema must declare label_template_package_schema_only_no_real_labels.')
    }
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'required_directories') -Required @(
        'annotation-templates',
        'metadata'
    ) -Label 'label-template package required_directories'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'required_metadata_files') -Required @(
        'label-template-package-manifest.json',
        'source-annotation-worklist-manifest-hash.json',
        'annotation-schema-hash.json',
        'annotation-guidelines-hash.json'
    ) -Label 'label-template package required_metadata_files'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'required_template_fields') -Required @(
        'annotation_template_id',
        'annotation_work_item_id',
        'run_id',
        'run_input_id',
        'task_id',
        'condition',
        'repeat_index',
        'task_suite_version',
        'prompt_version',
        'annotation_guideline_version',
        'required_label_fields',
        'label_placeholders',
        'rationale_span_placeholders',
        'confidence_placeholder',
        'transcript_spans_source',
        'redaction_status'
    ) -Label 'label-template package required_template_fields'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'join_requirements') -Required @(
        'every_annotation_work_item_has_label_template',
        'every_label_template_matches_annotation_work_item',
        'source_annotation_worklist_manifest_hash_recorded',
        'annotation_schema_hash_recorded',
        'annotation_guidelines_hash_recorded',
        'label_values_remain_unlabeled_placeholders'
    ) -Label 'label-template package join_requirements'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'forbidden_fields') -Required @(
        'annotation_record',
        'annotation_id',
        'annotator_type',
        'annotator_id',
        'human_label',
        'llm_judge_label',
        'pass_rate',
        'win_rate',
        'p_value',
        'confidence_interval',
        'statistical_significance',
        'aggregate_metrics',
        'effectiveness_claim',
        'empirical_effectiveness_proven',
        'paper_ready',
        'paper_readiness',
        'production_ready'
    ) -Label 'label-template package forbidden_fields'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'current_nonclaims') -Required @(
        'no_completed_annotations',
        'no_human_labels',
        'no_llm_judge_labels',
        'no_rule_based_labels',
        'no_agreement_results',
        'no_aggregate_metrics',
        'no_statistical_results',
        'no_empirical_effectiveness_claim',
        'no_paper_readiness'
    ) -Label 'label-template package current_nonclaims'
}

if (Test-Path -LiteralPath $paths.LabelTemplatePackageDoc) {
    $doc = Get-Content -LiteralPath $paths.LabelTemplatePackageDoc -Raw
    foreach ($check in @(
        'does not create human labels',
        'Run after producing an annotation worklist',
        'build-empirical-label-template-package.ps1 -SelfTest',
        'score-empirical-label-template-package.ps1 -SelfTest',
        'reject non-placeholder label',
        'metadata hash tampering',
        'non-JSON sensitive',
        'Current Nonclaims'
    )) {
        if (-not $doc.Contains($check)) {
            $failures.Add("Empirical label-template package doc is missing boundary '$check'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.LabelTemplatePackageBuilder) {
    $builder = Get-Content -LiteralPath $paths.LabelTemplatePackageBuilder -Raw
    foreach ($check in @(
        'Empirical label-template package builder',
        'label_template_package_unlabeled_no_completed_annotations',
        'Built a 9-template label-template package',
        'Refused non-generated files when -Force was used',
        'annotation-schema-hash.json',
        'source-annotation-worklist-manifest-hash.json'
    )) {
        if (-not $builder.Contains($check)) {
            $failures.Add("Empirical label-template package builder is missing invariant '$check'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.LabelTemplatePackageScorer) {
    $scorer = Get-Content -LiteralPath $paths.LabelTemplatePackageScorer -Raw
    foreach ($check in @(
        'Empirical label-template package scoring',
        'label_template_package_schema_only_no_real_labels',
        'label_template_package_unlabeled_no_completed_annotations',
        'Rejected missing templates, non-placeholder label values, mismatched work-item fields, duplicate templates, metadata hash tampering, and non-JSON sensitive files',
        'non_placeholder_label_value',
        'must remain __unlabeled__',
        'annotation-schema-hash.json',
        'source-annotation-worklist-manifest-hash.json'
    )) {
        if (-not $scorer.Contains($check)) {
            $failures.Add("Empirical label-template package scorer is missing invariant '$check'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.AnnotationIntakeSchema) {
    $schema = Get-Content -LiteralPath $paths.AnnotationIntakeSchema -Raw
    if ((Get-Scalar -Text $schema -Field 'claim_boundary') -ne 'annotation_intake_schema_only_no_aggregate_results') {
        $failures.Add('Annotation intake schema must declare annotation_intake_schema_only_no_aggregate_results.')
    }
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'required_directories') -Required @(
        'annotations',
        'metadata'
    ) -Label 'annotation intake required_directories'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'required_metadata_files') -Required @(
        'annotation-intake-manifest.json',
        'source-label-template-package-manifest-hash.json',
        'source-annotation-worklist-manifest-hash.json',
        'annotation-schema-hash.json',
        'annotation-guidelines-hash.json'
    ) -Label 'annotation intake required_metadata_files'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'join_requirements') -Required @(
        'every_label_template_has_completed_annotation',
        'every_annotation_maps_to_label_template',
        'every_annotation_matches_annotation_work_item',
        'annotation_template_id_matches_when_present',
        'annotation_guideline_version_matches_schema',
        'required_label_values_are_allowed',
        'rationale_spans_reference_transcript_message_indexes',
        'source_label_template_package_manifest_hash_recorded',
        'source_annotation_worklist_manifest_hash_recorded',
        'annotation_schema_hash_recorded',
        'annotation_guidelines_hash_recorded'
    ) -Label 'annotation intake join_requirements'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'forbidden_fields') -Required @(
        'pass_rate',
        'win_rate',
        'p_value',
        'confidence_interval',
        'statistical_significance',
        'aggregate_metrics',
        'agreement_summary',
        'effectiveness_claim',
        'empirical_effectiveness_proven',
        'paper_ready',
        'paper_readiness',
        'production_ready'
    ) -Label 'annotation intake forbidden_fields'
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $schema -Field 'current_nonclaims') -Required @(
        'no_real_human_labels_in_repository',
        'no_real_llm_judge_labels_in_repository',
        'no_rule_based_labels_in_repository',
        'no_agreement_results',
        'no_aggregate_metrics',
        'no_statistical_results',
        'no_annotator_quality_claim',
        'no_judge_validity_claim',
        'no_empirical_effectiveness_claim',
        'no_paper_readiness'
    ) -Label 'annotation intake current_nonclaims'
}

if (Test-Path -LiteralPath $paths.AnnotationIntakeDoc) {
    $doc = Get-Content -LiteralPath $paths.AnnotationIntakeDoc -Raw
    foreach ($check in @(
        'does not create labels',
        'score-empirical-annotation-intake.ps1 -SelfTest',
        'RequireHuman',
        'metadata hashes',
        'forbidden aggregate/result fields',
        'Current Nonclaims'
    )) {
        if (-not $doc.Contains($check)) {
            $failures.Add("Empirical annotation-intake doc is missing boundary '$check'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.AnnotationIntakeScorer) {
    $scorer = Get-Content -LiteralPath $paths.AnnotationIntakeScorer -Raw
    foreach ($check in @(
        'Empirical annotation intake scoring',
        'annotation_intake_schema_only_no_aggregate_results',
        'annotation_intake_validated_no_aggregate_results',
        'Rejected unsupported template labels, duplicate work-item run ids, work-item mismatches, missing annotation, invalid labels, NaN confidence, out-of-range spans, duplicate annotator records, mismatched task ids, metadata hash tampering, forbidden aggregate fields, and non-JSON sensitive files',
        'source-label-template-package-manifest-hash.json',
        'source-annotation-worklist-manifest-hash.json',
        'RequireHuman'
    )) {
        if (-not $scorer.Contains($check)) {
            $failures.Add("Empirical annotation-intake scorer is missing invariant '$check'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.EvidencePackageBuilderDoc) {
    $doc = Get-Content -LiteralPath $paths.EvidencePackageBuilderDoc -Raw
    foreach ($check in @(
        'build-empirical-evidence-package.ps1 -SelfTest',
        'PilotPackageRoot',
        'AnnotationIntakeRoot',
        'RunValidators',
        'SkipValidators',
        'runs the evidence-package validator by default',
        'does not execute model/API evals',
        'does not prove'
    )) {
        if (-not $doc.Contains($check)) {
            $failures.Add("Empirical evidence-package builder doc is missing boundary '$check'.")
        }
    }
}

if (Test-Path -LiteralPath $paths.EvidencePackageBuilder) {
    $builder = Get-Content -LiteralPath $paths.EvidencePackageBuilder -Raw
    foreach ($check in @(
        'Empirical evidence-package build',
        'evidence_package_assembled_no_results',
        'source-pilot-execution-package-hash.json',
        'source-annotation-intake-package-hash.json',
        'score-empirical-evidence-package.ps1',
        'SkipValidators',
        'validator was skipped by explicit -SkipValidators',
        'Rejected a missing annotation join',
        'Rejected non-JSON sensitive source material and non-generated overwrite attempts'
    )) {
        if (-not $builder.Contains($check)) {
            $failures.Add("Empirical evidence-package builder is missing invariant '$check'.")
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
        'run_input_id',
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
        'run_to_run_variance',
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
    Assert-ListContains -Failures $failures -Items (Get-YamlList -Text $resultsSummary -Field 'run_to_run_variance_fields') -Required @(
        'grouping',
        'group_count',
        'groups_with_two_or_more_repeats',
        'groups',
        'metric_variance_summary'
    ) -Label 'results summary run_to_run_variance_fields'
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
        'mock_execution_package_builder_available',
        'mock-execution-package-schema.yaml',
        'build-empirical-mock-execution-package.ps1 -SelfTest',
        'score-empirical-mock-execution-package.ps1 -SelfTest',
        'pilot-execution-package-schema.yaml',
        'build-empirical-pilot-execution-package.ps1 -SelfTest',
        'score-empirical-pilot-execution-package.ps1 -SelfTest',
        'pilot_run_chain_builder_available',
        'build-empirical-pilot-run-chain.ps1 -SelfTest',
        'pilot_execution_readiness_checker_available',
        'pilot-execution-readiness-schema.yaml',
        'check-empirical-pilot-execution-readiness.ps1 -SelfTest',
        'pilot execution readiness',
        'pilot_runner_request_package_builder_available',
        'pilot_runner_request_package_scorer_available',
        'pilot-runner-request-schema.yaml',
        'build-empirical-pilot-runner-requests.ps1 -SelfTest',
        'score-empirical-pilot-runner-requests.ps1 -SelfTest',
        'pilot runner request',
        'pilot runner request package with selected request JSON files',
        'annotation_worklist_builder_available',
        'label_template_package_builder_available',
        'annotation_intake_validator_available',
        'annotation-worklist-schema.yaml',
        'build-empirical-annotation-worklist.ps1 -SelfTest',
        'score-empirical-annotation-worklist.ps1 -SelfTest',
        'label-template-package-schema.yaml',
        'build-empirical-label-template-package.ps1 -SelfTest',
        'score-empirical-label-template-package.ps1 -SelfTest',
        'annotation-intake-schema.yaml',
        'score-empirical-annotation-intake.ps1 -SelfTest',
        'score-empirical-run-packet.ps1',
        'dry_run_package_builder_available',
        'build-empirical-dry-run-package.ps1 -SelfTest',
        'synthetic mock execution package',
        'pilot execution runner',
        'pilot run chain',
        'annotation worklist',
        'label-template package',
        'annotation-intake',
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
        'build-empirical-mock-execution-package.ps1 -SelfTest',
        'score-empirical-mock-execution-package.ps1 -SelfTest',
        'score-empirical-runner-response.ps1 -SelfTest',
        'build-empirical-pilot-runner-requests.ps1 -SelfTest',
        'score-empirical-pilot-runner-requests.ps1 -SelfTest',
        'build-empirical-pilot-execution-package.ps1 -SelfTest',
        'score-empirical-pilot-execution-package.ps1 -SelfTest',
        'build-empirical-pilot-run-chain.ps1 -SelfTest',
        'build-empirical-annotation-worklist.ps1 -SelfTest',
        'score-empirical-annotation-worklist.ps1 -SelfTest',
        'build-empirical-label-template-package.ps1 -SelfTest',
        'score-empirical-label-template-package.ps1 -SelfTest',
        'score-empirical-annotation-intake.ps1 -SelfTest',
        'score-empirical-run-packet.ps1',
        'score-empirical-evidence-package.ps1 -SelfTest',
        'score-empirical-results.ps1 -SelfTest',
        'score-empirical-agreement.ps1 -SelfTest',
        'build-empirical-dry-run-package.ps1 -SelfTest',
        'dry-run package builder',
        'mock execution package route',
        'pilot_runner_request_package_scorer_available',
        'score-empirical-pilot-runner-requests.ps1 -SelfTest',
        'pilot execution runner route',
        'pilot run chain route',
        'annotation worklist route',
        'label-template package route',
        'annotation intake route',
        'do not execute hosted'
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
