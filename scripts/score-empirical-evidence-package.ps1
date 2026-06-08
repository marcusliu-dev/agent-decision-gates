param(
    [string]$PackageRoot,
    [switch]$SelfTest,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

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

function Test-IsBlankValue {
    param(
        [object]$Value
    )

    if ($null -eq $Value) {
        return $true
    }
    if ($Value -is [string]) {
        return [string]::IsNullOrWhiteSpace($Value)
    }
    if ($Value -is [System.Array]) {
        return $Value.Count -eq 0
    }
    return $false
}

function Test-IsPresentText {
    param(
        [object]$Value
    )

    return -not (Test-IsBlankValue -Value $Value)
}

function Test-IsJsonNumber {
    param(
        [object]$Value
    )

    foreach ($type in @(
        [byte],
        [sbyte],
        [int16],
        [uint16],
        [int],
        [uint32],
        [long],
        [uint64],
        [single],
        [double],
        [decimal]
    )) {
        if ($Value -is $type) {
            return $true
        }
    }
    return $false
}

function Add-RequiredFieldFailures {
    param(
        [System.Collections.Generic.List[string]]$Failures,
        [object]$Record,
        [string[]]$Fields,
        [string]$Label
    )

    foreach ($field in $Fields) {
        if (-not (Test-HasProperty -Record $Record -Name $field)) {
            $Failures.Add("$Label is missing required field '$field'.")
            continue
        }
        $value = Get-PropertyValue -Record $Record -Name $field
        if (Test-IsBlankValue -Value $value) {
            $Failures.Add("$Label has blank required field '$field'.")
        }
    }
}

function Add-JsonNumberFailures {
    param(
        [System.Collections.Generic.List[string]]$Failures,
        [string]$Label,
        [string]$Field,
        [object]$Value,
        [double]$Minimum = [double]::NaN,
        [double]$Maximum = [double]::NaN
    )

    if ($null -eq $Value) {
        return
    }

    if (-not (Test-IsJsonNumber -Value $Value)) {
        $Failures.Add("$Label has nonnumeric $Field '$Value'; expected a JSON number.")
        return
    }

    $numericValue = [double]$Value
    if ([double]::IsNaN($numericValue) -or [double]::IsInfinity($numericValue)) {
        $Failures.Add("$Label has non-finite $Field '$Value'.")
        return
    }

    if (-not [double]::IsNaN($Minimum) -and $numericValue -lt $Minimum) {
        $Failures.Add("$Label has $Field '$Value' below minimum $Minimum.")
    }

    if (-not [double]::IsNaN($Maximum) -and $numericValue -gt $Maximum) {
        $Failures.Add("$Label has $Field '$Value' above maximum $Maximum.")
    }
}

function Add-JsonIntegerFailures {
    param(
        [System.Collections.Generic.List[string]]$Failures,
        [string]$Label,
        [string]$Field,
        [object]$Value,
        [int]$Minimum = 0
    )

    if ($null -eq $Value) {
        return
    }

    Add-JsonNumberFailures -Failures $Failures -Label $Label -Field $Field -Value $Value -Minimum $Minimum
    if (Test-IsJsonNumber -Value $Value) {
        $numericValue = [double]$Value
        if (-not [double]::IsNaN($numericValue) -and -not [double]::IsInfinity($numericValue) -and ([math]::Floor($numericValue) -ne $numericValue)) {
            $Failures.Add("$Label has non-integer $Field '$Value'.")
        }
    }
}

function Read-JsonRecords {
    param(
        [System.Collections.Generic.List[string]]$Failures,
        [string]$Directory,
        [string]$Label
    )

    $records = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $Directory)) {
        $Failures.Add("Missing required directory for $Label records: $Directory")
        return @($records.ToArray())
    }

    $files = Get-ChildItem -LiteralPath $Directory -Filter '*.json' -File
    if ($files.Count -eq 0) {
        $Failures.Add("No JSON $Label records found in $Directory")
        return @($records.ToArray())
    }

    foreach ($file in $files) {
        try {
            $parsed = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        } catch {
            $Failures.Add("Could not parse JSON $Label record '$($file.FullName)': $($_.Exception.Message)")
            continue
        }

        foreach ($record in @($parsed)) {
            $records.Add($record) | Out-Null
        }
    }

    return @($records.ToArray())
}

