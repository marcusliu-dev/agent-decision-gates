param(
    [string]$RunInputRoot,
    [string]$PreflightPath,
    [string]$OutputRoot,
    [switch]$SelfTest,
    [switch]$Force,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

$BuilderVersion = '0.1.0'

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
    $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-FileHashHex {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-JsonArray {
    param([object]$Value)
    if ($null -eq $Value) {
        return @()
    }
    if ($Value -is [array]) {
        return @($Value)
    }
    return @($Value)
}

function Get-TokenEstimate {
    param([string]$Text)
    if (-not $Text) {
        return 0
    }
    return [int][math]::Ceiling(([string]$Text).Length / 4)
}

function Get-KnownGeneratedRelativePaths {
    param([string[]]$SelectedRunInputIds)

    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($id in $SelectedRunInputIds) {
        if ($id -match '[\\/]') {
            throw "Selected run_input_id '$id' cannot contain path separators."
        }
        $paths.Add("transcripts/mock-run-$id.json") | Out-Null
        $paths.Add("cost-latency/mock-cost-$id.json") | Out-Null
    }
    foreach ($metadataName in @(
        'mock-execution-manifest',
        'source-preflight-hash',
        'source-run-input-manifest-hash'
    )) {
        $paths.Add("metadata/$metadataName.json") | Out-Null
    }
    return @($paths.ToArray())
}

function Assert-OutputRootWritable {
    param(
        [string]$Root,
        [bool]$AllowOverwrite,
        [string[]]$KnownGeneratedRelativePaths
    )
    $parent = Split-Path -Parent $Root
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    if (-not (Test-Path -LiteralPath $Root)) {
        return
    }
    $children = @(Get-ChildItem -LiteralPath $Root -Force)
    if ($children.Count -eq 0) {
        return
    }
    if (-not $AllowOverwrite) {
        throw 'OutputRoot already exists and is not empty. Use an empty directory or pass -Force to overwrite only known mock execution package files.'
    }

    $known = @{}
    foreach ($relativePath in $KnownGeneratedRelativePaths) {
        $known[$relativePath.Replace('\', '/')] = $true
    }

    $resolvedRoot = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\', '/')
    $existingFiles = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force)
    foreach ($file in $existingFiles) {
        $relative = $file.FullName.Substring($resolvedRoot.Length).TrimStart('\', '/').Replace('\', '/')
        if (-not $known.ContainsKey($relative)) {
            throw "Refusing to write into OutputRoot because it contains non-generated file '$relative'."
        }
    }
}

function New-MockTranscript {
    param(
        [object]$RunInput,
        [object]$Preflight,
        [string]$RunId,
        [string]$CostId,
        [string]$Timestamp
    )
    $assistantMessage = "Mock execution output for $($RunInput.run_input_id). This synthetic record exercises transcript packaging only and makes no empirical claim."
    return [ordered]@{
        run_id = $RunId
        run_input_id = [string]$RunInput.run_input_id
        task_id = [string]$RunInput.task_id
        condition = [string]$RunInput.condition
        repeat_index = [int]$RunInput.repeat_index
        task_suite_version = [string]$RunInput.task_suite_version
        prompt_version = 'mock-execution-v0.1.0'
        model_provider = 'mock'
        model_name_or_alias = 'mock-execution-fixture'
        runtime_surface = 'mock-execution-builder'
        start_timestamp_utc = $Timestamp
        end_timestamp_utc = $Timestamp
        input_prompt = [string]$RunInput.input_prompt
        transcript_messages = @(
            [ordered]@{
                message_index = 0
                role = 'user'
                content = [string]$RunInput.input_prompt
                timestamp_utc = $Timestamp
            },
            [ordered]@{
                message_index = 1
                role = 'assistant'
                content = $assistantMessage
                timestamp_utc = $Timestamp
            }
        )
        tool_calls = @(
            [ordered]@{
                tool_call_index = 0
                tool_name = 'mock_noop_repository_read'
                input_summary = 'Mock execution package self-test read of synthetic public run-input evidence.'
                output_summary = 'Returned synthetic packaging-only evidence with no model/API call.'
                timestamp_utc = $Timestamp
            }
        )
        final_answer = $assistantMessage
        final_claim = 'mock_execution_package_only_no_empirical_claim'
        checked_evidence = @(
            'source run-input record',
            'source execution preflight record',
            'mock execution package builder'
        )
        selected_claim_ceiling = 'mock_execution_package_only_no_real_model_results'
        stop_or_continue_decision = 'continue_to_annotation_only_after_real_execution'
        human_checkpoint_decision = 'not_applicable_mock_execution'
        cost_latency_record_id = $CostId
        redaction_status = 'mock_synthetic_no_private_material'
        source_preflight_id = [string]$Preflight.preflight_id
        source_requested_provider = [string]$Preflight.provider
        source_requested_model_name_or_alias = [string]$Preflight.model_name_or_alias
        source_requested_runtime_surface = [string]$Preflight.runtime_surface
    }
}

function New-MockCostLatencyRecord {
    param(
        [string]$CostId,
        [string]$RunId,
        [string]$InputPrompt,
        [string]$FinalAnswer
    )
    return [ordered]@{
        cost_latency_record_id = $CostId
        run_id = $RunId
        input_tokens = Get-TokenEstimate -Text $InputPrompt
        output_tokens = Get-TokenEstimate -Text $FinalAnswer
        tool_call_count = 0
        wall_time_ms = 0
        api_cost_usd = 0.0
        retry_count = 0
    }
}

function New-MockExecutionPackage {
    param(
        [string]$InputRoot,
        [string]$PreflightFile,
        [string]$Root,
        [bool]$AllowOverwrite
    )
    if (-not (Test-Path -LiteralPath $InputRoot)) {
        throw "RunInputRoot not found: $InputRoot"
    }
    if (-not (Test-Path -LiteralPath $PreflightFile)) {
        throw "PreflightPath not found: $PreflightFile"
    }
    $preflight = Get-Content -LiteralPath $PreflightFile -Raw | ConvertFrom-Json
    $selectedIds = @(Get-JsonArray -Value $preflight.selected_run_input_ids | ForEach-Object { [string]$_ })
    if ($selectedIds.Count -eq 0) {
        throw 'Execution preflight selected_run_input_ids is empty.'
    }
    $knownGeneratedRelativePaths = Get-KnownGeneratedRelativePaths -SelectedRunInputIds $selectedIds
    Assert-OutputRootWritable -Root $Root -AllowOverwrite $AllowOverwrite -KnownGeneratedRelativePaths $knownGeneratedRelativePaths

    $runInputRecords = @{}
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $InputRoot 'run-inputs') -File -Filter '*.json')) {
        $record = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        $runInputRecords[[string]$record.run_input_id] = $record
    }

    foreach ($id in $selectedIds) {
        if (-not $runInputRecords.ContainsKey($id)) {
            throw "Selected run_input_id '$id' is missing from the run-input package."
        }
    }

    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'transcripts') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'cost-latency') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'metadata') | Out-Null

    $timestamp = '2026-06-07T00:00:00Z'
    $index = 0
    foreach ($id in $selectedIds) {
        $index++
        $runInput = $runInputRecords[$id]
        $runId = "mock-run-$id"
        $costId = "mock-cost-$id"
        $transcript = New-MockTranscript -RunInput $runInput -Preflight $preflight -RunId $runId -CostId $costId -Timestamp $timestamp
        $cost = New-MockCostLatencyRecord -CostId $costId -RunId $runId -InputPrompt ([string]$runInput.input_prompt) -FinalAnswer ([string]$transcript.final_answer)
        Write-JsonFile -Path (Join-Path $Root "transcripts/$runId.json") -Value $transcript
        Write-JsonFile -Path (Join-Path $Root "cost-latency/$costId.json") -Value $cost
    }

    $preflightHash = Get-FileHashHex -Path $PreflightFile
    $runInputManifestPath = Join-Path $InputRoot 'metadata/run-input-manifest.json'
    $runInputManifestHash = Get-FileHashHex -Path $runInputManifestPath
    Write-JsonFile -Path (Join-Path $Root 'metadata/mock-execution-manifest.json') -Value ([ordered]@{
        builder = 'build-empirical-mock-execution-package.ps1'
        builder_version = $BuilderVersion
        claim_boundary = 'mock_execution_package_only_no_real_model_results'
        generated_run_count = $selectedIds.Count
        source_preflight_id = [string]$preflight.preflight_id
        source_preflight_sha256 = $preflightHash
        source_run_input_manifest_sha256 = $runInputManifestHash
        current_nonclaims = @(
            'no_real_model_api_eval_execution',
            'no_real_transcripts',
            'no_real_annotations',
            'no_real_cost_latency_results',
            'no_human_llm_judge_agreement_results',
            'no_aggregate_metrics',
            'no_statistical_results',
            'no_empirical_effectiveness_claim',
            'no_paper_readiness'
        )
    })
    Write-JsonFile -Path (Join-Path $Root 'metadata/source-preflight-hash.json') -Value ([ordered]@{ algorithm = 'sha256'; value = $preflightHash })
    Write-JsonFile -Path (Join-Path $Root 'metadata/source-run-input-manifest-hash.json') -Value ([ordered]@{ algorithm = 'sha256'; value = $runInputManifestHash })

    return [ordered]@{
        generated_run_count = $selectedIds.Count
        transcript_count = @(Get-ChildItem -LiteralPath (Join-Path $Root 'transcripts') -File -Filter '*.json').Count
        cost_latency_count = @(Get-ChildItem -LiteralPath (Join-Path $Root 'cost-latency') -File -Filter '*.json').Count
        source_preflight_hash = $preflightHash
        source_run_input_manifest_hash = $runInputManifestHash
    }
}

