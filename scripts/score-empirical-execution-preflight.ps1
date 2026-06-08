param(
    [string]$RunInputRoot,
    [string]$PreflightPath,
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

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Value
    )
    $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding UTF8
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

function Test-SameStringSet {
    param(
        [string[]]$Actual,
        [string[]]$Expected
    )
    $actualItems = @($Actual | Sort-Object -Unique)
    $expectedItems = @($Expected | Sort-Object -Unique)
    if ($actualItems.Count -ne $expectedItems.Count) {
        return $false
    }
    for ($index = 0; $index -lt $actualItems.Count; $index++) {
        if ($actualItems[$index] -ne $expectedItems[$index]) {
            return $false
        }
    }
    return $true
}

function Get-JsonArray {
    param(
        [object]$Value
    )
    if ($null -eq $Value) {
        return @()
    }
    if ($Value -is [array]) {
        return @($Value)
    }
    return @($Value)
}

function Test-ForbiddenJsonFields {
    param(
        [string]$RawJson,
        [string[]]$ForbiddenFields
    )
    $hits = New-Object System.Collections.Generic.List[string]
    foreach ($field in $ForbiddenFields) {
        if ([regex]::IsMatch($RawJson, '"' + [regex]::Escape($field) + '"\s*:')) {
            $hits.Add($field) | Out-Null
        }
    }
    return @($hits)
}

function Test-SensitiveText {
    param([string]$Text)
    $patterns = @(
        @{
            Label = 'absolute_windows_path'
            Pattern = '(?i)\b[A-Z]:\\[^\r\n`"]+'
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
            Label = 'private_key_marker'
            Pattern = '-----BEGIN [A-Z ]*PRIVATE KEY-----'
        }
    )
    $hits = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $patterns) {
        if ([regex]::IsMatch($Text, $entry.Pattern)) {
            $hits.Add($entry.Label) | Out-Null
        }
    }
    return @($hits)
}

function Invoke-RunInputScorer {
    param(
        [string]$PackageRoot,
        [string]$RepositoryRoot
    )
    $scorer = Join-Path $PSScriptRoot 'score-empirical-run-inputs.ps1'
    if (-not (Test-Path -LiteralPath $scorer)) {
        throw 'Missing score-empirical-run-inputs.ps1.'
    }
    $output = & $scorer -PackageRoot $PackageRoot -RepoRoot $RepositoryRoot -Json 2>&1
    if (-not $?) {
        throw "Run-input scorer failed before preflight scoring: $($output | Out-String)"
    }
}

