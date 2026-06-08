param(
    [string]$PackageRoot,
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
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

function Get-FileHashHex {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

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

function Get-TopLevelList {
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

function Split-YamlEntries {
    param(
        [string[]]$Lines,
        [string]$StartPattern
    )
    $entries = New-Object System.Collections.Generic.List[object]
    $current = $null
    foreach ($line in $Lines) {
        if ($line -match $StartPattern) {
            if ($null -ne $current) {
                $entries.Add($current) | Out-Null
            }
            $current = New-Object System.Collections.Generic.List[string]
        }
        if ($null -ne $current) {
            $current.Add($line) | Out-Null
        }
    }
    if ($null -ne $current) {
        $entries.Add($current) | Out-Null
    }
    return @($entries | ForEach-Object { ,@($_.ToArray()) })
}

function Get-EntryScalar {
    param(
        [string[]]$EntryLines,
        [string]$Field
    )
    $pattern = "^\s+(?:-\s+)?$([regex]::Escape($Field)):\s*(.+?)\s*$"
    foreach ($line in $EntryLines) {
        if ($line -match $pattern) {
            return $Matches[1].Trim()
        }
    }
    return $null
}

function Get-EntryList {
    param(
        [string[]]$EntryLines,
        [string]$Field
    )
    $items = New-Object System.Collections.Generic.List[string]
    $inList = $false
    foreach ($line in $EntryLines) {
        if ($line -match "^\s+$([regex]::Escape($Field)):\s*$") {
            $inList = $true
            continue
        }
        if ($inList) {
            if ($line -match '^\s{4}\S' -and $line -notmatch '^\s{6}-\s+') {
                break
            }
            if ($line -match '^\s{6}-\s*(.+?)\s*$') {
                $items.Add($Matches[1].Trim()) | Out-Null
            }
        }
    }
    return @($items)
}

function Get-EntryBlock {
    param(
        [string[]]$EntryLines,
        [string]$Field
    )
    $items = New-Object System.Collections.Generic.List[string]
    $inBlock = $false
    foreach ($line in $EntryLines) {
        if ($line -match "^\s+$([regex]::Escape($Field)):\s*\|\s*$") {
            $inBlock = $true
            continue
        }
        if ($inBlock) {
            if ($line -match '^\s{4}\S') {
                break
            }
            if ($line -match '^\s{6}(.*)$') {
                $items.Add($Matches[1]) | Out-Null
            } elseif ($line.Trim().Length -eq 0) {
                $items.Add('') | Out-Null
            }
        }
    }
    return ($items -join "`n").Trim()
}

function Get-TaskDefinitions {
    param([string]$Path)
    $lines = Get-Content -LiteralPath $Path
    $entries = Split-YamlEntries -Lines $lines -StartPattern '^\s{2}-\s+id:\s*'
    return @($entries | ForEach-Object {
        [ordered]@{
            id = Get-EntryScalar -EntryLines $_ -Field 'id'
            family = Get-EntryScalar -EntryLines $_ -Field 'family'
            prompt = Get-EntryBlock -EntryLines $_ -Field 'prompt'
            expected_failure_modes = Get-EntryList -EntryLines $_ -Field 'expected_failure_modes'
            required_conditions = Get-EntryList -EntryLines $_ -Field 'required_conditions'
            forbidden_claims = Get-EntryList -EntryLines $_ -Field 'forbidden_claims'
        }
    })
}

function Get-ConditionPrompts {
    param([string]$Path)
    $lines = Get-Content -LiteralPath $Path
    $entries = Split-YamlEntries -Lines $lines -StartPattern '^\s{2}-\s+condition:\s*'
    return @($entries | ForEach-Object {
        [ordered]@{
            condition = Get-EntryScalar -EntryLines $_ -Field 'condition'
            prompt_version = Get-EntryScalar -EntryLines $_ -Field 'prompt_version'
            instruction = Get-EntryBlock -EntryLines $_ -Field 'instruction'
            expected_controls = Get-EntryList -EntryLines $_ -Field 'expected_controls'
        }
    })
}

function ConvertTo-SafeFileName {
    param([string]$Value)
    return ([regex]::Replace($Value, '[^a-zA-Z0-9_.-]', '-')).ToLowerInvariant()
}

function New-InputPrompt {
    param(
        [hashtable]$Task,
        [hashtable]$Condition,
        [string[]]$OutputFields
    )
    return @"
Task id: $($Task.id)
Task family: $($Task.family)

Task prompt:
$($Task.prompt)

Condition: $($Condition.condition)
Prompt version: $($Condition.prompt_version)

Condition instruction:
$($Condition.instruction)

Measurement output fields:
$($OutputFields -join ', ')

Privacy boundary:
Use only public synthetic or redacted fixtures. Do not include private paths, credentials, or unpublished private documents.
"@.Trim()
}

function Test-SameStringArray {
    param(
        [object]$Actual,
        [string[]]$Expected
    )
    $actualItems = @($Actual | ForEach-Object { [string]$_ })
    $expectedItems = @($Expected | ForEach-Object { [string]$_ })
    if ($actualItems.Count -ne $expectedItems.Count) {
        return $false
    }
    for ($index = 0; $index -lt $expectedItems.Count; $index++) {
        if ($actualItems[$index] -ne $expectedItems[$index]) {
            return $false
        }
    }
    return $true
}

function Assert-HasProperty {
    param(
        [System.Collections.Generic.List[string]]$Failures,
        [object]$Object,
        [string]$PropertyName,
        [string]$Label
    )
    if (-not ($Object.PSObject.Properties.Name -contains $PropertyName)) {
        $Failures.Add("$Label is missing required field '$PropertyName'.")
    }
}

function Invoke-RunInputScoring {
    param(
        [string]$Root,
        [string]$RepositoryRoot
    )

    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}

    foreach ($path in @(
        'evals/empirical/run-input-schema.yaml',
        'evals/empirical/agent-decision-gates-task-suite.yaml',
        'evals/empirical/condition-prompt-pack.yaml',
        'evals/empirical/experiment-run-manifest.yaml',
        'docs/empirical-run-inputs.md',
        'scripts/build-empirical-run-inputs.ps1'
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $RepositoryRoot $path))) {
            $failures.Add("Missing repository artifact required for run-input scoring: $path")
        }
    }
    foreach ($path in @(
        'run-inputs',
        'metadata/run-input-manifest.json',
        'metadata/task-suite-hash.json',
        'metadata/prompt-pack-hash.json',
        'metadata/experiment-manifest-hash.json',
        'metadata/builder-version.json'
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root $path))) {
            $failures.Add("Missing run-input package artifact: $path")
        }
    }
    if ($failures.Count -gt 0) {
        return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
    }

    $schema = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'evals/empirical/run-input-schema.yaml') -Raw
    if ((Get-Scalar -Text $schema -Field 'claim_boundary') -ne 'run_input_schema_only_no_model_execution') {
        $failures.Add('Run-input schema must declare run_input_schema_only_no_model_execution.')
    }
    $requiredFields = Get-TopLevelList -Text $schema -Field 'required_fields'

    $taskSuitePath = Join-Path $RepositoryRoot 'evals/empirical/agent-decision-gates-task-suite.yaml'
    $promptPackPath = Join-Path $RepositoryRoot 'evals/empirical/condition-prompt-pack.yaml'
    $manifestPath = Join-Path $RepositoryRoot 'evals/empirical/experiment-run-manifest.yaml'
    $taskSuiteText = Get-Content -LiteralPath $taskSuitePath -Raw
    $promptPackText = Get-Content -LiteralPath $promptPackPath -Raw
    $manifestText = Get-Content -LiteralPath $manifestPath -Raw
    $taskCount = ([regex]::Matches($taskSuiteText, '(?m)^\s{2}-\s+id:\s*')).Count
    $conditionCount = (Get-TopLevelList -Text $manifestText -Field 'conditions').Count
    $repeatCount = [int](Get-Scalar -Text $manifestText -Field 'planned_repeats_per_task_condition')
    $expectedRecords = $taskCount * $conditionCount * $repeatCount
    $summary['expected_records'] = $expectedRecords
    $taskSuiteVersion = Get-Scalar -Text $taskSuiteText -Field 'version'
    $promptPackVersion = Get-Scalar -Text $promptPackText -Field 'prompt_pack_version'
    $manifestVersion = Get-Scalar -Text $manifestText -Field 'version'
    $manifestConditions = Get-TopLevelList -Text $manifestText -Field 'conditions'
    $outputFields = Get-TopLevelList -Text $promptPackText -Field 'required_record_fields'
    $privacyBoundary = @(
        'public_synthetic_task_suite_only',
        'no_private_paths',
        'no_credentials',
        'no_unpublished_private_documents'
    )
    $taskDefinitions = Get-TaskDefinitions -Path $taskSuitePath
    $conditionDefinitions = Get-ConditionPrompts -Path $promptPackPath
    $taskMap = @{}
    foreach ($task in $taskDefinitions) {
        $taskMap[$task.id] = $task
    }
    $conditionMap = @{}
    foreach ($condition in $conditionDefinitions) {
        $conditionMap[$condition.condition] = $condition
    }
    $expectedIds = New-Object System.Collections.Generic.HashSet[string]
    foreach ($task in $taskDefinitions) {
        foreach ($conditionName in $manifestConditions) {
            if (-not $conditionMap.ContainsKey($conditionName)) {
                $failures.Add("Condition prompt pack is missing manifest condition '$conditionName'.")
                continue
            }
            for ($repeat = 1; $repeat -le $repeatCount; $repeat++) {
                $expectedIds.Add("ri-$((ConvertTo-SafeFileName -Value $task.id))-$((ConvertTo-SafeFileName -Value $conditionName))-r$repeat") | Out-Null
            }
        }
    }

    $packageManifest = Get-Content -LiteralPath (Join-Path $Root 'metadata/run-input-manifest.json') -Raw | ConvertFrom-Json
    $summary['manifest_generated_record_count'] = $packageManifest.generated_record_count
    if ([int]$packageManifest.generated_record_count -ne $expectedRecords) {
        $failures.Add("Run-input manifest record count $($packageManifest.generated_record_count) does not match expected $expectedRecords.")
    }
    foreach ($nonclaim in @(
        'no_model_api_eval_execution',
        'no_transcripts',
        'no_annotations',
        'no_cost_latency_results',
        'no_human_llm_judge_agreement_results',
        'no_empirical_results',
        'no_paper_readiness'
    )) {
        if ($packageManifest.current_nonclaims -notcontains $nonclaim) {
            $failures.Add("Run-input manifest is missing nonclaim '$nonclaim'.")
        }
    }

    $hashExpectations = @(
        @{ File = 'metadata/task-suite-hash.json'; Path = $taskSuitePath; Field = 'task_suite_sha256' },
        @{ File = 'metadata/prompt-pack-hash.json'; Path = $promptPackPath; Field = 'prompt_pack_sha256' },
        @{ File = 'metadata/experiment-manifest-hash.json'; Path = $manifestPath; Field = 'manifest_sha256' }
    )
    foreach ($hashExpectation in $hashExpectations) {
        $record = Get-Content -LiteralPath (Join-Path $Root $hashExpectation.File) -Raw | ConvertFrom-Json
        $actual = Get-FileHashHex -Path $hashExpectation.Path
        if ($record.value -ne $actual) {
            $failures.Add("$($hashExpectation.File) does not match current repository hash.")
        }
        $summary[$hashExpectation.Field] = $actual
    }

    $runInputFiles = @(Get-ChildItem -LiteralPath (Join-Path $Root 'run-inputs') -File -Filter '*.json')
    $summary['run_input_files'] = $runInputFiles.Count
    if ($runInputFiles.Count -ne $expectedRecords) {
        $failures.Add("Expected $expectedRecords run-input JSON files; found $($runInputFiles.Count).")
    }

    $ids = New-Object System.Collections.Generic.HashSet[string]
    $allowedFields = New-Object System.Collections.Generic.HashSet[string]
    foreach ($field in $requiredFields) {
        $allowedFields.Add($field) | Out-Null
    }
    foreach ($file in $runInputFiles) {
        try {
            $record = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        } catch {
            $failures.Add("Run-input file '$($file.Name)' is not valid JSON: $($_.Exception.Message)")
            continue
        }
        foreach ($propertyName in $record.PSObject.Properties.Name) {
            if (-not $allowedFields.Contains($propertyName)) {
                $failures.Add("$($file.Name) contains unexpected top-level field '$propertyName'.")
            }
        }
        foreach ($field in $requiredFields) {
            Assert-HasProperty -Failures $failures -Object $record -PropertyName $field -Label $file.Name
        }
        if ($record.run_input_id) {
            if (-not $ids.Add([string]$record.run_input_id)) {
                $failures.Add("Duplicate run_input_id '$($record.run_input_id)'.")
            }
            if (-not $expectedIds.Contains([string]$record.run_input_id)) {
                $failures.Add("$($file.Name) has unexpected run_input_id '$($record.run_input_id)'.")
            }
            if ($file.Name -ne "$($record.run_input_id).json") {
                $failures.Add("$($file.Name) does not match run_input_id '$($record.run_input_id)'.")
            }
        }
        if (-not $taskMap.ContainsKey([string]$record.task_id)) {
            $failures.Add("$($file.Name) has task_id '$($record.task_id)' that is not in the current task suite.")
        }
        if ($manifestConditions -notcontains [string]$record.condition) {
            $failures.Add("$($file.Name) has condition '$($record.condition)' that is not in the current manifest.")
        }
        if ($record.repeat_index -lt 1 -or $record.repeat_index -gt $repeatCount) {
            $failures.Add("$($file.Name) has repeat_index '$($record.repeat_index)' outside 1..$repeatCount.")
        }
        if ($taskMap.ContainsKey([string]$record.task_id) -and $conditionMap.ContainsKey([string]$record.condition)) {
            $expectedTask = $taskMap[[string]$record.task_id]
            $expectedCondition = $conditionMap[[string]$record.condition]
            $expectedRunInputId = "ri-$((ConvertTo-SafeFileName -Value $expectedTask.id))-$((ConvertTo-SafeFileName -Value $expectedCondition.condition))-r$($record.repeat_index)"
            if ($record.run_input_id -ne $expectedRunInputId) {
                $failures.Add("$($file.Name) run_input_id '$($record.run_input_id)' does not match expected '$expectedRunInputId'.")
            }
            if ($record.task_family -ne $expectedTask.family) {
                $failures.Add("$($file.Name) has task_family '$($record.task_family)' but expected '$($expectedTask.family)'.")
            }
            if ($record.task_prompt -ne $expectedTask.prompt) {
                $failures.Add("$($file.Name) has task_prompt that does not match the current task suite.")
            }
            if ($record.condition_instruction -ne $expectedCondition.instruction) {
                $failures.Add("$($file.Name) has condition_instruction that does not match the current condition prompt pack.")
            }
            $expectedInputPrompt = New-InputPrompt -Task $expectedTask -Condition $expectedCondition -OutputFields $outputFields
            if ($record.input_prompt -ne $expectedInputPrompt) {
                $failures.Add("$($file.Name) has input_prompt that does not match the builder contract.")
            }
            if (-not (Test-SameStringArray -Actual $record.expected_failure_modes -Expected $expectedTask.expected_failure_modes)) {
                $failures.Add("$($file.Name) expected_failure_modes do not match the current task suite.")
            }
            if (-not (Test-SameStringArray -Actual $record.required_conditions -Expected $expectedTask.required_conditions)) {
                $failures.Add("$($file.Name) required_conditions do not match the current task suite.")
            }
            if (-not (Test-SameStringArray -Actual $record.forbidden_claims -Expected $expectedTask.forbidden_claims)) {
                $failures.Add("$($file.Name) forbidden_claims do not match the current task suite.")
            }
        }
        if ($record.task_suite_version -ne $taskSuiteVersion) {
            $failures.Add("$($file.Name) has task_suite_version '$($record.task_suite_version)' but expected '$taskSuiteVersion'.")
        }
        if ($record.prompt_pack_version -ne $promptPackVersion) {
            $failures.Add("$($file.Name) has prompt_pack_version '$($record.prompt_pack_version)' but expected '$promptPackVersion'.")
        }
        if ($record.manifest_version -ne $manifestVersion) {
            $failures.Add("$($file.Name) has manifest_version '$($record.manifest_version)' but expected '$manifestVersion'.")
        }
        if (-not (Test-SameStringArray -Actual $record.output_record_fields -Expected $outputFields)) {
            $failures.Add("$($file.Name) output_record_fields do not match the current condition prompt pack.")
        }
        if (-not (Test-SameStringArray -Actual $record.privacy_boundary -Expected $privacyBoundary)) {
            $failures.Add("$($file.Name) privacy_boundary does not match the run-input contract.")
        }
        if ($record.task_suite_sha256 -ne $summary.task_suite_sha256) {
            $failures.Add("$($file.Name) has stale task_suite_sha256.")
        }
        if ($record.prompt_pack_sha256 -ne $summary.prompt_pack_sha256) {
            $failures.Add("$($file.Name) has stale prompt_pack_sha256.")
        }
        if ($record.manifest_sha256 -ne $summary.manifest_sha256) {
            $failures.Add("$($file.Name) has stale manifest_sha256.")
        }
        if ($record.redaction_status -ne 'public_synthetic_no_private_material') {
            $failures.Add("$($file.Name) has unexpected redaction_status '$($record.redaction_status)'.")
        }
    }
    foreach ($expectedId in $expectedIds) {
        if (-not $ids.Contains($expectedId)) {
            $failures.Add("Missing expected run_input_id '$expectedId'.")
        }
    }

    $combined = (Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.json' | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
    foreach ($blocked in @(
        'raw_transcript',
        'transcript_messages',
        'model_output',
        'model_response',
        'annotation_record',
        'annotation_id',
        'human_primary_labels',
        'llm_judge_labels_if_used',
        'cost_latency_record',
        'cost_latency_summary',
        'pass_rate',
        'win_rate',
        'p_value',
        'confidence_interval',
        'statistical_significance',
        'effectiveness_claim',
        'empirical_effectiveness_proven',
        'paper_ready',
        'production_ready'
    )) {
        if ([regex]::IsMatch($combined, "(?m)^\s*`"$([regex]::Escape($blocked))`"\s*:")) {
            $failures.Add("Run-input package must not contain result field '$blocked'.")
        }
    }
    foreach ($pattern in @(
        '(?i)\b[A-Z]:\\[^\r\n`"]+',
        '(?i)\bBearer\s+[A-Za-z0-9._~+/-]+=*',
        '(?i)\bgh[pousr]_[A-Za-z0-9_]{20,}',
        '(?i)\bsk-[A-Za-z0-9_-]{16,}',
        '\bAKIA[0-9A-Z]{16}\b',
        '-----BEGIN [A-Z ]*PRIVATE KEY-----'
    )) {
        if ([regex]::IsMatch($combined, $pattern)) {
            $failures.Add("Run-input package contains blocked sensitive pattern '$pattern'.")
        }
    }

    $info.Add('Scored empirical run-input package structure.')
    $info.Add("Checked $($runInputFiles.Count) run-input record(s).")
    $status = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
    return (New-Result -Status $status -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
}

function Invoke-SelfTest {
    $tempBase = Join-Path ([System.IO.Path]::GetTempPath()) ("adg-run-input-scorer-selftest-" + [guid]::NewGuid().ToString())
    try {
        $builder = Join-Path $PSScriptRoot 'build-empirical-run-inputs.ps1'
        $buildOutput = & $builder -OutputRoot $tempBase 2>&1
        if (-not $?) {
            $failures = New-Object System.Collections.Generic.List[string]
            $failures.Add("Run-input builder failed during scorer self-test: $($buildOutput | Out-String)")
            return (New-Result -Status 'fail' -Failures $failures -Warnings (New-Object System.Collections.Generic.List[string]) -Info (New-Object System.Collections.Generic.List[string]) -Summary @{})
        }
        $positive = Invoke-RunInputScoring -Root $tempBase -RepositoryRoot $RepoRoot
        if ($positive.status -ne 'pass') {
            return $positive
        }
        $firstInput = @(Get-ChildItem -LiteralPath (Join-Path $tempBase 'run-inputs') -File -Filter '*.json' | Select-Object -First 1)
        if ($firstInput.Count -eq 1) {
            $originalInputContent = Get-Content -LiteralPath $firstInput[0].FullName -Raw

            $mutatedInput = $originalInputContent | ConvertFrom-Json
            $mutatedInput.task_id = 'not_in_task_suite'
            $mutatedInput | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $firstInput[0].FullName -Encoding UTF8
            $negativeWrongTask = Invoke-RunInputScoring -Root $tempBase -RepositoryRoot $RepoRoot
            Set-Content -LiteralPath $firstInput[0].FullName -Value $originalInputContent -Encoding UTF8

            $mutatedInput = $originalInputContent | ConvertFrom-Json
            $mutatedInput | Add-Member -NotePropertyName 'transcript_messages' -NotePropertyValue @() -Force
            $mutatedInput | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $firstInput[0].FullName -Encoding UTF8
            $negativeTranscriptField = Invoke-RunInputScoring -Root $tempBase -RepositoryRoot $RepoRoot
            Set-Content -LiteralPath $firstInput[0].FullName -Value $originalInputContent -Encoding UTF8

            $mutatedInput = $originalInputContent | ConvertFrom-Json
            $mutatedInput | Add-Member -NotePropertyName 'empirical_effectiveness_proven' -NotePropertyValue $true -Force
            $mutatedInput | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $firstInput[0].FullName -Encoding UTF8
            $negativeForbiddenField = Invoke-RunInputScoring -Root $tempBase -RepositoryRoot $RepoRoot
            Set-Content -LiteralPath $firstInput[0].FullName -Value $originalInputContent -Encoding UTF8

            $metadataManifestPath = Join-Path $tempBase 'metadata/run-input-manifest.json'
            $originalMetadataContent = Get-Content -LiteralPath $metadataManifestPath -Raw
            $mutatedMetadata = $originalMetadataContent | ConvertFrom-Json
            $mutatedMetadata | Add-Member -NotePropertyName 'empirical_effectiveness_proven' -NotePropertyValue $true -Force
            $mutatedMetadata | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $metadataManifestPath -Encoding UTF8
            $negativeMetadataForbiddenField = Invoke-RunInputScoring -Root $tempBase -RepositoryRoot $RepoRoot
            Set-Content -LiteralPath $metadataManifestPath -Value $originalMetadataContent -Encoding UTF8

            $mutatedMetadata = $originalMetadataContent | ConvertFrom-Json
            $mutatedMetadata | Add-Member -NotePropertyName 'debug_path' -NotePropertyValue ('X:' + '\ARD\private-material') -Force
            $mutatedMetadata | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $metadataManifestPath -Encoding UTF8
            $negativeMetadataSensitivePattern = Invoke-RunInputScoring -Root $tempBase -RepositoryRoot $RepoRoot
            Set-Content -LiteralPath $metadataManifestPath -Value $originalMetadataContent -Encoding UTF8

            Remove-Item -LiteralPath $firstInput[0].FullName -Force
        }
        $negative = Invoke-RunInputScoring -Root $tempBase -RepositoryRoot $RepoRoot
        $failures = New-Object System.Collections.Generic.List[string]
        $warnings = New-Object System.Collections.Generic.List[string]
        $info = New-Object System.Collections.Generic.List[string]
        $summary = @{}
        $summary['positive_status'] = $positive.status
        $summary['wrong_task_status'] = $negativeWrongTask.status
        $summary['transcript_field_status'] = $negativeTranscriptField.status
        $summary['forbidden_field_status'] = $negativeForbiddenField.status
        $summary['metadata_forbidden_field_status'] = $negativeMetadataForbiddenField.status
        $summary['metadata_sensitive_pattern_status'] = $negativeMetadataSensitivePattern.status
        $summary['negative_status'] = $negative.status
        $summary['expected_records'] = $positive.summary.expected_records
        if ($negativeWrongTask.status -ne 'fail') {
            $failures.Add('Scorer did not reject a package with a run-input task_id outside the current task suite.')
        }
        if ($negativeTranscriptField.status -ne 'fail') {
            $failures.Add('Scorer did not reject a package with a forbidden transcript_messages field.')
        }
        if ($negativeForbiddenField.status -ne 'fail') {
            $failures.Add('Scorer did not reject a package with a forbidden empirical_effectiveness_proven field.')
        }
        if ($negativeMetadataForbiddenField.status -ne 'fail') {
            $failures.Add('Scorer did not reject metadata with a forbidden empirical_effectiveness_proven field.')
        }
        if ($negativeMetadataSensitivePattern.status -ne 'fail') {
            $failures.Add('Scorer did not reject metadata with a blocked sensitive pattern.')
        }
        if ($negative.status -ne 'fail') {
            $failures.Add('Scorer did not reject a package with a missing run-input record.')
        }
        $info.Add('Validated generated run-input package.')
        $info.Add('Rejected package after task_id was changed outside the current task suite.')
        $info.Add('Rejected package after transcript_messages was injected.')
        $info.Add('Rejected package after empirical_effectiveness_proven was injected.')
        $info.Add('Rejected metadata after empirical_effectiveness_proven and a private-path pattern were injected.')
        $info.Add('Rejected package after one run-input record was removed.')
        $status = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
        return (New-Result -Status $status -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
    } finally {
        if (Test-Path -LiteralPath $tempBase) {
            Remove-Item -LiteralPath $tempBase -Recurse -Force
        }
    }
}

if ($SelfTest) {
    $result = Invoke-SelfTest
} elseif ($PackageRoot) {
    $result = Invoke-RunInputScoring -Root $PackageRoot -RepositoryRoot $RepoRoot
} else {
    $failures = New-Object System.Collections.Generic.List[string]
    $failures.Add('Provide -PackageRoot to score a run-input package or -SelfTest for the scorer self-test.')
    $result = New-Result -Status 'fail' -Failures $failures -Warnings (New-Object System.Collections.Generic.List[string]) -Info (New-Object System.Collections.Generic.List[string]) -Summary @{}
}

if ($Json) {
    $result | ConvertTo-Json -Depth 20
} else {
    "Empirical run-input scoring: $($result.status)"
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
