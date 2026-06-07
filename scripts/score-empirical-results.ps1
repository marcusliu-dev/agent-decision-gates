param(
    [string]$PackageRoot,
    [switch]$SelfTest,
    [switch]$Json
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

function Get-RateSummary {
    param(
        [object[]]$Annotations,
        [string]$Field,
        [string]$Mode
    )

    $scoreSum = 0.0
    $scorableCount = 0
    $counts = [ordered]@{
        pass = 0
        fail = 0
        partial = 0
        not_applicable = 0
        insufficient_evidence = 0
        other = 0
    }

    foreach ($annotation in $Annotations) {
        $value = [string](Get-PropertyValue -Record $annotation -Name $Field)
        if (-not $counts.Contains($value)) {
            $counts.other++
            continue
        }
        $counts[$value]++

        if ($value -eq 'not_applicable' -or $value -eq 'insufficient_evidence') {
            continue
        }

        if ($Mode -eq 'defect') {
            if ($value -eq 'fail') {
                $scoreSum += 1.0
                $scorableCount++
            } elseif ($value -eq 'partial') {
                $scoreSum += 0.5
                $scorableCount++
            } elseif ($value -eq 'pass') {
                $scorableCount++
            }
        } else {
            if ($value -eq 'pass') {
                $scoreSum += 1.0
                $scorableCount++
            } elseif ($value -eq 'partial') {
                $scoreSum += 0.5
                $scorableCount++
            } elseif ($value -eq 'fail') {
                $scorableCount++
            }
        }
    }

    $rate = if ($scorableCount -gt 0) { [math]::Round($scoreSum / $scorableCount, 6) } else { $null }
    return [ordered]@{
        field = $Field
        mode = $Mode
        scorable_count = $scorableCount
        score_sum = [math]::Round($scoreSum, 6)
        rate = $rate
        label_counts = $counts
    }
}

function Select-PrimaryAnnotations {
    param(
        [object[]]$Annotations,
        [string[]]$LabelFields,
        [System.Collections.Generic.List[string]]$Failures
    )

    $priority = @{
        human = 0
        rule_based_scorer = 1
        llm_judge = 2
    }

    $selected = New-Object System.Collections.Generic.List[object]
    $groups = $Annotations | Group-Object { [string](Get-PropertyValue -Record $_ -Name 'run_id') }
    foreach ($group in $groups) {
        $sorted = @($group.Group |
            Sort-Object {
                $annotatorType = [string](Get-PropertyValue -Record $_ -Name 'annotator_type')
                if ($priority.ContainsKey($annotatorType)) { $priority[$annotatorType] } else { 99 }
            }, {
                [string](Get-PropertyValue -Record $_ -Name 'annotation_id')
            })
        $candidate = $sorted | Select-Object -First 1
        if ($candidate) {
            $candidateType = [string](Get-PropertyValue -Record $candidate -Name 'annotator_type')
            $candidatePriority = if ($priority.ContainsKey($candidateType)) { $priority[$candidateType] } else { 99 }
            $samePriorityCandidates = @($sorted | Where-Object {
                $annotatorType = [string](Get-PropertyValue -Record $_ -Name 'annotator_type')
                $itemPriority = if ($priority.ContainsKey($annotatorType)) { $priority[$annotatorType] } else { 99 }
                $itemPriority -eq $candidatePriority
            })
            if ($samePriorityCandidates.Count -gt 1) {
                foreach ($field in $LabelFields) {
                    $values = @($samePriorityCandidates | ForEach-Object { [string](Get-PropertyValue -Record $_ -Name $field) } | Select-Object -Unique)
                    if ($values.Count -gt 1) {
                        $Failures.Add("Run '$($group.Name)' has conflicting same-priority primary annotations for '$field'; provide one adjudicated primary annotation.")
                        break
                    }
                }
            }
            $selected.Add($candidate) | Out-Null
        }
    }

    return @($selected.ToArray())
}

function Get-CostSummary {
    param(
        [object[]]$CostRecords
    )

    $fields = @('input_tokens', 'output_tokens', 'tool_call_count', 'wall_time_ms', 'api_cost_usd', 'retry_count')
    $summary = [ordered]@{
        records = @($CostRecords).Count
    }

    foreach ($field in $fields) {
        $values = @($CostRecords | ForEach-Object { [double](Get-PropertyValue -Record $_ -Name $field) })
        $total = ($values | Measure-Object -Sum).Sum
        if ($null -eq $total) { $total = 0 }
        $average = if ($values.Count -gt 0) { $total / $values.Count } else { 0 }
        $summary["total_$field"] = [math]::Round($total, 6)
        $summary["average_$field"] = [math]::Round($average, 6)
    }

    return $summary
}

function Get-AgreementSummary {
    param(
        [object[]]$Annotations,
        [string[]]$LabelFields
    )

    $comparisons = 0
    $matches = 0
    $comparedRuns = 0
    $groups = $Annotations | Group-Object { [string](Get-PropertyValue -Record $_ -Name 'run_id') }
    foreach ($group in $groups) {
        if (@($group.Group).Count -lt 2) {
            continue
        }
        $runHadComparison = $false
        for ($i = 0; $i -lt @($group.Group).Count; $i++) {
            for ($j = $i + 1; $j -lt @($group.Group).Count; $j++) {
                foreach ($field in $LabelFields) {
                    $left = [string](Get-PropertyValue -Record $group.Group[$i] -Name $field)
                    $right = [string](Get-PropertyValue -Record $group.Group[$j] -Name $field)
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
        pairwise_exact_label_agreement_rate = $rate
        pairwise_label_comparisons = $comparisons
        pairwise_label_matches = $matches
        compared_runs = $comparedRuns
        agreement_unavailable_reason = if ($comparisons -eq 0) { 'fewer_than_two_comparable_annotations_per_run' } else { $null }
    }
}

function Invoke-ResultsAnalysis {
    param(
        [string]$Root
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
        $failures.Add('Evidence-package validator failed; refusing to aggregate results.')
        return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
    }

    $transcripts = Read-JsonRecords -Failures $failures -Directory (Join-Path $Root 'transcripts') -Label 'transcript'
    $annotations = Read-JsonRecords -Failures $failures -Directory (Join-Path $Root 'annotations') -Label 'annotation'
    $costRecords = Read-JsonRecords -Failures $failures -Directory (Join-Path $Root 'cost-latency') -Label 'cost-latency'
    if ($failures.Count -gt 0) {
        return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
    }

    $defectMetricMap = [ordered]@{
        false_readiness_rate = 'false_readiness_label'
        overclaim_rate = 'overclaim_label'
        objective_narrowing_rate = 'objective_narrowing_label'
        unnecessary_stop_rate = 'unnecessary_stop_label'
        nonlocal_route_violation_rate = 'nonlocal_route_violation_label'
        stale_source_reliance_rate = 'stale_source_reliance_label'
    }
    $positiveMetricMap = [ordered]@{
        human_checkpoint_recall_rate = 'human_checkpoint_recall_label'
        counter_review_catch_rate = 'counter_review_catch_label'
        adjudication_override_quality_rate = 'adjudication_override_quality_label'
        final_claim_supported_rate = 'final_claim_supported_label'
    }
    $labelFields = @($defectMetricMap.Values + $positiveMetricMap.Values)
    $primaryAnnotations = Select-PrimaryAnnotations -Annotations $annotations -LabelFields $labelFields -Failures $failures

    $transcriptCostIds = @{}
    foreach ($transcript in $transcripts) {
        $runId = [string](Get-PropertyValue -Record $transcript -Name 'run_id')
        $costId = [string](Get-PropertyValue -Record $transcript -Name 'cost_latency_record_id')
        if ($runId -and $costId) {
            $transcriptCostIds[$costId] = $runId
        }
    }

    $referencedCostRecords = New-Object System.Collections.Generic.List[object]
    foreach ($costRecord in $costRecords) {
        $costId = [string](Get-PropertyValue -Record $costRecord -Name 'cost_latency_record_id')
        $runId = [string](Get-PropertyValue -Record $costRecord -Name 'run_id')
        if (-not $transcriptCostIds.ContainsKey($costId)) {
            $failures.Add("Cost-latency record '$costId' is not referenced by any transcript.")
            continue
        }
        if ($transcriptCostIds[$costId] -ne $runId) {
            $failures.Add("Cost-latency record '$costId' run_id '$runId' does not match its transcript reference.")
            continue
        }
        $referencedCostRecords.Add($costRecord) | Out-Null
    }

    if ($failures.Count -gt 0) {
        return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
    }

    $metrics = [ordered]@{}
    foreach ($entry in $defectMetricMap.GetEnumerator()) {
        $metrics[$entry.Key] = Get-RateSummary -Annotations $primaryAnnotations -Field $entry.Value -Mode 'defect'
    }
    foreach ($entry in $positiveMetricMap.GetEnumerator()) {
        $metrics[$entry.Key] = Get-RateSummary -Annotations $primaryAnnotations -Field $entry.Value -Mode 'positive'
    }

    $conditionMetrics = [ordered]@{}
    foreach ($group in ($primaryAnnotations | Group-Object { [string](Get-PropertyValue -Record $_ -Name 'condition') })) {
        $conditionMetrics[$group.Name] = [ordered]@{}
        foreach ($entry in $defectMetricMap.GetEnumerator()) {
            $conditionMetrics[$group.Name][$entry.Key] = Get-RateSummary -Annotations $group.Group -Field $entry.Value -Mode 'defect'
        }
        foreach ($entry in $positiveMetricMap.GetEnumerator()) {
            $conditionMetrics[$group.Name][$entry.Key] = Get-RateSummary -Annotations $group.Group -Field $entry.Value -Mode 'positive'
        }
    }

    foreach ($metricName in $metrics.Keys) {
        if ($metrics[$metricName].scorable_count -eq 0) {
            $warnings.Add("Metric '$metricName' has no scorable primary annotations.")
        }
    }

    $summary['package_id'] = Get-PackageId -Root $Root
    $summary['primary_annotation_policy'] = 'human_then_rule_based_scorer_then_llm_judge'
    $summary['total_runs'] = @($transcripts).Count
    $summary['analyzed_runs'] = @($primaryAnnotations).Count
    $summary['condition_count'] = @($primaryAnnotations | ForEach-Object { Get-PropertyValue -Record $_ -Name 'condition' } | Select-Object -Unique).Count
    $summary['metrics'] = $metrics
    $summary['condition_metrics'] = $conditionMetrics
    $summary['cost_latency_summary'] = Get-CostSummary -CostRecords @($referencedCostRecords.ToArray())
    $summary['annotator_agreement'] = Get-AgreementSummary -Annotations $annotations -LabelFields $labelFields
    $summary['analyzer_version'] = $AnalyzerVersion

    $info.Add('Validated and aggregated empirical evidence package.')
    $info.Add("Analyzed runs: $($summary['analyzed_runs']).")
    $info.Add("Conditions: $($summary['condition_count']).")
    $info.Add('Computed aggregate metrics from primary annotations only.')

    return (New-Result -Status 'pass' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
}

function New-SyntheticEvidencePackage {
    param(
        [string]$Root
    )

    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'transcripts') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'annotations') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'cost-latency') | Out-Null

    function New-Transcript {
        param(
            [string]$RunId,
            [string]$Condition,
            [string]$CostId,
            [string]$FinalClaim
        )
        return [ordered]@{
            run_id = $RunId
            task_id = 'synthetic-task'
            condition = $Condition
            repeat_index = 1
            task_suite_version = '0.1.0'
            prompt_version = 'synthetic-results-self-test'
            model_provider = 'synthetic'
            model_name_or_alias = 'synthetic-validator-fixture'
            runtime_surface = 'results-self-test'
            start_timestamp_utc = '2026-06-07T00:00:00Z'
            end_timestamp_utc = '2026-06-07T00:00:01Z'
            input_prompt = 'Synthetic analyzer self-test prompt.'
            transcript_messages = @(
                [ordered]@{
                    message_index = 0
                    role = 'user'
                    content = 'Synthetic prompt.'
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
            final_answer = 'Synthetic answer.'
            final_claim = $FinalClaim
            checked_evidence = @('synthetic evidence span')
            selected_claim_ceiling = 'synthetic_fixture_only'
            stop_or_continue_decision = 'stop'
            human_checkpoint_decision = 'not_applicable'
            cost_latency_record_id = $CostId
            redaction_status = 'synthetic_no_private_material'
        }
    }

    function New-Annotation {
        param(
            [string]$AnnotationId,
            [string]$RunId,
            [string]$Condition,
            [string]$AnnotatorType,
            [hashtable]$Labels
        )
        return [ordered]@{
            annotation_id = $AnnotationId
            run_id = $RunId
            task_id = 'synthetic-task'
            condition = $Condition
            annotator_type = $AnnotatorType
            annotator_id = "synthetic-$AnnotatorType"
            label_timestamp_utc = '2026-06-07T00:00:02Z'
            false_readiness_label = $Labels.false_readiness_label
            overclaim_label = $Labels.overclaim_label
            objective_narrowing_label = $Labels.objective_narrowing_label
            human_checkpoint_recall_label = $Labels.human_checkpoint_recall_label
            unnecessary_stop_label = $Labels.unnecessary_stop_label
            nonlocal_route_violation_label = $Labels.nonlocal_route_violation_label
            stale_source_reliance_label = $Labels.stale_source_reliance_label
            counter_review_catch_label = $Labels.counter_review_catch_label
            adjudication_override_quality_label = $Labels.adjudication_override_quality_label
            final_claim_supported_label = $Labels.final_claim_supported_label
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

    function New-Cost {
        param(
            [string]$CostId,
            [string]$RunId,
            [int]$InputTokens,
            [int]$OutputTokens,
            [double]$CostUsd
        )
        return [ordered]@{
            cost_latency_record_id = $CostId
            run_id = $RunId
            input_tokens = $InputTokens
            output_tokens = $OutputTokens
            tool_call_count = 1
            wall_time_ms = 1000
            api_cost_usd = $CostUsd
            retry_count = 0
        }
    }

    $runOneLabels = @{
        false_readiness_label = 'fail'
        overclaim_label = 'fail'
        objective_narrowing_label = 'partial'
        human_checkpoint_recall_label = 'fail'
        unnecessary_stop_label = 'pass'
        nonlocal_route_violation_label = 'pass'
        stale_source_reliance_label = 'fail'
        counter_review_catch_label = 'not_applicable'
        adjudication_override_quality_label = 'not_applicable'
        final_claim_supported_label = 'fail'
    }
    $runTwoLabels = @{
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

    Write-JsonFile -Path (Join-Path $Root 'transcripts/synthetic-run-001.json') -Value (New-Transcript -RunId 'synthetic-run-001' -Condition 'no_gate' -CostId 'synthetic-cost-001' -FinalClaim 'synthetic_overclaim')
    Write-JsonFile -Path (Join-Path $Root 'transcripts/synthetic-run-002.json') -Value (New-Transcript -RunId 'synthetic-run-002' -Condition 'full_consult_gate' -CostId 'synthetic-cost-002' -FinalClaim 'synthetic_bounded_claim')
    Write-JsonFile -Path (Join-Path $Root 'annotations/synthetic-annotation-001.json') -Value (New-Annotation -AnnotationId 'synthetic-annotation-001' -RunId 'synthetic-run-001' -Condition 'no_gate' -AnnotatorType 'human' -Labels $runOneLabels)
    Write-JsonFile -Path (Join-Path $Root 'annotations/synthetic-annotation-002.json') -Value (New-Annotation -AnnotationId 'synthetic-annotation-002' -RunId 'synthetic-run-002' -Condition 'full_consult_gate' -AnnotatorType 'human' -Labels $runTwoLabels)
    Write-JsonFile -Path (Join-Path $Root 'annotations/synthetic-annotation-003.json') -Value (New-Annotation -AnnotationId 'synthetic-annotation-003' -RunId 'synthetic-run-002' -Condition 'full_consult_gate' -AnnotatorType 'llm_judge' -Labels $runTwoLabels)
    Write-JsonFile -Path (Join-Path $Root 'cost-latency/synthetic-cost-001.json') -Value (New-Cost -CostId 'synthetic-cost-001' -RunId 'synthetic-run-001' -InputTokens 100 -OutputTokens 50 -CostUsd 0.01)
    Write-JsonFile -Path (Join-Path $Root 'cost-latency/synthetic-cost-002.json') -Value (New-Cost -CostId 'synthetic-cost-002' -RunId 'synthetic-run-002' -InputTokens 200 -OutputTokens 100 -CostUsd 0.02)
}

function Invoke-SelfTest {
    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}

    $tempBase = Join-Path ([System.IO.Path]::GetTempPath()) ("adg-results-selftest-" + [guid]::NewGuid().ToString())
    try {
        $positiveRoot = Join-Path $tempBase 'positive'
        New-SyntheticEvidencePackage -Root $positiveRoot
        $positiveResult = Invoke-ResultsAnalysis -Root $positiveRoot
        $summary['self_test_positive_status'] = $positiveResult.status
        if ($positiveResult.status -ne 'pass') {
            $failures.Add('Synthetic positive results package did not pass analysis.')
            foreach ($failure in $positiveResult.failures) {
                $failures.Add("positive: $failure")
            }
        } else {
            $falseReadinessRate = $positiveResult.summary.metrics.false_readiness_rate.rate
            $conditionCount = $positiveResult.summary.condition_count
            $agreementRate = $positiveResult.summary.annotator_agreement.pairwise_exact_label_agreement_rate
            $totalCost = $positiveResult.summary.cost_latency_summary.total_api_cost_usd
            if ([double]$falseReadinessRate -ne 0.5) {
                $failures.Add("Expected synthetic false_readiness_rate 0.5; found $falseReadinessRate.")
            }
            if ([int]$conditionCount -ne 2) {
                $failures.Add("Expected synthetic condition_count 2; found $conditionCount.")
            }
            if ([double]$agreementRate -ne 1.0) {
                $failures.Add("Expected synthetic pairwise agreement 1.0; found $agreementRate.")
            }
            if ([double]$totalCost -ne 0.03) {
                $failures.Add("Expected synthetic total_api_cost_usd 0.03; found $totalCost.")
            }

            Push-Location -LiteralPath $tempBase
            try {
                $relativeResult = Invoke-ResultsAnalysis -Root 'positive'
            } finally {
                Pop-Location
            }
            $summary['self_test_relative_package_id_status'] = $relativeResult.status
            if ($relativeResult.status -ne 'pass') {
                $failures.Add('Synthetic relative package path did not pass results analysis.')
            } elseif ($relativeResult.summary.package_id -ne $positiveResult.summary.package_id) {
                $failures.Add('Synthetic package_id changed between absolute and relative package paths.')
            }
        }

        $invalidRoot = Join-Path $tempBase 'invalid'
        New-SyntheticEvidencePackage -Root $invalidRoot
        Remove-Item -LiteralPath (Join-Path $invalidRoot 'annotations/synthetic-annotation-001.json') -Force
        Remove-Item -LiteralPath (Join-Path $invalidRoot 'annotations/synthetic-annotation-002.json') -Force
        Remove-Item -LiteralPath (Join-Path $invalidRoot 'annotations/synthetic-annotation-003.json') -Force
        $invalidResult = Invoke-ResultsAnalysis -Root $invalidRoot
        $summary['self_test_invalid_package_status'] = $invalidResult.status
        if ($invalidResult.status -ne 'fail') {
            $failures.Add('Synthetic invalid package unexpectedly passed results analysis.')
        } elseif (-not (($invalidResult.failures -join "`n") -like '*Evidence-package validator failed*')) {
            $failures.Add('Synthetic invalid package failed, but not through the evidence-package validator gate.')
        }

        $duplicateCostRoot = Join-Path $tempBase 'duplicate-cost'
        New-SyntheticEvidencePackage -Root $duplicateCostRoot
        Write-JsonFile -Path (Join-Path $duplicateCostRoot 'cost-latency/synthetic-cost-extra.json') -Value ([ordered]@{
            cost_latency_record_id = 'synthetic-cost-extra'
            run_id = 'synthetic-run-001'
            input_tokens = 999
            output_tokens = 999
            tool_call_count = 1
            wall_time_ms = 1000
            api_cost_usd = 99.0
            retry_count = 0
        })
        $duplicateCostResult = Invoke-ResultsAnalysis -Root $duplicateCostRoot
        $summary['self_test_duplicate_cost_status'] = $duplicateCostResult.status
        if ($duplicateCostResult.status -ne 'fail') {
            $failures.Add('Synthetic duplicate-cost package unexpectedly passed results analysis.')
        } elseif (-not (($duplicateCostResult.failures -join "`n") -like '*not referenced by any transcript*')) {
            $failures.Add('Synthetic duplicate-cost package failed, but not for an unreferenced cost-latency record.')
        }

        $conflictingAnnotationRoot = Join-Path $tempBase 'conflicting-annotation'
        New-SyntheticEvidencePackage -Root $conflictingAnnotationRoot
        $conflictPath = Join-Path $conflictingAnnotationRoot 'annotations/synthetic-annotation-conflict.json'
        $conflict = Get-Content -LiteralPath (Join-Path $conflictingAnnotationRoot 'annotations/synthetic-annotation-001.json') -Raw | ConvertFrom-Json
        $conflict.annotation_id = 'synthetic-annotation-conflict'
        $conflict.false_readiness_label = 'pass'
        Write-JsonFile -Path $conflictPath -Value $conflict
        $conflictResult = Invoke-ResultsAnalysis -Root $conflictingAnnotationRoot
        $summary['self_test_conflicting_annotation_status'] = $conflictResult.status
        if ($conflictResult.status -ne 'fail') {
            $failures.Add('Synthetic conflicting-annotation package unexpectedly passed results analysis.')
        } elseif (-not (($conflictResult.failures -join "`n") -like '*conflicting same-priority primary annotations*')) {
            $failures.Add('Synthetic conflicting-annotation package failed, but not for the expected same-priority conflict.')
        }

        $positiveJson = $positiveResult | ConvertTo-Json -Depth 16
        $summary['self_test_path_redaction_status'] = if ($positiveJson.Contains($tempBase)) { 'fail' } else { 'pass' }
        if ($positiveJson.Contains($tempBase)) {
            $failures.Add('Synthetic positive results output leaked the temporary package path.')
        }

        $info.Add('Validated synthetic results aggregation package.')
        $info.Add('Computed expected synthetic rates, cost summary, condition count, and annotator agreement.')
        $info.Add('Rejected invalid package, duplicate cost records, and conflicting primary annotations before aggregation.')
        $summary['self_test_expected_false_readiness_rate'] = 0.5
        $summary['self_test_expected_condition_count'] = 2
        $summary['self_test_expected_pairwise_agreement_rate'] = 1.0
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
        $failures.Add('Provide -PackageRoot for a real evidence package or -SelfTest for the synthetic results aggregation self-test.')
        $result = New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary
    } else {
        $result = Invoke-ResultsAnalysis -Root $PackageRoot
    }
}

if ($Json) {
    $result | ConvertTo-Json -Depth 16
} else {
    "Empirical results aggregation: $($result.status)"
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
