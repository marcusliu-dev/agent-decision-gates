param(
    [string]$PackageRoot,
    [switch]$SelfTest,
    [switch]$Json,
    [switch]$RequireHumanLlmPairs,
    [double]$MinimumAgreementRate = [double]::NaN
)

$ErrorActionPreference = 'Stop'

$AnalyzerVersion = '0.1.0'

function New-Result {
    param(
        [string]$Status,
        [System.Collections.Generic.List[string]]$Failures,
        [System.Collections.Generic.List[string]]$Warnings,
        [System.Collections.Generic.List[string]]$Info,
        [hashtable]$Summary
    )

    return [ordered]@{
        status = $Status
        failures = @($Failures)
        warnings = @($Warnings)
        info = @($Info)
        summary = $Summary
    }
}

function Test-HasProperty {
    param(
        [object]$Record,
        [string]$Name
    )

    return $Record.PSObject.Properties.Name -contains $Name
}

function Get-PropertyValue {
    param(
        [object]$Record,
        [string]$Name
    )

    if (-not (Test-HasProperty -Record $Record -Name $Name)) {
        return $null
    }
    return $Record.PSObject.Properties[$Name].Value
}

function Read-JsonRecords {
    param(
        [System.Collections.Generic.List[string]]$Failures,
        [string]$Directory,
        [string]$Label
    )

    $records = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $Directory)) {
        $Failures.Add("Missing required directory for $Label records.")
        return @($records.ToArray())
    }

    foreach ($file in (Get-ChildItem -LiteralPath $Directory -Filter '*.json' -File)) {
        try {
            $parsed = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        } catch {
            $Failures.Add("Could not parse JSON $Label record '$($file.Name)': $($_.Exception.Message)")
            continue
        }

        foreach ($record in @($parsed)) {
            $records.Add($record) | Out-Null
        }
    }

    return @($records.ToArray())
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Value
    )

    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-PackageId {
    param(
        [string]$Root
    )

    $resolvedRoot = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\', '/')
    $hashInputs = Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File -Filter '*.json' |
        Sort-Object FullName |
        ForEach-Object {
            $relative = $_.FullName.Substring($resolvedRoot.Length).TrimStart('\', '/')
            $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            "$relative=$hash"
        }
    $joined = ($hashInputs -join "`n")
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($joined)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha.ComputeHash($bytes)
    } finally {
        $sha.Dispose()
    }
    $hex = ([System.BitConverter]::ToString($digest)).Replace('-', '').ToLowerInvariant()
    return "sha256:$hex"
}

