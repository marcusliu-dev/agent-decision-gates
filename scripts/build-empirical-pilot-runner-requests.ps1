param(
    [string]$RunInputRoot,
    [string]$PreflightPath,
    [string]$OutputRoot,
    [string]$RunnerLabel = 'local-runner-script',
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
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

function Convert-JsonToolOutput {
    param(
        [string]$ScriptName,
        [object[]]$Output,
        [bool]$InvocationSucceeded
    )
    $text = ($Output | Out-String)
    try {
        $parsed = $text | ConvertFrom-Json
    } catch {
        throw "$ScriptName did not return JSON: $text"
    }
    if (-not $InvocationSucceeded -or [string]$parsed.status -ne 'pass') {
        throw "$ScriptName failed: $text"
    }
    return $parsed
}

function Get-KnownGeneratedRelativePaths {
    param([string[]]$SelectedRunInputIds)

    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($id in $SelectedRunInputIds) {
        if ($id -match '[\\/]') {
            throw "Selected run_input_id '$id' cannot contain path separators."
        }
        $paths.Add("requests/pilot-request-$id.json") | Out-Null
    }
    foreach ($metadataName in @(
        'pilot-runner-request-manifest',
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
        throw 'OutputRoot already exists and is not empty. Use an empty directory or pass -Force to overwrite only known pilot runner request package files.'
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
        [string]$RunnerLabelValue
    )
    $runInputId = [string]$RunInput.run_input_id
    return [ordered]@{
        request_id = "pilot-request-$runInputId"
        run_id = "pilot-run-$runInputId"
        run_input_id = $runInputId
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
        runner_label = $RunnerLabelValue
    }
}

function Invoke-InputScorers {
    param(
        [string]$InputRoot,
        [string]$PreflightFile,
        [string]$RepositoryRoot
    )
    $runInputScorer = Join-Path $RepositoryRoot 'scripts/score-empirical-run-inputs.ps1'
    $preflightScorer = Join-Path $RepositoryRoot 'scripts/score-empirical-execution-preflight.ps1'
    foreach ($requiredPath in @($runInputScorer, $preflightScorer)) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Required scorer missing: $requiredPath"
        }
    }
    $runInputOutput = & $runInputScorer -PackageRoot $InputRoot -RepoRoot $RepositoryRoot -Json 2>&1
    Convert-JsonToolOutput -ScriptName 'score-empirical-run-inputs.ps1' -Output $runInputOutput -InvocationSucceeded $? | Out-Null
    $preflightOutput = & $preflightScorer -RunInputRoot $InputRoot -PreflightPath $PreflightFile -RepoRoot $RepositoryRoot -Json 2>&1
    Convert-JsonToolOutput -ScriptName 'score-empirical-execution-preflight.ps1' -Output $preflightOutput -InvocationSucceeded $? | Out-Null
}