function Invoke-PreflightValidation {
    param(
        [string]$Root,
        [string]$Path,
        [string]$RepositoryRoot
    )

    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}

    foreach ($requiredPath in @(
        (Join-Path $RepositoryRoot 'evals/empirical/execution-preflight-schema.yaml'),
        (Join-Path $RepositoryRoot 'docs/empirical-execution-preflight.md'),
        (Join-Path $RepositoryRoot 'scripts/build-empirical-execution-preflight.ps1')
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            $failures.Add("Missing repository artifact required for execution-preflight scoring: $requiredPath")
        }
    }
    foreach ($requiredPath in @(
        (Join-Path $Root 'run-inputs'),
        (Join-Path $Root 'metadata/run-input-manifest.json'),
        (Join-Path $Root 'metadata/task-suite-hash.json'),
        (Join-Path $Root 'metadata/prompt-pack-hash.json'),
        (Join-Path $Root 'metadata/experiment-manifest-hash.json')
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            $failures.Add("Missing run-input package artifact: $requiredPath")
        }
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        $failures.Add("Missing execution preflight record: $Path")
    }
    if ($failures.Count -gt 0) {
        return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
    }

    try {
        Invoke-RunInputScorer -PackageRoot $Root -RepositoryRoot $RepositoryRoot
    } catch {
        $failures.Add($_.Exception.Message)
        return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
    }

    $schemaText = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'evals/empirical/execution-preflight-schema.yaml') -Raw
    if ((Get-Scalar -Text $schemaText -Field 'claim_boundary') -ne 'execution_preflight_schema_only_no_model_api_calls') {
        $failures.Add('Execution preflight schema must declare execution_preflight_schema_only_no_model_api_calls.')
    }
    $requiredFields = Get-TopLevelList -Text $schemaText -Field 'required_fields'
    $forbiddenFields = Get-TopLevelList -Text $schemaText -Field 'forbidden_fields'
    $requiredNonclaims = Get-TopLevelList -Text $schemaText -Field 'current_nonclaims'
    $metadataRequirements = Get-TopLevelList -Text $schemaText -Field 'metadata_requirements'

    $rawPreflight = Get-Content -LiteralPath $Path -Raw
    foreach ($hit in (Test-ForbiddenJsonFields -RawJson $rawPreflight -ForbiddenFields $forbiddenFields)) {
        $failures.Add("Execution preflight must not contain forbidden field '$hit'.")
    }
    foreach ($hit in (Test-SensitiveText -Text $rawPreflight)) {
        $failures.Add("Execution preflight contains blocked sensitive pattern '$hit'.")
    }

    $preflight = $rawPreflight | ConvertFrom-Json
    $propertyNames = @($preflight.PSObject.Properties.Name)
    foreach ($field in $requiredFields) {
        if ($propertyNames -notcontains $field) {
            $failures.Add("Execution preflight is missing required field '$field'.")
            continue
        }
        $value = $preflight.$field
        if ($null -eq $value) {
            $failures.Add("Execution preflight required field '$field' is null.")
        } elseif ($value -is [string] -and [string]::IsNullOrWhiteSpace($value)) {
            $failures.Add("Execution preflight required field '$field' is blank.")
        } elseif ($value -is [array] -and $value.Count -eq 0) {
            $failures.Add("Execution preflight required field '$field' is empty.")
        }
    }

    if ($preflight.claim_boundary -ne 'execution_preflight_only_no_model_api_calls') {
        $failures.Add('Execution preflight must declare execution_preflight_only_no_model_api_calls.')
    }
    if ($preflight.execution_mode -ne 'preflight_only_no_model_api_call') {
        $failures.Add('Execution preflight execution_mode must be preflight_only_no_model_api_call.')
    }
    if ($preflight.budget_recorded_before_execution -ne $true) {
        $failures.Add('Execution preflight must record budget_recorded_before_execution: true.')
    }
    if (-not ($preflight.max_budget_usd -is [ValueType]) -or [double]$preflight.max_budget_usd -le 0) {
        $failures.Add('Execution preflight max_budget_usd must be a positive JSON number.')
    }
    foreach ($field in @('provider', 'model_name_or_alias', 'runtime_surface')) {
        $value = [string]$preflight.$field
        if ([string]::IsNullOrWhiteSpace($value)) {
            $failures.Add("Execution preflight $field must be nonblank.")
        } else {
            foreach ($hit in (Test-SensitiveText -Text $value)) {
                $failures.Add("Execution preflight $field contains blocked sensitive pattern '$hit'.")
            }
        }
    }

    $metadataPaths = @{
        task_suite_sha256 = Join-Path $Root 'metadata/task-suite-hash.json'
        prompt_pack_sha256 = Join-Path $Root 'metadata/prompt-pack-hash.json'
        manifest_sha256 = Join-Path $Root 'metadata/experiment-manifest-hash.json'
    }
    foreach ($entry in $metadataPaths.GetEnumerator()) {
        $expectedHash = (Get-Content -LiteralPath $entry.Value -Raw | ConvertFrom-Json).value
        if ($preflight.($entry.Key) -ne $expectedHash) {
            $failures.Add("Execution preflight $($entry.Key) does not match run-input metadata.")
        }
    }
    $expectedManifestHash = Get-FileHashHex -Path (Join-Path $Root 'metadata/run-input-manifest.json')
    if ($preflight.run_input_manifest_sha256 -ne $expectedManifestHash) {
        $failures.Add('Execution preflight run_input_manifest_sha256 does not match metadata/run-input-manifest.json.')
    }

    $runInputFiles = @(Get-ChildItem -LiteralPath (Join-Path $Root 'run-inputs') -File -Filter '*.json')
    $recordById = @{}
    foreach ($file in $runInputFiles) {
        $record = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        $recordById[[string]$record.run_input_id] = $record
    }

    $selectedIds = @(Get-JsonArray -Value $preflight.selected_run_input_ids | ForEach-Object { [string]$_ })
    $selectedIdSet = New-Object System.Collections.Generic.HashSet[string]
    $selectedRecords = New-Object System.Collections.Generic.List[object]
    foreach ($id in $selectedIds) {
        if (-not $selectedIdSet.Add($id)) {
            $failures.Add("Execution preflight selected_run_input_ids contains duplicate id '$id'.")
        }
        if (-not $recordById.ContainsKey($id)) {
            $failures.Add("Execution preflight selected_run_input_ids contains missing id '$id'.")
        } else {
            $selectedRecords.Add($recordById[$id]) | Out-Null
        }
    }
    if ([int]$preflight.selected_run_count -ne $selectedIds.Count) {
        $failures.Add("Execution preflight selected_run_count $($preflight.selected_run_count) does not match selected id count $($selectedIds.Count).")
    }
    $allConditions = @($recordById.Values | Select-Object -ExpandProperty condition -Unique)
    $recordsPerCondition = [int]$preflight.records_per_condition
    if ($recordsPerCondition -lt 1) {
        $failures.Add('Execution preflight records_per_condition must be at least 1.')
    }
    $expectedSelectionCount = $allConditions.Count * $recordsPerCondition
    if ($selectedIds.Count -ne $expectedSelectionCount) {
        $failures.Add("Execution preflight selected $($selectedIds.Count) records; expected $expectedSelectionCount from $($allConditions.Count) conditions and records_per_condition $recordsPerCondition.")
    }
    foreach ($condition in $allConditions) {
        $count = @($selectedRecords | Where-Object { $_.condition -eq $condition }).Count
        if ($count -ne $recordsPerCondition) {
            $failures.Add("Execution preflight selected $count record(s) for condition '$condition'; expected $recordsPerCondition.")
        }
        $expectedFirstIds = @(
            $recordById.Values |
                Where-Object { $_.condition -eq $condition } |
                Sort-Object task_id, repeat_index, run_input_id |
                Select-Object -First $recordsPerCondition |
                ForEach-Object { [string]$_.run_input_id }
        )
        $actualConditionIds = @(
            $selectedRecords |
                Where-Object { $_.condition -eq $condition } |
                Sort-Object task_id, repeat_index, run_input_id |
                ForEach-Object { [string]$_.run_input_id }
        )
        if (-not (Test-SameStringSet -Actual $actualConditionIds -Expected $expectedFirstIds)) {
            $failures.Add("Execution preflight selection for condition '$condition' does not match first_sorted_run_input_per_condition.")
        }
    }
    $selectedConditions = @(Get-JsonArray -Value $preflight.selected_conditions | ForEach-Object { [string]$_ })
    $expectedConditions = @($selectedRecords | Select-Object -ExpandProperty condition -Unique)
    if (-not (Test-SameStringSet -Actual $selectedConditions -Expected $expectedConditions)) {
        $failures.Add('Execution preflight selected_conditions does not match selected run-input records.')
    }
    $selectedTasks = @(Get-JsonArray -Value $preflight.selected_task_ids | ForEach-Object { [string]$_ })
    $expectedTasks = @($selectedRecords | Select-Object -ExpandProperty task_id -Unique)
    if (-not (Test-SameStringSet -Actual $selectedTasks -Expected $expectedTasks)) {
        $failures.Add('Execution preflight selected_task_ids does not match selected run-input records.')
    }
    if ($preflight.selection_strategy -ne 'first_sorted_run_input_per_condition') {
        $failures.Add('Execution preflight selection_strategy must be first_sorted_run_input_per_condition.')
    }

    foreach ($field in @('estimated_input_tokens', 'estimated_output_tokens', 'estimated_total_tokens')) {
        if (-not ($preflight.$field -is [ValueType]) -or [int]$preflight.$field -le 0) {
            $failures.Add("Execution preflight $field must be a positive JSON number.")
        }
    }
    if ([int]$preflight.estimated_total_tokens -ne ([int]$preflight.estimated_input_tokens + [int]$preflight.estimated_output_tokens)) {
        $failures.Add('Execution preflight estimated_total_tokens must equal estimated_input_tokens plus estimated_output_tokens.')
    }

    $stopGates = @(Get-JsonArray -Value $preflight.stop_gates_satisfied | ForEach-Object { [string]$_ })
    Assert-ListContains -Failures $failures -Items $stopGates -Required @(
        'no_private_repository_material',
        'prompts_frozen_before_execution',
        'condition_prompt_pack_available',
        'run_input_builder_available',
        'selected_run_inputs_exist',
        'provider_model_runtime_recorded',
        'budget_recorded_before_execution',
        'no_model_api_call_performed'
    ) -Label 'execution preflight stop_gates_satisfied'
    Assert-ListContains -Failures $failures -Items $stopGates -Required $metadataRequirements -Label 'execution preflight metadata stop_gates_satisfied'

    $nonclaims = @(Get-JsonArray -Value $preflight.current_nonclaims | ForEach-Object { [string]$_ })
    Assert-ListContains -Failures $failures -Items $nonclaims -Required $requiredNonclaims -Label 'execution preflight current_nonclaims'

    $summary['selected_run_count'] = $selectedIds.Count
    $summary['selected_condition_count'] = $selectedConditions.Count
    $summary['selected_task_count'] = $selectedTasks.Count
    $summary['max_budget_usd'] = $preflight.max_budget_usd
    $summary['estimated_total_tokens'] = $preflight.estimated_total_tokens
    $info.Add('Scored empirical execution preflight structure.')
    $info.Add("Checked $($selectedIds.Count) selected run-input id(s) against the generated run-input package.")

    $status = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
    return (New-Result -Status $status -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
}

