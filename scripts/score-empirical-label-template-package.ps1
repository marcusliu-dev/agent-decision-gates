param(
    [string]$TemplatePackageRoot,
    [string]$WorklistRoot,
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$SelfTest,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

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
    $Value | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-FileHashHex {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-IsSha256Hex {
    param([string]$Value)
    return ([string]$Value) -match '^[a-f0-9]{64}$'
}

function Get-RelativePackagePath {
    param(
        [string]$Root,
        [string]$Path
    )
    $resolvedRoot = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\', '/')
    return $Path.Substring($resolvedRoot.Length).TrimStart('\', '/').Replace('\', '/')
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

function Test-HasProperty {
    param(
        [object]$Record,
        [string]$Name
    )
    return $Record.PSObject.Properties.Name -contains $Name
}

function Test-IsBlankValue {
    param([object]$Value)
    if ($null -eq $Value) {
        return $true
    }
    if ($Value -is [string]) {
        return [string]::IsNullOrWhiteSpace($Value)
    }
    if ($Value -is [array]) {
        return $Value.Count -eq 0
    }
    return $false
}

function Assert-RequiredFields {
    param(
        [System.Collections.Generic.List[string]]$Failures,
        [object]$Record,
        [string[]]$Fields,
        [string]$Label
    )
    foreach ($field in $Fields) {
        if (-not (Test-HasProperty -Record $Record -Name $field)) {
            $Failures.Add("$Label is missing required field '$field'.")
            continue
        }
        if (Test-IsBlankValue -Value $Record.$field) {
            $Failures.Add("$Label has blank required field '$field'.")
        }
    }
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

function Assert-Sha256Record {
    param(
        [System.Collections.Generic.List[string]]$Failures,
        [object]$Record,
        [string]$Label,
        [string]$ExpectedValue,
        [string]$MismatchMessage
    )
    if (-not (Test-HasProperty -Record $Record -Name 'algorithm')) {
        $Failures.Add("$Label is missing algorithm.")
    } elseif ([string]$Record.algorithm -ne 'sha256') {
        $Failures.Add("$Label algorithm must be sha256.")
    }
    if (-not (Test-HasProperty -Record $Record -Name 'value')) {
        $Failures.Add("$Label is missing value.")
        return
    }
    $value = [string]$Record.value
    if (-not (Test-IsSha256Hex -Value $value)) {
        $Failures.Add("$Label value must be a lowercase sha256 hex digest.")
        return
    }
    if ($value -ne $ExpectedValue) {
        $Failures.Add($MismatchMessage)
    }
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

function Assert-NoForbiddenJsonFields {
    param(
        [System.Collections.Generic.List[string]]$Failures,
        [string]$RawJson,
        [string[]]$ForbiddenFields,
        [string]$Label
    )
    foreach ($field in $ForbiddenFields) {
        if ([regex]::IsMatch($RawJson, '"' + [regex]::Escape($field) + '"\s*:')) {
            $Failures.Add("$Label must not contain forbidden field '$field'.")
        }
    }
}

function Read-JsonRecords {
    param(
        [System.Collections.Generic.List[string]]$Failures,
        [string]$Directory,
        [string]$Label
    )
    $records = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $Directory)) {
        $Failures.Add("Missing $Label directory: $Directory")
        return @($records.ToArray())
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $Directory -File -Filter '*.json')) {
        $raw = Get-Content -LiteralPath $file.FullName -Raw
        foreach ($hit in (Test-SensitiveText -Text $raw)) {
            $Failures.Add("$Label record '$($file.Name)' contains blocked sensitive pattern '$hit'.")
        }
        try {
            $records.Add(($raw | ConvertFrom-Json)) | Out-Null
        } catch {
            $Failures.Add("Could not parse $Label record '$($file.Name)': $($_.Exception.Message)")
        }
    }
    if ($records.Count -eq 0) {
        $Failures.Add("No $Label JSON records found in $Directory.")
    }
    return @($records.ToArray())
}

function Assert-PlaceholderObject {
    param(
        [System.Collections.Generic.List[string]]$Failures,
        [object]$Template,
        [string[]]$RequiredLabelFields
    )
    foreach ($labelField in $RequiredLabelFields) {
        if (-not (Test-HasProperty -Record $Template.label_placeholders -Name $labelField)) {
            $Failures.Add("Label template '$($Template.annotation_template_id)' label_placeholders is missing '$labelField'.")
            continue
        }
        if ([string]$Template.label_placeholders.$labelField -ne $PlaceholderValue) {
            $Failures.Add("Label template '$($Template.annotation_template_id)' label placeholder '$labelField' must remain $PlaceholderValue.")
        }
    }
    foreach ($property in $Template.label_placeholders.PSObject.Properties.Name) {
        if ($RequiredLabelFields -notcontains $property) {
            $Failures.Add("Label template '$($Template.annotation_template_id)' contains unexpected label placeholder '$property'.")
        }
    }
}

function Invoke-PackageValidation {
    param(
        [string]$Root,
        [string]$SourceWorklistRoot,
        [string]$RepositoryRoot
    )
    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}

    foreach ($requiredPath in @(
        (Join-Path $RepositoryRoot 'evals/empirical/label-template-package-schema.yaml'),
        (Join-Path $RepositoryRoot 'docs/empirical-label-template-package.md'),
        (Join-Path $RepositoryRoot 'scripts/build-empirical-label-template-package.ps1'),
        (Join-Path $RepositoryRoot 'docs/empirical-annotation-guidelines.md'),
        (Join-Path $RepositoryRoot 'evals/empirical/annotation-schema.yaml')
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            $failures.Add("Missing repository artifact required for label-template package scoring: $requiredPath")
        }
    }
    foreach ($requiredPath in @($Root, $SourceWorklistRoot)) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            $failures.Add("Missing required label-template package scoring input: $requiredPath")
        }
    }
    if ($failures.Count -gt 0) {
        return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
    }

    $schemaText = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'evals/empirical/label-template-package-schema.yaml') -Raw
    if ((Get-Scalar -Text $schemaText -Field 'claim_boundary') -ne 'label_template_package_schema_only_no_real_labels') {
        $failures.Add('Label-template package schema must declare label_template_package_schema_only_no_real_labels.')
    }
    $requiredTemplateFields = Get-TopLevelList -Text $schemaText -Field 'required_template_fields'
    $requiredNonclaims = Get-TopLevelList -Text $schemaText -Field 'current_nonclaims'
    $forbiddenFields = Get-TopLevelList -Text $schemaText -Field 'forbidden_fields'

    $packageTextParts = New-Object System.Collections.Generic.List[string]
    $packageFiles = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force)
    foreach ($file in $packageFiles) {
        $relative = Get-RelativePackagePath -Root $Root -Path $file.FullName
        $raw = ''
        try {
            $raw = Get-Content -LiteralPath $file.FullName -Raw
        } catch {
            $failures.Add("Could not read label-template package file '$relative': $($_.Exception.Message)")
            continue
        }
        $packageTextParts.Add($raw) | Out-Null
        foreach ($hit in (Test-SensitiveText -Text $raw)) {
            $failures.Add("Label-template package file '$relative' contains blocked sensitive pattern '$hit'.")
        }
        if ($file.Extension -ne '.json') {
            $failures.Add("Label-template package contains unexpected non-JSON file '$relative'.")
        }
    }
    $packageText = $packageTextParts -join "`n"
    Assert-NoForbiddenJsonFields -Failures $failures -RawJson $packageText -ForbiddenFields $forbiddenFields -Label 'label-template package'

    foreach ($directory in @('annotation-templates', 'metadata')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root $directory))) {
            $failures.Add("Label-template package is missing required directory '$directory'.")
        }
    }

    $templates = @(Read-JsonRecords -Failures $failures -Directory (Join-Path $Root 'annotation-templates') -Label 'label template')
    $workItems = @(Read-JsonRecords -Failures $failures -Directory (Join-Path $SourceWorklistRoot 'annotation-work-items') -Label 'annotation work item')
    if ($failures.Count -gt 0) {
        return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
    }

    $workItemById = @{}
    foreach ($workItem in $workItems) {
        $workItemById[[string]$workItem.annotation_work_item_id] = $workItem
    }

    $templateByWorkItemId = @{}
    foreach ($template in $templates) {
        Assert-RequiredFields -Failures $failures -Record $template -Fields $requiredTemplateFields -Label "label template $($template.annotation_template_id)"
        $workItemId = [string]$template.annotation_work_item_id
        if ($templateByWorkItemId.ContainsKey($workItemId)) {
            $failures.Add("Multiple label templates found for annotation_work_item_id '$workItemId'.")
        } else {
            $templateByWorkItemId[$workItemId] = $template
        }
        if (-not $workItemById.ContainsKey($workItemId)) {
            $failures.Add("Label template '$($template.annotation_template_id)' references missing annotation work item '$workItemId'.")
            continue
        }
        $workItem = $workItemById[$workItemId]
        foreach ($field in @(
            'run_id',
            'run_input_id',
            'task_id',
            'condition',
            'repeat_index',
            'task_suite_version',
            'prompt_version',
            'annotation_guideline_version',
            'transcript_spans_source',
            'redaction_status'
        )) {
            if ([string]$template.$field -ne [string]$workItem.$field) {
                $failures.Add("Label template '$($template.annotation_template_id)' $field does not match annotation work item.")
            }
        }
        $templateLabelFields = @(Get-JsonArray -Value $template.required_label_fields | ForEach-Object { [string]$_ })
        $workItemLabelFields = @(Get-JsonArray -Value $workItem.required_label_fields | ForEach-Object { [string]$_ })
        Assert-ListContains -Failures $failures -Items $templateLabelFields -Required $workItemLabelFields -Label "label template $($template.annotation_template_id) required_label_fields"
        Assert-ListContains -Failures $failures -Items $workItemLabelFields -Required $templateLabelFields -Label "annotation work item $workItemId required_label_fields"
        Assert-PlaceholderObject -Failures $failures -Template $template -RequiredLabelFields $workItemLabelFields
        if ([string]$template.confidence_placeholder -ne $PlaceholderValue) {
            $failures.Add("Label template '$($template.annotation_template_id)' confidence_placeholder must remain $PlaceholderValue.")
        }
        $rationaleSpans = @(Get-JsonArray -Value $template.rationale_span_placeholders)
        if ($rationaleSpans.Count -eq 0) {
            $failures.Add("Label template '$($template.annotation_template_id)' is missing rationale_span_placeholders.")
        } else {
            foreach ($span in $rationaleSpans) {
                foreach ($field in @('transcript_message_index', 'start_offset', 'end_offset', 'rationale_note')) {
                    if (-not (Test-HasProperty -Record $span -Name $field)) {
                        $failures.Add("Label template '$($template.annotation_template_id)' rationale span is missing '$field'.")
                    } elseif ([string]$span.$field -ne $PlaceholderValue) {
                        $failures.Add("Label template '$($template.annotation_template_id)' rationale span '$field' must remain $PlaceholderValue.")
                    }
                }
            }
        }
    }

    foreach ($workItem in $workItems) {
        if (-not $templateByWorkItemId.ContainsKey([string]$workItem.annotation_work_item_id)) {
            $failures.Add("Annotation work item '$($workItem.annotation_work_item_id)' has no label template.")
        }
    }
    if ($templates.Count -ne $workItems.Count) {
        $failures.Add("Expected $($workItems.Count) label template records from annotation work items; found $($templates.Count).")
    }

    $manifestPath = Join-Path $Root 'metadata/label-template-package-manifest.json'
    $worklistHashPath = Join-Path $Root 'metadata/source-annotation-worklist-manifest-hash.json'
    $schemaHashPath = Join-Path $Root 'metadata/annotation-schema-hash.json'
    $guidelinesHashPath = Join-Path $Root 'metadata/annotation-guidelines-hash.json'
    foreach ($metadataPath in @($manifestPath, $worklistHashPath, $schemaHashPath, $guidelinesHashPath)) {
        if (-not (Test-Path -LiteralPath $metadataPath)) {
            $failures.Add("Missing required label-template package metadata file: $metadataPath")
        }
    }

    $expectedWorklistManifestHash = Get-FileHashHex -Path (Join-Path $SourceWorklistRoot 'metadata/annotation-worklist-manifest.json')
    $expectedAnnotationSchemaHash = Get-FileHashHex -Path (Join-Path $RepositoryRoot 'evals/empirical/annotation-schema.yaml')
    $expectedGuidelinesHash = Get-FileHashHex -Path (Join-Path $RepositoryRoot 'docs/empirical-annotation-guidelines.md')
    $worklistHashRecord = $null
    $schemaHashRecord = $null
    $guidelinesHashRecord = $null
    if (Test-Path -LiteralPath $worklistHashPath) {
        $worklistHashRecord = Get-Content -LiteralPath $worklistHashPath -Raw | ConvertFrom-Json
        Assert-Sha256Record -Failures $failures -Record $worklistHashRecord -Label 'source-annotation-worklist-manifest-hash.json' -ExpectedValue $expectedWorklistManifestHash -MismatchMessage 'source-annotation-worklist-manifest-hash.json does not match annotation worklist manifest.'
    }
    if (Test-Path -LiteralPath $schemaHashPath) {
        $schemaHashRecord = Get-Content -LiteralPath $schemaHashPath -Raw | ConvertFrom-Json
        Assert-Sha256Record -Failures $failures -Record $schemaHashRecord -Label 'annotation-schema-hash.json' -ExpectedValue $expectedAnnotationSchemaHash -MismatchMessage 'annotation-schema-hash.json does not match annotation schema.'
    }
    if (Test-Path -LiteralPath $guidelinesHashPath) {
        $guidelinesHashRecord = Get-Content -LiteralPath $guidelinesHashPath -Raw | ConvertFrom-Json
        Assert-Sha256Record -Failures $failures -Record $guidelinesHashRecord -Label 'annotation-guidelines-hash.json' -ExpectedValue $expectedGuidelinesHash -MismatchMessage 'annotation-guidelines-hash.json does not match annotation guidelines.'
    }
    if (Test-Path -LiteralPath $manifestPath) {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        if ($manifest.claim_boundary -ne 'label_template_package_unlabeled_no_completed_annotations') {
            $failures.Add('Label-template package manifest must declare label_template_package_unlabeled_no_completed_annotations.')
        }
        if ([int]$manifest.generated_template_count -ne $workItems.Count) {
            $failures.Add("Label-template package manifest generated_template_count $($manifest.generated_template_count) does not match work-item count $($workItems.Count).")
        }
        Assert-ListContains -Failures $failures -Items @(Get-JsonArray -Value $manifest.current_nonclaims | ForEach-Object { [string]$_ }) -Required $requiredNonclaims -Label 'label-template package manifest current_nonclaims'
        if (-not (Test-HasProperty -Record $manifest -Name 'source_annotation_worklist_manifest_sha256')) {
            $failures.Add('Label-template package manifest is missing source_annotation_worklist_manifest_sha256.')
        } elseif ([string]$manifest.source_annotation_worklist_manifest_sha256 -ne $expectedWorklistManifestHash) {
            $failures.Add('Label-template package manifest source_annotation_worklist_manifest_sha256 does not match annotation worklist manifest.')
        } elseif ($worklistHashRecord -and [string]$manifest.source_annotation_worklist_manifest_sha256 -ne [string]$worklistHashRecord.value) {
            $failures.Add('Label-template package manifest source_annotation_worklist_manifest_sha256 does not match source-annotation-worklist-manifest-hash.json.')
        }
        if (-not (Test-HasProperty -Record $manifest -Name 'annotation_schema_sha256')) {
            $failures.Add('Label-template package manifest is missing annotation_schema_sha256.')
        } elseif ([string]$manifest.annotation_schema_sha256 -ne $expectedAnnotationSchemaHash) {
            $failures.Add('Label-template package manifest annotation_schema_sha256 does not match annotation schema.')
        } elseif ($schemaHashRecord -and [string]$manifest.annotation_schema_sha256 -ne [string]$schemaHashRecord.value) {
            $failures.Add('Label-template package manifest annotation_schema_sha256 does not match annotation-schema-hash.json.')
        }
        if (-not (Test-HasProperty -Record $manifest -Name 'annotation_guidelines_sha256')) {
            $failures.Add('Label-template package manifest is missing annotation_guidelines_sha256.')
        } elseif ([string]$manifest.annotation_guidelines_sha256 -ne $expectedGuidelinesHash) {
            $failures.Add('Label-template package manifest annotation_guidelines_sha256 does not match annotation guidelines.')
        } elseif ($guidelinesHashRecord -and [string]$manifest.annotation_guidelines_sha256 -ne [string]$guidelinesHashRecord.value) {
            $failures.Add('Label-template package manifest annotation_guidelines_sha256 does not match annotation-guidelines-hash.json.')
        }
    }

    $summary['annotation_work_item_count'] = $workItems.Count
    $summary['label_template_count'] = $templates.Count
    $info.Add('Scored empirical label-template package structure.')
    $info.Add("Checked $($templates.Count) label template record(s) against $($workItems.Count) annotation work item record(s).")

    $status = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
    return (New-Result -Status $status -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
}

