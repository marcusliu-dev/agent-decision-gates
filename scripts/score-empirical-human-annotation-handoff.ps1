param(
    [string]$HandoffRoot,
    [string]$PilotPackageRoot,
    [string]$TemplatePackageRoot,
    [string]$WorklistRoot,
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$SelfTest,
    [switch]$Json
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
        [string]$RawText,
        [string[]]$ForbiddenFields,
        [string]$Label
    )
    foreach ($field in $ForbiddenFields) {
        if ([regex]::IsMatch($RawText, '"' + [regex]::Escape($field) + '"\s*:')) {
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
    foreach ($file in @(Get-ChildItem -LiteralPath $Directory -File -Filter '*.json' | Sort-Object Name)) {
        $raw = Get-Content -LiteralPath $file.FullName -Raw
        foreach ($hit in (Test-SensitiveText -Text $raw)) {
            $Failures.Add("$Label record '$($file.Name)' contains blocked sensitive pattern '$hit'.")
        }
        try {
            $record = $raw | ConvertFrom-Json
            $record | Add-Member -NotePropertyName '__source_file_name' -NotePropertyValue $file.Name -Force
            $records.Add($record) | Out-Null
        } catch {
            $Failures.Add("Could not parse $Label record '$($file.Name)': $($_.Exception.Message)")
        }
    }
    if ($records.Count -eq 0) {
        $Failures.Add("No $Label JSON records found in $Directory.")
    }
    return @($records.ToArray())
}

function Assert-HumanDraftPlaceholders {
    param(
        [System.Collections.Generic.List[string]]$Failures,
        [object]$Draft,
        [string[]]$RequiredLabelFields,
        [string]$LabelPlaceholder,
        [string]$AnnotatorIdPlaceholder,
        [string]$TimestampPlaceholder,
        [string]$MessageIndexPlaceholder,
        [string]$StartOffsetPlaceholder,
        [string]$EndOffsetPlaceholder,
        [string]$ConfidencePlaceholder
    )
    if ([string]$Draft.annotator_type -ne 'human') {
        $Failures.Add("Human handoff draft '$($Draft.annotation_id)' annotator_type must be human.")
    }
    if ([string]$Draft.annotator_id -ne $AnnotatorIdPlaceholder) {
        $Failures.Add("Human handoff draft '$($Draft.annotation_id)' annotator_id must remain $AnnotatorIdPlaceholder.")
    }
    if ([string]$Draft.label_timestamp_utc -ne $TimestampPlaceholder) {
        $Failures.Add("Human handoff draft '$($Draft.annotation_id)' label_timestamp_utc must remain $TimestampPlaceholder.")
    }
    if ([string]$Draft.confidence -ne $ConfidencePlaceholder) {
        $Failures.Add("Human handoff draft '$($Draft.annotation_id)' confidence must remain $ConfidencePlaceholder.")
    }
    if ([string]$Draft.claim_boundary -ne 'human_annotation_draft_unfilled_no_label_claim') {
        $Failures.Add("Human handoff draft '$($Draft.annotation_id)' claim_boundary must be human_annotation_draft_unfilled_no_label_claim.")
    }
    foreach ($labelField in $RequiredLabelFields) {
        if (-not (Test-HasProperty -Record $Draft -Name $labelField)) {
            $Failures.Add("Human handoff draft '$($Draft.annotation_id)' is missing label field '$labelField'.")
            continue
        }
        if ([string]$Draft.$labelField -ne $LabelPlaceholder) {
            $Failures.Add("Human handoff draft '$($Draft.annotation_id)' label '$labelField' must remain $LabelPlaceholder.")
        }
    }
    $spans = @(Get-JsonArray -Value $Draft.rationale_transcript_spans)
    if ($spans.Count -ne 1) {
        $Failures.Add("Human handoff draft '$($Draft.annotation_id)' must contain exactly one placeholder rationale span.")
    } else {
        $span = $spans[0]
        $expectations = @{
            transcript_message_index = $MessageIndexPlaceholder
            start_offset = $StartOffsetPlaceholder
            end_offset = $EndOffsetPlaceholder
        }
        foreach ($field in $expectations.Keys) {
            if (-not (Test-HasProperty -Record $span -Name $field)) {
                $Failures.Add("Human handoff draft '$($Draft.annotation_id)' rationale span is missing '$field'.")
            } elseif ([string]$span.$field -ne [string]$expectations[$field]) {
                $Failures.Add("Human handoff draft '$($Draft.annotation_id)' rationale span '$field' must remain $($expectations[$field]).")
            }
        }
    }
}

function Invoke-PackageValidation {
    param(
        [string]$Root,
        [string]$SourcePilotPackageRoot,
        [string]$SourceTemplatePackageRoot,
        [string]$SourceWorklistRoot,
        [string]$RepositoryRoot
    )
    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}

    foreach ($requiredPath in @(
        (Join-Path $RepositoryRoot 'evals/empirical/human-annotation-handoff-schema.yaml'),
        (Join-Path $RepositoryRoot 'docs/empirical-human-annotation-handoff.md'),
        (Join-Path $RepositoryRoot 'scripts/build-empirical-human-annotation-handoff.ps1'),
        (Join-Path $RepositoryRoot 'docs/empirical-annotation-guidelines.md'),
        (Join-Path $RepositoryRoot 'evals/empirical/annotation-schema.yaml')
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            $failures.Add("Missing repository artifact required for human handoff scoring: $requiredPath")
        }
    }
    foreach ($requiredPath in @($Root, $SourcePilotPackageRoot, $SourceTemplatePackageRoot, $SourceWorklistRoot)) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            $failures.Add("Missing required human handoff scoring input: $requiredPath")
        }
    }
    if ($failures.Count -gt 0) {
        return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
    }

    $schemaText = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'evals/empirical/human-annotation-handoff-schema.yaml') -Raw
    if ((Get-Scalar -Text $schemaText -Field 'claim_boundary') -ne 'human_annotation_handoff_schema_only_no_completed_labels') {
        $failures.Add('Human annotation handoff schema must declare human_annotation_handoff_schema_only_no_completed_labels.')
    }
    $requiredDraftFields = Get-TopLevelList -Text $schemaText -Field 'required_draft_fields'
    $requiredNonclaims = Get-TopLevelList -Text $schemaText -Field 'current_nonclaims'
    $forbiddenFields = Get-TopLevelList -Text $schemaText -Field 'forbidden_fields'
    $labelPlaceholder = Get-Scalar -Text $schemaText -Field 'label_placeholder_value'
    $annotatorIdPlaceholder = Get-Scalar -Text $schemaText -Field 'annotator_id_placeholder'
    $timestampPlaceholder = Get-Scalar -Text $schemaText -Field 'timestamp_placeholder'
    $messageIndexPlaceholder = Get-Scalar -Text $schemaText -Field 'message_index_placeholder'
    $startOffsetPlaceholder = Get-Scalar -Text $schemaText -Field 'start_offset_placeholder'
    $endOffsetPlaceholder = Get-Scalar -Text $schemaText -Field 'end_offset_placeholder'
    $confidencePlaceholder = Get-Scalar -Text $schemaText -Field 'confidence_placeholder'

    $packageTextParts = New-Object System.Collections.Generic.List[string]
    $packageFiles = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force)
    foreach ($file in $packageFiles) {
        $relative = Get-RelativePackagePath -Root $Root -Path $file.FullName
        $raw = ''
        try {
            $raw = Get-Content -LiteralPath $file.FullName -Raw
        } catch {
            $failures.Add("Could not read human handoff file '$relative': $($_.Exception.Message)")
            continue
        }
        $packageTextParts.Add($raw) | Out-Null
        foreach ($hit in (Test-SensitiveText -Text $raw)) {
            $failures.Add("Human handoff file '$relative' contains blocked sensitive pattern '$hit'.")
        }
        if ($relative -eq 'README.md') {
            continue
        }
        if ($relative -like 'transcript-readouts/*.md') {
            continue
        }
        if ($relative -like 'annotation-drafts/*.json' -or $relative -like 'metadata/*.json') {
            continue
        }
        $failures.Add("Human handoff package contains unexpected file '$relative'.")
    }
    $packageText = $packageTextParts -join "`n"
    Assert-NoForbiddenJsonFields -Failures $failures -RawText $packageText -ForbiddenFields $forbiddenFields -Label 'human annotation handoff package'

    foreach ($directory in @('annotation-drafts', 'transcript-readouts', 'metadata')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root $directory))) {
            $failures.Add("Human annotation handoff package is missing required directory '$directory'.")
        }
    }

    $drafts = @(Read-JsonRecords -Failures $failures -Directory (Join-Path $Root 'annotation-drafts') -Label 'human handoff draft')
    $templates = @(Read-JsonRecords -Failures $failures -Directory (Join-Path $SourceTemplatePackageRoot 'annotation-templates') -Label 'label template')
    $workItems = @(Read-JsonRecords -Failures $failures -Directory (Join-Path $SourceWorklistRoot 'annotation-work-items') -Label 'annotation work item')
    if ($failures.Count -gt 0) {
        return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
    }

    $templateByWorkItemId = @{}
    foreach ($template in $templates) {
        $templateByWorkItemId[[string]$template.annotation_work_item_id] = $template
    }
    $workItemById = @{}
    foreach ($workItem in $workItems) {
        $workItemById[[string]$workItem.annotation_work_item_id] = $workItem
    }

    $draftByWorkItemId = @{}
    foreach ($draft in $drafts) {
        Assert-RequiredFields -Failures $failures -Record $draft -Fields $requiredDraftFields -Label "human handoff draft $($draft.annotation_id)"
        $workItemId = [string]$draft.annotation_work_item_id
        if ($draftByWorkItemId.ContainsKey($workItemId)) {
            $failures.Add("Multiple human handoff drafts found for annotation_work_item_id '$workItemId'.")
        } else {
            $draftByWorkItemId[$workItemId] = $draft
        }
        if (-not $templateByWorkItemId.ContainsKey($workItemId)) {
            $failures.Add("Human handoff draft '$($draft.annotation_id)' references missing label template work item '$workItemId'.")
            continue
        }
        if (-not $workItemById.ContainsKey($workItemId)) {
            $failures.Add("Human handoff draft '$($draft.annotation_id)' references missing annotation work item '$workItemId'.")
            continue
        }
        $template = $templateByWorkItemId[$workItemId]
        $workItem = $workItemById[$workItemId]
        foreach ($field in @(
            'annotation_template_id',
            'run_id',
            'run_input_id',
            'task_id',
            'condition',
            'repeat_index',
            'task_suite_version',
            'prompt_version'
        )) {
            if ([string]$draft.$field -ne [string]$template.$field) {
                $failures.Add("Human handoff draft '$($draft.annotation_id)' $field does not match label template.")
            }
        }
        if ([string]$draft.source_redaction_status -ne [string]$workItem.redaction_status) {
            $failures.Add("Human handoff draft '$($draft.annotation_id)' source_redaction_status does not match annotation work item.")
        }
        $templateLabelFields = @(Get-JsonArray -Value $template.required_label_fields | ForEach-Object { [string]$_ })
        Assert-HumanDraftPlaceholders -Failures $failures -Draft $draft -RequiredLabelFields $templateLabelFields -LabelPlaceholder $labelPlaceholder -AnnotatorIdPlaceholder $annotatorIdPlaceholder -TimestampPlaceholder $timestampPlaceholder -MessageIndexPlaceholder $messageIndexPlaceholder -StartOffsetPlaceholder $startOffsetPlaceholder -EndOffsetPlaceholder $endOffsetPlaceholder -ConfidencePlaceholder $confidencePlaceholder
        $readoutPath = Join-Path (Join-Path $Root 'transcript-readouts') "$($draft.run_id).md"
        if (-not (Test-Path -LiteralPath $readoutPath)) {
            $failures.Add("Human handoff draft '$($draft.annotation_id)' is missing transcript readout '$($draft.run_id).md'.")
        } else {
            $readout = Get-Content -LiteralPath $readoutPath -Raw
            foreach ($check in @([string]$draft.run_id, [string]$draft.task_id, [string]$draft.condition, "annotation-drafts/$($draft.__source_file_name)")) {
                if (-not $readout.Contains($check)) {
                    $failures.Add("Transcript readout '$($draft.run_id).md' is missing '$check'.")
                }
            }
        }
        $transcriptPath = Join-Path (Join-Path $SourcePilotPackageRoot 'transcripts') "$($draft.run_id).json"
        if (-not (Test-Path -LiteralPath $transcriptPath)) {
            $failures.Add("Human handoff draft '$($draft.annotation_id)' references missing pilot transcript '$($draft.run_id).json'.")
        }
    }

    foreach ($template in $templates) {
        if (-not $draftByWorkItemId.ContainsKey([string]$template.annotation_work_item_id)) {
            $failures.Add("Label template '$($template.annotation_template_id)' has no human handoff draft.")
        }
    }
    if ($drafts.Count -ne $templates.Count) {
        $failures.Add("Expected $($templates.Count) human handoff draft records from label templates; found $($drafts.Count).")
    }
    $readoutFiles = @(Get-ChildItem -LiteralPath (Join-Path $Root 'transcript-readouts') -File -Filter '*.md')
    if ($readoutFiles.Count -ne $templates.Count) {
        $failures.Add("Expected $($templates.Count) transcript readout records from label templates; found $($readoutFiles.Count).")
    }

    $manifestPath = Join-Path $Root 'metadata/human-annotation-handoff-manifest.json'
    $templateHashPath = Join-Path $Root 'metadata/source-label-template-package-manifest-hash.json'
    $worklistHashPath = Join-Path $Root 'metadata/source-annotation-worklist-manifest-hash.json'
    $pilotHashPath = Join-Path $Root 'metadata/source-pilot-execution-manifest-hash.json'
    $schemaHashPath = Join-Path $Root 'metadata/annotation-schema-hash.json'
    $guidelinesHashPath = Join-Path $Root 'metadata/annotation-guidelines-hash.json'
    foreach ($metadataPath in @($manifestPath, $templateHashPath, $worklistHashPath, $pilotHashPath, $schemaHashPath, $guidelinesHashPath)) {
        if (-not (Test-Path -LiteralPath $metadataPath)) {
            $failures.Add("Missing required human handoff metadata file: $metadataPath")
        }
    }

    $expectedTemplateManifestHash = Get-FileHashHex -Path (Join-Path $SourceTemplatePackageRoot 'metadata/label-template-package-manifest.json')
    $expectedWorklistManifestHash = Get-FileHashHex -Path (Join-Path $SourceWorklistRoot 'metadata/annotation-worklist-manifest.json')
    $expectedPilotManifestHash = Get-FileHashHex -Path (Join-Path $SourcePilotPackageRoot 'metadata/pilot-execution-manifest.json')
    $expectedAnnotationSchemaHash = Get-FileHashHex -Path (Join-Path $RepositoryRoot 'evals/empirical/annotation-schema.yaml')
    $expectedGuidelinesHash = Get-FileHashHex -Path (Join-Path $RepositoryRoot 'docs/empirical-annotation-guidelines.md')

    $templateHashRecord = $null
    $worklistHashRecord = $null
    $pilotHashRecord = $null
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
    if (Test-Path -LiteralPath $pilotHashPath) {
        $pilotHashRecord = Get-Content -LiteralPath $pilotHashPath -Raw | ConvertFrom-Json
        Assert-Sha256Record -Failures $failures -Record $pilotHashRecord -Label 'source-pilot-execution-manifest-hash.json' -ExpectedValue $expectedPilotManifestHash -MismatchMessage 'source-pilot-execution-manifest-hash.json does not match pilot execution manifest.'
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
        if ($manifest.claim_boundary -ne 'human_annotation_handoff_unfilled_no_labels') {
            $failures.Add('Human annotation handoff manifest must declare human_annotation_handoff_unfilled_no_labels.')
        }
        if ([int]$manifest.draft_count -ne $templates.Count) {
            $failures.Add("Human annotation handoff manifest draft_count $($manifest.draft_count) does not match template count $($templates.Count).")
        }
        if ([int]$manifest.transcript_readout_count -ne $templates.Count) {
            $failures.Add("Human annotation handoff manifest transcript_readout_count $($manifest.transcript_readout_count) does not match template count $($templates.Count).")
        }
        Assert-ListContains -Failures $failures -Items @(Get-JsonArray -Value $manifest.current_nonclaims | ForEach-Object { [string]$_ }) -Required $requiredNonclaims -Label 'human annotation handoff manifest current_nonclaims'
        if ([string]$manifest.source_label_template_package_manifest_sha256 -ne $expectedTemplateManifestHash -or ($templateHashRecord -and [string]$manifest.source_label_template_package_manifest_sha256 -ne [string]$templateHashRecord.value)) {
            $failures.Add('Human annotation handoff manifest source_label_template_package_manifest_sha256 does not match source hash record or label-template manifest.')
        }
        if ([string]$manifest.source_annotation_worklist_manifest_sha256 -ne $expectedWorklistManifestHash -or ($worklistHashRecord -and [string]$manifest.source_annotation_worklist_manifest_sha256 -ne [string]$worklistHashRecord.value)) {
            $failures.Add('Human annotation handoff manifest source_annotation_worklist_manifest_sha256 does not match source hash record or annotation worklist manifest.')
        }
        if ([string]$manifest.source_pilot_execution_manifest_sha256 -ne $expectedPilotManifestHash -or ($pilotHashRecord -and [string]$manifest.source_pilot_execution_manifest_sha256 -ne [string]$pilotHashRecord.value)) {
            $failures.Add('Human annotation handoff manifest source_pilot_execution_manifest_sha256 does not match source hash record or pilot execution manifest.')
        }
        if ([string]$manifest.annotation_schema_sha256 -ne $expectedAnnotationSchemaHash -or ($schemaHashRecord -and [string]$manifest.annotation_schema_sha256 -ne [string]$schemaHashRecord.value)) {
            $failures.Add('Human annotation handoff manifest annotation_schema_sha256 does not match source hash record or annotation schema.')
        }
        if ([string]$manifest.annotation_guidelines_sha256 -ne $expectedGuidelinesHash -or ($guidelinesHashRecord -and [string]$manifest.annotation_guidelines_sha256 -ne [string]$guidelinesHashRecord.value)) {
            $failures.Add('Human annotation handoff manifest annotation_guidelines_sha256 does not match source hash record or annotation guidelines.')
        }
    }

    $readmePath = Join-Path $Root 'README.md'
    if (-not (Test-Path -LiteralPath $readmePath)) {
        $failures.Add('Human annotation handoff package is missing README.md.')
    } else {
        $readme = Get-Content -LiteralPath $readmePath -Raw
        foreach ($check in @(
            'not an annotation intake package',
            'does not contain completed labels',
            'human_annotation_handoff_unfilled_no_labels',
            'paper readiness'
        )) {
            if (-not $readme.Contains($check)) {
                $failures.Add("Human annotation handoff README is missing boundary text '$check'.")
            }
        }
    }

    $summary['label_template_count'] = $templates.Count
    $summary['human_draft_count'] = $drafts.Count
    $summary['transcript_readout_count'] = $readoutFiles.Count
    $info.Add('Empirical human annotation handoff scoring complete.')
    $info.Add('Rejected completed label values, metadata hash tampering, missing readouts, forbidden aggregate fields, and sensitive package text.')
    $info.Add("Checked $($drafts.Count) human draft record(s), $($readoutFiles.Count) transcript readout(s), and $($templates.Count) label template record(s).")

    $status = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
    return (New-Result -Status $status -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
}