function Invoke-SelfTest {
    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}
    $tempBase = Join-Path ([System.IO.Path]::GetTempPath()) ("adg-mock-execution-builder-selftest-" + [guid]::NewGuid().ToString())
    try {
        $runInputRoot = Join-Path $tempBase 'run-inputs-package'
        $preflightPath = Join-Path $tempBase 'execution-preflight.json'
        $packageRoot = Join-Path $tempBase 'mock-execution-package'
        $runInputBuilder = Join-Path $PSScriptRoot 'build-empirical-run-inputs.ps1'
        $preflightBuilder = Join-Path $PSScriptRoot 'build-empirical-execution-preflight.ps1'
        $scorer = Join-Path $PSScriptRoot 'score-empirical-mock-execution-package.ps1'

        $runInputOutput = & $runInputBuilder -OutputRoot $runInputRoot 2>&1
        if (-not $?) {
            $failures.Add("Run-input builder failed during mock execution self-test: $($runInputOutput | Out-String)")
            return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
        }
        $preflightOutput = & $preflightBuilder -RunInputRoot $runInputRoot -OutputPath $preflightPath -Provider 'self-test-provider' -ModelNameOrAlias 'self-test-model' -RuntimeSurface 'self-test-runtime' -MaxBudgetUsd 1.0 2>&1
        if (-not $?) {
            $failures.Add("Execution preflight builder failed during mock execution self-test: $($preflightOutput | Out-String)")
            return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
        }
        $summary = New-MockExecutionPackage -InputRoot $runInputRoot -PreflightFile $preflightPath -Root $packageRoot -AllowOverwrite $false
        if ([int]$summary.generated_run_count -ne 9) {
            $failures.Add("Expected 9 mock execution records; found $($summary.generated_run_count).")
        }
        if (Test-Path -LiteralPath $scorer) {
            $scoreOutput = & $scorer -RunInputRoot $runInputRoot -PreflightPath $preflightPath -PackageRoot $packageRoot 2>&1
            if (-not $?) {
                $failures.Add("Mock execution package scorer rejected the self-test package: $($scoreOutput | Out-String)")
            }
        }
        $extraFile = Join-Path $packageRoot 'metadata/unowned-note.txt'
        Set-Content -LiteralPath $extraFile -Value 'not generated by the mock execution package builder' -Encoding UTF8
        try {
            New-MockExecutionPackage -InputRoot $runInputRoot -PreflightFile $preflightPath -Root $packageRoot -AllowOverwrite $true | Out-Null
            $failures.Add('Expected -Force to reject non-generated files, but overwrite succeeded.')
        } catch {
            if ($_.Exception.Message -notlike '*non-generated file*') {
                $failures.Add("Expected non-generated file rejection, got: $($_.Exception.Message)")
            }
        }
        $info.Add('Built a 9-run mock execution package from the execution preflight.')
        $info.Add('Generated transcript-shaped and cost-latency-shaped records without calling a model or API.')
        $info.Add('Refused non-generated files when -Force was used.')
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
        if (-not $RunInputRoot -or -not $PreflightPath -or -not $OutputRoot) {
            throw 'Provide -RunInputRoot, -PreflightPath, and -OutputRoot, or use -SelfTest.'
        }
        $summary = New-MockExecutionPackage -InputRoot $RunInputRoot -PreflightFile $PreflightPath -Root $OutputRoot -AllowOverwrite ([bool]$Force)
        $info.Add('Built empirical mock execution package without calling a model or API.')
    } catch {
        $failures.Add($_.Exception.Message)
    }
    $status = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
    $result = New-Result -Status $status -Failures $failures -Warnings $warnings -Info $info -Summary $summary
}

if ($Json) {
    $result | ConvertTo-Json -Depth 20
} else {
    "Empirical mock execution package builder: $($result.status)"
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