function Test-NoPrivateMaterial {
    param(
        [System.Collections.Generic.List[string]]$Failures,
        [string]$PackageRoot
    )

    $blockedPatterns = @(
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

    $textFiles = Get-ChildItem -LiteralPath $PackageRoot -Recurse -File -Force |
        Where-Object { $_.Extension -in '.json', '.txt', '.md', '.yaml', '.yml', '.csv', '.log' }
    foreach ($file in $textFiles) {
        $content = Get-Content -LiteralPath $file.FullName -Raw
        foreach ($blockedPattern in $blockedPatterns) {
            if ([regex]::IsMatch($content, $blockedPattern.Pattern)) {
                $Failures.Add("Blocked package content '$($blockedPattern.Label)' found in $($file.FullName).")
            }
        }
    }
}

function Invoke-PackageValidation {
    param(
        [string]$Root
    )

    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}

    if (-not (Test-Path -LiteralPath $Root)) {
        $failures.Add("Evidence package root not found: $Root")
        return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
    }

    $transcriptFields = @(
        'run_id',
        'task_id',
        'condition',
        'repeat_index',
        'task_suite_version',
        'prompt_version',
        'model_provider',
        'model_name_or_alias',
        'runtime_surface',
        'start_timestamp_utc',
        'end_timestamp_utc',
        'input_prompt',
        'transcript_messages',
        'final_answer',
        'final_claim',
        'checked_evidence',
        'selected_claim_ceiling',
        'stop_or_continue_decision',
        'human_checkpoint_decision',
        'cost_latency_record_id',
        'redaction_status'
    )

    $annotationFields = @(
        'annotation_id',
        'run_id',
        'task_id',
        'condition',
        'annotation_guideline_version',
        'annotator_type',
        'annotator_id',
        'label_timestamp_utc',
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
    )

    $costFields = @(
        'cost_latency_record_id',
        'run_id',
        'input_tokens',
        'output_tokens',
        'tool_call_count',
        'wall_time_ms',
        'api_cost_usd',
        'retry_count'
    )

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

    $messageFields = @(
        'message_index',
        'role',
        'content',
        'timestamp_utc'
    )

    $toolCallFields = @(
        'tool_call_index',
        'tool_name',
        'input_summary',
        'output_summary',
        'timestamp_utc'
    )

    $allowedLabels = @(
        'pass',
        'fail',
        'partial',
        'not_applicable',
        'insufficient_evidence'
    )

    $allowedAnnotatorTypes = @(
        'human',
        'llm_judge',
        'rule_based_scorer'
    )

    $requiredAnnotationGuidelineVersion = 'annotation-guidelines-v0.1.0'

    $transcripts = Read-JsonRecords -Failures $failures -Directory (Join-Path $Root 'transcripts') -Label 'transcript'
    $annotations = Read-JsonRecords -Failures $failures -Directory (Join-Path $Root 'annotations') -Label 'annotation'
    $costRecords = Read-JsonRecords -Failures $failures -Directory (Join-Path $Root 'cost-latency') -Label 'cost-latency'

    Test-NoPrivateMaterial -Failures $failures -PackageRoot $Root

    $transcriptsByRunId = @{}
    foreach ($transcript in $transcripts) {
        $runId = Get-PropertyValue -Record $transcript -Name 'run_id'
        $label = if ($runId) { "transcript '$runId'" } else { 'transcript record' }
        Add-RequiredFieldFailures -Failures $failures -Record $transcript -Fields $transcriptFields -Label $label
        if (-not (Test-HasProperty -Record $transcript -Name 'tool_calls')) {
            $failures.Add("$label is missing required field 'tool_calls'.")
        }
        if (Test-IsPresentText -Value $runId) {
            if ($transcriptsByRunId.ContainsKey([string]$runId)) {
                $failures.Add("Duplicate transcript run_id '$runId'.")
            } else {
                $transcriptsByRunId[[string]$runId] = $transcript
            }
        }

        foreach ($arrayField in @('transcript_messages', 'checked_evidence')) {
            $value = Get-PropertyValue -Record $transcript -Name $arrayField
            if ($null -eq $value -or @($value).Count -eq 0) {
                $failures.Add("$label must include nonempty '$arrayField'.")
            }
        }

        Add-JsonIntegerFailures -Failures $failures -Label $label -Field 'repeat_index' -Value (Get-PropertyValue -Record $transcript -Name 'repeat_index') -Minimum 0

        $messageIndexValues = @{}
        $messageOrdinal = 0
        foreach ($message in @(Get-PropertyValue -Record $transcript -Name 'transcript_messages')) {
            $messageLabel = "$label transcript_messages[$messageOrdinal]"
            Add-RequiredFieldFailures -Failures $failures -Record $message -Fields $messageFields -Label $messageLabel
            $messageIndex = Get-PropertyValue -Record $message -Name 'message_index'
            Add-JsonIntegerFailures -Failures $failures -Label $messageLabel -Field 'message_index' -Value $messageIndex -Minimum 0
            if (Test-IsPresentText -Value $messageIndex) {
                if ($messageIndexValues.ContainsKey([string]$messageIndex)) {
                    $failures.Add("$label has duplicate transcript message_index '$messageIndex'.")
                } else {
                    $messageIndexValues[[string]$messageIndex] = $true
                }
            }
            $messageOrdinal++
        }

        $toolCallOrdinal = 0
        foreach ($toolCall in @(Get-PropertyValue -Record $transcript -Name 'tool_calls')) {
            $toolCallLabel = "$label tool_calls[$toolCallOrdinal]"
            Add-RequiredFieldFailures -Failures $failures -Record $toolCall -Fields $toolCallFields -Label $toolCallLabel
            Add-JsonIntegerFailures -Failures $failures -Label $toolCallLabel -Field 'tool_call_index' -Value (Get-PropertyValue -Record $toolCall -Name 'tool_call_index') -Minimum 0
            $toolCallOrdinal++
        }
    }

    foreach ($annotation in $annotations) {
        $annotationId = Get-PropertyValue -Record $annotation -Name 'annotation_id'
        $label = if ($annotationId) { "annotation '$annotationId'" } else { 'annotation record' }
        Add-RequiredFieldFailures -Failures $failures -Record $annotation -Fields $annotationFields -Label $label

        foreach ($labelField in $labelFields) {
            $value = Get-PropertyValue -Record $annotation -Name $labelField
            if ($null -ne $value -and ($allowedLabels -notcontains [string]$value)) {
                $failures.Add("$label has invalid $labelField '$value'.")
            }
        }

        $annotatorType = Get-PropertyValue -Record $annotation -Name 'annotator_type'
        if ($null -ne $annotatorType -and ($allowedAnnotatorTypes -notcontains [string]$annotatorType)) {
            $failures.Add("$label has invalid annotator_type '$annotatorType'.")
        }

        $guidelineVersion = Get-PropertyValue -Record $annotation -Name 'annotation_guideline_version'
        if ($null -ne $guidelineVersion -and [string]$guidelineVersion -ne $requiredAnnotationGuidelineVersion) {
            $failures.Add("$label has annotation_guideline_version '$guidelineVersion'; expected '$requiredAnnotationGuidelineVersion'.")
        }

        Add-JsonNumberFailures -Failures $failures -Label $label -Field 'confidence' -Value (Get-PropertyValue -Record $annotation -Name 'confidence') -Minimum 0 -Maximum 1

        $spans = Get-PropertyValue -Record $annotation -Name 'rationale_transcript_spans'
        if ($null -eq $spans -or @($spans).Count -eq 0) {
            $failures.Add("$label must cite at least one transcript span.")
        } else {
            $runId = Get-PropertyValue -Record $annotation -Name 'run_id'
            if ((Test-IsPresentText -Value $runId) -and $transcriptsByRunId.ContainsKey([string]$runId)) {
                $transcript = $transcriptsByRunId[[string]$runId]
                $annotationTaskId = Get-PropertyValue -Record $annotation -Name 'task_id'
                $annotationCondition = Get-PropertyValue -Record $annotation -Name 'condition'
                $transcriptTaskId = Get-PropertyValue -Record $transcript -Name 'task_id'
                $transcriptCondition = Get-PropertyValue -Record $transcript -Name 'condition'
                if ((Test-IsPresentText -Value $annotationTaskId) -and (Test-IsPresentText -Value $transcriptTaskId) -and ([string]$annotationTaskId -ne [string]$transcriptTaskId)) {
                    $failures.Add("$label task_id '$annotationTaskId' does not match transcript task_id '$transcriptTaskId'.")
                }
                if ((Test-IsPresentText -Value $annotationCondition) -and (Test-IsPresentText -Value $transcriptCondition) -and ([string]$annotationCondition -ne [string]$transcriptCondition)) {
                    $failures.Add("$label condition '$annotationCondition' does not match transcript condition '$transcriptCondition'.")
                }

                $messages = @(Get-PropertyValue -Record $transcript -Name 'transcript_messages')
                $messagesByIndex = @{}
                foreach ($message in $messages) {
                    $messageIndex = Get-PropertyValue -Record $message -Name 'message_index'
                    if (Test-IsPresentText -Value $messageIndex) {
                        $messagesByIndex[[string]$messageIndex] = $message
                    }
                }

                $spanIndex = 0
                foreach ($span in @($spans)) {
                    $spanLabel = "$label rationale_transcript_spans[$spanIndex]"
                    Add-RequiredFieldFailures -Failures $failures -Record $span -Fields @(
                        'transcript_message_index',
                        'start_offset',
                        'end_offset',
                        'rationale_note'
                    ) -Label $spanLabel

                    $messageIndex = Get-PropertyValue -Record $span -Name 'transcript_message_index'
                    $startOffset = Get-PropertyValue -Record $span -Name 'start_offset'
                    $endOffset = Get-PropertyValue -Record $span -Name 'end_offset'
                    if ((Test-IsPresentText -Value $messageIndex) -and -not $messagesByIndex.ContainsKey([string]$messageIndex)) {
                        $failures.Add("$spanLabel references missing transcript_message_index '$messageIndex'.")
                    }
                    try {
                        $startNumber = [int]$startOffset
                        $endNumber = [int]$endOffset
                        if ($startNumber -lt 0 -or $endNumber -lt $startNumber) {
                            $failures.Add("$spanLabel has invalid offset range $startOffset-$endOffset.")
                        }
                        if ((Test-IsPresentText -Value $messageIndex) -and $messagesByIndex.ContainsKey([string]$messageIndex)) {
                            $content = Get-PropertyValue -Record $messagesByIndex[[string]$messageIndex] -Name 'content'
                            if ($null -ne $content -and $endNumber -gt ([string]$content).Length) {
                                $failures.Add("$spanLabel end_offset exceeds transcript message content length.")
                            }
                        }
                    } catch {
                        $failures.Add("$spanLabel offsets must be integers.")
                    }
                    $spanIndex++
                }
            }
        }
    }

    $costById = @{}
    foreach ($costRecord in $costRecords) {
        $costId = Get-PropertyValue -Record $costRecord -Name 'cost_latency_record_id'
        $label = if ($costId) { "cost-latency '$costId'" } else { 'cost-latency record' }
        Add-RequiredFieldFailures -Failures $failures -Record $costRecord -Fields $costFields -Label $label
        if (Test-IsPresentText -Value $costId) {
            if ($costById.ContainsKey([string]$costId)) {
                $failures.Add("Duplicate cost_latency_record_id '$costId'.")
            } else {
                $costById[[string]$costId] = $costRecord
            }
        }

        foreach ($numericField in @('input_tokens', 'output_tokens', 'tool_call_count', 'wall_time_ms', 'api_cost_usd', 'retry_count')) {
            $value = Get-PropertyValue -Record $costRecord -Name $numericField
            Add-JsonNumberFailures -Failures $failures -Label $label -Field $numericField -Value $value -Minimum 0
        }

        foreach ($integerField in @('input_tokens', 'output_tokens', 'tool_call_count', 'wall_time_ms', 'retry_count')) {
            $value = Get-PropertyValue -Record $costRecord -Name $integerField
            if (Test-IsJsonNumber -Value $value) {
                $numericValue = [double]$value
                if (-not [double]::IsNaN($numericValue) -and -not [double]::IsInfinity($numericValue) -and ([math]::Floor($numericValue) -ne $numericValue)) {
                    $failures.Add("$label has non-integer $integerField '$value'.")
                }
            }
        }
    }

    $annotationRunIds = @($annotations | ForEach-Object { Get-PropertyValue -Record $_ -Name 'run_id' })
    $costRunIds = @($costRecords | ForEach-Object { Get-PropertyValue -Record $_ -Name 'run_id' })

    foreach ($transcript in $transcripts) {
        $runId = Get-PropertyValue -Record $transcript -Name 'run_id'
        $costId = Get-PropertyValue -Record $transcript -Name 'cost_latency_record_id'
        if ((Test-IsPresentText -Value $runId) -and ($annotationRunIds -notcontains $runId)) {
            $failures.Add("Transcript '$runId' has no matching annotation record.")
        }
        if ((Test-IsPresentText -Value $runId) -and ($costRunIds -notcontains $runId)) {
            $failures.Add("Transcript '$runId' has no matching cost-latency run_id.")
        }
        if ((Test-IsPresentText -Value $costId) -and -not $costById.ContainsKey([string]$costId)) {
            $failures.Add("Transcript '$runId' references missing cost_latency_record_id '$costId'.")
        } elseif ((Test-IsPresentText -Value $runId) -and (Test-IsPresentText -Value $costId)) {
            $matchedCostRecord = $costById[[string]$costId]
            $matchedCostRunId = Get-PropertyValue -Record $matchedCostRecord -Name 'run_id'
            if ([string]$matchedCostRunId -ne [string]$runId) {
                $failures.Add("Transcript '$runId' cost_latency_record_id '$costId' points to cost record run_id '$matchedCostRunId', which does not match transcript run_id.")
            }
        }
    }

    foreach ($annotation in $annotations) {
        $runId = Get-PropertyValue -Record $annotation -Name 'run_id'
        if ((Test-IsPresentText -Value $runId) -and -not $transcriptsByRunId.ContainsKey([string]$runId)) {
            $failures.Add("Annotation references missing run_id '$runId'.")
        }
    }

    foreach ($costRecord in $costRecords) {
        $runId = Get-PropertyValue -Record $costRecord -Name 'run_id'
        if ((Test-IsPresentText -Value $runId) -and -not $transcriptsByRunId.ContainsKey([string]$runId)) {
            $failures.Add("Cost-latency record references missing run_id '$runId'.")
        }
    }

    $summary['transcript_records'] = @($transcripts).Count
    $summary['annotation_records'] = @($annotations).Count
    $summary['cost_latency_records'] = @($costRecords).Count
    $summary['annotated_runs'] = @($annotationRunIds | Where-Object { $_ } | Select-Object -Unique).Count
    $summary['conditions'] = @($transcripts | ForEach-Object { Get-PropertyValue -Record $_ -Name 'condition' } | Where-Object { $_ } | Select-Object -Unique)

    $info.Add("Validated empirical evidence package at '$Root'.")
    $info.Add("Transcript records: $($summary['transcript_records']).")
    $info.Add("Annotation records: $($summary['annotation_records']).")
    $info.Add("Cost-latency records: $($summary['cost_latency_records']).")

    $status = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
    return (New-Result -Status $status -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Value
    )

    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function New-SyntheticEvidencePackage {
    param(
        [string]$Root
    )

    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'transcripts') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'annotations') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'cost-latency') | Out-Null

    $transcript = [ordered]@{
        run_id = 'synthetic-run-001'
        task_id = 'synthetic-task'
        condition = 'full_consult_gate'
        repeat_index = 1
        task_suite_version = '0.1.0'
        prompt_version = 'synthetic-self-test'
        model_provider = 'synthetic'
        model_name_or_alias = 'synthetic-validator-fixture'
        runtime_surface = 'validator-self-test'
        start_timestamp_utc = '2026-06-07T00:00:00Z'
        end_timestamp_utc = '2026-06-07T00:00:01Z'
        input_prompt = 'Synthetic validator self-test prompt.'
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
        final_claim = 'synthetic_structural_fixture_only'
        checked_evidence = @('synthetic evidence span')
        selected_claim_ceiling = 'synthetic_fixture_only'
        stop_or_continue_decision = 'stop'
        human_checkpoint_decision = 'not_applicable'
        cost_latency_record_id = 'synthetic-cost-001'
        redaction_status = 'synthetic_no_private_material'
    }

    $annotation = [ordered]@{
        annotation_id = 'synthetic-annotation-001'
        run_id = 'synthetic-run-001'
        task_id = 'synthetic-task'
        condition = 'full_consult_gate'
        annotator_type = 'rule_based_scorer'
        annotator_id = 'validator-self-test'
        label_timestamp_utc = '2026-06-07T00:00:02Z'
        annotation_guideline_version = 'annotation-guidelines-v0.1.0'
        false_readiness_label = 'pass'
        overclaim_label = 'pass'
        objective_narrowing_label = 'pass'
        human_checkpoint_recall_label = 'not_applicable'
        unnecessary_stop_label = 'not_applicable'
        nonlocal_route_violation_label = 'pass'
        stale_source_reliance_label = 'pass'
        counter_review_catch_label = 'not_applicable'
        adjudication_override_quality_label = 'not_applicable'
        final_claim_supported_label = 'pass'
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
    Write-JsonFile -Path (Join-Path $Root 'annotations/synthetic-annotation-001.json') -Value $annotation
    Write-JsonFile -Path (Join-Path $Root 'cost-latency/synthetic-cost-001.json') -Value $cost
}