function Assert-NegativeCase {
    param(
        [System.Collections.Generic.List[string]]$Failures,
        [string]$Name,
        [scriptblock]$Mutate,
        [string]$Root,
        [string]$SourcePilotPackageRoot,
        [string]$SourceTemplatePackageRoot,
        [string]$SourceWorklistRoot,
        [string]$RepositoryRoot,
        [string]$ExpectedFailureText
    )
    & $Mutate
    $result = Invoke-PackageValidation -Root $Root -SourcePilotPackageRoot $SourcePilotPackageRoot -SourceTemplatePackageRoot $SourceTemplatePackageRoot -SourceWorklistRoot $SourceWorklistRoot -RepositoryRoot $RepositoryRoot
    if ($result.status -eq 'pass') {
        $Failures.Add("Negative human handoff case '$Name' unexpectedly passed.")
        return
    }
    $failureText = ($result.failures -join "`n")
    if ($failureText -notlike "*$ExpectedFailureText*") {
        $Failures.Add("Negative human handoff case '$Name' failed, but not for expected text '$ExpectedFailureText'.")
    }
}

function Get-FirstDraftFile {
    param([string]$Root)
    $files = @(Get-ChildItem -LiteralPath (Join-Path $Root 'annotation-drafts') -File -Filter '*.json' | Sort-Object Name)
    if ($files.Count -eq 0) {
        throw 'Expected human handoff package to contain draft JSON files.'
    }
    return $files[0]
}

