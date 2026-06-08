param(
    [string]$PilotPackageRoot,
    [string]$OutputRoot,
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$SelfTest,
    [switch]$Force,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

$BuilderVersion = '0.1.0'
$GuidelineVersion = 'annotation-guidelines-v0.1.0'

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

function Get-YamlList {
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

function Get-SafeWorkItemId {
    param([string]$RunId)
    if (-not $RunId -or $RunId -match '[\\/]') {
        throw "run_id '$RunId' cannot be blank or contain path separators."
    }
    return "annotation-work-item-$RunId"
}

function Get-RequiredLabelFields {
    param([string]$RepositoryRoot)
    $schemaPath = Join-Path $RepositoryRoot 'evals/empirical/annotation-schema.yaml'
    if (-not (Test-Path -LiteralPath $schemaPath)) {
        throw "Annotation schema not found: $schemaPath"
    }
    $schemaText = Get-Content -LiteralPath $schemaPath -Raw
    return @(Get-YamlList -Text $schemaText -Field 'required_fields' | Where-Object { $_ -like '*_label' })
}

function Get-KnownGeneratedRelativePaths {
    param([object[]]$Transcripts)
    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($transcript in $Transcripts) {
        $workItemId = Get-SafeWorkItemId -RunId ([string]$transcript.run_id)
        $paths.Add("annotation-work-items/$workItemId.json") | Out-Null
    }
    foreach ($metadataName in @(
        'annotation-worklist-manifest',
        'source-pilot-execution-manifest-hash',
        'annotation-guidelines-hash'
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
        throw 'OutputRoot already exists and is not empty. Use an empty directory or pass -Force to overwrite only known annotation worklist files.'
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

function Get-PilotTranscripts {
    param([string]$Root)
    $transcriptDir = Join-Path $Root 'transcripts'
    if (-not (Test-Path -LiteralPath $transcriptDir)) {
        throw "Pilot package transcripts directory not found: $transcriptDir"
    }
    $records = New-Object System.Collections.Generic.List[object]
    foreach ($file in @(Get-ChildItem -LiteralPath $transcriptDir -File -Filter '*.json' | Sort-Object Name)) {
        $records.Add((Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json)) | Out-Null
    }
    if ($records.Count -eq 0) {
        throw 'Pilot package contains no transcript JSON records.'
    }
    return @($records.ToArray())
}

function New-AnnotationWorklist {
    param(
        [string]$PilotRoot,
        [string]$Root,
        [string]$RepositoryRoot,
        [bool]$AllowOverwrite
    )
    if (-not (Test-Path -LiteralPath $PilotRoot)) {
        throw "PilotPackageRoot not found: $PilotRoot"
    }
    $pilotManifestPath = Join-Path $PilotRoot 'metadata/pilot-execution-manifest.json'
    if (-not (Test-Path -LiteralPath $pilotManifestPath)) {
        throw "Pilot execution manifest not found: $pilotManifestPath"
    }
    $guidelinesPath = Join-Path $RepositoryRoot 'docs/empirical-annotation-guidelines.md'
    if (-not (Test-Path -LiteralPath $guidelinesPath)) {
        throw "Annotation guidelines not found: $guidelinesPath"
    }

    $transcripts = @(Get-PilotTranscripts -Root $PilotRoot)
    $knownGeneratedRelativePaths = Get-KnownGeneratedRelativePaths -Transcripts $transcripts
    Assert-OutputRootWritable -Root $Root -AllowOverwrite $AllowOverwrite -KnownGeneratedRelativePaths $knownGeneratedRelativePaths

    $requiredLabelFields = Get-RequiredLabelFields -RepositoryRoot $RepositoryRoot
    $pilotManifestHash = Get-FileHashHex -Path $pilotManifestPath
    $guidelinesHash = Get-FileHashHex -Path $guidelinesPath

    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'annotation-work-items') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'metadata') | Out-Null

    foreach ($transcript in $transcripts) {
        $workItemId = Get-SafeWorkItemId -RunId ([string]$transcript.run_id)
        $messages = @(Get-JsonArray -Value $transcript.transcript_messages)
        $workItem = [ordered]@{
            annotation_work_item_id = $workItemId
            run_id = [string]$transcript.run_id
            run_input_id = [string]$transcript.run_input_id
            task_id = [string]$transcript.task_id
            condition = [string]$transcript.condition
            repeat_index = [int]$transcript.repeat_index
            task_suite_version = [string]$transcript.task_suite_version
            prompt_version = [string]$transcript.prompt_version
            model_provider = [string]$transcript.model_provider
            model_name_or_alias = [string]$transcript.model_name_or_alias
            runtime_surface = [string]$transcript.runtime_surface
            input_prompt = [string]$transcript.input_prompt
            final_answer = [string]$transcript.final_answer
            final_claim = [string]$transcript.final_claim
            checked_evidence = @(Get-JsonArray -Value $transcript.checked_evidence)
            selected_claim_ceiling = [string]$transcript.selected_claim_ceiling
            stop_or_continue_decision = [string]$transcript.stop_or_continue_decision
            human_checkpoint_decision = [string]$transcript.human_checkpoint_decision
            transcript_message_count = $messages.Count
            transcript_spans_source = [string]$transcript.run_id
            annotation_guideline_version = $GuidelineVersion
            required_label_fields = @($requiredLabelFields)
            redaction_status = [string]$transcript.redaction_status
        }
        Write-JsonFile -Path (Join-Path $Root "annotation-work-items/$workItemId.json") -Value $workItem
    }

    Write-JsonFile -Path (Join-Path $Root 'metadata/annotation-worklist-manifest.json') -Value ([ordered]@{
        builder = 'build-empirical-annotation-worklist.ps1'
        builder_version = $BuilderVersion
        claim_boundary = 'annotation_worklist_unlabeled_no_annotations'
        generated_work_item_count = $transcripts.Count
        annotation_guideline_version = $GuidelineVersion
        source_pilot_execution_manifest_sha256 = $pilotManifestHash
        annotation_guidelines_sha256 = $guidelinesHash
        current_nonclaims = @(
            'no_annotations',
            'no_human_labels',
            'no_llm_judge_labels',
            'no_agreement_results',
            'no_aggregate_metrics',
            'no_statistical_results',
            'no_empirical_effectiveness_claim',
            'no_paper_readiness'
        )
    })
    Write-JsonFile -Path (Join-Path $Root 'metadata/source-pilot-execution-manifest-hash.json') -Value ([ordered]@{ algorithm = 'sha256'; value = $pilotManifestHash })
    Write-JsonFile -Path (Join-Path $Root 'metadata/annotation-guidelines-hash.json') -Value ([ordered]@{ algorithm = 'sha256'; value = $guidelinesHash })

    return [ordered]@{
        generated_work_item_count = $transcripts.Count
        source_pilot_execution_manifest_hash = $pilotManifestHash
        annotation_guidelines_hash = $guidelinesHash
    }
}

function Invoke-SelfTest {
    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}
    $tempBase = Join-Path ([System.IO.Path]::GetTempPath()) ("adg-annotation-worklist-builder-selftest-" + [guid]::NewGuid().ToString())
    try {
        New-Item -ItemType Directory -Force -Path $tempBase | Out-Null
        $runInputRoot = Join-Path $tempBase 'run-inputs-package'
        $preflightPath = Join-Path $tempBase 'execution-preflight.json'
        $pilotRoot = Join-Path $tempBase 'pilot-execution-package'
        $worklistRoot = Join-Path $tempBase 'annotation-worklist'
        $runnerPath = Join-Path $tempBase 'fixture-runner.ps1'
        $runInputBuilder = Join-Path $PSScriptRoot 'build-empirical-run-inputs.ps1'
        $preflightBuilder = Join-Path $PSScriptRoot 'build-empirical-execution-preflight.ps1'
        $pilotBuilder = Join-Path $PSScriptRoot 'build-empirical-pilot-execution-package.ps1'
        $scorer = Join-Path $PSScriptRoot 'score-empirical-annotation-worklist.ps1'

        @'
param(
    [string]$RequestPath,
    [string]$ResponsePath
)
$ErrorActionPreference = 'Stop'
$request = Get-Content -LiteralPath $RequestPath -Raw | ConvertFrom-Json
$answer = "Fixture pilot response for $($request.run_input_id). This local runner self-test output is not an empirical result."
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
            $failures.Add("Run-input builder failed during annotation worklist self-test: $($runInputOutput | Out-String)")
            return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
        }
        $preflightOutput = & $preflightBuilder -RunInputRoot $runInputRoot -OutputPath $preflightPath -Provider 'self-test-provider' -ModelNameOrAlias 'self-test-model' -RuntimeSurface 'self-test-runner-script' -MaxBudgetUsd 1.0 2>&1
        if (-not $?) {
            $failures.Add("Execution preflight builder failed during annotation worklist self-test: $($preflightOutput | Out-String)")
            return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
        }
        $pilotOutput = & $pilotBuilder -RunInputRoot $runInputRoot -PreflightPath $preflightPath -OutputRoot $pilotRoot -RunnerScriptPath $runnerPath -RunnerLabel 'fixture-runner-v0' -AllowRunnerScript 2>&1
        if (-not $?) {
            $failures.Add("Pilot execution package builder failed during annotation worklist self-test: $($pilotOutput | Out-String)")
            return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
        }

        try {
            $summary = New-AnnotationWorklist -PilotRoot $pilotRoot -Root $worklistRoot -RepositoryRoot $RepoRoot -AllowOverwrite $false
            if ([int]$summary.generated_work_item_count -ne 9) {
                $failures.Add("Expected 9 annotation work items; found $($summary.generated_work_item_count).")
            }
        } catch {
            $failures.Add("Annotation worklist builder failed during self-test: $($_.Exception.Message)")
            return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
        }
        if (Test-Path -LiteralPath $scorer) {
            $scoreOutput = & $scorer -PilotPackageRoot $pilotRoot -WorklistRoot $worklistRoot 2>&1
            if (-not $?) {
                $failures.Add("Annotation worklist scorer rejected the self-test package: $($scoreOutput | Out-String)")
            }
        }
        $extraFile = Join-Path $worklistRoot 'metadata/unowned-note.txt'
        Set-Content -LiteralPath $extraFile -Value 'not generated by the annotation worklist builder' -Encoding UTF8
        try {
            New-AnnotationWorklist -PilotRoot $pilotRoot -Root $worklistRoot -RepositoryRoot $RepoRoot -AllowOverwrite $true | Out-Null
            $failures.Add('Expected -Force to reject non-generated files, but overwrite succeeded.')
        } catch {
            if ($_.Exception.Message -notlike '*non-generated file*') {
                $failures.Add("Expected non-generated file rejection, got: $($_.Exception.Message)")
            }
        }
        $info.Add('Built a 9-item annotation worklist from a local fixture pilot execution package.')
        $info.Add('Generated work items without labels, agreement metrics, aggregate metrics, or model/API calls.')
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
        if (-not $PilotPackageRoot -or -not $OutputRoot) {
            throw 'Provide -PilotPackageRoot and -OutputRoot, or use -SelfTest.'
        }
        $summary = New-AnnotationWorklist -PilotRoot $PilotPackageRoot -Root $OutputRoot -RepositoryRoot $RepoRoot -AllowOverwrite ([bool]$Force)
        $info.Add('Built empirical annotation worklist from pilot execution package.')
    } catch {
        $failures.Add($_.Exception.Message)
    }
    $status = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
    $result = New-Result -Status $status -Failures $failures -Warnings $warnings -Info $info -Summary $summary
}

if ($Json) {
    $result | ConvertTo-Json -Depth 20
} else {
    "Empirical annotation worklist builder: $($result.status)"
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