function Assert-NegativeCase {
    param(
        [System.Collections.Generic.List[string]]$Failures,
        [string]$Name,
        [object]$Record,
        [string]$Path,
        [string]$Root,
        [string]$RepositoryRoot,
        [string]$ExpectedFailureText
    )
    Write-JsonFile -Path $Path -Value $Record
    $result = Invoke-PreflightValidation -Root $Root -Path $Path -RepositoryRoot $RepositoryRoot
    if ($result.status -eq 'pass') {
        $Failures.Add("Negative execution-preflight case '$Name' unexpectedly passed.")
        return
    }
    $failureText = ($result.failures -join "`n")
    if ($failureText -notlike "*$ExpectedFailureText*") {
        $Failures.Add("Negative execution-preflight case '$Name' failed, but not for expected text '$ExpectedFailureText'.")
    }
}

function Invoke-SelfTest {
    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}
    $tempBase = Join-Path ([System.IO.Path]::GetTempPath()) ("adg-execution-preflight-scorer-selftest-" + [guid]::NewGuid().ToString())
    try {
        $runInputRoot = Join-Path $tempBase 'run-inputs-package'
        $preflightPath = Join-Path $tempBase 'execution-preflight.json'
        $runInputBuilder = Join-Path $PSScriptRoot 'build-empirical-run-inputs.ps1'
        $preflightBuilder = Join-Path $PSScriptRoot 'build-empirical-execution-preflight.ps1'
        $buildOutput = & $runInputBuilder -OutputRoot $runInputRoot 2>&1
        if (-not $?) {
            $failures.Add("Run-input builder failed during execution-preflight scorer self-test: $($buildOutput | Out-String)")
            return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
        }
        $preflightOutput = & $preflightBuilder -RunInputRoot $runInputRoot -OutputPath $preflightPath -Provider 'self-test-provider' -ModelNameOrAlias 'self-test-model' -RuntimeSurface 'self-test-runtime' -MaxBudgetUsd 1.0 2>&1
        if (-not $?) {
            $failures.Add("Execution-preflight builder failed during scorer self-test: $($preflightOutput | Out-String)")
            return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
        }

        $positive = Invoke-PreflightValidation -Root $runInputRoot -Path $preflightPath -RepositoryRoot $RepoRoot
        if ($positive.status -ne 'pass') {
            $failures.Add("Positive execution-preflight self-test failed: $($positive.failures -join '; ')")
        } else {
            $summary['selected_run_count'] = $positive.summary.selected_run_count
            $summary['selected_condition_count'] = $positive.summary.selected_condition_count
        }

        $baseRecord = Get-Content -LiteralPath $preflightPath -Raw | ConvertFrom-Json

        Write-JsonFile -Path $preflightPath -Value $baseRecord
        $badBudget = Get-Content -LiteralPath $preflightPath -Raw | ConvertFrom-Json
        $badBudget.budget_recorded_before_execution = $false
        $badBudget.max_budget_usd = 0
        Assert-NegativeCase -Failures $failures -Name 'missing_budget' -Record $badBudget -Path $preflightPath -Root $runInputRoot -RepositoryRoot $RepoRoot -ExpectedFailureText 'budget_recorded_before_execution'

        Write-JsonFile -Path $preflightPath -Value $baseRecord
        $badId = Get-Content -LiteralPath $preflightPath -Raw | ConvertFrom-Json
        $ids = @(Get-JsonArray -Value $badId.selected_run_input_ids | ForEach-Object { [string]$_ })
        $ids[0] = 'ri-missing-run-input'
        $badId.selected_run_input_ids = @($ids)
        Assert-NegativeCase -Failures $failures -Name 'missing_run_input_id' -Record $badId -Path $preflightPath -Root $runInputRoot -RepositoryRoot $RepoRoot -ExpectedFailureText 'missing id'

        Write-JsonFile -Path $preflightPath -Value $baseRecord
        $badSelection = Get-Content -LiteralPath $preflightPath -Raw | ConvertFrom-Json
        $selectedIds = @(Get-JsonArray -Value $badSelection.selected_run_input_ids | ForEach-Object { [string]$_ })
        $selectedRecords = @($selectedIds | ForEach-Object { Get-Content -LiteralPath (Join-Path $runInputRoot "run-inputs/$_.json") -Raw | ConvertFrom-Json })
        $targetCondition = [string]$selectedRecords[0].condition
        $replacement = @(
            Get-ChildItem -LiteralPath (Join-Path $runInputRoot 'run-inputs') -File -Filter '*.json' |
                ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json } |
                Where-Object { $_.condition -eq $targetCondition -and $selectedIds -notcontains [string]$_.run_input_id } |
                Sort-Object task_id, repeat_index, run_input_id |
                Select-Object -First 1
        )
        if ($replacement.Count -eq 0) {
            $failures.Add('Self-test could not find a replacement run-input id for the non-first selection negative case.')
        } else {
            $selectedIds[0] = [string]$replacement[0].run_input_id
            $badSelection.selected_run_input_ids = @($selectedIds)
            Assert-NegativeCase -Failures $failures -Name 'non_first_sorted_selection' -Record $badSelection -Path $preflightPath -Root $runInputRoot -RepositoryRoot $RepoRoot -ExpectedFailureText 'first_sorted_run_input_per_condition'
        }

        Write-JsonFile -Path $preflightPath -Value $baseRecord
        $badTranscript = Get-Content -LiteralPath $preflightPath -Raw | ConvertFrom-Json
        $badTranscript | Add-Member -NotePropertyName 'transcript_messages' -NotePropertyValue @('not allowed') -Force
        Assert-NegativeCase -Failures $failures -Name 'transcript_field_injection' -Record $badTranscript -Path $preflightPath -Root $runInputRoot -RepositoryRoot $RepoRoot -ExpectedFailureText 'forbidden field'

        Write-JsonFile -Path $preflightPath -Value $baseRecord
        $badHash = Get-Content -LiteralPath $preflightPath -Raw | ConvertFrom-Json
        $badHash.task_suite_sha256 = ('0' * 64)
        Assert-NegativeCase -Failures $failures -Name 'metadata_hash_mutation' -Record $badHash -Path $preflightPath -Root $runInputRoot -RepositoryRoot $RepoRoot -ExpectedFailureText 'task_suite_sha256'

        Write-JsonFile -Path $preflightPath -Value $baseRecord
        $info.Add('Validated generated execution preflight record.')
        $info.Add('Rejected missing budget, missing run-input id, non-first sorted selection, transcript field injection, and metadata hash mutation cases.')
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
    if (-not $RunInputRoot -or -not $PreflightPath) {
        $failures = New-Object System.Collections.Generic.List[string]
        $warnings = New-Object System.Collections.Generic.List[string]
        $info = New-Object System.Collections.Generic.List[string]
        $summary = @{}
        $failures.Add('Provide -RunInputRoot and -PreflightPath, or use -SelfTest.')
        $result = New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary
    } else {
        $result = Invoke-PreflightValidation -Root $RunInputRoot -Path $PreflightPath -RepositoryRoot $RepoRoot
    }
}

if ($Json) {
    $result | ConvertTo-Json -Depth 20
} else {
    "Empirical execution preflight scoring: $($result.status)"
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
