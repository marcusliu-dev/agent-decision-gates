param(
    [string]$AnnotationRoot,
    [string]$TemplatePackageRoot,
    [string]$WorklistRoot,
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$SelfTest,
    [switch]$Json,
    [switch]$RequireHuman,
    [switch]$RequireLlmJudge
)

$ErrorActionPreference = 'Stop'

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
    $Value | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath $Path -Encoding UTF8
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

function Assert-RationaleSpans {
    param(
        [System.Collections.Generic.List[string]]$Failures,
        [object]$Annotation,
        [object]$WorkItem,
        [string[]]$RequiredSpanFields
    )
    $spans = @(Get-JsonArray -Value $Annotation.rationale_transcript_spans)
    if ($spans.Count -eq 0) {
        $Failures.Add("Annotation '$($Annotation.annotation_id)' must include at least one rationale transcript span.")
        return
    }
    $messageCount = [int]$WorkItem.transcript_message_count
    foreach ($span in $spans) {
        Assert-RequiredFields -Failures $Failures -Record $span -Fields $RequiredSpanFields -Label "annotation '$($Annotation.annotation_id)' rationale span"
        if ($RequiredSpanFields | Where-Object { -not (Test-HasProperty -Record $span -Name $_) }) {
            continue
        }
        $messageIndex = -1
        $startOffset = -1
        $endOffset = -1
        if (-not [int]::TryParse([string]$span.transcript_message_index, [ref]$messageIndex)) {
            $Failures.Add("Annotation '$($Annotation.annotation_id)' rationale span transcript_message_index must be an integer.")
        } elseif ($messageIndex -lt 0 -or $messageIndex -ge $messageCount) {
            $Failures.Add("Annotation '$($Annotation.annotation_id)' rationale span transcript_message_index is outside transcript_message_count.")
        }
        if (-not [int]::TryParse([string]$span.start_offset, [ref]$startOffset)) {
            $Failures.Add("Annotation '$($Annotation.annotation_id)' rationale span start_offset must be an integer.")
        }
        if (-not [int]::TryParse([string]$span.end_offset, [ref]$endOffset)) {
            $Failures.Add("Annotation '$($Annotation.annotation_id)' rationale span end_offset must be an integer.")
        }
        if ($startOffset -lt 0 -or $endOffset -lt $startOffset) {
            $Failures.Add("Annotation '$($Annotation.annotation_id)' rationale span offsets must be nonnegative and ordered.")
        }
        if ([string]::IsNullOrWhiteSpace([string]$span.rationale_note)) {
            $Failures.Add("Annotation '$($Annotation.annotation_id)' rationale span rationale_note must be nonblank.")
        }
    }
}