function New-PilotRunnerRequestPackage {
    param(
        [string]$InputRoot,
        [string]$PreflightFile,
        [string]$Root,
        [string]$RunnerLabelValue,
        [string]$RepositoryRoot,
        [bool]$AllowOverwrite
    )
    if (-not (Test-Path -LiteralPath $InputRoot)) {
        throw "RunInputRoot not found: $InputRoot"
    }
    if (-not (Test-Path -LiteralPath $PreflightFile)) {
        throw "PreflightPath not found: $PreflightFile"
    }
    if (-not $Root) {
        throw 'OutputRoot is required.'
    }
    if ([string]::IsNullOrWhiteSpace($RunnerLabelValue) -or $RunnerLabelValue -match '[\\/:]') {
        throw 'RunnerLabel must be nonblank and contain no path separators.'
    }

    Invoke-InputScorers -InputRoot $InputRoot -PreflightFile $PreflightFile -RepositoryRoot $RepositoryRoot

    $preflight = Get-Content -LiteralPath $PreflightFile -Raw | ConvertFrom-Json
    $selectedIds = @(Get-JsonArray -Value $preflight.selected_run_input_ids | ForEach-Object { [string]$_ })
    if ($selectedIds.Count -eq 0) {
        throw 'Execution preflight selected_run_input_ids is empty.'
    }

    $knownGeneratedRelativePaths = Get-KnownGeneratedRelativePaths -SelectedRunInputIds $selectedIds
    Assert-OutputRootWritable -Root $Root -AllowOverwrite $AllowOverwrite -KnownGeneratedRelativePaths $knownGeneratedRelativePaths

    $runInputRecords = @{}
    $runInputDir = Join-Path $InputRoot 'run-inputs'
    foreach ($file in @(Get-ChildItem -LiteralPath $runInputDir -File -Filter '*.json')) {
        $record = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        $runInputRecords[[string]$record.run_input_id] = $record
    }
    foreach ($id in $selectedIds) {
        if (-not $runInputRecords.ContainsKey($id)) {
            throw "Selected run_input_id '$id' is missing from the run-input package."
        }
    }

    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'requests') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'metadata') | Out-Null

    foreach ($id in $selectedIds) {
        $request = New-RunnerRequest -RunInput $runInputRecords[$id] -Preflight $preflight -RunnerLabelValue $RunnerLabelValue
        Write-JsonFile -Path (Join-Path $Root "requests/pilot-request-$id.json") -Value $request
    }

    $preflightHash = Get-FileHashHex -Path $PreflightFile
    $runInputManifestPath = Join-Path $InputRoot 'metadata/run-input-manifest.json'
    $runInputManifestHash = Get-FileHashHex -Path $runInputManifestPath
    $requestFiles = @(Get-ChildItem -LiteralPath (Join-Path $Root 'requests') -File -Filter '*.json' | Sort-Object Name)
    $requestRecords = @()
    foreach ($requestFile in $requestFiles) {
        $requestRecords += [ordered]@{
            request_file = "requests/$($requestFile.Name)"
            request_sha256 = Get-FileHashHex -Path $requestFile.FullName
        }
    }

    Write-JsonFile -Path (Join-Path $Root 'metadata/pilot-runner-request-manifest.json') -Value ([ordered]@{
        builder = 'build-empirical-pilot-runner-requests.ps1'
        builder_version = $BuilderVersion
        claim_boundary = 'pilot_runner_request_package_no_runner_execution'
        request_count = $requestFiles.Count
        source_preflight_id = [string]$preflight.preflight_id
        source_preflight_sha256 = $preflightHash
        source_run_input_manifest_sha256 = $runInputManifestHash
        runner_label = $RunnerLabelValue
        request_records = $requestRecords
        current_nonclaims = @(
            'no_runner_execution',
            'no_model_api_eval_execution',
            'no_runner_responses',
            'no_real_transcripts',
            'no_real_cost_latency_results',
            'no_annotations',
            'no_aggregate_metrics',
            'no_empirical_effectiveness_claim',
            'no_paper_readiness'
        )
    })
    Write-JsonFile -Path (Join-Path $Root 'metadata/source-preflight-hash.json') -Value ([ordered]@{ algorithm = 'sha256'; value = $preflightHash })
    Write-JsonFile -Path (Join-Path $Root 'metadata/source-run-input-manifest-hash.json') -Value ([ordered]@{ algorithm = 'sha256'; value = $runInputManifestHash })

    return [ordered]@{
        request_count = $requestFiles.Count
        selected_run_count = $selectedIds.Count
        source_preflight_hash = $preflightHash
        source_run_input_manifest_hash = $runInputManifestHash
        runner_label = $RunnerLabelValue
    }
}

function Invoke-NegativeCase {
    param(
        [System.Collections.Generic.List[string]]$Failures,
        [string]$Name,
        [string]$ExpectedFailureText,
        [scriptblock]$Run
    )
    try {
        & $Run | Out-Null
        $Failures.Add("Negative request-package case '$Name' unexpectedly passed.")
    } catch {
        if ($_.Exception.Message -notlike "*$ExpectedFailureText*") {
            $Failures.Add("Negative request-package case '$Name' failed, but not for expected text '$ExpectedFailureText': $($_.Exception.Message)")
        }
    }
}

