param(
    [string]$RunInputRoot,
    [string]$OutputPath,
    [string]$Provider,
    [string]$ModelNameOrAlias,
    [string]$RuntimeSurface,
    [double]$MaxBudgetUsd = -1,
    [int]$RecordsPerCondition = 1,
    [string[]]$TaskIds,
    [switch]$SelfTest,
    [switch]$Force,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

$PreflightVersion = '0.1.0'

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
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-FileHashHex {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-TokenEstimate {
    param([string]$Text)
    if (-not $Text) {
        return 0
    }
    return [int][math]::Ceiling(([string]$Text).Length / 4)
}

function Assert-OutputPathWritable {
    param(
        [string]$Path,
        [bool]$AllowOverwrite
    )
    if ((Test-Path -LiteralPath $Path) -and -not $AllowOverwrite) {
        throw 'OutputPath already exists. Use -Force to replace an existing preflight record.'
    }
}

function Get-NormalizedTaskIds {
    param([string[]]$RequestedTaskIds)
    $normalized = New-Object System.Collections.Generic.List[string]
    $seen = New-Object System.Collections.Generic.HashSet[string]
    foreach ($rawTaskId in @($RequestedTaskIds)) {
        foreach ($part in ([string]$rawTaskId -split ',')) {
            $taskId = ([string]$part).Trim()
            if ([string]::IsNullOrWhiteSpace($taskId)) {
                throw 'TaskIds entries must be nonblank when provided.'
            }
            if ($taskId -match '[\\/]') {
                throw "TaskIds entry '$taskId' cannot contain path separators."
            }
            if ($seen.Add($taskId)) {
                $normalized.Add($taskId) | Out-Null
            }
        }
    }
    return @($normalized.ToArray())
}

function New-ExecutionPreflight {
    param(
        [string]$InputRoot,
        [string]$Path,
        [string]$ModelProvider,
        [string]$ModelAlias,
        [string]$RuntimeName,
        [double]$BudgetUsd,
        [int]$PerCondition,
        [string[]]$RequestedTaskIds,
        [bool]$AllowOverwrite
    )

    if (-not (Test-Path -LiteralPath $InputRoot)) {
        throw "RunInputRoot not found: $InputRoot"
    }
    if (-not $ModelProvider) {
        throw 'Provider is required before execution preflight can be recorded.'
    }
    if (-not $ModelAlias) {
        throw 'ModelNameOrAlias is required before execution preflight can be recorded.'
    }
    if (-not $RuntimeName) {
        throw 'RuntimeSurface is required before execution preflight can be recorded.'
    }
    if ($BudgetUsd -le 0) {
        throw 'MaxBudgetUsd must be recorded as a positive value before execution preflight can be recorded.'
    }
    if ($PerCondition -lt 1) {
        throw 'RecordsPerCondition must be at least 1.'
    }
    Assert-OutputPathWritable -Path $Path -AllowOverwrite $AllowOverwrite

    $manifestPath = Join-Path $InputRoot 'metadata/run-input-manifest.json'
    $taskHashPath = Join-Path $InputRoot 'metadata/task-suite-hash.json'
    $promptHashPath = Join-Path $InputRoot 'metadata/prompt-pack-hash.json'
    $experimentHashPath = Join-Path $InputRoot 'metadata/experiment-manifest-hash.json'
    foreach ($requiredPath in @($manifestPath, $taskHashPath, $promptHashPath, $experimentHashPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Missing run-input metadata file: $requiredPath"
        }
    }

    $runInputFiles = @(Get-ChildItem -LiteralPath (Join-Path $InputRoot 'run-inputs') -File -Filter '*.json')
    if ($runInputFiles.Count -eq 0) {
        throw 'No run-input JSON files found.'
    }

    $records = @($runInputFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json })
    $normalizedTaskIds = @(Get-NormalizedTaskIds -RequestedTaskIds $RequestedTaskIds)
    $taskSelectionScope = 'all_tasks_first_sorted'
    $selectionStrategy = 'first_sorted_run_input_per_condition'
    if ($normalizedTaskIds.Count -gt 0) {
        $taskSelectionScope = 'requested_task_ids'
        $selectionStrategy = 'first_sorted_run_input_per_condition_per_requested_task'
        $knownTaskIds = @($records | Select-Object -ExpandProperty task_id -Unique)
        foreach ($taskId in $normalizedTaskIds) {
            if ($knownTaskIds -notcontains $taskId) {
                throw "TaskIds contains unknown task id '$taskId'."
            }
        }
    }

    $selected = New-Object System.Collections.Generic.List[object]
    $conditions = @($records | Sort-Object condition | Select-Object -ExpandProperty condition -Unique)
    if ($normalizedTaskIds.Count -gt 0) {
        foreach ($condition in $conditions) {
            foreach ($taskId in $normalizedTaskIds) {
                $conditionTaskRecords = @($records | Where-Object { $_.condition -eq $condition -and $_.task_id -eq $taskId } | Sort-Object repeat_index, run_input_id | Select-Object -First $PerCondition)
                if ($conditionTaskRecords.Count -lt $PerCondition) {
                    throw "Only found $($conditionTaskRecords.Count) run input(s) for task '$taskId' and condition '$condition'; expected $PerCondition."
                }
                foreach ($record in $conditionTaskRecords) {
                    $selected.Add($record) | Out-Null
                }
            }
        }
    } else {
        foreach ($condition in $conditions) {
            $conditionRecords = @($records | Where-Object { $_.condition -eq $condition } | Sort-Object task_id, repeat_index, run_input_id | Select-Object -First $PerCondition)
            foreach ($record in $conditionRecords) {
                $selected.Add($record) | Out-Null
            }
        }
    }
    if ($selected.Count -eq 0) {
        throw 'No run inputs were selected for execution preflight.'
    }

    $taskHash = (Get-Content -LiteralPath $taskHashPath -Raw | ConvertFrom-Json).value
    $promptHash = (Get-Content -LiteralPath $promptHashPath -Raw | ConvertFrom-Json).value
    $experimentHash = (Get-Content -LiteralPath $experimentHashPath -Raw | ConvertFrom-Json).value
    $manifestHash = Get-FileHashHex -Path $manifestPath
    $estimatedInputTokens = 0
    foreach ($record in $selected) {
        $estimatedInputTokens += Get-TokenEstimate -Text ([string]$record.input_prompt)
    }
    $estimatedOutputTokens = 800 * $selected.Count
    $preflight = [ordered]@{
        preflight_id = 'execution-preflight-v0.1.0'
        preflight_version = $PreflightVersion
        claim_boundary = 'execution_preflight_only_no_model_api_calls'
        run_input_package_root_label = 'local_generated_run_input_package'
        task_suite_sha256 = $taskHash
        prompt_pack_sha256 = $promptHash
        manifest_sha256 = $experimentHash
        run_input_manifest_sha256 = $manifestHash
        selected_run_input_ids = @($selected | Select-Object -ExpandProperty run_input_id)
        selected_run_count = $selected.Count
        selected_conditions = @($selected | Select-Object -ExpandProperty condition -Unique)
        selected_task_ids = @($selected | Select-Object -ExpandProperty task_id -Unique)
        task_selection_scope = $taskSelectionScope
        requested_task_ids = @($normalizedTaskIds)
        provider = $ModelProvider
        model_name_or_alias = $ModelAlias
        runtime_surface = $RuntimeName
        execution_mode = 'preflight_only_no_model_api_call'
        budget_recorded_before_execution = $true
        max_budget_usd = $BudgetUsd
        estimated_input_tokens = $estimatedInputTokens
        estimated_output_tokens = $estimatedOutputTokens
        estimated_total_tokens = $estimatedInputTokens + $estimatedOutputTokens
        records_per_condition = $PerCondition
        selection_strategy = $selectionStrategy
        stop_gates_satisfied = @(
            'no_private_repository_material',
            'prompts_frozen_before_execution',
            'run_input_builder_available',
            'condition_prompt_pack_available',
            'selected_run_inputs_exist',
            'source_run_input_manifest_hash_recorded',
            'task_suite_hash_recorded',
            'task_selection_scope_recorded',
            'provider_model_runtime_recorded',
            'budget_recorded_before_execution',
            'no_model_api_call_performed'
        )
        current_nonclaims = @(
            'no_model_api_eval_execution',
            'no_transcripts',
            'no_annotations',
            'no_cost_latency_results',
            'no_human_llm_judge_agreement_results',
            'no_aggregate_metrics',
            'no_statistical_results',
            'no_empirical_effectiveness_claim',
            'no_paper_readiness'
        )
    }

    Write-JsonFile -Path $Path -Value $preflight
    return [ordered]@{
        selected_run_count = $selected.Count
        selected_condition_count = @($preflight.selected_conditions).Count
        selected_task_count = @($preflight.selected_task_ids).Count
        task_selection_scope = $taskSelectionScope
        estimated_input_tokens = $estimatedInputTokens
        estimated_total_tokens = $preflight.estimated_total_tokens
        max_budget_usd = $BudgetUsd
    }
}

function Invoke-SelfTest {
    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}
    $tempBase = Join-Path ([System.IO.Path]::GetTempPath()) ("adg-execution-preflight-builder-selftest-" + [guid]::NewGuid().ToString())
    try {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $runInputRoot = Join-Path $tempBase 'run-inputs-package'
        $preflightPath = Join-Path $tempBase 'execution-preflight.json'
        $builder = Join-Path $PSScriptRoot 'build-empirical-run-inputs.ps1'
        $buildOutput = & $builder -OutputRoot $runInputRoot 2>&1
        if (-not $?) {
            $failures.Add("Run-input builder failed during execution-preflight self-test: $($buildOutput | Out-String)")
            return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
        }
        $summary = New-ExecutionPreflight -InputRoot $runInputRoot -Path $preflightPath -ModelProvider 'self-test-provider' -ModelAlias 'self-test-model' -RuntimeName 'self-test-runtime' -BudgetUsd 1.0 -PerCondition 1 -RequestedTaskIds @() -AllowOverwrite $false
        if ([int]$summary.selected_run_count -ne 9) {
            $failures.Add("Expected 9 selected run inputs; found $($summary.selected_run_count).")
        }
        if ([int]$summary.selected_condition_count -ne 9) {
            $failures.Add("Expected 9 selected conditions; found $($summary.selected_condition_count).")
        }
        $filteredPreflightPath = Join-Path $tempBase 'execution-preflight-task-filtered.json'
        $filteredSummary = New-ExecutionPreflight -InputRoot $runInputRoot -Path $filteredPreflightPath -ModelProvider 'self-test-provider' -ModelAlias 'self-test-model' -RuntimeName 'self-test-runtime' -BudgetUsd 1.0 -PerCondition 2 -RequestedTaskIds @('objective-narrowing-release-chain') -AllowOverwrite $false
        if ([int]$filteredSummary.selected_run_count -ne 18) {
            $failures.Add("Expected 18 selected requested-task run inputs; found $($filteredSummary.selected_run_count).")
        }
        if ([int]$filteredSummary.selected_task_count -ne 1) {
            $failures.Add("Expected 1 selected requested task; found $($filteredSummary.selected_task_count).")
        }
        $multiTaskPreflightPath = Join-Path $tempBase 'execution-preflight-multi-task-filtered.json'
        $multiTaskSummary = New-ExecutionPreflight -InputRoot $runInputRoot -Path $multiTaskPreflightPath -ModelProvider 'self-test-provider' -ModelAlias 'self-test-model' -RuntimeName 'self-test-runtime' -BudgetUsd 1.0 -PerCondition 2 -RequestedTaskIds @('objective-narrowing-release-chain,verifier-overclaim-single-green-check') -AllowOverwrite $false
        if ([int]$multiTaskSummary.selected_run_count -ne 36) {
            $failures.Add("Expected 36 selected comma-separated requested-task run inputs; found $($multiTaskSummary.selected_run_count).")
        }
        if ([int]$multiTaskSummary.selected_task_count -ne 2) {
            $failures.Add("Expected 2 selected comma-separated requested tasks; found $($multiTaskSummary.selected_task_count).")
        }
        $scorer = Join-Path $PSScriptRoot 'score-empirical-execution-preflight.ps1'
        if (Test-Path -LiteralPath $scorer) {
            $scoreOutput = & $scorer -RunInputRoot $runInputRoot -PreflightPath $preflightPath 2>&1
            if (-not $?) {
                $failures.Add("Execution-preflight scorer rejected the self-test preflight: $($scoreOutput | Out-String)")
            }
            $filteredScoreOutput = & $scorer -RunInputRoot $runInputRoot -PreflightPath $filteredPreflightPath 2>&1
            if (-not $?) {
                $failures.Add("Execution-preflight scorer rejected the requested-task self-test preflight: $($filteredScoreOutput | Out-String)")
            }
            $multiTaskScoreOutput = & $scorer -RunInputRoot $runInputRoot -PreflightPath $multiTaskPreflightPath 2>&1
            if (-not $?) {
                $failures.Add("Execution-preflight scorer rejected the comma-separated requested-task self-test preflight: $($multiTaskScoreOutput | Out-String)")
            }
        }
        $info.Add('Built a 9-record execution preflight from the generated run-input package.')
        $info.Add('Built requested-task execution preflights with one TaskIds entry and a comma-separated multi-task TaskIds entry without calling a model or API.')
        $info.Add('Recorded provider, model, runtime surface, budget, source hashes, and no-results boundary.')
        try {
            New-ExecutionPreflight -InputRoot $runInputRoot -Path (Join-Path $tempBase 'execution-preflight-missing-task.json') -ModelProvider 'self-test-provider' -ModelAlias 'self-test-model' -RuntimeName 'self-test-runtime' -BudgetUsd 1.0 -PerCondition 1 -RequestedTaskIds @('missing-task-id') -AllowOverwrite $false | Out-Null
            $failures.Add('Expected unknown TaskIds self-test to fail, but it succeeded.')
        } catch {
            if ($_.Exception.Message -notlike '*unknown task id*') {
                $failures.Add("Expected unknown TaskIds failure, got: $($_.Exception.Message)")
            }
        }
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
    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}
    try {
        if (-not $RunInputRoot -or -not $OutputPath) {
            throw 'Provide -RunInputRoot and -OutputPath, or use -SelfTest.'
        }
        $summary = New-ExecutionPreflight -InputRoot $RunInputRoot -Path $OutputPath -ModelProvider $Provider -ModelAlias $ModelNameOrAlias -RuntimeName $RuntimeSurface -BudgetUsd $MaxBudgetUsd -PerCondition $RecordsPerCondition -RequestedTaskIds $TaskIds -AllowOverwrite ([bool]$Force)
        $info.Add('Built empirical execution preflight record without calling a model or API.')
    } catch {
        $failures.Add($_.Exception.Message)
    }
    $status = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
    $result = New-Result -Status $status -Failures $failures -Warnings $warnings -Info $info -Summary $summary
}

if ($Json) {
    $result | ConvertTo-Json -Depth 20
} else {
    "Empirical execution preflight builder: $($result.status)"
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