function Invoke-SelfTest {
    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}
    $tempBase = Join-Path ([System.IO.Path]::GetTempPath()) ("adg-human-handoff-scorer-selftest-" + [guid]::NewGuid().ToString())
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
        $handoffBuilder = Join-Path $PSScriptRoot 'build-empirical-human-annotation-handoff.ps1'

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
        & $handoffBuilder -PilotPackageRoot $pilotRoot -WorklistRoot $worklistRoot -TemplatePackageRoot $templateRoot -OutputRoot $handoffRoot | Out-Null

        $positive = Invoke-PackageValidation -Root $handoffRoot -SourcePilotPackageRoot $pilotRoot -SourceTemplatePackageRoot $templateRoot -SourceWorklistRoot $worklistRoot -RepositoryRoot $RepoRoot
        if ($positive.status -ne 'pass') {
            $failures.Add("Positive human annotation handoff self-test failed: $($positive.failures -join '; ')")
        }

        $draftFile = Get-FirstDraftFile -Root $handoffRoot
        $originalDraft = Get-Content -LiteralPath $draftFile.FullName -Raw
        Assert-NegativeCase -Failures $failures -Name 'completed_label_value' -Root $handoffRoot -SourcePilotPackageRoot $pilotRoot -SourceTemplatePackageRoot $templateRoot -SourceWorklistRoot $worklistRoot -RepositoryRoot $RepoRoot -ExpectedFailureText 'must remain __fill_one_of_pass_fail_partial_not_applicable_insufficient_evidence__' -Mutate {
            $draft = $originalDraft | ConvertFrom-Json
            $draft.false_readiness_label = 'pass'
            $draft | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath $draftFile.FullName -Encoding UTF8
        }
        Set-Content -LiteralPath $draftFile.FullName -Value $originalDraft -Encoding UTF8

        $manifestPath = Join-Path $handoffRoot 'metadata/human-annotation-handoff-manifest.json'
        $originalManifest = Get-Content -LiteralPath $manifestPath -Raw
        Assert-NegativeCase -Failures $failures -Name 'metadata_hash_tampering' -Root $handoffRoot -SourcePilotPackageRoot $pilotRoot -SourceTemplatePackageRoot $templateRoot -SourceWorklistRoot $worklistRoot -RepositoryRoot $RepoRoot -ExpectedFailureText 'source_label_template_package_manifest_sha256 does not match' -Mutate {
            $manifest = $originalManifest | ConvertFrom-Json
            $manifest.source_label_template_package_manifest_sha256 = '0000000000000000000000000000000000000000000000000000000000000000'
            $manifest | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
        }
        Set-Content -LiteralPath $manifestPath -Value $originalManifest -Encoding UTF8

        Assert-NegativeCase -Failures $failures -Name 'forbidden_aggregate_field' -Root $handoffRoot -SourcePilotPackageRoot $pilotRoot -SourceTemplatePackageRoot $templateRoot -SourceWorklistRoot $worklistRoot -RepositoryRoot $RepoRoot -ExpectedFailureText "must not contain forbidden field 'pass_rate'" -Mutate {
            $manifest = $originalManifest | ConvertFrom-Json
            $manifest | Add-Member -NotePropertyName 'pass_rate' -NotePropertyValue 1 -Force
            $manifest | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
        }
        Set-Content -LiteralPath $manifestPath -Value $originalManifest -Encoding UTF8

        $draftForReadout = $originalDraft | ConvertFrom-Json
        $readoutPath = Join-Path (Join-Path $handoffRoot 'transcript-readouts') "$($draftForReadout.run_id).md"
        $originalReadout = Get-Content -LiteralPath $readoutPath -Raw
        Assert-NegativeCase -Failures $failures -Name 'missing_readout' -Root $handoffRoot -SourcePilotPackageRoot $pilotRoot -SourceTemplatePackageRoot $templateRoot -SourceWorklistRoot $worklistRoot -RepositoryRoot $RepoRoot -ExpectedFailureText 'is missing transcript readout' -Mutate {
            Remove-Item -LiteralPath $readoutPath -Force
        }
        Set-Content -LiteralPath $readoutPath -Value $originalReadout -Encoding UTF8

        $badFile = Join-Path $handoffRoot 'transcript-readouts/private-path.md'
        Assert-NegativeCase -Failures $failures -Name 'sensitive_text' -Root $handoffRoot -SourcePilotPackageRoot $pilotRoot -SourceTemplatePackageRoot $templateRoot -SourceWorklistRoot $worklistRoot -RepositoryRoot $RepoRoot -ExpectedFailureText 'contains blocked sensitive pattern' -Mutate {
            Set-Content -LiteralPath $badFile -Value ('temporary path ' + 'C:' + '\private\material') -Encoding UTF8
        }
        if (Test-Path -LiteralPath $badFile) {
            Remove-Item -LiteralPath $badFile -Force
        }

        $info.Add('Validated a 9-draft human annotation handoff from a local fixture label-template package.')
        $info.Add('Rejected completed label values, metadata hash tampering, missing readouts, forbidden aggregate fields, sensitive package text, and missing joins without model/API calls.')
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
        if (-not $HandoffRoot -or -not $PilotPackageRoot -or -not $TemplatePackageRoot -or -not $WorklistRoot) {
            throw 'Provide -HandoffRoot, -PilotPackageRoot, -TemplatePackageRoot, and -WorklistRoot, or use -SelfTest.'
        }
        $result = Invoke-PackageValidation -Root $HandoffRoot -SourcePilotPackageRoot $PilotPackageRoot -SourceTemplatePackageRoot $TemplatePackageRoot -SourceWorklistRoot $WorklistRoot -RepositoryRoot $RepoRoot
    } catch {
        $failures.Add($_.Exception.Message)
        $result = New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary
    }
}

if ($Json) {
    $result | ConvertTo-Json -Depth 20
} else {
    "Empirical human annotation handoff scoring: $($result.status)"
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