function Invoke-AnnotationIntakeValidation {
    param(
        [string]$Root,
        [string]$SourceTemplateRoot,
        [string]$SourceWorklistRoot,
        [string]$RepositoryRoot,
        [bool]$MustHaveHuman,
        [bool]$MustHaveLlmJudge
    )
    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}

    foreach ($requiredPath in @(
        (Join-Path $RepositoryRoot 'evals/empirical/annotation-intake-schema.yaml'),
        (Join-Path $RepositoryRoot 'docs/empirical-annotation-intake.md'),
        (Join-Path $RepositoryRoot 'evals/empirical/annotation-schema.yaml'),
        (Join-Path $RepositoryRoot 'evals/empirical/label-template-package-schema.yaml'),
        (Join-Path $RepositoryRoot 'docs/empirical-annotation-guidelines.md')
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            $failures.Add("Missing repository artifact required for annotation intake scoring: $requiredPath")
        }
    }
    foreach ($requiredPath in @($Root, $SourceTemplateRoot, $SourceWorklistRoot)) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            $failures.Add("Missing required annotation intake scoring input: $requiredPath")
        }
    }
    if ($failures.Count -gt 0) {
        return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
    }

    $intakeSchemaText = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'evals/empirical/annotation-intake-schema.yaml') -Raw
    if ((Get-Scalar -Text $intakeSchemaText -Field 'claim_boundary') -ne 'annotation_intake_schema_only_no_aggregate_results') {
        $failures.Add('Annotation intake schema must declare annotation_intake_schema_only_no_aggregate_results.')
    }
    $requiredNonclaims = Get-TopLevelList -Text $intakeSchemaText -Field 'current_nonclaims'
    $forbiddenFields = Get-TopLevelList -Text $intakeSchemaText -Field 'forbidden_fields'
    $requiredJoinFields = Get-TopLevelList -Text $intakeSchemaText -Field 'required_join_fields'

    $annotationSchemaText = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'evals/empirical/annotation-schema.yaml') -Raw
    $annotationRequiredFields = Get-TopLevelList -Text $annotationSchemaText -Field 'required_fields'
    $allowedAnnotatorTypes = Get-TopLevelList -Text $annotationSchemaText -Field 'allowed_annotator_types'
    $allowedLabelValues = Get-TopLevelList -Text $annotationSchemaText -Field 'allowed_label_values'
    $requiredSpanFields = Get-TopLevelList -Text $annotationSchemaText -Field 'rationale_span_fields'
    $requiredGuidelineVersion = Get-Scalar -Text $annotationSchemaText -Field 'required_guideline_version'
    $schemaLabelFields = @($annotationRequiredFields | Where-Object { $_ -like '*_label' })
    Assert-ListContains -Failures $failures -Items $annotationRequiredFields -Required $requiredJoinFields -Label 'annotation schema required_fields'

    $packageTextParts = New-Object System.Collections.Generic.List[string]
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force)) {
        $relative = Get-RelativePackagePath -Root $Root -Path $file.FullName
        $raw = Get-Content -LiteralPath $file.FullName -Raw
        $packageTextParts.Add($raw) | Out-Null
        foreach ($hit in (Test-SensitiveText -Text $raw)) {
            $failures.Add("Annotation intake file '$relative' contains blocked sensitive pattern '$hit'.")
        }
        if ($file.Extension -ne '.json') {
            $failures.Add("Annotation intake package contains unexpected non-JSON file '$relative'.")
        }
    }
    Assert-NoForbiddenJsonFields -Failures $failures -RawJson ($packageTextParts -join "`n") -ForbiddenFields $forbiddenFields -Label 'annotation intake package'

    foreach ($directory in @('annotations', 'metadata')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root $directory))) {
            $failures.Add("Annotation intake package is missing required directory '$directory'.")
        }
    }

    $annotations = @(Read-JsonRecords -Failures $failures -Directory (Join-Path $Root 'annotations') -Label 'annotation')
    $templates = @(Read-JsonRecords -Failures $failures -Directory (Join-Path $SourceTemplateRoot 'annotation-templates') -Label 'label template')
    $workItems = @(Read-JsonRecords -Failures $failures -Directory (Join-Path $SourceWorklistRoot 'annotation-work-items') -Label 'annotation work item')
    if ($failures.Count -gt 0) {
        return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
    }

    $workItemByRunId = @{}
    foreach ($workItem in $workItems) {
        $runId = [string]$workItem.run_id
        if ($workItemByRunId.ContainsKey($runId)) {
            $failures.Add("Multiple annotation work items found for run_id '$runId'.")
        } else {
            $workItemByRunId[$runId] = $workItem
        }
    }
    $templateByRunId = @{}
    foreach ($template in $templates) {
        $runId = [string]$template.run_id
        if ($templateByRunId.ContainsKey($runId)) {
            $failures.Add("Multiple label templates found for run_id '$runId'.")
        } else {
            $templateByRunId[$runId] = $template
        }
        $templateLabelFields = @(Get-JsonArray -Value $template.required_label_fields | ForEach-Object { [string]$_ })
        foreach ($labelField in $templateLabelFields) {
            if ($schemaLabelFields -notcontains $labelField) {
                $failures.Add("Label template '$($template.annotation_template_id)' required_label_fields includes label field not present in annotation schema: '$labelField'.")
            }
        }
        Assert-ListContains -Failures $failures -Items $templateLabelFields -Required $schemaLabelFields -Label "label template $($template.annotation_template_id) required_label_fields"
        if ($workItemByRunId.ContainsKey($runId)) {
            $workItem = $workItemByRunId[$runId]
            foreach ($field in @(
                'annotation_work_item_id',
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
            $workItemLabelFields = @(Get-JsonArray -Value $workItem.required_label_fields | ForEach-Object { [string]$_ })
            foreach ($labelField in $workItemLabelFields) {
                if ($schemaLabelFields -notcontains $labelField) {
                    $failures.Add("Annotation work item '$($workItem.annotation_work_item_id)' required_label_fields includes label field not present in annotation schema: '$labelField'.")
                }
            }
            Assert-ListContains -Failures $failures -Items $workItemLabelFields -Required $schemaLabelFields -Label "annotation work item $($workItem.annotation_work_item_id) required_label_fields"
            Assert-ListContains -Failures $failures -Items $templateLabelFields -Required $workItemLabelFields -Label "label template $($template.annotation_template_id) required_label_fields"
            Assert-ListContains -Failures $failures -Items $workItemLabelFields -Required $templateLabelFields -Label "annotation work item $($workItem.annotation_work_item_id) required_label_fields"
        }
    }

    $annotationIds = @{}
    $annotationKeys = @{}
    $annotationCountByRunId = @{}
    $humanCountByRunId = @{}
    $llmJudgeCountByRunId = @{}

    foreach ($annotation in $annotations) {
        Assert-RequiredFields -Failures $failures -Record $annotation -Fields $annotationRequiredFields -Label "annotation $($annotation.annotation_id)"
        if ($annotationRequiredFields | Where-Object { -not (Test-HasProperty -Record $annotation -Name $_) }) {
            continue
        }

        $annotationId = [string]$annotation.annotation_id
        $runId = [string]$annotation.run_id
        if ($annotationIds.ContainsKey($annotationId)) {
            $failures.Add("Duplicate annotation_id '$annotationId'.")
        } else {
            $annotationIds[$annotationId] = $true
        }
        if (-not $templateByRunId.ContainsKey($runId)) {
            $failures.Add("Annotation '$annotationId' references missing label template for run_id '$runId'.")
            continue
        }
        if (-not $workItemByRunId.ContainsKey($runId)) {
            $failures.Add("Annotation '$annotationId' references missing annotation work item for run_id '$runId'.")
            continue
        }

        $template = $templateByRunId[$runId]
        $workItem = $workItemByRunId[$runId]
        if (Test-HasProperty -Record $annotation -Name 'annotation_template_id') {
            if ([string]$annotation.annotation_template_id -ne [string]$template.annotation_template_id) {
                $failures.Add("Annotation '$annotationId' annotation_template_id does not match source label template.")
            }
        }
        foreach ($field in @('task_id', 'condition', 'annotation_guideline_version')) {
            if ([string]$annotation.$field -ne [string]$template.$field) {
                $failures.Add("Annotation '$annotationId' $field does not match source label template.")
            }
            if ([string]$annotation.$field -ne [string]$workItem.$field) {
                $failures.Add("Annotation '$annotationId' $field does not match annotation work item.")
            }
        }
        if ([string]$annotation.annotation_guideline_version -ne $requiredGuidelineVersion) {
            $failures.Add("Annotation '$annotationId' annotation_guideline_version must be $requiredGuidelineVersion.")
        }

        $annotatorType = [string]$annotation.annotator_type
        if ($allowedAnnotatorTypes -notcontains $annotatorType) {
            $failures.Add("Annotation '$annotationId' annotator_type '$annotatorType' is not allowed.")
        }
        $annotationKey = "$runId|$annotatorType|$($annotation.annotator_id)"
        if ($annotationKeys.ContainsKey($annotationKey)) {
            $failures.Add("Duplicate annotation for run_id, annotator_type, and annotator_id '$annotationKey'.")
        } else {
            $annotationKeys[$annotationKey] = $true
        }

        $requiredLabelFields = $schemaLabelFields
        foreach ($labelField in $requiredLabelFields) {
            if (-not (Test-HasProperty -Record $annotation -Name $labelField)) {
                $failures.Add("Annotation '$annotationId' is missing required label field '$labelField'.")
                continue
            }
            $labelValue = [string]$annotation.$labelField
            if ($allowedLabelValues -notcontains $labelValue) {
                $failures.Add("Annotation '$annotationId' has invalid label value '$labelValue' for '$labelField'.")
            }
        }
        foreach ($property in $annotation.PSObject.Properties.Name | Where-Object { $_ -like '*_label' }) {
            if ($schemaLabelFields -notcontains $property) {
                $failures.Add("Annotation '$annotationId' contains unexpected label field '$property'.")
            }
        }

        $confidence = 0.0
        if (-not [double]::TryParse([string]$annotation.confidence, [ref]$confidence)) {
            $failures.Add("Annotation '$annotationId' confidence must be numeric.")
        } elseif ([double]::IsNaN($confidence) -or [double]::IsInfinity($confidence) -or $confidence -lt 0 -or $confidence -gt 1) {
            $failures.Add("Annotation '$annotationId' confidence must be between 0 and 1.")
        }
        try {
            [void][DateTimeOffset]::Parse([string]$annotation.label_timestamp_utc)
        } catch {
            $failures.Add("Annotation '$annotationId' label_timestamp_utc must parse as a timestamp.")
        }
        Assert-RationaleSpans -Failures $failures -Annotation $annotation -WorkItem $workItem -RequiredSpanFields $requiredSpanFields

        if (-not $annotationCountByRunId.ContainsKey($runId)) {
            $annotationCountByRunId[$runId] = 0
            $humanCountByRunId[$runId] = 0
            $llmJudgeCountByRunId[$runId] = 0
        }
        $annotationCountByRunId[$runId] = [int]$annotationCountByRunId[$runId] + 1
        if ($annotatorType -eq 'human') {
            $humanCountByRunId[$runId] = [int]$humanCountByRunId[$runId] + 1
        }
        if ($annotatorType -eq 'llm_judge') {
            $llmJudgeCountByRunId[$runId] = [int]$llmJudgeCountByRunId[$runId] + 1
        }
    }

    foreach ($template in $templates) {
        $runId = [string]$template.run_id
        if (-not $annotationCountByRunId.ContainsKey($runId)) {
            $failures.Add("Label template '$($template.annotation_template_id)' has no annotation.")
        }
        if ($MustHaveHuman -and (-not $humanCountByRunId.ContainsKey($runId) -or [int]$humanCountByRunId[$runId] -lt 1)) {
            $failures.Add("Label template '$($template.annotation_template_id)' has no human annotation.")
        }
        if ($MustHaveLlmJudge -and (-not $llmJudgeCountByRunId.ContainsKey($runId) -or [int]$llmJudgeCountByRunId[$runId] -lt 1)) {
            $failures.Add("Label template '$($template.annotation_template_id)' has no LLM-judge annotation.")
        }
    }

    $manifestPath = Join-Path $Root 'metadata/annotation-intake-manifest.json'
    $templateHashPath = Join-Path $Root 'metadata/source-label-template-package-manifest-hash.json'
    $worklistHashPath = Join-Path $Root 'metadata/source-annotation-worklist-manifest-hash.json'
    $schemaHashPath = Join-Path $Root 'metadata/annotation-schema-hash.json'
    $guidelinesHashPath = Join-Path $Root 'metadata/annotation-guidelines-hash.json'
    foreach ($metadataPath in @($manifestPath, $templateHashPath, $worklistHashPath, $schemaHashPath, $guidelinesHashPath)) {
        if (-not (Test-Path -LiteralPath $metadataPath)) {
            $failures.Add("Missing required annotation intake metadata file: $metadataPath")
        }
    }

    $expectedTemplateManifestHash = Get-FileHashHex -Path (Join-Path $SourceTemplateRoot 'metadata/label-template-package-manifest.json')
    $expectedWorklistManifestHash = Get-FileHashHex -Path (Join-Path $SourceWorklistRoot 'metadata/annotation-worklist-manifest.json')
    $expectedAnnotationSchemaHash = Get-FileHashHex -Path (Join-Path $RepositoryRoot 'evals/empirical/annotation-schema.yaml')
    $expectedGuidelinesHash = Get-FileHashHex -Path (Join-Path $RepositoryRoot 'docs/empirical-annotation-guidelines.md')
    $templateHashRecord = $null
    $worklistHashRecord = $null
    $schemaHashRecord = $null
    $guidelinesHashRecord = $null
    if (Test-Path -LiteralPath $templateHashPath) {
        $templateHashRecord = Get-Content -LiteralPath $templateHashPath -Raw | ConvertFrom-Json
        Assert-Sha256Record -Failures $failures -Record $templateHashRecord -Label 'source-label-template-package-manifest-hash.json' -ExpectedValue $expectedTemplateManifestHash -MismatchMessage 'source-label-template-package-manifest-hash.json does not match label-template package manifest.'
    }
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
        if ($manifest.claim_boundary -ne 'annotation_intake_validated_no_aggregate_results') {
            $failures.Add('Annotation intake manifest must declare annotation_intake_validated_no_aggregate_results.')
        }
        if ([int]$manifest.annotation_count -ne $annotations.Count) {
            $failures.Add("Annotation intake manifest annotation_count $($manifest.annotation_count) does not match annotation count $($annotations.Count).")
        }
        if ([int]$manifest.template_count -ne $templates.Count) {
            $failures.Add("Annotation intake manifest template_count $($manifest.template_count) does not match template count $($templates.Count).")
        }
        if ([string]$manifest.annotation_guideline_version -ne $requiredGuidelineVersion) {
            $failures.Add("Annotation intake manifest annotation_guideline_version must be $requiredGuidelineVersion.")
        }
        Assert-ListContains -Failures $failures -Items @(Get-JsonArray -Value $manifest.current_nonclaims | ForEach-Object { [string]$_ }) -Required $requiredNonclaims -Label 'annotation intake manifest current_nonclaims'
        foreach ($hashCheck in @(
            @{
                Field = 'source_label_template_package_manifest_sha256'
                Expected = $expectedTemplateManifestHash
                Sidecar = $templateHashRecord
                Label = 'label-template package manifest'
            },
            @{
                Field = 'source_annotation_worklist_manifest_sha256'
                Expected = $expectedWorklistManifestHash
                Sidecar = $worklistHashRecord
                Label = 'annotation worklist manifest'
            },
            @{
                Field = 'annotation_schema_sha256'
                Expected = $expectedAnnotationSchemaHash
                Sidecar = $schemaHashRecord
                Label = 'annotation schema'
            },
            @{
                Field = 'annotation_guidelines_sha256'
                Expected = $expectedGuidelinesHash
                Sidecar = $guidelinesHashRecord
                Label = 'annotation guidelines'
            }
        )) {
            if (-not (Test-HasProperty -Record $manifest -Name $hashCheck.Field)) {
                $failures.Add("Annotation intake manifest is missing $($hashCheck.Field).")
            } elseif ([string]$manifest.($hashCheck.Field) -ne [string]$hashCheck.Expected) {
                $failures.Add("Annotation intake manifest $($hashCheck.Field) does not match $($hashCheck.Label).")
            } elseif ($hashCheck.Sidecar -and [string]$manifest.($hashCheck.Field) -ne [string]$hashCheck.Sidecar.value) {
                $failures.Add("Annotation intake manifest $($hashCheck.Field) does not match sidecar hash record.")
            }
        }
    }

    $summary['annotation_count'] = $annotations.Count
    $summary['label_template_count'] = $templates.Count
    $summary['require_human'] = $MustHaveHuman
    $summary['require_llm_judge'] = $MustHaveLlmJudge
    $info.Add('Scored empirical annotation intake package structure.')
    $info.Add("Checked $($annotations.Count) annotation record(s) against $($templates.Count) label template record(s).")

    $status = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
    return (New-Result -Status $status -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
}

function New-SyntheticAnnotationIntakePackage {
    param(
        [string]$Root,
        [string]$TemplateRoot,
        [string]$WorklistRoot,
        [string]$RepositoryRoot
    )
    if (Test-Path -LiteralPath $Root) {
        Remove-Item -LiteralPath $Root -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'annotations') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'metadata') | Out-Null
    $templates = @(Get-ChildItem -LiteralPath (Join-Path $TemplateRoot 'annotation-templates') -File -Filter '*.json' | Sort-Object Name | ForEach-Object {
        Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
    })
    $index = 0
    foreach ($template in $templates) {
        $index++
        $annotation = [ordered]@{
            annotation_id = ('synthetic-human-annotation-{0:0000}' -f $index)
            annotation_template_id = [string]$template.annotation_template_id
            run_id = [string]$template.run_id
            task_id = [string]$template.task_id
            condition = [string]$template.condition
            annotation_guideline_version = [string]$template.annotation_guideline_version
            annotator_type = 'human'
            annotator_id = 'synthetic-human-01'
            label_timestamp_utc = '2026-01-01T00:00:00Z'
            rationale_transcript_spans = @(
                [ordered]@{
                    transcript_message_index = 0
                    start_offset = 0
                    end_offset = 20
                    rationale_note = 'Synthetic validator self-test span; not a real label rationale.'
                }
            )
            confidence = 0.75
        }
        foreach ($labelField in @(Get-JsonArray -Value $template.required_label_fields | ForEach-Object { [string]$_ })) {
            $annotation[$labelField] = 'pass'
        }
        Write-JsonFile -Path (Join-Path $Root ("annotations/{0}.json" -f $annotation.annotation_id)) -Value $annotation
    }
    $templateManifestHash = Get-FileHashHex -Path (Join-Path $TemplateRoot 'metadata/label-template-package-manifest.json')
    $worklistManifestHash = Get-FileHashHex -Path (Join-Path $WorklistRoot 'metadata/annotation-worklist-manifest.json')
    $schemaHash = Get-FileHashHex -Path (Join-Path $RepositoryRoot 'evals/empirical/annotation-schema.yaml')
    $guidelinesHash = Get-FileHashHex -Path (Join-Path $RepositoryRoot 'docs/empirical-annotation-guidelines.md')
    $currentNonclaims = @(
        'no_real_human_labels_in_repository',
        'no_real_llm_judge_labels_in_repository',
        'no_rule_based_labels_in_repository',
        'no_agreement_results',
        'no_aggregate_metrics',
        'no_statistical_results',
        'no_annotator_quality_claim',
        'no_judge_validity_claim',
        'no_empirical_effectiveness_claim',
        'no_paper_readiness'
    )
    Write-JsonFile -Path (Join-Path $Root 'metadata/source-label-template-package-manifest-hash.json') -Value ([ordered]@{ algorithm = 'sha256'; value = $templateManifestHash })
    Write-JsonFile -Path (Join-Path $Root 'metadata/source-annotation-worklist-manifest-hash.json') -Value ([ordered]@{ algorithm = 'sha256'; value = $worklistManifestHash })
    Write-JsonFile -Path (Join-Path $Root 'metadata/annotation-schema-hash.json') -Value ([ordered]@{ algorithm = 'sha256'; value = $schemaHash })
    Write-JsonFile -Path (Join-Path $Root 'metadata/annotation-guidelines-hash.json') -Value ([ordered]@{ algorithm = 'sha256'; value = $guidelinesHash })
    Write-JsonFile -Path (Join-Path $Root 'metadata/annotation-intake-manifest.json') -Value ([ordered]@{
        claim_boundary = 'annotation_intake_validated_no_aggregate_results'
        package_kind = 'synthetic_annotation_intake_selftest'
        annotation_count = $templates.Count
        template_count = $templates.Count
        annotation_guideline_version = 'annotation-guidelines-v0.1.0'
        source_label_template_package_manifest_sha256 = $templateManifestHash
        source_annotation_worklist_manifest_sha256 = $worklistManifestHash
        annotation_schema_sha256 = $schemaHash
        annotation_guidelines_sha256 = $guidelinesHash
        current_nonclaims = $currentNonclaims
    })
}

