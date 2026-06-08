param(
    [string]$RunInputRoot,
    [string]$PreflightPath,
    [string]$OutputRoot,
    [string]$RunnerScriptPath,
    [string]$RunnerLabel = 'local-runner-script',
    [switch]$AllowRunnerScript,
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
    $Value | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $Path -Encoding UTF8
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

function Has-JsonProperty {
    param(
        [object]$Object,
        [string]$Name
    )
    return ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name])
}

function Assert-RequiredRunnerTelemetry {
    param(
        [object]$RunnerResponse,
        [string]$Field,
        [string]$RunInputId
    )
    if (-not (Has-JsonProperty -Object $RunnerResponse -Name $Field) -or $null -eq $RunnerResponse.PSObject.Properties[$Field].Value) {
        throw "Runner response for run_input_id '$RunInputId' is missing required telemetry field '$Field'."
    }
    $value = $RunnerResponse.PSObject.Properties[$Field].Value
    if ($value -is [string] -and -not $value.Trim()) {
        throw "Runner response for run_input_id '$RunInputId' is missing required telemetry field '$Field'."
    }
}

function Convert-RunnerTelemetryNumber {
    param(
        [object]$RunnerResponse,
        [string]$Field,
        [string]$RunInputId,
        [bool]$RequireInteger,
        [bool]$Required
    )
    if (-not (Has-JsonProperty -Object $RunnerResponse -Name $Field) -or $null -eq $RunnerResponse.PSObject.Properties[$Field].Value) {
        if ($Required) {
            throw "Runner response for run_input_id '$RunInputId' is missing required telemetry field '$Field'."
        }
        return $null
    }
    $rawValue = $RunnerResponse.PSObject.Properties[$Field].Value
    if ($rawValue -is [bool]) {
        throw "Runner response for run_input_id '$RunInputId' telemetry field '$Field' must be numeric."
    }
    if ($rawValue -is [string] -and -not $rawValue.Trim()) {
        if ($Required) {
            throw "Runner response for run_input_id '$RunInputId' is missing required telemetry field '$Field'."
        }
        throw "Runner response for run_input_id '$RunInputId' telemetry field '$Field' must be numeric."
    }
    $number = 0.0
    if ($rawValue -is [string]) {
        if (-not [double]::TryParse($rawValue.Trim(), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
            throw "Runner response for run_input_id '$RunInputId' telemetry field '$Field' must be numeric."
        }
    } elseif ($rawValue -is [byte] -or $rawValue -is [sbyte] -or $rawValue -is [int16] -or $rawValue -is [uint16] -or $rawValue -is [int] -or $rawValue -is [uint32] -or $rawValue -is [long] -or $rawValue -is [uint64] -or $rawValue -is [single] -or $rawValue -is [double] -or $rawValue -is [decimal]) {
        $number = [double]$rawValue
    } else {
        throw "Runner response for run_input_id '$RunInputId' telemetry field '$Field' must be numeric."
    }
    if ([double]::IsNaN($number) -or [double]::IsInfinity($number) -or $number -lt 0) {
        throw "Runner response for run_input_id '$RunInputId' telemetry field '$Field' must be a finite nonnegative number."
    }
    if ($RequireInteger -and [math]::Floor($number) -ne $number) {
        throw "Runner response for run_input_id '$RunInputId' telemetry field '$Field' must be an integer."
    }
    if ($RequireInteger) {
        return [int]$number
    }
    return [double]$number
}

function Get-KnownGeneratedRelativePaths {
    param([string[]]$SelectedRunInputIds)

    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($id in $SelectedRunInputIds) {
        if ($id -match '[\\/]') {
            throw "Selected run_input_id '$id' cannot contain path separators."
        }
        $paths.Add("transcripts/pilot-run-$id.json") | Out-Null
        $paths.Add("cost-latency/pilot-cost-$id.json") | Out-Null
    }
    foreach ($metadataName in @(
        'pilot-execution-manifest',
        'source-preflight-hash',
        'source-run-input-manifest-hash',
        'runner-script-hash'
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
        throw 'OutputRoot already exists and is not empty. Use an empty directory or pass -Force to overwrite only known pilot execution package files.'
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

function New-RunnerRequest {
    param(
        [object]$RunInput,
        [object]$Preflight,
        [string]$RunId
    )
    return [ordered]@{
        run_id = $RunId
        run_input_id = [string]$RunInput.run_input_id
        task_id = [string]$RunInput.task_id
        condition = [string]$RunInput.condition
        repeat_index = [int]$RunInput.repeat_index
        task_suite_version = [string]$RunInput.task_suite_version
        prompt_pack_version = [string]$RunInput.prompt_pack_version
        input_prompt = [string]$RunInput.input_prompt
        expected_failure_modes = @(Get-JsonArray -Value $RunInput.expected_failure_modes)
        required_conditions = @(Get-JsonArray -Value $RunInput.required_conditions)
        forbidden_claims = @(Get-JsonArray -Value $RunInput.forbidden_claims)
        preflight_id = [string]$Preflight.preflight_id
        model_provider = [string]$Preflight.provider
        model_name_or_alias = [string]$Preflight.model_name_or_alias
        runtime_surface = [string]$Preflight.runtime_surface
    }
}

function Invoke-LocalRunner {
    param(
        [string]$ScriptPath,
        [object]$Request
    )
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("adg-pilot-runner-call-" + [guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
    try {
        $requestPath = Join-Path $tempDir 'request.json'
        $responsePath = Join-Path $tempDir 'response.json'
        Write-JsonFile -Path $requestPath -Value $Request
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -RequestPath $requestPath -ResponsePath $responsePath 2>&1
        if (-not $?) {
            throw "Runner script failed for run_input_id '$($Request.run_input_id)': $($output | Out-String)"
        }
        if (-not (Test-Path -LiteralPath $responsePath)) {
            throw "Runner script did not create response JSON for run_input_id '$($Request.run_input_id)'."
        }
        $runnerResponseScorer = Join-Path $PSScriptRoot 'score-empirical-runner-response.ps1'
        if (-not (Test-Path -LiteralPath $runnerResponseScorer)) {
            throw 'Runner response scorer is missing; cannot validate local runner output before package wrapping.'
        }
        $scoreOutput = & $runnerResponseScorer -ResponsePath $responsePath -RequestPath $requestPath -Json 2>&1
        $scoreInvocationSucceeded = $?
        $scoreText = ($scoreOutput | Out-String)
        try {
            $score = $scoreText | ConvertFrom-Json
        } catch {
            throw "Runner response scorer did not return JSON for run_input_id '$($Request.run_input_id)': $scoreText"
        }
        if (-not $scoreInvocationSucceeded -or [string]$score.status -ne 'pass') {
            throw "Runner response failed contract scoring for run_input_id '$($Request.run_input_id)': $scoreText"
        }
        return (Get-Content -LiteralPath $responsePath -Raw | ConvertFrom-Json)
    } finally {
        if (Test-Path -LiteralPath $tempDir) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force
        }
    }
}

function New-PilotTranscript {
    param(
        [object]$RunInput,
        [object]$Preflight,
        [object]$RunnerResponse,
        [string]$RunId,
        [string]$CostId,
        [string]$StartedAt,
        [string]$EndedAt
    )
    if (-not $RunnerResponse.final_answer) {
        throw "Runner response for run_input_id '$($RunInput.run_input_id)' is missing final_answer."
    }
    $messages = @(Get-JsonArray -Value $RunnerResponse.transcript_messages)
    if ($messages.Count -eq 0) {
        $messages = @(
            [ordered]@{
                message_index = 0
                role = 'user'
                content = [string]$RunInput.input_prompt
                timestamp_utc = $StartedAt
            },
            [ordered]@{
                message_index = 1
                role = 'assistant'
                content = [string]$RunnerResponse.final_answer
                timestamp_utc = $EndedAt
            }
        )
    }
    return [ordered]@{
        run_id = $RunId
        run_input_id = [string]$RunInput.run_input_id
        task_id = [string]$RunInput.task_id
        condition = [string]$RunInput.condition
        repeat_index = [int]$RunInput.repeat_index
        task_suite_version = [string]$RunInput.task_suite_version
        prompt_version = [string]$RunInput.prompt_pack_version
        model_provider = [string]$Preflight.provider
        model_name_or_alias = [string]$Preflight.model_name_or_alias
        runtime_surface = [string]$Preflight.runtime_surface
        start_timestamp_utc = $StartedAt
        end_timestamp_utc = $EndedAt
        input_prompt = [string]$RunInput.input_prompt
        transcript_messages = $messages
        tool_calls = @(Get-JsonArray -Value $RunnerResponse.tool_calls)
        final_answer = [string]$RunnerResponse.final_answer
        final_claim = if ($RunnerResponse.final_claim) { [string]$RunnerResponse.final_claim } else { 'pilot_execution_output_unlabeled_no_empirical_claim' }
        checked_evidence = if ($RunnerResponse.checked_evidence) { @(Get-JsonArray -Value $RunnerResponse.checked_evidence) } else { @('runner response', 'source run-input record', 'source execution preflight record') }
        selected_claim_ceiling = if ($RunnerResponse.selected_claim_ceiling) { [string]$RunnerResponse.selected_claim_ceiling } else { 'pilot_execution_transcripts_present_unlabeled_no_results' }
        stop_or_continue_decision = if ($RunnerResponse.stop_or_continue_decision) { [string]$RunnerResponse.stop_or_continue_decision } else { 'continue_to_annotation_after_package_validation' }
        human_checkpoint_decision = if ($RunnerResponse.human_checkpoint_decision) { [string]$RunnerResponse.human_checkpoint_decision } else { 'not_evaluated_by_runner' }
        cost_latency_record_id = $CostId
        redaction_status = 'public_synthetic_task_no_private_material'
        source_preflight_id = [string]$Preflight.preflight_id
    }
}

function New-PilotCostLatencyRecord {
    param(
        [string]$CostId,
        [string]$RunId,
        [string]$RunInputId,
        [string]$InputPrompt,
        [string]$FinalAnswer,
        [object]$RunnerResponse,
        [int]$MeasuredWallTimeMs
    )
    foreach ($field in @('input_tokens', 'output_tokens', 'api_cost_usd', 'retry_count')) {
        Assert-RequiredRunnerTelemetry -RunnerResponse $RunnerResponse -Field $field -RunInputId $RunInputId
    }
    $inputTokens = Convert-RunnerTelemetryNumber -RunnerResponse $RunnerResponse -Field 'input_tokens' -RunInputId $RunInputId -RequireInteger $true -Required $true
    $outputTokens = Convert-RunnerTelemetryNumber -RunnerResponse $RunnerResponse -Field 'output_tokens' -RunInputId $RunInputId -RequireInteger $true -Required $true
    $apiCostUsd = Convert-RunnerTelemetryNumber -RunnerResponse $RunnerResponse -Field 'api_cost_usd' -RunInputId $RunInputId -RequireInteger $false -Required $true
    $retryCount = Convert-RunnerTelemetryNumber -RunnerResponse $RunnerResponse -Field 'retry_count' -RunInputId $RunInputId -RequireInteger $true -Required $true
    $runnerWallTimeMs = Convert-RunnerTelemetryNumber -RunnerResponse $RunnerResponse -Field 'wall_time_ms' -RunInputId $RunInputId -RequireInteger $true -Required $false
    return [ordered]@{
        cost_latency_record_id = $CostId
        run_id = $RunId
        input_tokens = $inputTokens
        output_tokens = $outputTokens
        tool_call_count = @(Get-JsonArray -Value $RunnerResponse.tool_calls).Count
        wall_time_ms = if ($null -ne $runnerWallTimeMs) { $runnerWallTimeMs } else { $MeasuredWallTimeMs }
        api_cost_usd = $apiCostUsd
        retry_count = $retryCount
    }
}

function New-PilotExecutionPackage {
    param(
        [string]$InputRoot,
        [string]$PreflightFile,
        [string]$Root,
        [string]$ScriptPath,
        [string]$ScriptLabel,
        [bool]$AllowRunner,
        [bool]$AllowOverwrite
    )
    if (-not $AllowRunner) {
        throw 'Pass -AllowRunnerScript to confirm that executing the local runner script is intentional.'
    }
    if (-not (Test-Path -LiteralPath $InputRoot)) {
        throw "RunInputRoot not found: $InputRoot"
    }
    if (-not (Test-Path -LiteralPath $PreflightFile)) {
        throw "PreflightPath not found: $PreflightFile"
    }
    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        throw "RunnerScriptPath not found: $ScriptPath"
    }
    if (-not $ScriptLabel -or $ScriptLabel -match '[\\/:]') {
        throw 'RunnerLabel is required and must not contain path separators.'
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

    foreach ($id in $selectedIds) {
        $runInput = $runInputRecords[$id]
        $runId = "pilot-run-$id"
        $costId = "pilot-cost-$id"
        $request = New-RunnerRequest -RunInput $runInput -Preflight $preflight -RunId $runId
        $started = [datetime]::UtcNow
        $runnerResponse = Invoke-LocalRunner -ScriptPath $ScriptPath -Request $request
        $ended = [datetime]::UtcNow
        $wallTimeMs = [int][math]::Max(0, ($ended - $started).TotalMilliseconds)
        $startedText = $started.ToString('o')
        $endedText = $ended.ToString('o')
        $transcript = New-PilotTranscript -RunInput $runInput -Preflight $preflight -RunnerResponse $runnerResponse -RunId $runId -CostId $costId -StartedAt $startedText -EndedAt $endedText
        $cost = New-PilotCostLatencyRecord -CostId $costId -RunId $runId -RunInputId ([string]$runInput.run_input_id) -InputPrompt ([string]$runInput.input_prompt) -FinalAnswer ([string]$transcript.final_answer) -RunnerResponse $runnerResponse -MeasuredWallTimeMs $wallTimeMs
        Write-JsonFile -Path (Join-Path $Root "transcripts/$runId.json") -Value $transcript
        Write-JsonFile -Path (Join-Path $Root "cost-latency/$costId.json") -Value $cost
    }

    $preflightHash = Get-FileHashHex -Path $PreflightFile
    $runInputManifestPath = Join-Path $InputRoot 'metadata/run-input-manifest.json'
    $runInputManifestHash = Get-FileHashHex -Path $runInputManifestPath
    $runnerHash = Get-FileHashHex -Path $ScriptPath
    Write-JsonFile -Path (Join-Path $Root 'metadata/pilot-execution-manifest.json') -Value ([ordered]@{
        builder = 'build-empirical-pilot-execution-package.ps1'
        builder_version = $BuilderVersion
        claim_boundary = 'pilot_execution_package_unlabeled_no_empirical_results'
        generated_run_count = $selectedIds.Count
        source_preflight_id = [string]$preflight.preflight_id
        source_preflight_sha256 = $preflightHash
        source_run_input_manifest_sha256 = $runInputManifestHash
        runner_script_label = $ScriptLabel
        runner_script_sha256 = $runnerHash
        current_nonclaims = @(
            'no_annotations',
            'no_human_llm_judge_agreement_results',
            'no_aggregate_metrics',
            'no_statistical_results',
            'no_empirical_effectiveness_claim',
            'no_paper_readiness',
            'no_runner_quality_claim'
        )
    })
    Write-JsonFile -Path (Join-Path $Root 'metadata/source-preflight-hash.json') -Value ([ordered]@{ algorithm = 'sha256'; value = $preflightHash })
    Write-JsonFile -Path (Join-Path $Root 'metadata/source-run-input-manifest-hash.json') -Value ([ordered]@{ algorithm = 'sha256'; value = $runInputManifestHash })
    Write-JsonFile -Path (Join-Path $Root 'metadata/runner-script-hash.json') -Value ([ordered]@{ algorithm = 'sha256'; label = $ScriptLabel; value = $runnerHash })

    return [ordered]@{
        generated_run_count = $selectedIds.Count
        transcript_count = @(Get-ChildItem -LiteralPath (Join-Path $Root 'transcripts') -File -Filter '*.json').Count
        cost_latency_count = @(Get-ChildItem -LiteralPath (Join-Path $Root 'cost-latency') -File -Filter '*.json').Count
        source_preflight_hash = $preflightHash
        source_run_input_manifest_hash = $runInputManifestHash
        runner_script_hash = $runnerHash
    }
}

function Invoke-SelfTest {
    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}
    $tempBase = Join-Path ([System.IO.Path]::GetTempPath()) ("adg-pilot-execution-builder-selftest-" + [guid]::NewGuid().ToString())
    try {
        New-Item -ItemType Directory -Force -Path $tempBase | Out-Null
        $runInputRoot = Join-Path $tempBase 'run-inputs-package'
        $preflightPath = Join-Path $tempBase 'execution-preflight.json'
        $packageRoot = Join-Path $tempBase 'pilot-execution-package'
        $runnerPath = Join-Path $tempBase 'fixture-runner.ps1'
        $runInputBuilder = Join-Path $PSScriptRoot 'build-empirical-run-inputs.ps1'
        $preflightBuilder = Join-Path $PSScriptRoot 'build-empirical-execution-preflight.ps1'
        $scorer = Join-Path $PSScriptRoot 'score-empirical-pilot-execution-package.ps1'

        @'
param(
    [string]$RequestPath,
    [string]$ResponsePath
)
$ErrorActionPreference = 'Stop'
$request = Get-Content -LiteralPath $RequestPath -Raw | ConvertFrom-Json
$answer = "Fixture pilot response for $($request.run_input_id). This is a local runner self-test output for package wrapping only."
$response = [ordered]@{
    final_answer = $answer
    final_claim = 'pilot_execution_output_unlabeled_no_empirical_claim'
    checked_evidence = @('fixture runner request', 'public synthetic task prompt')
    selected_claim_ceiling = 'pilot_execution_transcripts_present_unlabeled_no_results'
    stop_or_continue_decision = 'continue_to_annotation_after_package_validation'
    human_checkpoint_decision = 'not_evaluated_by_fixture_runner'
    input_tokens = [int][math]::Ceiling(([string]$request.input_prompt).Length / 4)
    output_tokens = [int][math]::Ceiling($answer.Length / 4)
    wall_time_ms = 1
    api_cost_usd = 0
    retry_count = 0
}
$response | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ResponsePath -Encoding UTF8
'@ | Set-Content -LiteralPath $runnerPath -Encoding UTF8

        $runInputOutput = & $runInputBuilder -OutputRoot $runInputRoot 2>&1
        if (-not $?) {
            $failures.Add("Run-input builder failed during pilot execution self-test: $($runInputOutput | Out-String)")
            return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
        }
        $preflightOutput = & $preflightBuilder -RunInputRoot $runInputRoot -OutputPath $preflightPath -Provider 'self-test-provider' -ModelNameOrAlias 'self-test-model' -RuntimeSurface 'self-test-runner-script' -MaxBudgetUsd 1.0 2>&1
        if (-not $?) {
            $failures.Add("Execution preflight builder failed during pilot execution self-test: $($preflightOutput | Out-String)")
            return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
        }
        try {
            New-PilotExecutionPackage -InputRoot $runInputRoot -PreflightFile $preflightPath -Root $packageRoot -ScriptPath $runnerPath -ScriptLabel 'fixture-runner-v0' -AllowRunner $false -AllowOverwrite $false | Out-Null
            $failures.Add('Expected pilot builder to require -AllowRunnerScript, but it executed without the gate.')
        } catch {
            if ($_.Exception.Message -notlike '*AllowRunnerScript*') {
                $failures.Add("Expected AllowRunnerScript gate failure, got: $($_.Exception.Message)")
            }
        }
        $summary = New-PilotExecutionPackage -InputRoot $runInputRoot -PreflightFile $preflightPath -Root $packageRoot -ScriptPath $runnerPath -ScriptLabel 'fixture-runner-v0' -AllowRunner $true -AllowOverwrite $false
        if ([int]$summary.generated_run_count -ne 9) {
            $failures.Add("Expected 9 pilot execution records; found $($summary.generated_run_count).")
        }
        if (Test-Path -LiteralPath $scorer) {
            $scoreOutput = & $scorer -RunInputRoot $runInputRoot -PreflightPath $preflightPath -PackageRoot $packageRoot 2>&1
            if (-not $?) {
                $failures.Add("Pilot execution package scorer rejected the self-test package: $($scoreOutput | Out-String)")
            }
        }
        $telemetryRunnerTemplate = @'
param(
    [string]$RequestPath,
    [string]$ResponsePath
)
$ErrorActionPreference = 'Stop'
$request = Get-Content -LiteralPath $RequestPath -Raw | ConvertFrom-Json
$answer = "Fixture pilot response for $($request.run_input_id). This response intentionally emits incomplete telemetry."
$response = [ordered]@{
    final_answer = $answer
    final_claim = 'pilot_execution_output_unlabeled_no_empirical_claim'
    checked_evidence = @('fixture runner request', 'public synthetic task prompt')
    selected_claim_ceiling = 'pilot_execution_transcripts_present_unlabeled_no_results'
    stop_or_continue_decision = 'continue_to_annotation_after_package_validation'
    human_checkpoint_decision = 'not_evaluated_by_fixture_runner'
    input_tokens = [int][math]::Ceiling(([string]$request.input_prompt).Length / 4)
    output_tokens = [int][math]::Ceiling($answer.Length / 4)
    wall_time_ms = 1
    api_cost_usd = 0
    retry_count = 0
}
__MUTATION__
$response | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ResponsePath -Encoding UTF8
'@
        foreach ($missingField in @('input_tokens', 'output_tokens', 'api_cost_usd', 'retry_count')) {
            $missingTelemetryRunner = Join-Path $tempBase "fixture-runner-missing-$missingField.ps1"
            $missingMutation = "`$response.Remove('$missingField')"
            $telemetryRunnerTemplate.Replace('__MUTATION__', $missingMutation) | Set-Content -LiteralPath $missingTelemetryRunner -Encoding UTF8
            $missingTelemetryRoot = Join-Path $tempBase "negative-missing-$missingField"
            try {
                New-PilotExecutionPackage -InputRoot $runInputRoot -PreflightFile $preflightPath -Root $missingTelemetryRoot -ScriptPath $missingTelemetryRunner -ScriptLabel "fixture-runner-missing-$missingField-v0" -AllowRunner $true -AllowOverwrite $false | Out-Null
                $failures.Add("Expected pilot builder to reject missing runner telemetry field '$missingField', but it built a package.")
            } catch {
                if ($_.Exception.Message -notlike "*missing required telemetry field '$missingField'*") {
                    $failures.Add("Expected missing $missingField telemetry rejection, got: $($_.Exception.Message)")
                }
            }
        }
        $blankTelemetryRoot = Join-Path $tempBase 'negative-blank-api-cost'
        $blankTelemetryRunner = Join-Path $tempBase 'fixture-runner-blank-api-cost.ps1'
        $blankMutation = "`$response['api_cost_usd'] = ''"
        $telemetryRunnerTemplate.Replace('__MUTATION__', $blankMutation) | Set-Content -LiteralPath $blankTelemetryRunner -Encoding UTF8
        try {
            New-PilotExecutionPackage -InputRoot $runInputRoot -PreflightFile $preflightPath -Root $blankTelemetryRoot -ScriptPath $blankTelemetryRunner -ScriptLabel 'fixture-runner-blank-api-cost-v0' -AllowRunner $true -AllowOverwrite $false | Out-Null
            $failures.Add('Expected pilot builder to reject blank runner API cost telemetry, but it built a package.')
        } catch {
            if ($_.Exception.Message -notlike '*api_cost_usd*must be numeric*' -and $_.Exception.Message -notlike "*missing required telemetry field 'api_cost_usd'*") {
                $failures.Add("Expected blank api_cost_usd telemetry rejection, got: $($_.Exception.Message)")
            }
        }
        $booleanTelemetryRoot = Join-Path $tempBase 'negative-boolean-api-cost'
        $booleanTelemetryRunner = Join-Path $tempBase 'fixture-runner-boolean-api-cost.ps1'
        $booleanMutation = "`$response['api_cost_usd'] = `$false"
        $telemetryRunnerTemplate.Replace('__MUTATION__', $booleanMutation) | Set-Content -LiteralPath $booleanTelemetryRunner -Encoding UTF8
        try {
            New-PilotExecutionPackage -InputRoot $runInputRoot -PreflightFile $preflightPath -Root $booleanTelemetryRoot -ScriptPath $booleanTelemetryRunner -ScriptLabel 'fixture-runner-boolean-api-cost-v0' -AllowRunner $true -AllowOverwrite $false | Out-Null
            $failures.Add('Expected pilot builder to reject boolean runner API cost telemetry, but it built a package.')
        } catch {
            if ($_.Exception.Message -notlike '*api_cost_usd*must be numeric*') {
                $failures.Add("Expected boolean api_cost_usd telemetry rejection, got: $($_.Exception.Message)")
            }
        }
        $extraFile = Join-Path $packageRoot 'metadata/unowned-note.txt'
        Set-Content -LiteralPath $extraFile -Value 'not generated by the pilot execution package builder' -Encoding UTF8
        try {
            New-PilotExecutionPackage -InputRoot $runInputRoot -PreflightFile $preflightPath -Root $packageRoot -ScriptPath $runnerPath -ScriptLabel 'fixture-runner-v0' -AllowRunner $true -AllowOverwrite $true | Out-Null
            $failures.Add('Expected -Force to reject non-generated files, but overwrite succeeded.')
        } catch {
            if ($_.Exception.Message -notlike '*non-generated file*') {
                $failures.Add("Expected non-generated file rejection, got: $($_.Exception.Message)")
            }
        }
        $info.Add('Built a 9-run pilot execution package through a local fixture runner script.')
        $info.Add('Generated transcript-shaped and cost-latency-shaped records without hosted model/API calls.')
        $info.Add('Required explicit runner token, API cost, and retry telemetry before package wrapping.')
        $info.Add('Required -AllowRunnerScript and refused non-generated files when -Force was used.')
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
        if (-not $RunInputRoot -or -not $PreflightPath -or -not $OutputRoot -or -not $RunnerScriptPath) {
            throw 'Provide -RunInputRoot, -PreflightPath, -OutputRoot, -RunnerScriptPath, and -AllowRunnerScript, or use -SelfTest.'
        }
        $summary = New-PilotExecutionPackage -InputRoot $RunInputRoot -PreflightFile $PreflightPath -Root $OutputRoot -ScriptPath $RunnerScriptPath -ScriptLabel $RunnerLabel -AllowRunner ([bool]$AllowRunnerScript) -AllowOverwrite ([bool]$Force)
        $info.Add('Built empirical pilot execution package through an explicit local runner script.')
    } catch {
        $failures.Add($_.Exception.Message)
    }
    $status = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
    $result = New-Result -Status $status -Failures $failures -Warnings $warnings -Info $info -Summary $summary
}

if ($Json) {
    $result | ConvertTo-Json -Depth 20
} else {
    "Empirical pilot execution package builder: $($result.status)"
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