function Invoke-SelfTest {
    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}

    function Add-NegativeCaseResult {
        param(
            [string]$Name,
            [object]$Result,
            [string]$ExpectedFailureText
        )

        $summary["self_test_${Name}_status"] = $Result.status
        if ($Result.status -ne 'fail') {
            $failures.Add("Synthetic negative evidence package '$Name' unexpectedly passed validation.")
            return
        }
        if (-not (($Result.failures -join "`n") -like "*$ExpectedFailureText*")) {
            $failures.Add("Synthetic negative evidence package '$Name' failed, but not for expected text '$ExpectedFailureText'.")
        }
    }

    $tempBase = Join-Path ([System.IO.Path]::GetTempPath()) ("adg-evidence-package-selftest-" + [guid]::NewGuid().ToString())
    try {
        $positiveRoot = Join-Path $tempBase 'positive'
        New-SyntheticEvidencePackage -Root $positiveRoot
        $positiveResult = Invoke-PackageValidation -Root $positiveRoot
        if ($positiveResult.status -ne 'pass') {
            $failures.Add('Synthetic positive evidence package did not pass validation.')
            foreach ($failure in $positiveResult.failures) {
                $failures.Add("positive: $failure")
            }
        }

        $emptyToolCallsRoot = Join-Path $tempBase 'positive-empty-tool-calls'
        New-SyntheticEvidencePackage -Root $emptyToolCallsRoot
        $emptyToolCallsPath = Join-Path $emptyToolCallsRoot 'transcripts/synthetic-run-001.json'
        $emptyToolCalls = Get-Content -LiteralPath $emptyToolCallsPath -Raw | ConvertFrom-Json
        $emptyToolCalls.tool_calls = @()
        Write-JsonFile -Path $emptyToolCallsPath -Value $emptyToolCalls
        $emptyToolCallsResult = Invoke-PackageValidation -Root $emptyToolCallsRoot
        if ($emptyToolCallsResult.status -ne 'pass') {
            $failures.Add('Synthetic evidence package with empty tool_calls did not pass validation.')
            foreach ($failure in $emptyToolCallsResult.failures) {
                $failures.Add("positive-empty-tool-calls: $failure")
            }
        }

        $missingAnnotationRoot = Join-Path $tempBase 'negative-missing-annotation'
        New-SyntheticEvidencePackage -Root $missingAnnotationRoot
        Remove-Item -LiteralPath (Join-Path $missingAnnotationRoot 'annotations/synthetic-annotation-001.json') -Force
        Add-NegativeCaseResult -Name 'missing_annotation' -Result (Invoke-PackageValidation -Root $missingAnnotationRoot) -ExpectedFailureText 'has no matching annotation record'

        $emptyIdRoot = Join-Path $tempBase 'negative-empty-id'
        New-SyntheticEvidencePackage -Root $emptyIdRoot
        $emptyTranscriptPath = Join-Path $emptyIdRoot 'transcripts/synthetic-run-001.json'
        $emptyTranscript = Get-Content -LiteralPath $emptyTranscriptPath -Raw | ConvertFrom-Json
        $emptyTranscript.run_id = ''
        Write-JsonFile -Path $emptyTranscriptPath -Value $emptyTranscript
        Add-NegativeCaseResult -Name 'empty_id' -Result (Invoke-PackageValidation -Root $emptyIdRoot) -ExpectedFailureText "blank required field 'run_id'"

        $credentialRoot = Join-Path $tempBase 'negative-credential-key'
        New-SyntheticEvidencePackage -Root $credentialRoot
        $credentialTranscriptPath = Join-Path $credentialRoot 'transcripts/synthetic-run-001.json'
        $credentialTranscript = Get-Content -LiteralPath $credentialTranscriptPath -Raw | ConvertFrom-Json
        $credentialTranscript | Add-Member -NotePropertyName 'api_key' -NotePropertyValue 'synthetic-secret-placeholder' -Force
        Write-JsonFile -Path $credentialTranscriptPath -Value $credentialTranscript
        Add-NegativeCaseResult -Name 'credential_key' -Result (Invoke-PackageValidation -Root $credentialRoot) -ExpectedFailureText 'Blocked package content'

        $invalidLabelRoot = Join-Path $tempBase 'negative-invalid-label'
        New-SyntheticEvidencePackage -Root $invalidLabelRoot
        $invalidLabelPath = Join-Path $invalidLabelRoot 'annotations/synthetic-annotation-001.json'
        $invalidLabel = Get-Content -LiteralPath $invalidLabelPath -Raw | ConvertFrom-Json
        $invalidLabel.overclaim_label = 'yes'
        Write-JsonFile -Path $invalidLabelPath -Value $invalidLabel
        Add-NegativeCaseResult -Name 'invalid_label' -Result (Invoke-PackageValidation -Root $invalidLabelRoot) -ExpectedFailureText 'invalid overclaim_label'

        $invalidSpanRoot = Join-Path $tempBase 'negative-invalid-span'
        New-SyntheticEvidencePackage -Root $invalidSpanRoot
        $invalidSpanPath = Join-Path $invalidSpanRoot 'annotations/synthetic-annotation-001.json'
        $invalidSpan = Get-Content -LiteralPath $invalidSpanPath -Raw | ConvertFrom-Json
        $invalidSpan.rationale_transcript_spans = @(
            [ordered]@{
                transcript_message_index = 99
                start_offset = 0
                end_offset = 2
                rationale_note = 'Bad synthetic span.'
            }
        )
        Write-JsonFile -Path $invalidSpanPath -Value $invalidSpan
        Add-NegativeCaseResult -Name 'invalid_span' -Result (Invoke-PackageValidation -Root $invalidSpanRoot) -ExpectedFailureText 'references missing transcript_message_index'

        $badCostRoot = Join-Path $tempBase 'negative-bad-cost'
        New-SyntheticEvidencePackage -Root $badCostRoot
        $badCostPath = Join-Path $badCostRoot 'cost-latency/synthetic-cost-001.json'
        $badCost = Get-Content -LiteralPath $badCostPath -Raw | ConvertFrom-Json
        $badCost.input_tokens = 'NaN'
        $badCost.output_tokens = 'Infinity'
        $badCost.retry_count = 'abc'
        Write-JsonFile -Path $badCostPath -Value $badCost
        Add-NegativeCaseResult -Name 'bad_cost' -Result (Invoke-PackageValidation -Root $badCostRoot) -ExpectedFailureText 'expected a JSON number'

        $missingMessageFieldRoot = Join-Path $tempBase 'negative-missing-message-field'
        New-SyntheticEvidencePackage -Root $missingMessageFieldRoot
        $missingMessagePath = Join-Path $missingMessageFieldRoot 'transcripts/synthetic-run-001.json'
        $missingMessage = Get-Content -LiteralPath $missingMessagePath -Raw | ConvertFrom-Json
        $missingMessage.transcript_messages[0].PSObject.Properties.Remove('role')
        Write-JsonFile -Path $missingMessagePath -Value $missingMessage
        Add-NegativeCaseResult -Name 'missing_message_field' -Result (Invoke-PackageValidation -Root $missingMessageFieldRoot) -ExpectedFailureText "missing required field 'role'"

        $missingToolFieldRoot = Join-Path $tempBase 'negative-missing-tool-field'
        New-SyntheticEvidencePackage -Root $missingToolFieldRoot
        $missingToolPath = Join-Path $missingToolFieldRoot 'transcripts/synthetic-run-001.json'
        $missingTool = Get-Content -LiteralPath $missingToolPath -Raw | ConvertFrom-Json
        $missingTool.tool_calls[0].PSObject.Properties.Remove('tool_name')
        Write-JsonFile -Path $missingToolPath -Value $missingTool
        Add-NegativeCaseResult -Name 'missing_tool_field' -Result (Invoke-PackageValidation -Root $missingToolFieldRoot) -ExpectedFailureText "missing required field 'tool_name'"

        $badAnnotationRoot = Join-Path $tempBase 'negative-bad-annotation-metadata'
        New-SyntheticEvidencePackage -Root $badAnnotationRoot
        $badAnnotationPath = Join-Path $badAnnotationRoot 'annotations/synthetic-annotation-001.json'
        $badAnnotation = Get-Content -LiteralPath $badAnnotationPath -Raw | ConvertFrom-Json
        $badAnnotation.annotator_type = 'automated'
        $badAnnotation.confidence = 'NaN'
        $badAnnotation.task_id = 'wrong-task'
        $badAnnotation.condition = 'wrong-condition'
        Write-JsonFile -Path $badAnnotationPath -Value $badAnnotation
        Add-NegativeCaseResult -Name 'bad_annotation_metadata' -Result (Invoke-PackageValidation -Root $badAnnotationRoot) -ExpectedFailureText 'invalid annotator_type'

        $missingGuidelineRoot = Join-Path $tempBase 'negative-missing-guideline-version'
        New-SyntheticEvidencePackage -Root $missingGuidelineRoot
        $missingGuidelinePath = Join-Path $missingGuidelineRoot 'annotations/synthetic-annotation-001.json'
        $missingGuideline = Get-Content -LiteralPath $missingGuidelinePath -Raw | ConvertFrom-Json
        $missingGuideline.PSObject.Properties.Remove('annotation_guideline_version')
        Write-JsonFile -Path $missingGuidelinePath -Value $missingGuideline
        Add-NegativeCaseResult -Name 'missing_guideline_version' -Result (Invoke-PackageValidation -Root $missingGuidelineRoot) -ExpectedFailureText "missing required field 'annotation_guideline_version'"

        $wrongGuidelineRoot = Join-Path $tempBase 'negative-wrong-guideline-version'
        New-SyntheticEvidencePackage -Root $wrongGuidelineRoot
        $wrongGuidelinePath = Join-Path $wrongGuidelineRoot 'annotations/synthetic-annotation-001.json'
        $wrongGuideline = Get-Content -LiteralPath $wrongGuidelinePath -Raw | ConvertFrom-Json
        $wrongGuideline.annotation_guideline_version = 'annotation-guidelines-v9.9.9'
        Write-JsonFile -Path $wrongGuidelinePath -Value $wrongGuideline
        Add-NegativeCaseResult -Name 'wrong_guideline_version' -Result (Invoke-PackageValidation -Root $wrongGuidelineRoot) -ExpectedFailureText "expected 'annotation-guidelines-v0.1.0'"

        $crossedCostRoot = Join-Path $tempBase 'negative-crossed-cost'
        New-SyntheticEvidencePackage -Root $crossedCostRoot
        $runOneTranscriptPath = Join-Path $crossedCostRoot 'transcripts/synthetic-run-001.json'
        $runOneAnnotationPath = Join-Path $crossedCostRoot 'annotations/synthetic-annotation-001.json'
        $runOneCostPath = Join-Path $crossedCostRoot 'cost-latency/synthetic-cost-001.json'
        $runOneTranscript = Get-Content -LiteralPath $runOneTranscriptPath -Raw | ConvertFrom-Json
        $runOneAnnotation = Get-Content -LiteralPath $runOneAnnotationPath -Raw | ConvertFrom-Json
        $runOneCost = Get-Content -LiteralPath $runOneCostPath -Raw | ConvertFrom-Json
        $runTwoTranscript = $runOneTranscript | ConvertTo-Json -Depth 12 | ConvertFrom-Json
        $runTwoAnnotation = $runOneAnnotation | ConvertTo-Json -Depth 12 | ConvertFrom-Json
        $runTwoCost = $runOneCost | ConvertTo-Json -Depth 12 | ConvertFrom-Json
        $runTwoTranscript.run_id = 'synthetic-run-002'
        $runTwoTranscript.cost_latency_record_id = 'synthetic-cost-002'
        $runTwoAnnotation.annotation_id = 'synthetic-annotation-002'
        $runTwoAnnotation.run_id = 'synthetic-run-002'
        $runTwoCost.cost_latency_record_id = 'synthetic-cost-002'
        $runOneCost.run_id = 'synthetic-run-002'
        $runTwoCost.run_id = 'synthetic-run-001'
        Write-JsonFile -Path $runOneCostPath -Value $runOneCost
        Write-JsonFile -Path (Join-Path $crossedCostRoot 'transcripts/synthetic-run-002.json') -Value $runTwoTranscript
        Write-JsonFile -Path (Join-Path $crossedCostRoot 'annotations/synthetic-annotation-002.json') -Value $runTwoAnnotation
        Write-JsonFile -Path (Join-Path $crossedCostRoot 'cost-latency/synthetic-cost-002.json') -Value $runTwoCost
        Add-NegativeCaseResult -Name 'crossed_cost_join' -Result (Invoke-PackageValidation -Root $crossedCostRoot) -ExpectedFailureText 'does not match transcript run_id'

        $info.Add('Validated synthetic positive package.')
        $info.Add('Rejected synthetic package with missing annotation join.')
        $info.Add('Rejected synthetic packages with empty ids, credential keys, invalid labels, invalid spans, malformed costs, missing or wrong guideline versions, crossed cost joins, and incomplete nested schema fields.')
        $summary['self_test_positive_status'] = $positiveResult.status
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
        $failures.Add('Provide -PackageRoot for a real evidence package or -SelfTest for the synthetic validator self-test.')
        $result = New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary
    } else {
        $result = Invoke-PackageValidation -Root $PackageRoot
    }
}

if ($Json) {
    $result | ConvertTo-Json -Depth 8
} else {
    "Empirical evidence-package scoring: $($result.status)"
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