function Assert-NegativeCase {
    param(
        [System.Collections.Generic.List[string]]$Failures,
        [string]$Name,
        [scriptblock]$Mutate,
        [string]$Root,
        [string]$SourceTemplateRoot,
        [string]$SourceWorklistRoot,
        [string]$RepositoryRoot,
        [string]$ExpectedFailureText
    )
    & $Mutate
    $result = Invoke-AnnotationIntakeValidation -Root $Root -SourceTemplateRoot $SourceTemplateRoot -SourceWorklistRoot $SourceWorklistRoot -RepositoryRoot $RepositoryRoot -MustHaveHuman $true -MustHaveLlmJudge $false
    if ($result.status -eq 'pass') {
        $Failures.Add("Negative annotation intake case '$Name' unexpectedly passed.")
        return
    }
    $failureText = ($result.failures -join "`n")
    if ($failureText -notlike "*$ExpectedFailureText*") {
        $Failures.Add("Negative annotation intake case '$Name' failed, but not for expected text '$ExpectedFailureText'. Actual failures: $failureText")
    }
}

function Get-FirstAnnotationFile {
    param([string]$Root)
    $files = @(Get-ChildItem -LiteralPath (Join-Path $Root 'annotations') -File -Filter '*.json' | Sort-Object Name)
    if ($files.Count -eq 0) {
        throw 'Expected annotation intake package to contain annotation JSON files.'
    }
    return $files[0]
}

