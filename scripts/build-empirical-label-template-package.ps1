param(
    [string]$WorklistRoot,
    [string]$OutputRoot,
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$SelfTest,
    [switch]$Force,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

$BuilderVersion = '0.1.0'
$PlaceholderValue = '__unlabeled__'

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

function Get-SafeTemplateId {
    param([string]$WorkItemId)
    if (-not $WorkItemId -or $WorkItemId -match '[\\/]') {
        throw "annotation_work_item_id '$WorkItemId' cannot be blank or contain path separators."
    }
    return "label-template-$WorkItemId"
}

function Get-KnownGeneratedRelativePaths {
    param([object[]]$WorkItems)
    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($workItem in $WorkItems) {
        $templateId = Get-SafeTemplateId -WorkItemId ([string]$workItem.annotation_work_item_id)
        $paths.Add("annotation-templates/$templateId.json") | Out-Null
    }
    foreach ($metadataName in @(
        'label-template-package-manifest',
        'source-annotation-worklist-manifest-hash',
        'annotation-schema-hash',
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
        throw 'OutputRoot already exists and is not empty. Use an empty directory or pass -Force to overwrite only known label-template package files.'
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

function Get-AnnotationWorkItems {
    param([string]$Root)
    $workItemDir = Join-Path $Root 'annotation-work-items'
    if (-not (Test-Path -LiteralPath $workItemDir)) {
        throw "Annotation worklist work-item directory not found: $workItemDir"
    }
    $records = New-Object System.Collections.Generic.List[object]
    foreach ($file in @(Get-ChildItem -LiteralPath $workItemDir -File -Filter '*.json' | Sort-Object Name)) {
        $records.Add((Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json)) | Out-Null
    }
    if ($records.Count -eq 0) {
        throw 'Annotation worklist contains no work-item JSON records.'
    }
    return @($records.ToArray())
}

function New-LabelTemplatePackage {
    param(
        [string]$SourceWorklistRoot,
        [string]$Root,
        [string]$RepositoryRoot,
        [bool]$AllowOverwrite
    )
    if (-not (Test-Path -LiteralPath $SourceWorklistRoot)) {
        throw "WorklistRoot not found: $SourceWorklistRoot"
    }
    $worklistManifestPath = Join-Path $SourceWorklistRoot 'metadata/annotation-worklist-manifest.json'
    if (-not (Test-Path -LiteralPath $worklistManifestPath)) {
        throw "Annotation worklist manifest not found: $worklistManifestPath"
    }
    $annotationSchemaPath = Join-Path $RepositoryRoot 'evals/empirical/annotation-schema.yaml'
    $guidelinesPath = Join-Path $RepositoryRoot 'docs/empirical-annotation-guidelines.md'
    foreach ($requiredPath in @($annotationSchemaPath, $guidelinesPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Required label-template source artifact not found: $requiredPath"
        }
    }

    $workItems = @(Get-AnnotationWorkItems -Root $SourceWorklistRoot)
    $knownGeneratedRelativePaths = Get-KnownGeneratedRelativePaths -WorkItems $workItems
    Assert-OutputRootWritable -Root $Root -AllowOverwrite $AllowOverwrite -KnownGeneratedRelativePaths $knownGeneratedRelativePaths

    $worklistManifestHash = Get-FileHashHex -Path $worklistManifestPath
    $annotationSchemaHash = Get-FileHashHex -Path $annotationSchemaPath
    $guidelinesHash = Get-FileHashHex -Path $guidelinesPath

    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'annotation-templates') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'metadata') | Out-Null

    foreach ($workItem in $workItems) {
        $templateId = Get-SafeTemplateId -WorkItemId ([string]$workItem.annotation_work_item_id)
        $labelFields = @(Get-JsonArray -Value $workItem.required_label_fields | ForEach-Object { [string]$_ })
        $placeholders = [ordered]@{}
        foreach ($labelField in $labelFields) {
            $placeholders[$labelField] = $PlaceholderValue
        }
        $template = [ordered]@{
            annotation_template_id = $templateId
            annotation_work_item_id = [string]$workItem.annotation_work_item_id
            run_id = [string]$workItem.run_id
            run_input_id = [string]$workItem.run_input_id
            task_id = [string]$workItem.task_id
            condition = [string]$workItem.condition
            repeat_index = [int]$workItem.repeat_index
            task_suite_version = [string]$workItem.task_suite_version
            prompt_version = [string]$workItem.prompt_version
            annotation_guideline_version = [string]$workItem.annotation_guideline_version
            required_label_fields = @($labelFields)
            label_placeholders = $placeholders
            rationale_span_placeholders = @(
                [ordered]@{
                    transcript_message_index = $PlaceholderValue
                    start_offset = $PlaceholderValue
                    end_offset = $PlaceholderValue
                    rationale_note = $PlaceholderValue
                }
            )
            confidence_placeholder = $PlaceholderValue
            transcript_spans_source = [string]$workItem.transcript_spans_source
            redaction_status = [string]$workItem.redaction_status
        }
        Write-JsonFile -Path (Join-Path $Root "annotation-templates/$templateId.json") -Value $template
    }

    Write-JsonFile -Path (Join-Path $Root 'metadata/label-template-package-manifest.json') -Value ([ordered]@{
        builder = 'build-empirical-label-template-package.ps1'
        builder_version = $BuilderVersion
        claim_boundary = 'label_template_package_unlabeled_no_completed_annotations'
        generated_template_count = $workItems.Count
        source_annotation_worklist_manifest_sha256 = $worklistManifestHash
        annotation_schema_sha256 = $annotationSchemaHash
        annotation_guidelines_sha256 = $guidelinesHash
        current_nonclaims = @(
            'no_completed_annotations',
            'no_human_labels',
            'no_llm_judge_labels',
            'no_rule_based_labels',
            'no_agreement_results',
            'no_aggregate_metrics',
            'no_statistical_results',
            'no_empirical_effectiveness_claim',
            'no_paper_readiness'
        )
    })
    Write-JsonFile -Path (Join-Path $Root 'metadata/source-annotation-worklist-manifest-hash.json') -Value ([ordered]@{ algorithm = 'sha256'; value = $worklistManifestHash })
    Write-JsonFile -Path (Join-Path $Root 'metadata/annotation-schema-hash.json') -Value ([ordered]@{ algorithm = 'sha256'; value = $annotationSchemaHash })
    Write-JsonFile -Path (Join-Path $Root 'metadata/annotation-guidelines-hash.json') -Value ([ordered]@{ algorithm = 'sha256'; value = $guidelinesHash })

    return [ordered]@{
        generated_template_count = $workItems.Count
        source_annotation_worklist_manifest_hash = $worklistManifestHash
        annotation_schema_hash = $annotationSchemaHash
        annotation_guidelines_hash = $guidelinesHash
    }
}

function Invoke-SelfTest {
    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}
    $tempBase = Join-Path ([System.IO.Path]::GetTempPath()) ("adg-label-template-builder-selftest-" + [guid]::NewGuid().ToString())
    try {
        New-Item -ItemType Directory -Force -Path $tempBase | Out-Null
        $runInputRoot = Join-Path $tempBase 'run-inputs-package'
        $preflightPath = Join-Path $tempBase 'execution-preflight.json'
        $pilotRoot = Join-Path $tempBase 'pilot-execution-package'
        $worklistRoot = Join-Path $tempBase 'annotation-worklist'
        $templateRoot = Join-Path $tempBase 'label-template-package'
        $runnerPath = Join-Path $tempBase 'fixture-runner.ps1'
        $runInputBuilder = Join-Path $PSScriptRoot 'build-empirical-run-inputs.ps1'
        $preflightBuilder = Join-Path $PSScriptRoot 'build-empirical-execution-preflight.ps1'
        $pilotBuilder = Join-Path $PSScriptRoot 'build-empirical-pilot-execution-package.ps1'
        $worklistBuilder = Join-Path $PSScriptRoot 'build-empirical-annotation-worklist.ps1'
        $scorer = Join-Path $PSScriptRoot 'score-empirical-label-template-package.ps1'

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

        & $runInputBuilder -OutputRoot $runInputRoot | Out-Null
        & $preflightBuilder -RunInputRoot $runInputRoot -OutputPath $preflightPath -Provider 'self-test-provider' -ModelNameOrAlias 'self-test-model' -RuntimeSurface 'self-test-runner-script' -MaxBudgetUsd 1.0 | Out-Null
        & $pilotBuilder -RunInputRoot $runInputRoot -PreflightPath $preflightPath -OutputRoot $pilotRoot -RunnerScriptPath $runnerPath -RunnerLabel 'fixture-runner-v0' -AllowRunnerScript | Out-Null
        & $worklistBuilder -PilotPackageRoot $pilotRoot -OutputRoot $worklistRoot | Out-Null

        try {
            $summary = New-LabelTemplatePackage -SourceWorklistRoot $worklistRoot -Root $templateRoot -RepositoryRoot $RepoRoot -AllowOverwrite $false
            if ([int]$summary.generated_template_count -ne 9) {
                $failures.Add("Expected 9 label templates; found $($summary.generated_template_count).")
            }
        } catch {
            $failures.Add("Label-template package builder failed during self-test: $($_.Exception.Message)")
            return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
        }
        if (Test-Path -LiteralPath $scorer) {
            $scoreOutput = & $scorer -WorklistRoot $worklistRoot -TemplatePackageRoot $templateRoot 2>&1
            if (-not $?) {
                $failures.Add("Label-template package scorer rejected the self-test package: $($scoreOutput | Out-String)")
            }
        }
        $extraFile = Join-Path $templateRoot 'metadata/unowned-note.txt'
        Set-Content -LiteralPath $extraFile -Value 'not generated by the label-template package builder' -Encoding UTF8
        try {
            New-LabelTemplatePackage -SourceWorklistRoot $worklistRoot -Root $templateRoot -RepositoryRoot $RepoRoot -AllowOverwrite $true | Out-Null
            $failures.Add('Expected -Force to reject non-generated files, but overwrite succeeded.')
        } catch {
            if ($_.Exception.Message -notlike '*non-generated file*') {
                $failures.Add("Expected non-generated file rejection, got: $($_.Exception.Message)")
            }
        }
        $info.Add('Built a 9-template label-template package from a local fixture annotation worklist.')
        $info.Add('Generated templates with placeholders only, no completed labels, agreement metrics, aggregate metrics, or model/API calls.')
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
        if (-not $WorklistRoot -or -not $OutputRoot) {
            throw 'Provide -WorklistRoot and -OutputRoot, or use -SelfTest.'
        }
        $summary = New-LabelTemplatePackage -SourceWorklistRoot $WorklistRoot -Root $OutputRoot -RepositoryRoot $RepoRoot -AllowOverwrite ([bool]$Force)
        $info.Add('Built empirical label-template package from annotation worklist.')
    } catch {
        $failures.Add($_.Exception.Message)
    }
    $status = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
    $result = New-Result -Status $status -Failures $failures -Warnings $warnings -Info $info -Summary $summary
}

if ($Json) {
    $result | ConvertTo-Json -Depth 20
} else {
    "Empirical label-template package builder: $($result.status)"
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