function Invoke-SelfTest {
    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}
    $tempBase = Join-Path ([System.IO.Path]::GetTempPath()) ("adg-pilot-runner-requests-selftest-" + [guid]::NewGuid().ToString())
    try {
        New-Item -ItemType Directory -Force -Path $tempBase | Out-Null
        $runInputRoot = Join-Path $tempBase 'run-inputs'
        $preflightPath = Join-Path $tempBase 'execution-preflight.json'
        $outputRoot = Join-Path $tempBase 'pilot-runner-requests'
        $runInputBuilder = Join-Path $RepoRoot 'scripts/build-empirical-run-inputs.ps1'
        $preflightBuilder = Join-Path $RepoRoot 'scripts/build-empirical-execution-preflight.ps1'

        $runInputOutput = & $runInputBuilder -OutputRoot $runInputRoot -Json 2>&1
        Convert-JsonToolOutput -ScriptName 'build-empirical-run-inputs.ps1' -Output $runInputOutput -InvocationSucceeded $? | Out-Null
        $preflightOutput = & $preflightBuilder -RunInputRoot $runInputRoot -OutputPath $preflightPath -Provider 'selftest-provider' -ModelNameOrAlias 'selftest-model' -RuntimeSurface 'selftest-local-runner' -MaxBudgetUsd 1.0 -Force -Json 2>&1
        Convert-JsonToolOutput -ScriptName 'build-empirical-execution-preflight.ps1' -Output $preflightOutput -InvocationSucceeded $? | Out-Null

        $summary = New-PilotRunnerRequestPackage -InputRoot $runInputRoot -PreflightFile $preflightPath -Root $outputRoot -RunnerLabelValue 'fixture-runner-v0' -RepositoryRoot $RepoRoot -AllowOverwrite $false
        if ([int]$summary.request_count -ne 9) {
            $failures.Add("Expected 9 pilot runner requests; found $($summary.request_count).")
        }
        if (Test-Path -LiteralPath (Join-Path $outputRoot 'transcripts')) {
            $failures.Add('Request package builder must not create transcripts.')
        }
        if (Test-Path -LiteralPath (Join-Path $outputRoot 'cost-latency')) {
            $failures.Add('Request package builder must not create cost-latency records.')
        }
        $firstRequest = Get-Content -LiteralPath (Get-ChildItem -LiteralPath (Join-Path $outputRoot 'requests') -File -Filter '*.json' | Sort-Object Name | Select-Object -First 1).FullName -Raw | ConvertFrom-Json
        foreach ($requiredProperty in @('request_id', 'run_id', 'run_input_id', 'task_id', 'condition', 'input_prompt', 'preflight_id', 'model_provider', 'model_name_or_alias', 'runtime_surface', 'runner_label')) {
            if ($null -eq $firstRequest.PSObject.Properties[$requiredProperty]) {
                $failures.Add("Generated request is missing required property '$requiredProperty'.")
            }
        }

        Invoke-NegativeCase -Failures $failures -Name 'bad_runner_label' -ExpectedFailureText 'RunnerLabel must be nonblank' -Run {
            New-PilotRunnerRequestPackage -InputRoot $runInputRoot -PreflightFile $preflightPath -Root (Join-Path $tempBase 'bad-label') -RunnerLabelValue 'bad/label' -RepositoryRoot $RepoRoot -AllowOverwrite $false
        }

        $badPreflightPath = Join-Path $tempBase 'execution-preflight-missing-id.json'
        $badPreflight = Get-Content -LiteralPath $preflightPath -Raw | ConvertFrom-Json
        $ids = @(Get-JsonArray -Value $badPreflight.selected_run_input_ids | ForEach-Object { [string]$_ })
        $ids[0] = 'ri-missing-run-input'
        $badPreflight.selected_run_input_ids = @($ids)
        Write-JsonFile -Path $badPreflightPath -Value $badPreflight
        Invoke-NegativeCase -Failures $failures -Name 'missing_selected_run_input' -ExpectedFailureText 'missing id' -Run {
            New-PilotRunnerRequestPackage -InputRoot $runInputRoot -PreflightFile $badPreflightPath -Root (Join-Path $tempBase 'missing-selected') -RunnerLabelValue 'fixture-runner-v0' -RepositoryRoot $RepoRoot -AllowOverwrite $false
        }

        Set-Content -LiteralPath (Join-Path $outputRoot 'metadata/unowned-note.txt') -Value 'not generated by the pilot runner request package builder' -Encoding UTF8
        Invoke-NegativeCase -Failures $failures -Name 'non_generated_force_overwrite' -ExpectedFailureText 'non-generated file' -Run {
            New-PilotRunnerRequestPackage -InputRoot $runInputRoot -PreflightFile $preflightPath -Root $outputRoot -RunnerLabelValue 'fixture-runner-v0' -RepositoryRoot $RepoRoot -AllowOverwrite $true
        }

        $info.Add('Built a 9-request pilot runner request package.')
        $info.Add('Rejected missing selected run inputs, bad runner labels, and non-generated overwrite attempts.')
        $info.Add('No runner script was executed and no model/API calls were made by this request builder.')
    } catch {
        $failures.Add($_.Exception.Message)
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
        $summary = New-PilotRunnerRequestPackage -InputRoot $RunInputRoot -PreflightFile $PreflightPath -Root $OutputRoot -RunnerLabelValue $RunnerLabel -RepositoryRoot $RepoRoot -AllowOverwrite ([bool]$Force)
        $info.Add('Built empirical pilot runner request package without executing a runner.')
    } catch {
        $failures.Add($_.Exception.Message)
    }
    $status = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
    $result = New-Result -Status $status -Failures $failures -Warnings $warnings -Info $info -Summary $summary
}

if ($Json) {
    $result | ConvertTo-Json -Depth 20
} else {
    "Empirical pilot runner request package builder: $($result.status)"
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
