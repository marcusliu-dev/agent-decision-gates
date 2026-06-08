param(
    [string]$RunInputRoot,
    [string]$OutputPath,
    [string]$Provider,
    [string]$ModelNameOrAlias,
    [string]$RuntimeSurface,
    [double]$MaxBudgetUsd = -1,
    [int]$RecordsPerCondition = 1,
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

function New-ExecutionPreflight {
    param(
        [string]$InputRoot,
        [string]$Path,
        [string]$ModelProvider,
        [string]$ModelAlias,
        [string]$RuntimeName,
        [double]$BudgetUsd,
        [int]$PerCondition,
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
    $selected = New-Object System.Collections.Generic.List[object]
    foreach ($condition in @($records | Sort-Object condition, task_id, repeat_index | Select-Object -ExpandProperty condition -Unique)) {
        $conditionRecords = @($records | Where-Object { $_.condition -eq $condition } | Sort-Object task_id, repeat_index, run_input_id | Select-Object -First $PerCondition)
        foreach ($record in $conditionRecords) {
            $selected.Add($record) | Out-Null
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
        selection_strategy = 'first_sorted_run_input_per_condition'
        stop_gates_satisfied = @(
            'no_private_repository_material',
            'prompts_frozen_before_execution',
            'run_input_builder_available',
            'condition_prompt_pack_available',
            'selected_run_inputs_exist',
            'source_run_input_manifest_hash_recorded',
            'task_suite_hash_recorded',
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
        $summary = New-ExecutionPreflight -InputRoot $runInputRoot -Path $preflightPath -ModelProvider 'self-test-provider' -ModelAlias 'self-test-model' -RuntimeName 'self-test-runtime' -BudgetUsd 1.0 -PerCondition 1 -AllowOverwrite $false
        if ([int]$summary.selected_run_count -ne 9) {
            $failures.Add("Expected 9 selected run inputs; found $($summary.selected_run_count).")
        }
        if ([int]$summary.selected_condition_count -ne 9) {
            $failures.Add("Expected 9 selected conditions; found $($summary.selected_condition_count).")
        }
        $scorer = Join-Path $PSScriptRoot 'score-empirical-execution-preflight.ps1'
        if (Test-Path -LiteralPath $scorer) {
            $scoreOutput = & $scorer -RunInputRoot $runInputRoot -PreflightPath $preflightPath 2>&1
            if (-not $?) {
                $failures.Add("Execution-preflight scorer rejected the self-test preflight: $($scoreOutput | Out-String)")
            }
        }
        $info.Add('Built a 9-record execution preflight from the generated run-input package.')
        $info.Add('Recorded provider, model, runtime surface, budget, source hashes, and no-results boundary.')
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
        $summary = New-ExecutionPreflight -InputRoot $RunInputRoot -Path $OutputPath -ModelProvider $Provider -ModelAlias $ModelNameOrAlias -RuntimeName $RuntimeSurface -BudgetUsd $MaxBudgetUsd -PerCondition $RecordsPerCondition -AllowOverwrite ([bool]$Force)
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
