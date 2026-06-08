param(
    [string]$OutputRoot,
    [string]$RunnerScriptPath,
    [string]$RunnerLabel = 'local-runner-script',
    [string]$Provider = 'provider-under-test',
    [string]$ModelNameOrAlias = 'model-under-test',
    [string]$RuntimeSurface = 'explicit-local-runner-chain',
    [double]$MaxBudgetUsd = 1.0,
    [int]$RecordsPerCondition = 1,
    [switch]$AllowRunnerScript,
    [switch]$SelfTest,
    [switch]$Force,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

$ChainBuilderVersion = '0.1.0'

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

function Get-KnownGeneratedRelativePaths {
    $paths = New-Object System.Collections.Generic.List[string]
    $paths.Add('execution-preflight.json') | Out-Null
    $paths.Add('metadata/pilot-run-chain-manifest.json') | Out-Null

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("adg-pilot-chain-known-paths-" + [guid]::NewGuid().ToString())
    try {
        $runInputRoot = Join-Path $tempRoot 'run-inputs'
        $runInputBuilder = Join-Path $PSScriptRoot 'build-empirical-run-inputs.ps1'
        $output = & $runInputBuilder -OutputRoot $runInputRoot -Json 2>&1
        $runInputs = Convert-ToolOutput -ScriptName 'build-empirical-run-inputs.ps1' -Output $output -InvocationSucceeded $?
        if ([int](Get-SummaryValue -Result $runInputs -Name 'record_count') -lt 1) {
            throw 'Generated run-input package contained no records while computing pilot-chain overwrite allowlist.'
        }

        $resolvedRunInputRoot = (Resolve-Path -LiteralPath $runInputRoot).Path.TrimEnd('\', '/')
        $runInputIds = New-Object System.Collections.Generic.List[string]
        foreach ($file in @(Get-ChildItem -LiteralPath $runInputRoot -Recurse -File -Force | Sort-Object FullName)) {
            $relative = $file.FullName.Substring($resolvedRunInputRoot.Length).TrimStart('\', '/').Replace('\', '/')
            $paths.Add("run-inputs/$relative") | Out-Null
            if ($relative -like 'run-inputs/*.json') {
                $record = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
                $runInputId = [string]$record.run_input_id
                if (-not $runInputId) {
                    throw "Run-input record '$relative' is missing run_input_id."
                }
                if ($runInputId -match '[\\/]') {
                    throw "Run-input id '$runInputId' cannot contain path separators."
                }
                $runInputIds.Add($runInputId) | Out-Null
            }
        }

        foreach ($runInputId in @($runInputIds.ToArray())) {
            $paths.Add("pilot-execution-package/transcripts/pilot-run-$runInputId.json") | Out-Null
            $paths.Add("pilot-execution-package/cost-latency/pilot-cost-$runInputId.json") | Out-Null
            $workItemId = "annotation-work-item-pilot-run-$runInputId"
            $paths.Add("annotation-worklist/annotation-work-items/$workItemId.json") | Out-Null
            $paths.Add("label-template-package/annotation-templates/label-template-$workItemId.json") | Out-Null
        }

        foreach ($relative in @(
            'pilot-execution-package/metadata/pilot-execution-manifest.json',
            'pilot-execution-package/metadata/source-preflight-hash.json',
            'pilot-execution-package/metadata/source-run-input-manifest-hash.json',
            'pilot-execution-package/metadata/runner-script-hash.json',
            'annotation-worklist/metadata/annotation-worklist-manifest.json',
            'annotation-worklist/metadata/source-pilot-execution-manifest-hash.json',
            'annotation-worklist/metadata/annotation-guidelines-hash.json',
            'label-template-package/metadata/label-template-package-manifest.json',
            'label-template-package/metadata/source-annotation-worklist-manifest-hash.json',
            'label-template-package/metadata/annotation-schema-hash.json',
            'label-template-package/metadata/annotation-guidelines-hash.json'
        )) {
            $paths.Add($relative) | Out-Null
        }
    } finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    return @($paths.ToArray() | Sort-Object -Unique)
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
        throw 'OutputRoot already exists and is not empty. Use an empty directory or pass -Force to overwrite only known pilot-run-chain files.'
    }

    $allowedTopLevel = @{
        'run-inputs' = $true
        'execution-preflight.json' = $true
        'pilot-execution-package' = $true
        'annotation-worklist' = $true
        'label-template-package' = $true
        'metadata' = $true
    }
    $resolvedRoot = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\', '/')
    foreach ($child in $children) {
        if (-not $allowedTopLevel.ContainsKey($child.Name)) {
            throw "Refusing to overwrite OutputRoot because it contains non-generated file '$($child.Name)'."
        }
        $resolvedChild = (Resolve-Path -LiteralPath $child.FullName).Path
        if (-not $resolvedChild.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove path outside OutputRoot: $resolvedChild"
        }
    }

    $known = @{}
    foreach ($relativePath in $KnownGeneratedRelativePaths) {
        $known[$relativePath.Replace('\', '/')] = $true
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force)) {
        $relative = $file.FullName.Substring($resolvedRoot.Length).TrimStart('\', '/').Replace('\', '/')
        if (-not $known.ContainsKey($relative)) {
            throw "Refusing to overwrite OutputRoot because it contains non-generated file '$relative'."
        }
    }
    foreach ($child in $children) {
        Remove-Item -LiteralPath $child.FullName -Recurse -Force
    }
}

function Convert-ToolOutput {
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

function Get-SummaryValue {
    param(
        [object]$Result,
        [string]$Name
    )
    if ($Result.summary -and $Result.summary.PSObject.Properties[$Name]) {
        return $Result.summary.$Name
    }
    return $null
}

function New-PilotRunChain {
    param(
        [string]$Root,
        [string]$ScriptPath,
        [string]$ScriptLabel,
        [string]$ModelProvider,
        [string]$ModelAlias,
        [string]$RuntimeName,
        [double]$BudgetUsd,
        [int]$PerCondition,
        [bool]$AllowRunner,
        [bool]$AllowOverwrite
    )
    if (-not $AllowRunner) {
        throw 'Pass -AllowRunnerScript to confirm that executing the local runner script is intentional.'
    }
    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        throw "RunnerScriptPath not found: $ScriptPath"
    }
    $knownGeneratedRelativePaths = Get-KnownGeneratedRelativePaths
    Assert-OutputRootWritable -Root $Root -AllowOverwrite $AllowOverwrite -KnownGeneratedRelativePaths $knownGeneratedRelativePaths
    New-Item -ItemType Directory -Force -Path $Root | Out-Null

    $runInputRoot = Join-Path $Root 'run-inputs'
    $preflightPath = Join-Path $Root 'execution-preflight.json'
    $pilotRoot = Join-Path $Root 'pilot-execution-package'
    $worklistRoot = Join-Path $Root 'annotation-worklist'
    $templateRoot = Join-Path $Root 'label-template-package'
    $metadataRoot = Join-Path $Root 'metadata'
    New-Item -ItemType Directory -Force -Path $metadataRoot | Out-Null

    $repoRoot = Split-Path -Parent $PSScriptRoot
    $runInputBuilder = Join-Path $PSScriptRoot 'build-empirical-run-inputs.ps1'
    $runInputScorer = Join-Path $PSScriptRoot 'score-empirical-run-inputs.ps1'
    $preflightBuilder = Join-Path $PSScriptRoot 'build-empirical-execution-preflight.ps1'
    $preflightScorer = Join-Path $PSScriptRoot 'score-empirical-execution-preflight.ps1'
    $pilotBuilder = Join-Path $PSScriptRoot 'build-empirical-pilot-execution-package.ps1'
    $pilotScorer = Join-Path $PSScriptRoot 'score-empirical-pilot-execution-package.ps1'
    $worklistBuilder = Join-Path $PSScriptRoot 'build-empirical-annotation-worklist.ps1'
    $worklistScorer = Join-Path $PSScriptRoot 'score-empirical-annotation-worklist.ps1'
    $templateBuilder = Join-Path $PSScriptRoot 'build-empirical-label-template-package.ps1'
    $templateScorer = Join-Path $PSScriptRoot 'score-empirical-label-template-package.ps1'

    $output = & $runInputBuilder -OutputRoot $runInputRoot -Json 2>&1
    $runInputs = Convert-ToolOutput -ScriptName 'build-empirical-run-inputs.ps1' -Output $output -InvocationSucceeded $?
    $output = & $runInputScorer -PackageRoot $runInputRoot -RepoRoot $repoRoot -Json 2>&1
    $runInputScore = Convert-ToolOutput -ScriptName 'score-empirical-run-inputs.ps1' -Output $output -InvocationSucceeded $?
    $output = & $preflightBuilder -RunInputRoot $runInputRoot -OutputPath $preflightPath -Provider $ModelProvider -ModelNameOrAlias $ModelAlias -RuntimeSurface $RuntimeName -MaxBudgetUsd $BudgetUsd -RecordsPerCondition $PerCondition -Json 2>&1
    $preflight = Convert-ToolOutput -ScriptName 'build-empirical-execution-preflight.ps1' -Output $output -InvocationSucceeded $?
    $output = & $preflightScorer -RunInputRoot $runInputRoot -PreflightPath $preflightPath -RepoRoot $repoRoot -Json 2>&1
    $preflightScore = Convert-ToolOutput -ScriptName 'score-empirical-execution-preflight.ps1' -Output $output -InvocationSucceeded $?
    $output = & $pilotBuilder -RunInputRoot $runInputRoot -PreflightPath $preflightPath -OutputRoot $pilotRoot -RunnerScriptPath $ScriptPath -RunnerLabel $ScriptLabel -AllowRunnerScript -Json 2>&1
    $pilot = Convert-ToolOutput -ScriptName 'build-empirical-pilot-execution-package.ps1' -Output $output -InvocationSucceeded $?
    $output = & $pilotScorer -RunInputRoot $runInputRoot -PreflightPath $preflightPath -PackageRoot $pilotRoot -RepoRoot $repoRoot -Json 2>&1
    $pilotScore = Convert-ToolOutput -ScriptName 'score-empirical-pilot-execution-package.ps1' -Output $output -InvocationSucceeded $?
    $output = & $worklistBuilder -PilotPackageRoot $pilotRoot -OutputRoot $worklistRoot -Json 2>&1
    $worklist = Convert-ToolOutput -ScriptName 'build-empirical-annotation-worklist.ps1' -Output $output -InvocationSucceeded $?
    $output = & $worklistScorer -PilotPackageRoot $pilotRoot -WorklistRoot $worklistRoot -RepoRoot $repoRoot -Json 2>&1
    $worklistScore = Convert-ToolOutput -ScriptName 'score-empirical-annotation-worklist.ps1' -Output $output -InvocationSucceeded $?
    $output = & $templateBuilder -WorklistRoot $worklistRoot -OutputRoot $templateRoot -Json 2>&1
    $templates = Convert-ToolOutput -ScriptName 'build-empirical-label-template-package.ps1' -Output $output -InvocationSucceeded $?
    $output = & $templateScorer -WorklistRoot $worklistRoot -TemplatePackageRoot $templateRoot -RepoRoot $repoRoot -Json 2>&1
    $templateScore = Convert-ToolOutput -ScriptName 'score-empirical-label-template-package.ps1' -Output $output -InvocationSucceeded $?

    $runnerHash = Get-FileHashHex -Path $ScriptPath
    $manifest = [ordered]@{
        package_type = 'empirical_pilot_run_chain'
        claim_boundary = 'pilot_run_chain_executed_no_labels_no_metrics'
        chain_builder_version = $ChainBuilderVersion
        model_provider = $ModelProvider
        model_name_or_alias = $ModelAlias
        runtime_surface = $RuntimeName
        records_per_condition = $PerCondition
        runner_script_label = $ScriptLabel
        runner_script_sha256 = $runnerHash
        artifacts = [ordered]@{
            run_inputs = 'run-inputs'
            execution_preflight = 'execution-preflight.json'
            pilot_execution_package = 'pilot-execution-package'
            annotation_worklist = 'annotation-worklist'
            label_template_package = 'label-template-package'
        }
        current_nonclaims = @(
            'no_completed_annotations',
            'no_real_label_quality_claim',
            'no_human_llm_judge_agreement_results',
            'no_aggregate_metrics',
            'no_statistical_results',
            'no_empirical_effectiveness_claim',
            'no_paper_readiness'
        )
    }
    Write-JsonFile -Path (Join-Path $metadataRoot 'pilot-run-chain-manifest.json') -Value $manifest

    return [ordered]@{
        run_input_records = Get-SummaryValue -Result $runInputs -Name 'record_count'
        selected_run_count = Get-SummaryValue -Result $preflight -Name 'selected_run_count'
        selected_condition_count = Get-SummaryValue -Result $preflight -Name 'selected_condition_count'
        pilot_transcript_count = Get-SummaryValue -Result $pilot -Name 'transcript_count'
        pilot_cost_latency_count = Get-SummaryValue -Result $pilot -Name 'cost_latency_count'
        annotation_work_item_count = Get-SummaryValue -Result $worklist -Name 'generated_work_item_count'
        label_template_count = Get-SummaryValue -Result $templates -Name 'generated_template_count'
        runner_script_hash = $runnerHash
        run_input_score_status = [string]$runInputScore.status
        preflight_score_status = [string]$preflightScore.status
        pilot_score_status = [string]$pilotScore.status
        worklist_score_status = [string]$worklistScore.status
        template_score_status = [string]$templateScore.status
    }
}

function New-FixtureRunner {
    param([string]$Path)
    @'
param(
    [string]$RequestPath,
    [string]$ResponsePath
)
$ErrorActionPreference = 'Stop'
$request = Get-Content -LiteralPath $RequestPath -Raw | ConvertFrom-Json
$answer = "Fixture chain response for $($request.run_input_id). This local runner output exercises package wrapping only."
$response = [ordered]@{
    final_answer = $answer
    final_claim = 'pilot_chain_fixture_output_only'
    checked_evidence = @('fixture runner request', 'public synthetic task prompt')
    selected_claim_ceiling = 'pilot_chain_fixture_output_only'
    stop_or_continue_decision = 'continue_to_annotation_worklist'
    human_checkpoint_decision = 'not_evaluated_by_fixture_runner'
    input_tokens = 12
    output_tokens = 16
    wall_time_ms = 5
    api_cost_usd = 0.0
    retry_count = 0
}
$response | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ResponsePath -Encoding UTF8
'@ | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-SelfTest {
    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}
    $tempBase = Join-Path ([System.IO.Path]::GetTempPath()) ("adg-pilot-run-chain-selftest-" + [guid]::NewGuid().ToString())
    try {
        New-Item -ItemType Directory -Force -Path $tempBase | Out-Null
        $runnerPath = Join-Path $tempBase 'fixture-runner.ps1'
        New-FixtureRunner -Path $runnerPath
        $positiveRoot = Join-Path $tempBase 'positive-chain'
        $positive = New-PilotRunChain -Root $positiveRoot -ScriptPath $runnerPath -ScriptLabel 'fixture-chain-runner-v0' -ModelProvider 'self-test-provider' -ModelAlias 'self-test-model' -RuntimeName 'self-test-runner-chain' -BudgetUsd 1.0 -PerCondition 1 -AllowRunner $true -AllowOverwrite $false
        if ([int]$positive.selected_run_count -ne 9) {
            $failures.Add("Expected 9 selected pilot runs; found $($positive.selected_run_count).")
        }
        if ([int]$positive.pilot_transcript_count -ne 9) {
            $failures.Add("Expected 9 pilot transcripts; found $($positive.pilot_transcript_count).")
        }
        if ([int]$positive.annotation_work_item_count -ne 9) {
            $failures.Add("Expected 9 annotation work items; found $($positive.annotation_work_item_count).")
        }
        if ([int]$positive.label_template_count -ne 9) {
            $failures.Add("Expected 9 label templates; found $($positive.label_template_count).")
        }
        $manifestRaw = Get-Content -LiteralPath (Join-Path $positiveRoot 'metadata/pilot-run-chain-manifest.json') -Raw
        if ($manifestRaw.Contains($tempBase)) {
            $failures.Add('Pilot-run-chain manifest exposed the temporary local package path.')
        }
        $forcePositive = New-PilotRunChain -Root $positiveRoot -ScriptPath $runnerPath -ScriptLabel 'fixture-chain-runner-v0' -ModelProvider 'self-test-provider' -ModelAlias 'self-test-model' -RuntimeName 'self-test-runner-chain' -BudgetUsd 1.0 -PerCondition 1 -AllowRunner $true -AllowOverwrite $true
        if ([int]$forcePositive.selected_run_count -ne 9) {
            $failures.Add("Expected -Force overwrite of generated chain to preserve 9 selected runs; found $($forcePositive.selected_run_count).")
        }

        try {
            New-PilotRunChain -Root (Join-Path $tempBase 'negative-no-allow') -ScriptPath $runnerPath -ScriptLabel 'fixture-chain-runner-v0' -ModelProvider 'self-test-provider' -ModelAlias 'self-test-model' -RuntimeName 'self-test-runner-chain' -BudgetUsd 1.0 -PerCondition 1 -AllowRunner $false -AllowOverwrite $false | Out-Null
            $failures.Add('Expected pilot run chain to require -AllowRunnerScript, but it executed without the gate.')
        } catch {
            if ($_.Exception.Message -notlike '*AllowRunnerScript*') {
                $failures.Add("Expected AllowRunnerScript gate failure, got: $($_.Exception.Message)")
            }
        }

        $overwriteRoot = Join-Path $tempBase 'negative-overwrite'
        New-Item -ItemType Directory -Force -Path $overwriteRoot | Out-Null
        Set-Content -LiteralPath (Join-Path $overwriteRoot 'manual-note.txt') -Value 'not generated by the pilot run chain' -Encoding UTF8
        try {
            New-PilotRunChain -Root $overwriteRoot -ScriptPath $runnerPath -ScriptLabel 'fixture-chain-runner-v0' -ModelProvider 'self-test-provider' -ModelAlias 'self-test-model' -RuntimeName 'self-test-runner-chain' -BudgetUsd 1.0 -PerCondition 1 -AllowRunner $true -AllowOverwrite $true | Out-Null
            $failures.Add('Expected -Force to reject non-generated files, but overwrite succeeded.')
        } catch {
            if ($_.Exception.Message -notlike '*non-generated file*') {
                $failures.Add("Expected non-generated file rejection, got: $($_.Exception.Message)")
            }
        }

        $nestedOverwriteRoot = Join-Path $tempBase 'negative-nested-overwrite'
        New-Item -ItemType Directory -Force -Path (Join-Path $nestedOverwriteRoot 'metadata') | Out-Null
        Set-Content -LiteralPath (Join-Path $nestedOverwriteRoot 'metadata/manual-note.txt') -Value 'not generated by the pilot run chain' -Encoding UTF8
        try {
            New-PilotRunChain -Root $nestedOverwriteRoot -ScriptPath $runnerPath -ScriptLabel 'fixture-chain-runner-v0' -ModelProvider 'self-test-provider' -ModelAlias 'self-test-model' -RuntimeName 'self-test-runner-chain' -BudgetUsd 1.0 -PerCondition 1 -AllowRunner $true -AllowOverwrite $true | Out-Null
            $failures.Add('Expected -Force to reject nested non-generated files, but overwrite succeeded.')
        } catch {
            if ($_.Exception.Message -notlike '*metadata/manual-note.txt*') {
                $failures.Add("Expected nested non-generated file rejection, got: $($_.Exception.Message)")
            }
        }

        $summary = $forcePositive
        $info.Add('Built a fixture pilot run chain through run inputs, preflight, explicit runner execution, pilot package, annotation worklist, and label templates.')
        $info.Add('Required -AllowRunnerScript and refused non-generated files when -Force was used.')
        $info.Add('Rejected root-level and nested non-generated files when -Force was used.')
        $info.Add('Generated no completed labels, agreement metrics, aggregate metrics, or paper-readiness claim.')
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
        if (-not $OutputRoot -or -not $RunnerScriptPath) {
            throw 'Provide -OutputRoot, -RunnerScriptPath, and -AllowRunnerScript, or use -SelfTest.'
        }
        $summary = New-PilotRunChain -Root $OutputRoot -ScriptPath $RunnerScriptPath -ScriptLabel $RunnerLabel -ModelProvider $Provider -ModelAlias $ModelNameOrAlias -RuntimeName $RuntimeSurface -BudgetUsd $MaxBudgetUsd -PerCondition $RecordsPerCondition -AllowRunner ([bool]$AllowRunnerScript) -AllowOverwrite ([bool]$Force)
        $info.Add('Built empirical pilot run chain at the requested OutputRoot.')
        $info.Add('Generated pilot transcripts, cost-latency records, annotation work items, and label templates through an explicit local runner script.')
    } catch {
        $failures.Add($_.Exception.Message)
    }
    $status = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
    $result = New-Result -Status $status -Failures $failures -Warnings $warnings -Info $info -Summary $summary
}

if ($Json) {
    $result | ConvertTo-Json -Depth 20
} else {
    "Empirical pilot run chain builder: $($result.status)"
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