function Assert-NegativeCase {
    param(
        [System.Collections.Generic.List[string]]$Failures,
        [string]$Name,
        [scriptblock]$Mutate,
        [string]$Root,
        [string]$SourceWorklistRoot,
        [string]$RepositoryRoot,
        [string]$ExpectedFailureText
    )
    & $Mutate
    $result = Invoke-PackageValidation -Root $Root -SourceWorklistRoot $SourceWorklistRoot -RepositoryRoot $RepositoryRoot
    if ($result.status -eq 'pass') {
        $Failures.Add("Negative label-template package case '$Name' unexpectedly passed.")
        return
    }
    $failureText = ($result.failures -join "`n")
    if ($failureText -notlike "*$ExpectedFailureText*") {
        $Failures.Add("Negative label-template package case '$Name' failed, but not for expected text '$ExpectedFailureText'.")
    }
}

function Get-FirstTemplateFile {
    param([string]$Root)
    $files = @(Get-ChildItem -LiteralPath (Join-Path $Root 'annotation-templates') -File -Filter '*.json' | Sort-Object Name)
    if ($files.Count -eq 0) {
        throw 'Expected label-template package to contain template JSON files.'
    }
    return $files[0]
}

function Invoke-SelfTest {
    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}
    $tempBase = Join-Path ([System.IO.Path]::GetTempPath()) ("adg-label-template-scorer-selftest-" + [guid]::NewGuid().ToString())
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
        $templateBuilder = Join-Path $PSScriptRoot 'build-empirical-label-template-package.ps1'

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

        $positive = Invoke-PackageValidation -Root $templateRoot -SourceWorklistRoot $worklistRoot -RepositoryRoot $RepoRoot
        if ($positive.status -ne 'pass') {
            $failures.Add("Positive label-template package self-test failed: $($positive.failures -join '; ')")
        } else {
            $summary['label_template_count'] = $positive.summary.label_template_count
        }

        $templateFile = Get-FirstTemplateFile -Root $templateRoot
        Assert-NegativeCase -Failures $failures -Name 'missing_template' -Root $templateRoot -SourceWorklistRoot $worklistRoot -RepositoryRoot $RepoRoot -ExpectedFailureText 'has no label template' -Mutate {
            Remove-Item -LiteralPath $templateFile.FullName -Force
        }
        & $templateBuilder -WorklistRoot $worklistRoot -OutputRoot $templateRoot -Force | Out-Null
        $templateFile = Get-FirstTemplateFile -Root $templateRoot

        Assert-NegativeCase -Failures $failures -Name 'non_placeholder_label_value' -Root $templateRoot -SourceWorklistRoot $worklistRoot -RepositoryRoot $RepoRoot -ExpectedFailureText 'must remain __unlabeled__' -Mutate {
            $template = Get-Content -LiteralPath $templateFile.FullName -Raw | ConvertFrom-Json
            $firstLabel = @($template.required_label_fields)[0]
            $template.label_placeholders.$firstLabel = 'pass'
            Write-JsonFile -Path $templateFile.FullName -Value $template
        }
        & $templateBuilder -WorklistRoot $worklistRoot -OutputRoot $templateRoot -Force | Out-Null
        $templateFile = Get-FirstTemplateFile -Root $templateRoot

        Assert-NegativeCase -Failures $failures -Name 'mismatched_task_id' -Root $templateRoot -SourceWorklistRoot $worklistRoot -RepositoryRoot $RepoRoot -ExpectedFailureText 'task_id does not match annotation work item' -Mutate {
            $template = Get-Content -LiteralPath $templateFile.FullName -Raw | ConvertFrom-Json
            $template.task_id = 'changed-task'
            Write-JsonFile -Path $templateFile.FullName -Value $template
        }
        & $templateBuilder -WorklistRoot $worklistRoot -OutputRoot $templateRoot -Force | Out-Null
        $templateFile = Get-FirstTemplateFile -Root $templateRoot

        Assert-NegativeCase -Failures $failures -Name 'duplicate_template' -Root $templateRoot -SourceWorklistRoot $worklistRoot -RepositoryRoot $RepoRoot -ExpectedFailureText 'Multiple label templates found' -Mutate {
            $duplicatePath = Join-Path (Split-Path -Parent $templateFile.FullName) 'duplicate-template.json'
            Copy-Item -LiteralPath $templateFile.FullName -Destination $duplicatePath
        }
        & $templateBuilder -WorklistRoot $worklistRoot -OutputRoot $templateRoot -Force | Out-Null
        $templateFile = Get-FirstTemplateFile -Root $templateRoot

        Assert-NegativeCase -Failures $failures -Name 'manifest_worklist_hash_mismatch' -Root $templateRoot -SourceWorklistRoot $worklistRoot -RepositoryRoot $RepoRoot -ExpectedFailureText 'Label-template package manifest source_annotation_worklist_manifest_sha256 does not match annotation worklist manifest.' -Mutate {
            $manifestPath = Join-Path $templateRoot 'metadata/label-template-package-manifest.json'
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $manifest.source_annotation_worklist_manifest_sha256 = ('0' * 64)
            Write-JsonFile -Path $manifestPath -Value $manifest
        }
        & $templateBuilder -WorklistRoot $worklistRoot -OutputRoot $templateRoot -Force | Out-Null
        $templateFile = Get-FirstTemplateFile -Root $templateRoot

        $extraSecretFile = Join-Path $templateRoot 'metadata/extra-sensitive.txt'
        Assert-NegativeCase -Failures $failures -Name 'non_json_sensitive_file' -Root $templateRoot -SourceWorklistRoot $worklistRoot -RepositoryRoot $RepoRoot -ExpectedFailureText 'unexpected non-JSON file' -Mutate {
            Set-Content -LiteralPath $extraSecretFile -Value ('sk-' + 'abcdefghijklmnop') -Encoding UTF8
        }
        if (Test-Path -LiteralPath $extraSecretFile) {
            Remove-Item -LiteralPath $extraSecretFile -Force
        }

        $info.Add('Validated generated label-template package.')
        $info.Add('Rejected missing templates, non-placeholder label values, mismatched work-item fields, duplicate templates, metadata hash tampering, and non-JSON sensitive files.')
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
    if (-not $TemplatePackageRoot -or -not $WorklistRoot) {
        $failures = New-Object System.Collections.Generic.List[string]
        $warnings = New-Object System.Collections.Generic.List[string]
        $info = New-Object System.Collections.Generic.List[string]
        $summary = @{}
        $failures.Add('Provide -TemplatePackageRoot and -WorklistRoot, or use -SelfTest.')
        $result = New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary
    } else {
        $result = Invoke-PackageValidation -Root $TemplatePackageRoot -SourceWorklistRoot $WorklistRoot -RepositoryRoot $RepoRoot
    }
}

if ($Json) {
    $result | ConvertTo-Json -Depth 20
} else {
    "Empirical label-template package scoring: $($result.status)"
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
