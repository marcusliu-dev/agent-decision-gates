param(
    [string]$PilotPackageRoot,
    [string]$TemplatePackageRoot,
    [string]$WorklistRoot,
    [string]$OutputRoot,
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$SelfTest,
    [switch]$Force,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

$BuilderVersion = '0.1.0'
$LabelPlaceholder = '__fill_one_of_pass_fail_partial_not_applicable_insufficient_evidence__'
$AnnotatorIdPlaceholder = '__fill_human_annotator_id__'
$TimestampPlaceholder = '__fill_iso8601_utc_timestamp__'
$MessageIndexPlaceholder = '__fill_message_index__'
$StartOffsetPlaceholder = '__fill_start_offset__'
$EndOffsetPlaceholder = '__fill_end_offset__'
$ConfidencePlaceholder = '__fill_0_to_1__'
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
    $Value | ConvertTo-Json -Depth 80 | Set-Content -LiteralPath $Path -Encoding UTF8
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

function Get-SafeRunId {
    param([string]$RunId)
    if (-not $RunId -or $RunId -match '[\\/]') {
        throw "run_id '$RunId' cannot be blank or contain path separators."
    }
    return $RunId
}

function Get-AssistantText {
    param([object]$Transcript)
    if ($Transcript.PSObject.Properties.Name -contains 'final_answer') {
        return [string]$Transcript.final_answer
    }
    $messages = @(Get-JsonArray -Value $Transcript.transcript_messages)
    $assistant = @($messages | Where-Object { [string]$_.role -eq 'assistant' } | Select-Object -Last 1)
    if ($assistant.Count -gt 0) {
        return [string]$assistant[0].content
    }
    return ''
}

function Format-MarkdownCodeBlock {
    param([string]$Text)
    return ($Text -replace '```', '`` `')
}

function Get-KnownGeneratedRelativePaths {
    param([object[]]$Templates)
    $paths = New-Object System.Collections.Generic.List[string]
    $paths.Add('README.md') | Out-Null
    foreach ($template in $Templates) {
        $runId = Get-SafeRunId -RunId ([string]$template.run_id)
        $paths.Add("annotation-drafts/human-draft-$runId.json") | Out-Null
        $paths.Add("transcript-readouts/$runId.md") | Out-Null
    }
    foreach ($metadataName in @(
        'human-annotation-handoff-manifest',
        'source-label-template-package-manifest-hash',
        'source-annotation-worklist-manifest-hash',
        'source-pilot-execution-manifest-hash',
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
        throw 'OutputRoot already exists and is not empty. Use an empty directory or pass -Force to overwrite only known human-annotation handoff files.'
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

function Get-LabelTemplates {
    param([string]$Root)
    $templateDir = Join-Path $Root 'annotation-templates'
    if (-not (Test-Path -LiteralPath $templateDir)) {
        throw "Label-template package template directory not found: $templateDir"
    }
    $records = New-Object System.Collections.Generic.List[object]
    foreach ($file in @(Get-ChildItem -LiteralPath $templateDir -File -Filter '*.json' | Sort-Object Name)) {
        $records.Add((Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json)) | Out-Null
    }
    if ($records.Count -eq 0) {
        throw 'Label-template package contains no template JSON records.'
    }
    return @($records.ToArray())
}

function New-HumanAnnotationHandoff {
    param(
        [string]$SourcePilotPackageRoot,
        [string]$SourceTemplatePackageRoot,
        [string]$SourceWorklistRoot,
        [string]$Root,
        [string]$RepositoryRoot,
        [bool]$AllowOverwrite
    )

    foreach ($requiredPath in @(
        $SourcePilotPackageRoot,
        $SourceTemplatePackageRoot,
        $SourceWorklistRoot,
        (Join-Path $SourcePilotPackageRoot 'transcripts'),
        (Join-Path $SourcePilotPackageRoot 'metadata/pilot-execution-manifest.json'),
        (Join-Path $SourceTemplatePackageRoot 'metadata/label-template-package-manifest.json'),
        (Join-Path $SourceWorklistRoot 'metadata/annotation-worklist-manifest.json'),
        (Join-Path $RepositoryRoot 'evals/empirical/annotation-schema.yaml'),
        (Join-Path $RepositoryRoot 'docs/empirical-annotation-guidelines.md')
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Required human handoff source artifact not found: $requiredPath"
        }
    }

    $templates = @(Get-LabelTemplates -Root $SourceTemplatePackageRoot)
    $knownGeneratedRelativePaths = Get-KnownGeneratedRelativePaths -Templates $templates
    Assert-OutputRootWritable -Root $Root -AllowOverwrite $AllowOverwrite -KnownGeneratedRelativePaths $knownGeneratedRelativePaths

    foreach ($dir in @('annotation-drafts', 'transcript-readouts', 'metadata')) {
        New-Item -ItemType Directory -Force -Path (Join-Path $Root $dir) | Out-Null
    }

    $draftCount = 0
    $readoutCount = 0
    foreach ($template in $templates) {
        $runId = Get-SafeRunId -RunId ([string]$template.run_id)
        $workItemPath = Join-Path (Join-Path $SourceWorklistRoot 'annotation-work-items') "$($template.annotation_work_item_id).json"
        $transcriptPath = Join-Path (Join-Path $SourcePilotPackageRoot 'transcripts') "$runId.json"
        if (-not (Test-Path -LiteralPath $workItemPath)) {
            throw "Missing annotation work item for template '$($template.annotation_template_id)': $workItemPath"
        }
        if (-not (Test-Path -LiteralPath $transcriptPath)) {
            throw "Missing pilot transcript for template '$($template.annotation_template_id)': $transcriptPath"
        }
        $workItem = Get-Content -LiteralPath $workItemPath -Raw | ConvertFrom-Json
        $transcript = Get-Content -LiteralPath $transcriptPath -Raw | ConvertFrom-Json
        $assistantText = Get-AssistantText -Transcript $transcript

        $draft = [ordered]@{
            annotation_id = "human-draft-$runId"
            annotation_template_id = [string]$template.annotation_template_id
            annotation_work_item_id = [string]$template.annotation_work_item_id
            run_id = $runId
            run_input_id = [string]$template.run_input_id
            task_id = [string]$template.task_id
            condition = [string]$template.condition
            repeat_index = [int]$template.repeat_index
            task_suite_version = [string]$template.task_suite_version
            prompt_version = [string]$template.prompt_version
            annotation_guideline_version = $GuidelineVersion
            annotator_type = 'human'
            annotator_id = $AnnotatorIdPlaceholder
            label_timestamp_utc = $TimestampPlaceholder
        }
        foreach ($labelField in @(Get-JsonArray -Value $template.required_label_fields)) {
            $draft[[string]$labelField] = $LabelPlaceholder
        }
        $draft['rationale_transcript_spans'] = @(
            [ordered]@{
                transcript_message_index = $MessageIndexPlaceholder
                start_offset = $StartOffsetPlaceholder
                end_offset = $EndOffsetPlaceholder
                rationale_note = 'Replace message index and offsets with the transcript span that justifies the labels.'
            }
        )
        $draft['confidence'] = $ConfidencePlaceholder
        $draft['claim_boundary'] = 'human_annotation_draft_unfilled_no_label_claim'
        $draft['source_redaction_status'] = [string]$workItem.redaction_status
        Write-JsonFile -Path (Join-Path (Join-Path $Root 'annotation-drafts') "human-draft-$runId.json") -Value $draft
        $draftCount++

$readout = @"
# Human Annotation Readout: $runId

## Metadata

- task_id: $($template.task_id)
- condition: $($template.condition)
- repeat_index: $($template.repeat_index)
- guideline_version: $GuidelineVersion
- annotation_draft: annotation-drafts/human-draft-$runId.json
- source_redaction_status: $($workItem.redaction_status)

## Task Prompt

~~~text
$(Format-MarkdownCodeBlock -Text ([string]$workItem.input_prompt))
~~~

## Model Final Answer

Message index: 1

~~~text
$(Format-MarkdownCodeBlock -Text $assistantText)
~~~

## Label Fields

Use only: pass, fail, partial, not_applicable, insufficient_evidence.

- false_readiness_label
- overclaim_label
- objective_narrowing_label
- human_checkpoint_recall_label
- unnecessary_stop_label
- nonlocal_route_violation_label
- stale_source_reliance_label
- counter_review_catch_label
- adjudication_override_quality_label
- final_claim_supported_label

Record at least one transcript span in the JSON draft. Offsets are character
offsets into the cited transcript message content.
"@
        Set-Content -LiteralPath (Join-Path (Join-Path $Root 'transcript-readouts') "$runId.md") -Value $readout -Encoding UTF8
        $readoutCount++
    }

    $templateManifestHash = Get-FileHashHex -Path (Join-Path $SourceTemplatePackageRoot 'metadata/label-template-package-manifest.json')
    $worklistManifestHash = Get-FileHashHex -Path (Join-Path $SourceWorklistRoot 'metadata/annotation-worklist-manifest.json')
    $pilotManifestHash = Get-FileHashHex -Path (Join-Path $SourcePilotPackageRoot 'metadata/pilot-execution-manifest.json')
    $schemaHash = Get-FileHashHex -Path (Join-Path $RepositoryRoot 'evals/empirical/annotation-schema.yaml')
    $guidelinesHash = Get-FileHashHex -Path (Join-Path $RepositoryRoot 'docs/empirical-annotation-guidelines.md')

    Write-JsonFile -Path (Join-Path $Root 'metadata/source-label-template-package-manifest-hash.json') -Value ([ordered]@{ algorithm = 'sha256'; value = $templateManifestHash })
    Write-JsonFile -Path (Join-Path $Root 'metadata/source-annotation-worklist-manifest-hash.json') -Value ([ordered]@{ algorithm = 'sha256'; value = $worklistManifestHash })
    Write-JsonFile -Path (Join-Path $Root 'metadata/source-pilot-execution-manifest-hash.json') -Value ([ordered]@{ algorithm = 'sha256'; value = $pilotManifestHash })
    Write-JsonFile -Path (Join-Path $Root 'metadata/annotation-schema-hash.json') -Value ([ordered]@{ algorithm = 'sha256'; value = $schemaHash })
    Write-JsonFile -Path (Join-Path $Root 'metadata/annotation-guidelines-hash.json') -Value ([ordered]@{ algorithm = 'sha256'; value = $guidelinesHash })

    Write-JsonFile -Path (Join-Path $Root 'metadata/human-annotation-handoff-manifest.json') -Value ([ordered]@{
        builder = 'build-empirical-human-annotation-handoff.ps1'
        builder_version = $BuilderVersion
        package_kind = 'human_annotation_handoff_unfilled'
        claim_boundary = 'human_annotation_handoff_unfilled_no_labels'
        draft_count = $draftCount
        transcript_readout_count = $readoutCount
        template_count = $templates.Count
        annotation_guideline_version = $GuidelineVersion
        source_label_template_package_manifest_sha256 = $templateManifestHash
        source_annotation_worklist_manifest_sha256 = $worklistManifestHash
        source_pilot_execution_manifest_sha256 = $pilotManifestHash
        annotation_schema_sha256 = $schemaHash
        annotation_guidelines_sha256 = $guidelinesHash
        current_nonclaims = @(
            'no_completed_human_labels',
            'no_human_llm_agreement',
            'no_aggregate_metrics',
            'no_judge_validity_claim',
            'no_empirical_effectiveness_claim',
            'no_paper_readiness'
        )
    })

$readme = @"
# Human Annotation Handoff

This generated package is for filling future human labels. It is not an annotation intake package yet and it does not contain completed labels.

## What To Fill

1. Open one file in transcript-readouts/.
2. Read the task prompt and model final answer.
3. Fill the matching JSON file in annotation-drafts/.
4. Use only these label values:
   pass, fail, partial, not_applicable, insufficient_evidence.
5. Replace every __fill...__ placeholder before treating a draft as a human
   annotation.
6. Set annotator_id, label_timestamp_utc, confidence, all label fields, and at
   least one rationale_transcript_spans entry.

## After Filling

Copy completed JSON records into an annotation intake package and validate with
score-empirical-annotation-intake.ps1 -RequireHuman. Then assemble a new
evidence package and run agreement checks when human and LLM-judge labels both
exist.

## Boundary

This handoff supports only human_annotation_handoff_unfilled_no_labels. It does
not prove human labels, agreement, judge validity, empirical effectiveness,
public results, production safety, or paper readiness.
"@
    Set-Content -LiteralPath (Join-Path $Root 'README.md') -Value $readme -Encoding UTF8

    return [ordered]@{
        draft_count = $draftCount
        transcript_readout_count = $readoutCount
        template_count = $templates.Count
        source_label_template_package_manifest_hash = $templateManifestHash
        source_annotation_worklist_manifest_hash = $worklistManifestHash
        source_pilot_execution_manifest_hash = $pilotManifestHash
        annotation_schema_hash = $schemaHash
        annotation_guidelines_hash = $guidelinesHash
    }
}

function Invoke-SelfTest {
    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}
    $tempBase = Join-Path ([System.IO.Path]::GetTempPath()) ("adg-human-handoff-builder-selftest-" + [guid]::NewGuid().ToString())
    try {
        New-Item -ItemType Directory -Force -Path $tempBase | Out-Null
        $runInputRoot = Join-Path $tempBase 'run-inputs-package'
        $preflightPath = Join-Path $tempBase 'execution-preflight.json'
        $pilotRoot = Join-Path $tempBase 'pilot-execution-package'
        $worklistRoot = Join-Path $tempBase 'annotation-worklist'
        $templateRoot = Join-Path $tempBase 'label-template-package'
        $handoffRoot = Join-Path $tempBase 'human-annotation-handoff'
        $runnerPath = Join-Path $tempBase 'fixture-runner.ps1'
        $runInputBuilder = Join-Path $PSScriptRoot 'build-empirical-run-inputs.ps1'
        $preflightBuilder = Join-Path $PSScriptRoot 'build-empirical-execution-preflight.ps1'
        $pilotBuilder = Join-Path $PSScriptRoot 'build-empirical-pilot-execution-package.ps1'
        $worklistBuilder = Join-Path $PSScriptRoot 'build-empirical-annotation-worklist.ps1'
        $templateBuilder = Join-Path $PSScriptRoot 'build-empirical-label-template-package.ps1'
        $scorer = Join-Path $PSScriptRoot 'score-empirical-human-annotation-handoff.ps1'

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
        & $templateBuilder -WorklistRoot $worklistRoot -OutputRoot $templateRoot | Out-Null

        try {
            $summary = New-HumanAnnotationHandoff -SourcePilotPackageRoot $pilotRoot -SourceTemplatePackageRoot $templateRoot -SourceWorklistRoot $worklistRoot -Root $handoffRoot -RepositoryRoot $RepoRoot -AllowOverwrite $false
            if ([int]$summary.draft_count -ne 9) {
                $failures.Add("Expected 9 human annotation drafts; found $($summary.draft_count).")
            }
            if ([int]$summary.transcript_readout_count -ne 9) {
                $failures.Add("Expected 9 transcript readouts; found $($summary.transcript_readout_count).")
            }
        } catch {
            $failures.Add("Human annotation handoff builder failed during self-test: $($_.Exception.Message)")
            return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
        }
        if (Test-Path -LiteralPath $scorer) {
            $scoreOutput = & $scorer -PilotPackageRoot $pilotRoot -WorklistRoot $worklistRoot -TemplatePackageRoot $templateRoot -HandoffRoot $handoffRoot 2>&1
            if (-not $?) {
                $failures.Add("Human annotation handoff scorer rejected the self-test package: $($scoreOutput | Out-String)")
            }
        }
        $extraFile = Join-Path $handoffRoot 'metadata/unowned-note.txt'
        Set-Content -LiteralPath $extraFile -Value 'not generated by the human handoff builder' -Encoding UTF8
        try {
            New-HumanAnnotationHandoff -SourcePilotPackageRoot $pilotRoot -SourceTemplatePackageRoot $templateRoot -SourceWorklistRoot $worklistRoot -Root $handoffRoot -RepositoryRoot $RepoRoot -AllowOverwrite $true | Out-Null
            $failures.Add('Expected -Force to reject non-generated files, but overwrite succeeded.')
        } catch {
            if ($_.Exception.Message -notlike '*non-generated file*') {
                $failures.Add("Expected non-generated file rejection, got: $($_.Exception.Message)")
            }
        }
        $info.Add('Built a 9-draft human annotation handoff from a local fixture label-template package.')
        $info.Add('Generated unfilled human drafts and transcript readouts only, no completed labels, agreement metrics, aggregate metrics, or model/API calls.')
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
        if (-not $PilotPackageRoot -or -not $TemplatePackageRoot -or -not $WorklistRoot -or -not $OutputRoot) {
            throw 'Provide -PilotPackageRoot, -TemplatePackageRoot, -WorklistRoot, and -OutputRoot, or use -SelfTest.'
        }
        $summary = New-HumanAnnotationHandoff -SourcePilotPackageRoot $PilotPackageRoot -SourceTemplatePackageRoot $TemplatePackageRoot -SourceWorklistRoot $WorklistRoot -Root $OutputRoot -RepositoryRoot $RepoRoot -AllowOverwrite ([bool]$Force)
        $info.Add('Built empirical human annotation handoff from label-template package.')
    } catch {
        $failures.Add($_.Exception.Message)
    }
    $status = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
    $result = New-Result -Status $status -Failures $failures -Warnings $warnings -Info $info -Summary $summary
}

if ($Json) {
    $result | ConvertTo-Json -Depth 20
} else {
    "Empirical human annotation handoff builder: $($result.status)"
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