function Get-FirstTemplateFile {
    param([string]$Root)
    $files = @(Get-ChildItem -LiteralPath (Join-Path $Root 'annotation-templates') -File -Filter '*.json' | Sort-Object Name)
    if ($files.Count -eq 0) {
        throw 'Expected label-template package to contain template JSON files.'
    }
    return $files[0]
}

function Get-FirstWorkItemFile {
    param([string]$Root)
    $files = @(Get-ChildItem -LiteralPath (Join-Path $Root 'annotation-work-items') -File -Filter '*.json' | Sort-Object Name)
    if ($files.Count -eq 0) {
        throw 'Expected annotation worklist to contain work-item JSON files.'
    }
    return $files[0]
}

function Invoke-SelfTest {
    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}
    $tempBase = Join-Path ([System.IO.Path]::GetTempPath()) ("adg-annotation-intake-scorer-selftest-" + [guid]::NewGuid().ToString())
    try {
        New-Item -ItemType Directory -Force -Path $tempBase | Out-Null
        $runInputRoot = Join-Path $tempBase 'run-inputs-package'
        $preflightPath = Join-Path $tempBase 'execution-preflight.json'
        $pilotRoot = Join-Path $tempBase 'pilot-execution-package'
        $worklistRoot = Join-Path $tempBase 'annotation-worklist'
        $templateRoot = Join-Path $tempBase 'label-template-package'
        $intakeRoot = Join-Path $tempBase 'annotation-intake'
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
        New-SyntheticAnnotationIntakePackage -Root $intakeRoot -TemplateRoot $templateRoot -WorklistRoot $worklistRoot -RepositoryRoot $RepoRoot

        $positive = Invoke-AnnotationIntakeValidation -Root $intakeRoot -SourceTemplateRoot $templateRoot -SourceWorklistRoot $worklistRoot -RepositoryRoot $RepoRoot -MustHaveHuman $true -MustHaveLlmJudge $false
        if ($positive.status -ne 'pass') {
            $failures.Add("Positive annotation intake self-test failed: $($positive.failures -join '; ')")
        } else {
            $summary['annotation_count'] = $positive.summary.annotation_count
        }

        $templateFile = Get-FirstTemplateFile -Root $templateRoot
        Assert-NegativeCase -Failures $failures -Name 'unsupported_template_label' -Root $intakeRoot -SourceTemplateRoot $templateRoot -SourceWorklistRoot $worklistRoot -RepositoryRoot $RepoRoot -ExpectedFailureText 'not present in annotation schema' -Mutate {
            $template = Get-Content -LiteralPath $templateFile.FullName -Raw | ConvertFrom-Json
            $template.required_label_fields = @($template.required_label_fields) + @('unsupported_label')
            Write-JsonFile -Path $templateFile.FullName -Value $template
        }
        Remove-Item -LiteralPath $worklistRoot -Recurse -Force
        Remove-Item -LiteralPath $templateRoot -Recurse -Force
        Remove-Item -LiteralPath $intakeRoot -Recurse -Force
        & $worklistBuilder -PilotPackageRoot $pilotRoot -OutputRoot $worklistRoot | Out-Null
        & $templateBuilder -WorklistRoot $worklistRoot -OutputRoot $templateRoot | Out-Null
        New-SyntheticAnnotationIntakePackage -Root $intakeRoot -TemplateRoot $templateRoot -WorklistRoot $worklistRoot -RepositoryRoot $RepoRoot

        $workItemFile = Get-FirstWorkItemFile -Root $worklistRoot
        Assert-NegativeCase -Failures $failures -Name 'duplicate_work_item_run_id' -Root $intakeRoot -SourceTemplateRoot $templateRoot -SourceWorklistRoot $worklistRoot -RepositoryRoot $RepoRoot -ExpectedFailureText 'Multiple annotation work items found' -Mutate {
            $workItem = Get-Content -LiteralPath $workItemFile.FullName -Raw | ConvertFrom-Json
            $workItem.annotation_work_item_id = 'synthetic-duplicate-work-item'
            Write-JsonFile -Path (Join-Path (Split-Path -Parent $workItemFile.FullName) 'synthetic-duplicate-work-item.json') -Value $workItem
        }
        Remove-Item -LiteralPath $worklistRoot -Recurse -Force
        Remove-Item -LiteralPath $templateRoot -Recurse -Force
        Remove-Item -LiteralPath $intakeRoot -Recurse -Force
        & $worklistBuilder -PilotPackageRoot $pilotRoot -OutputRoot $worklistRoot | Out-Null
        & $templateBuilder -WorklistRoot $worklistRoot -OutputRoot $templateRoot | Out-Null
        New-SyntheticAnnotationIntakePackage -Root $intakeRoot -TemplateRoot $templateRoot -WorklistRoot $worklistRoot -RepositoryRoot $RepoRoot

        $workItemFile = Get-FirstWorkItemFile -Root $worklistRoot
        Assert-NegativeCase -Failures $failures -Name 'work_item_task_mismatch' -Root $intakeRoot -SourceTemplateRoot $templateRoot -SourceWorklistRoot $worklistRoot -RepositoryRoot $RepoRoot -ExpectedFailureText 'task_id does not match annotation work item' -Mutate {
            $workItem = Get-Content -LiteralPath $workItemFile.FullName -Raw | ConvertFrom-Json
            $workItem.task_id = 'changed-work-item-task'
            Write-JsonFile -Path $workItemFile.FullName -Value $workItem
        }
        Remove-Item -LiteralPath $worklistRoot -Recurse -Force
        Remove-Item -LiteralPath $templateRoot -Recurse -Force
        Remove-Item -LiteralPath $intakeRoot -Recurse -Force
        & $worklistBuilder -PilotPackageRoot $pilotRoot -OutputRoot $worklistRoot | Out-Null
        & $templateBuilder -WorklistRoot $worklistRoot -OutputRoot $templateRoot | Out-Null
        New-SyntheticAnnotationIntakePackage -Root $intakeRoot -TemplateRoot $templateRoot -WorklistRoot $worklistRoot -RepositoryRoot $RepoRoot

        $annotationFile = Get-FirstAnnotationFile -Root $intakeRoot
        Assert-NegativeCase -Failures $failures -Name 'missing_annotation_for_template' -Root $intakeRoot -SourceTemplateRoot $templateRoot -SourceWorklistRoot $worklistRoot -RepositoryRoot $RepoRoot -ExpectedFailureText 'has no human annotation' -Mutate {
            Remove-Item -LiteralPath $annotationFile.FullName -Force
        }
        New-SyntheticAnnotationIntakePackage -Root $intakeRoot -TemplateRoot $templateRoot -WorklistRoot $worklistRoot -RepositoryRoot $RepoRoot
        $annotationFile = Get-FirstAnnotationFile -Root $intakeRoot

        Assert-NegativeCase -Failures $failures -Name 'invalid_label_value' -Root $intakeRoot -SourceTemplateRoot $templateRoot -SourceWorklistRoot $worklistRoot -RepositoryRoot $RepoRoot -ExpectedFailureText 'invalid label value' -Mutate {
            $annotation = Get-Content -LiteralPath $annotationFile.FullName -Raw | ConvertFrom-Json
            $annotation.false_readiness_label = 'unsupported'
            Write-JsonFile -Path $annotationFile.FullName -Value $annotation
        }
        New-SyntheticAnnotationIntakePackage -Root $intakeRoot -TemplateRoot $templateRoot -WorklistRoot $worklistRoot -RepositoryRoot $RepoRoot
        $annotationFile = Get-FirstAnnotationFile -Root $intakeRoot

        Assert-NegativeCase -Failures $failures -Name 'confidence_nan_string' -Root $intakeRoot -SourceTemplateRoot $templateRoot -SourceWorklistRoot $worklistRoot -RepositoryRoot $RepoRoot -ExpectedFailureText 'confidence must be between 0 and 1' -Mutate {
            $annotation = Get-Content -LiteralPath $annotationFile.FullName -Raw | ConvertFrom-Json
            $annotation.confidence = 'NaN'
            Write-JsonFile -Path $annotationFile.FullName -Value $annotation
        }
        New-SyntheticAnnotationIntakePackage -Root $intakeRoot -TemplateRoot $templateRoot -WorklistRoot $worklistRoot -RepositoryRoot $RepoRoot
        $annotationFile = Get-FirstAnnotationFile -Root $intakeRoot

        Assert-NegativeCase -Failures $failures -Name 'span_out_of_range' -Root $intakeRoot -SourceTemplateRoot $templateRoot -SourceWorklistRoot $worklistRoot -RepositoryRoot $RepoRoot -ExpectedFailureText 'outside transcript_message_count' -Mutate {
            $annotation = Get-Content -LiteralPath $annotationFile.FullName -Raw | ConvertFrom-Json
            $annotation.rationale_transcript_spans[0].transcript_message_index = 9999
            Write-JsonFile -Path $annotationFile.FullName -Value $annotation
        }
        New-SyntheticAnnotationIntakePackage -Root $intakeRoot -TemplateRoot $templateRoot -WorklistRoot $worklistRoot -RepositoryRoot $RepoRoot
        $annotationFile = Get-FirstAnnotationFile -Root $intakeRoot

        Assert-NegativeCase -Failures $failures -Name 'duplicate_same_annotator' -Root $intakeRoot -SourceTemplateRoot $templateRoot -SourceWorklistRoot $worklistRoot -RepositoryRoot $RepoRoot -ExpectedFailureText 'Duplicate annotation for run_id' -Mutate {
            $annotation = Get-Content -LiteralPath $annotationFile.FullName -Raw | ConvertFrom-Json
            $annotation.annotation_id = 'synthetic-duplicate-annotation'
            Write-JsonFile -Path (Join-Path (Split-Path -Parent $annotationFile.FullName) 'synthetic-duplicate-annotation.json') -Value $annotation
        }
        New-SyntheticAnnotationIntakePackage -Root $intakeRoot -TemplateRoot $templateRoot -WorklistRoot $worklistRoot -RepositoryRoot $RepoRoot
        $annotationFile = Get-FirstAnnotationFile -Root $intakeRoot

        Assert-NegativeCase -Failures $failures -Name 'mismatched_task_id' -Root $intakeRoot -SourceTemplateRoot $templateRoot -SourceWorklistRoot $worklistRoot -RepositoryRoot $RepoRoot -ExpectedFailureText 'task_id does not match' -Mutate {
            $annotation = Get-Content -LiteralPath $annotationFile.FullName -Raw | ConvertFrom-Json
            $annotation.task_id = 'changed-task'
            Write-JsonFile -Path $annotationFile.FullName -Value $annotation
        }
        New-SyntheticAnnotationIntakePackage -Root $intakeRoot -TemplateRoot $templateRoot -WorklistRoot $worklistRoot -RepositoryRoot $RepoRoot
        $annotationFile = Get-FirstAnnotationFile -Root $intakeRoot

        Assert-NegativeCase -Failures $failures -Name 'manifest_schema_hash_mismatch' -Root $intakeRoot -SourceTemplateRoot $templateRoot -SourceWorklistRoot $worklistRoot -RepositoryRoot $RepoRoot -ExpectedFailureText 'does not match annotation schema' -Mutate {
            $manifestPath = Join-Path $intakeRoot 'metadata/annotation-intake-manifest.json'
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $manifest.annotation_schema_sha256 = ('0' * 64)
            Write-JsonFile -Path $manifestPath -Value $manifest
        }
        New-SyntheticAnnotationIntakePackage -Root $intakeRoot -TemplateRoot $templateRoot -WorklistRoot $worklistRoot -RepositoryRoot $RepoRoot
        $annotationFile = Get-FirstAnnotationFile -Root $intakeRoot

        Assert-NegativeCase -Failures $failures -Name 'forbidden_aggregate_field' -Root $intakeRoot -SourceTemplateRoot $templateRoot -SourceWorklistRoot $worklistRoot -RepositoryRoot $RepoRoot -ExpectedFailureText "forbidden field 'pass_rate'" -Mutate {
            $annotation = Get-Content -LiteralPath $annotationFile.FullName -Raw | ConvertFrom-Json
            $annotation | Add-Member -NotePropertyName 'pass_rate' -NotePropertyValue 1.0
            Write-JsonFile -Path $annotationFile.FullName -Value $annotation
        }
        New-SyntheticAnnotationIntakePackage -Root $intakeRoot -TemplateRoot $templateRoot -WorklistRoot $worklistRoot -RepositoryRoot $RepoRoot

        $extraSecretFile = Join-Path $intakeRoot 'metadata/extra-sensitive.txt'
        Assert-NegativeCase -Failures $failures -Name 'non_json_sensitive_file' -Root $intakeRoot -SourceTemplateRoot $templateRoot -SourceWorklistRoot $worklistRoot -RepositoryRoot $RepoRoot -ExpectedFailureText 'unexpected non-JSON file' -Mutate {
            Set-Content -LiteralPath $extraSecretFile -Value ('sk-' + 'abcdefghijklmnop') -Encoding UTF8
        }

        $info.Add('Validated synthetic completed-annotation intake package.')
        $info.Add('Rejected unsupported template labels, duplicate work-item run ids, work-item mismatches, missing annotation, invalid labels, NaN confidence, out-of-range spans, duplicate annotator records, mismatched task ids, metadata hash tampering, forbidden aggregate fields, and non-JSON sensitive files.')
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
    if (-not $AnnotationRoot -or -not $TemplatePackageRoot -or -not $WorklistRoot) {
        $failures = New-Object System.Collections.Generic.List[string]
        $warnings = New-Object System.Collections.Generic.List[string]
        $info = New-Object System.Collections.Generic.List[string]
        $summary = @{}
        $failures.Add('Provide -AnnotationRoot, -TemplatePackageRoot, and -WorklistRoot, or use -SelfTest.')
        $result = New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary
    } else {
        $result = Invoke-AnnotationIntakeValidation -Root $AnnotationRoot -SourceTemplateRoot $TemplatePackageRoot -SourceWorklistRoot $WorklistRoot -RepositoryRoot $RepoRoot -MustHaveHuman ([bool]$RequireHuman) -MustHaveLlmJudge ([bool]$RequireLlmJudge)
    }
}

if ($Json) {
    $result | ConvertTo-Json -Depth 20
} else {
    "Empirical annotation intake scoring: $($result.status)"
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