function Invoke-EvidencePackageValidator {
    param(
        [string]$Root
    )

    $validatorPath = Join-Path $PSScriptRoot 'score-empirical-evidence-package.ps1'
    if (-not (Test-Path -LiteralPath $validatorPath)) {
        return [ordered]@{
            status = 'fail'
            failures = @("Missing evidence-package validator: $validatorPath")
        }
    }

    $output = & $validatorPath -PackageRoot $Root -Json 2>&1
    if ($LASTEXITCODE -ne 0) {
        try {
            return (($output | Out-String) | ConvertFrom-Json)
        } catch {
            return [ordered]@{
                status = 'fail'
                failures = @("Evidence-package validator failed: $($output -join "`n")")
            }
        }
    }

    return (($output | Out-String) | ConvertFrom-Json)
}

function Get-HumanLlmAgreementSummary {
    param(
        [object[]]$Annotations,
        [string[]]$LabelFields
    )

    $comparisons = 0
    $matches = 0
    $comparedRuns = 0
    $groups = $Annotations | Group-Object { [string](Get-PropertyValue -Record $_ -Name 'run_id') }

    foreach ($group in $groups) {
        $humans = @($group.Group | Where-Object { [string](Get-PropertyValue -Record $_ -Name 'annotator_type') -eq 'human' })
        $llmJudges = @($group.Group | Where-Object { [string](Get-PropertyValue -Record $_ -Name 'annotator_type') -eq 'llm_judge' })
        if ($humans.Count -eq 0 -or $llmJudges.Count -eq 0) {
            continue
        }

        $runHadComparison = $false
        foreach ($human in $humans) {
            foreach ($judge in $llmJudges) {
                foreach ($field in $LabelFields) {
                    $left = [string](Get-PropertyValue -Record $human -Name $field)
                    $right = [string](Get-PropertyValue -Record $judge -Name $field)
                    if ($left -in @('not_applicable', 'insufficient_evidence') -or $right -in @('not_applicable', 'insufficient_evidence')) {
                        continue
                    }
                    $comparisons++
                    $runHadComparison = $true
                    if ($left -eq $right) {
                        $matches++
                    }
                }
            }
        }

        if ($runHadComparison) {
            $comparedRuns++
        }
    }

    $rate = if ($comparisons -gt 0) { [math]::Round($matches / $comparisons, 6) } else { $null }
    return [ordered]@{
        compared_runs = $comparedRuns
        human_llm_pairwise_exact_label_agreement_rate = $rate
        human_llm_label_comparisons = $comparisons
        human_llm_label_matches = $matches
        agreement_unavailable_reason = if ($comparisons -eq 0) { 'no_comparable_human_llm_annotation_pairs' } else { $null }
    }
}

function Invoke-AgreementAnalysis {
    param(
        [string]$Root,
        [bool]$RequirePairs,
        [double]$MinimumRate
    )

    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}

    if (-not (Test-Path -LiteralPath $Root)) {
        $failures.Add('Evidence package root not found.')
        return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
    }

    $validatorResult = Invoke-EvidencePackageValidator -Root $Root
    if ($validatorResult.status -ne 'pass') {
        $failures.Add('Evidence-package validator failed; refusing to compute agreement.')
        return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
    }

    $annotations = Read-JsonRecords -Failures $failures -Directory (Join-Path $Root 'annotations') -Label 'annotation'
    if ($failures.Count -gt 0) {
        return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
    }

    $labelFields = @(
        'false_readiness_label',
        'overclaim_label',
        'objective_narrowing_label',
        'human_checkpoint_recall_label',
        'unnecessary_stop_label',
        'nonlocal_route_violation_label',
        'stale_source_reliance_label',
        'counter_review_catch_label',
        'adjudication_override_quality_label',
        'final_claim_supported_label'
    )

    $agreement = Get-HumanLlmAgreementSummary -Annotations $annotations -LabelFields $labelFields
    $humanCount = @($annotations | Where-Object { [string](Get-PropertyValue -Record $_ -Name 'annotator_type') -eq 'human' }).Count
    $judgeCount = @($annotations | Where-Object { [string](Get-PropertyValue -Record $_ -Name 'annotator_type') -eq 'llm_judge' }).Count
    $ruleCount = @($annotations | Where-Object { [string](Get-PropertyValue -Record $_ -Name 'annotator_type') -eq 'rule_based_scorer' }).Count

    if ($RequirePairs -and [int]$agreement.compared_runs -eq 0) {
        $failures.Add('Human/LLM-judge annotation pairs are required but none were comparable.')
    }

    if (-not [double]::IsNaN($MinimumRate)) {
        if ($null -eq $agreement.human_llm_pairwise_exact_label_agreement_rate) {
            $failures.Add("Minimum agreement rate $MinimumRate was required but no agreement rate is available.")
        } elseif ([double]$agreement.human_llm_pairwise_exact_label_agreement_rate -lt $MinimumRate) {
            $failures.Add("Human/LLM-judge agreement rate $($agreement.human_llm_pairwise_exact_label_agreement_rate) is below required minimum $MinimumRate.")
        }
    }

    if ($null -eq $agreement.human_llm_pairwise_exact_label_agreement_rate) {
        $warnings.Add('Human/LLM-judge agreement is unavailable because no comparable pairs exist.')
    }

    $summary['package_id'] = Get-PackageId -Root $Root
    $summary['compared_runs'] = $agreement.compared_runs
    $summary['human_llm_pairwise_exact_label_agreement_rate'] = $agreement.human_llm_pairwise_exact_label_agreement_rate
    $summary['human_llm_label_comparisons'] = $agreement.human_llm_label_comparisons
    $summary['human_llm_label_matches'] = $agreement.human_llm_label_matches
    $summary['human_annotation_count'] = $humanCount
    $summary['llm_judge_annotation_count'] = $judgeCount
    $summary['rule_based_annotation_count'] = $ruleCount
    $summary['agreement_unavailable_reason'] = $agreement.agreement_unavailable_reason
    $summary['known_bias_limitations'] = @(
        'verbosity_bias',
        'position_bias',
        'self_enhancement_bias',
        'correlated_model_failure',
        'rubric_drift',
        'missing_human_ground_truth'
    )
    $summary['analyzer_version'] = $AnalyzerVersion

    $info.Add('Validated and summarized human-vs-LLM-judge agreement route.')
    $info.Add("Comparable human/LLM runs: $($agreement.compared_runs).")
    $info.Add("Human/LLM label comparisons: $($agreement.human_llm_label_comparisons).")

    $status = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
    return (New-Result -Status $status -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
}

function New-SyntheticEvidencePackage {
    param(
        [string]$Root,
        [switch]$HumanOnly,
        [switch]$LowAgreement,
        [switch]$MissingAnnotation
    )

    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'transcripts') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'annotations') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'cost-latency') | Out-Null

    $labels = [ordered]@{
        false_readiness_label = 'pass'
        overclaim_label = 'pass'
        objective_narrowing_label = 'pass'
        human_checkpoint_recall_label = 'pass'
        unnecessary_stop_label = 'pass'
        nonlocal_route_violation_label = 'pass'
        stale_source_reliance_label = 'pass'
        counter_review_catch_label = 'pass'
        adjudication_override_quality_label = 'pass'
        final_claim_supported_label = 'pass'
    }
    $judgeLabels = [ordered]@{}
    foreach ($entry in $labels.GetEnumerator()) {
        $judgeLabels[$entry.Key] = $entry.Value
    }
    if ($LowAgreement) {
        $judgeLabels.false_readiness_label = 'fail'
        $judgeLabels.overclaim_label = 'fail'
        $judgeLabels.objective_narrowing_label = 'fail'
    }

    $transcript = [ordered]@{
        run_id = 'synthetic-run-001'
        task_id = 'synthetic-task'
        condition = 'full_consult_gate'
        repeat_index = 1
        task_suite_version = '0.1.0'
        prompt_version = 'synthetic-agreement-self-test'
        model_provider = 'synthetic'
        model_name_or_alias = 'synthetic-validator-fixture'
        runtime_surface = 'agreement-self-test'
        start_timestamp_utc = '2026-06-07T00:00:00Z'
        end_timestamp_utc = '2026-06-07T00:00:01Z'
        input_prompt = 'Synthetic agreement checker self-test prompt.'
        transcript_messages = @(
            [ordered]@{
                message_index = 0
                role = 'assistant'
                content = 'Synthetic answer supports a bounded claim.'
                timestamp_utc = '2026-06-07T00:00:00Z'
            }
        )
        tool_calls = @(
            [ordered]@{
                tool_call_index = 0
                tool_name = 'synthetic_tool'
                input_summary = 'none'
                output_summary = 'none'
                timestamp_utc = '2026-06-07T00:00:00Z'
            }
        )
        final_answer = 'Synthetic answer supports a bounded claim.'
        final_claim = 'synthetic_structural_fixture_only'
        checked_evidence = @('synthetic evidence span')
        selected_claim_ceiling = 'synthetic_fixture_only'
        stop_or_continue_decision = 'stop'
        human_checkpoint_decision = 'not_applicable'
        cost_latency_record_id = 'synthetic-cost-001'
        redaction_status = 'synthetic_no_private_material'
    }

    function New-Annotation {
        param(
            [string]$AnnotationId,
            [string]$AnnotatorType,
            [hashtable]$AnnotationLabels
        )
        return [ordered]@{
            annotation_id = $AnnotationId
            run_id = 'synthetic-run-001'
            task_id = 'synthetic-task'
            condition = 'full_consult_gate'
            annotation_guideline_version = 'annotation-guidelines-v0.1.0'
            annotator_type = $AnnotatorType
            annotator_id = "synthetic-$AnnotatorType"
            label_timestamp_utc = '2026-06-07T00:00:02Z'
            false_readiness_label = $AnnotationLabels.false_readiness_label
            overclaim_label = $AnnotationLabels.overclaim_label
            objective_narrowing_label = $AnnotationLabels.objective_narrowing_label
            human_checkpoint_recall_label = $AnnotationLabels.human_checkpoint_recall_label
            unnecessary_stop_label = $AnnotationLabels.unnecessary_stop_label
            nonlocal_route_violation_label = $AnnotationLabels.nonlocal_route_violation_label
            stale_source_reliance_label = $AnnotationLabels.stale_source_reliance_label
            counter_review_catch_label = $AnnotationLabels.counter_review_catch_label
            adjudication_override_quality_label = $AnnotationLabels.adjudication_override_quality_label
            final_claim_supported_label = $AnnotationLabels.final_claim_supported_label
            rationale_transcript_spans = @(
                [ordered]@{
                    transcript_message_index = 0
                    start_offset = 0
                    end_offset = 9
                    rationale_note = 'Synthetic span.'
                }
            )
            confidence = 1.0
        }
    }

    $cost = [ordered]@{
        cost_latency_record_id = 'synthetic-cost-001'
        run_id = 'synthetic-run-001'
        input_tokens = 1
        output_tokens = 1
        tool_call_count = 1
        wall_time_ms = 1
        api_cost_usd = 0
        retry_count = 0
    }

    Write-JsonFile -Path (Join-Path $Root 'transcripts/synthetic-run-001.json') -Value $transcript
    if (-not $MissingAnnotation) {
        Write-JsonFile -Path (Join-Path $Root 'annotations/synthetic-human-001.json') -Value (New-Annotation -AnnotationId 'synthetic-human-001' -AnnotatorType 'human' -AnnotationLabels $labels)
        if (-not $HumanOnly) {
            Write-JsonFile -Path (Join-Path $Root 'annotations/synthetic-llm-001.json') -Value (New-Annotation -AnnotationId 'synthetic-llm-001' -AnnotatorType 'llm_judge' -AnnotationLabels $judgeLabels)
        }
    }
    Write-JsonFile -Path (Join-Path $Root 'cost-latency/synthetic-cost-001.json') -Value $cost
}

function Invoke-SelfTest {
    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}

    $tempBase = Join-Path ([System.IO.Path]::GetTempPath()) ("adg-agreement-selftest-" + [guid]::NewGuid().ToString())
    try {
        $positiveRoot = Join-Path $tempBase 'positive'
        New-SyntheticEvidencePackage -Root $positiveRoot
        $positiveResult = Invoke-AgreementAnalysis -Root $positiveRoot -RequirePairs $true -MinimumRate 1.0
        $summary['self_test_positive_status'] = $positiveResult.status
        if ($positiveResult.status -ne 'pass') {
            $failures.Add('Synthetic positive agreement package did not pass analysis.')
            foreach ($failure in $positiveResult.failures) {
                $failures.Add("positive: $failure")
            }
        } else {
            $agreementRate = $positiveResult.summary.human_llm_pairwise_exact_label_agreement_rate
            $comparisonCount = $positiveResult.summary.human_llm_label_comparisons
            if ([double]$agreementRate -ne 1.0) {
                $failures.Add("Expected synthetic human/LLM agreement rate 1.0; found $agreementRate.")
            }
            if ([int]$comparisonCount -ne 10) {
                $failures.Add("Expected synthetic human/LLM comparison count 10; found $comparisonCount.")
            }
        }

        $humanOnlyRoot = Join-Path $tempBase 'human-only'
        New-SyntheticEvidencePackage -Root $humanOnlyRoot -HumanOnly
        $humanOnlyResult = Invoke-AgreementAnalysis -Root $humanOnlyRoot -RequirePairs $true -MinimumRate ([double]::NaN)
        $summary['self_test_missing_pair_status'] = $humanOnlyResult.status
        if ($humanOnlyResult.status -ne 'fail') {
            $failures.Add('Synthetic human-only package unexpectedly passed with required human/LLM pairs.')
        } elseif (-not (($humanOnlyResult.failures -join "`n") -like '*Human/LLM-judge annotation pairs are required*')) {
            $failures.Add('Synthetic human-only package failed, but not for the expected required-pair reason.')
        }

        $lowAgreementRoot = Join-Path $tempBase 'low-agreement'
        New-SyntheticEvidencePackage -Root $lowAgreementRoot -LowAgreement
        $lowAgreementResult = Invoke-AgreementAnalysis -Root $lowAgreementRoot -RequirePairs $true -MinimumRate 0.8
        $summary['self_test_low_agreement_status'] = $lowAgreementResult.status
        if ($lowAgreementResult.status -ne 'fail') {
            $failures.Add('Synthetic low-agreement package unexpectedly passed the minimum agreement threshold.')
        } elseif (-not (($lowAgreementResult.failures -join "`n") -like '*below required minimum*')) {
            $failures.Add('Synthetic low-agreement package failed, but not for the expected threshold reason.')
        }

        $invalidRoot = Join-Path $tempBase 'invalid'
        New-SyntheticEvidencePackage -Root $invalidRoot -MissingAnnotation
        $invalidResult = Invoke-AgreementAnalysis -Root $invalidRoot -RequirePairs $true -MinimumRate 0.8
        $summary['self_test_invalid_package_status'] = $invalidResult.status
        if ($invalidResult.status -ne 'fail') {
            $failures.Add('Synthetic invalid package unexpectedly passed agreement analysis.')
        } elseif (-not (($invalidResult.failures -join "`n") -like '*Evidence-package validator failed*')) {
            $failures.Add('Synthetic invalid package failed, but not through the evidence-package validator gate.')
        }

        $positiveJson = $positiveResult | ConvertTo-Json -Depth 16
        $summary['self_test_path_redaction_status'] = if ($positiveJson.Contains($tempBase)) { 'fail' } else { 'pass' }
        if ($positiveJson.Contains($tempBase)) {
            $failures.Add('Synthetic agreement output leaked the temporary package path.')
        }

        $info.Add('Validated synthetic human-vs-LLM agreement package.')
        $info.Add('Rejected missing human/LLM pairs when required.')
        $info.Add('Rejected low agreement when a minimum threshold was required.')
        $info.Add('Rejected invalid package before agreement analysis.')
        $summary['self_test_expected_human_llm_agreement_rate'] = 1.0
        $summary['self_test_expected_human_llm_comparisons'] = 10
    } finally {
        if (Test-Path -LiteralPath $tempBase) {
            Remove-Item -LiteralPath $tempBase -Recurse -Force
        }
    }

    $status = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
    return (New-Result -Status $status -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
}

if ($SelfTest) {
    $result = Invoke-SelfTest
} else {
    if (-not $PackageRoot) {
        $failures = New-Object System.Collections.Generic.List[string]
        $warnings = New-Object System.Collections.Generic.List[string]
        $info = New-Object System.Collections.Generic.List[string]
        $summary = @{}
        $failures.Add('Provide -PackageRoot for a real evidence package or -SelfTest for the synthetic agreement self-test.')
        $result = New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary
    } else {
        $result = Invoke-AgreementAnalysis -Root $PackageRoot -RequirePairs ([bool]$RequireHumanLlmPairs) -MinimumRate $MinimumAgreementRate
    }
}

if ($Json) {
    $result | ConvertTo-Json -Depth 16
} else {
    "Empirical agreement checks: $($result.status)"
    ''
    'Failures:'
    if ($result.failures.Count -eq 0) { '  none' } else { $result.failures | ForEach-Object { "  - $_" } }
    ''
    'Warnings:'
    if ($result.warnings.Count -eq 0) { '  none' } else { $result.warnings | ForEach-Object { "  - $_" } }
    ''
    'Info:'
    if ($result.info.Count -eq 0) { '  none' } else { $result.info | ForEach-Object { "  - $_" } }
}

if ($result.status -ne 'pass') {
    exit 1
}
