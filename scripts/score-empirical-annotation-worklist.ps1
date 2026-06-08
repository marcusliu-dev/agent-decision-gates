param(
    [string]$WorklistRoot,
    [string]$PilotPackageRoot,
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

function Invoke-PackageValidation {
    param(
        [string]$Root,
        [string]$PilotRoot,
        [string]$RepositoryRoot
    )
    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}

    foreach ($requiredPath in @(
        (Join-Path $RepositoryRoot 'evals/empirical/annotation-worklist-schema.yaml'),
        (Join-Path $RepositoryRoot 'docs/empirical-annotation-worklist.md'),
        (Join-Path $RepositoryRoot 'scripts/build-empirical-annotation-worklist.ps1'),
        (Join-Path $RepositoryRoot 'docs/empirical-annotation-guidelines.md'),
        (Join-Path $RepositoryRoot 'evals/empirical/annotation-schema.yaml')
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            $failures.Add("Missing repository artifact required for annotation worklist scoring: $requiredPath")
        }
    }
    foreach ($requiredPath in @($Root, $PilotRoot)) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            $failures.Add("Missing required annotation worklist scoring input: $requiredPath")
        }
    }
    if ($failures.Count -gt 0) {
        return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
    }

    $schemaText = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'evals/empirical/annotation-worklist-schema.yaml') -Raw
    if ((Get-Scalar -Text $schemaText -Field 'claim_boundary') -ne 'annotation_worklist_schema_only_no_labels') {
        $failures.Add('Annotation worklist schema must declare annotation_worklist_schema_only_no_labels.')
    }
    $requiredWorkItemFields = Get-TopLevelList -Text $schemaText -Field 'required_work_item_fields'
    $requiredNonclaims = Get-TopLevelList -Text $schemaText -Field 'current_nonclaims'
    $forbiddenFields = Get-TopLevelList -Text $schemaText -Field 'forbidden_fields'

    $annotationSchemaText = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'evals/empirical/annotation-schema.yaml') -Raw
    $requiredLabelFields = @(Get-TopLevelList -Text $annotationSchemaText -Field 'required_fields' | Where-Object { $_ -like '*_label' })

    $packageTextParts = New-Object System.Collections.Generic.List[string]
    $packageFiles = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force)
    foreach ($file in $packageFiles) {
        $relative = Get-RelativePackagePath -Root $Root -Path $file.FullName
        $raw = ''
        try {
            $raw = Get-Content -LiteralPath $file.FullName -Raw
        } catch {
            $failures.Add("Could not read annotation worklist file '$relative': $($_.Exception.Message)")
            continue
        }
        $packageTextParts.Add($raw) | Out-Null
        foreach ($hit in (Test-SensitiveText -Text $raw)) {
            $failures.Add("Annotation worklist file '$relative' contains blocked sensitive pattern '$hit'.")
        }
        if ($file.Extension -ne '.json') {
            $failures.Add("Annotation worklist contains unexpected non-JSON file '$relative'.")
        }
    }
    $packageText = $packageTextParts -join "`n"
    Assert-NoForbiddenJsonFields -Failures $failures -RawJson $packageText -ForbiddenFields $forbiddenFields -Label 'annotation worklist'

    foreach ($directory in @('annotation-work-items', 'metadata')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root $directory))) {
            $failures.Add("Annotation worklist is missing required directory '$directory'.")
        }
    }
    $workItems = @(Read-JsonRecords -Failures $failures -Directory (Join-Path $Root 'annotation-work-items') -Label 'annotation work item')
    $transcripts = @(Read-JsonRecords -Failures $failures -Directory (Join-Path $PilotRoot 'transcripts') -Label 'pilot transcript')
    if ($failures.Count -gt 0) {
        return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
    }

    $transcriptByRunId = @{}
    foreach ($transcript in $transcripts) {
        $transcriptByRunId[[string]$transcript.run_id] = $transcript
    }

    $workItemByRunId = @{}
    foreach ($item in $workItems) {
        Assert-RequiredFields -Failures $failures -Record $item -Fields $requiredWorkItemFields -Label "annotation work item $($item.annotation_work_item_id)"
        $runId = [string]$item.run_id
        if ($workItemByRunId.ContainsKey($runId)) {
            $failures.Add("Multiple annotation work items found for run_id '$runId'.")
        } else {
            $workItemByRunId[$runId] = $item
        }
        if (-not $transcriptByRunId.ContainsKey($runId)) {
            $failures.Add("Annotation work item '$($item.annotation_work_item_id)' references missing pilot transcript run_id '$runId'.")
            continue
        }
        $transcript = $transcriptByRunId[$runId]
        foreach ($field in @(
            'run_input_id',
            'task_id',
            'condition',
            'repeat_index',
            'task_suite_version',
            'prompt_version',
            'model_provider',
            'model_name_or_alias',
            'runtime_surface',
            'input_prompt',
            'final_answer',
            'final_claim',
            'selected_claim_ceiling',
            'stop_or_continue_decision',
            'human_checkpoint_decision',
            'redaction_status'
        )) {
            if ([string]$item.$field -ne [string]$transcript.$field) {
                $failures.Add("Annotation work item '$($item.annotation_work_item_id)' $field does not match pilot transcript.")
            }
        }
        $itemCheckedEvidence = @(Get-JsonArray -Value $item.checked_evidence | ForEach-Object { [string]$_ })
        $transcriptCheckedEvidence = @(Get-JsonArray -Value $transcript.checked_evidence | ForEach-Object { [string]$_ })
        if ($itemCheckedEvidence.Count -ne $transcriptCheckedEvidence.Count) {
            $failures.Add("Annotation work item '$($item.annotation_work_item_id)' checked_evidence does not match pilot transcript.")
        } else {
            for ($evidenceIndex = 0; $evidenceIndex -lt $itemCheckedEvidence.Count; $evidenceIndex++) {
                if ($itemCheckedEvidence[$evidenceIndex] -ne $transcriptCheckedEvidence[$evidenceIndex]) {
                    $failures.Add("Annotation work item '$($item.annotation_work_item_id)' checked_evidence does not match pilot transcript.")
                    break
                }
            }
        }
        $messages = @(Get-JsonArray -Value $transcript.transcript_messages)
        if ([int]$item.transcript_message_count -ne $messages.Count) {
            $failures.Add("Annotation work item '$($item.annotation_work_item_id)' transcript_message_count does not match pilot transcript.")
        }
        if ([string]$item.transcript_spans_source -ne [string]$transcript.run_id) {
            $failures.Add("Annotation work item '$($item.annotation_work_item_id)' transcript_spans_source does not match pilot transcript run_id.")
        }
        if ([string]$item.annotation_guideline_version -ne 'annotation-guidelines-v0.1.0') {
            $failures.Add("Annotation work item '$($item.annotation_work_item_id)' has wrong annotation_guideline_version '$($item.annotation_guideline_version)'.")
        }
        Assert-ListContains -Failures $failures -Items @(Get-JsonArray -Value $item.required_label_fields | ForEach-Object { [string]$_ }) -Required $requiredLabelFields -Label "annotation work item $($item.annotation_work_item_id) required_label_fields"
    }

    foreach ($transcript in $transcripts) {
        if (-not $workItemByRunId.ContainsKey([string]$transcript.run_id)) {
            $failures.Add("Pilot transcript '$($transcript.run_id)' has no annotation work item.")
        }
    }
    if ($workItems.Count -ne $transcripts.Count) {
        $failures.Add("Expected $($transcripts.Count) annotation work item records from pilot transcripts; found $($workItems.Count).")
    }

    $manifestPath = Join-Path $Root 'metadata/annotation-worklist-manifest.json'
    $pilotHashPath = Join-Path $Root 'metadata/source-pilot-execution-manifest-hash.json'
    $guidelinesHashPath = Join-Path $Root 'metadata/annotation-guidelines-hash.json'
    foreach ($metadataPath in @($manifestPath, $pilotHashPath, $guidelinesHashPath)) {
        if (-not (Test-Path -LiteralPath $metadataPath)) {
            $failures.Add("Missing required annotation worklist metadata file: $metadataPath")
        }
    }
    $expectedPilotManifestHash = Get-FileHashHex -Path (Join-Path $PilotRoot 'metadata/pilot-execution-manifest.json')
    $expectedGuidelinesHash = Get-FileHashHex -Path (Join-Path $RepositoryRoot 'docs/empirical-annotation-guidelines.md')
    $pilotHashRecord = $null
    $guidelinesHashRecord = $null
    if (Test-Path -LiteralPath $pilotHashPath) {
        $pilotHashRecord = Get-Content -LiteralPath $pilotHashPath -Raw | ConvertFrom-Json
        Assert-Sha256Record -Failures $failures -Record $pilotHashRecord -Label 'source-pilot-execution-manifest-hash.json' -ExpectedValue $expectedPilotManifestHash -MismatchMessage 'source-pilot-execution-manifest-hash.json does not match pilot execution manifest.'
    }
    if (Test-Path -LiteralPath $guidelinesHashPath) {
        $guidelinesHashRecord = Get-Content -LiteralPath $guidelinesHashPath -Raw | ConvertFrom-Json
        Assert-Sha256Record -Failures $failures -Record $guidelinesHashRecord -Label 'annotation-guidelines-hash.json' -ExpectedValue $expectedGuidelinesHash -MismatchMessage 'annotation-guidelines-hash.json does not match annotation guidelines.'
    }
    if (Test-Path -LiteralPath $manifestPath) {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        if ($manifest.claim_boundary -ne 'annotation_worklist_unlabeled_no_annotations') {
            $failures.Add('Annotation worklist manifest must declare annotation_worklist_unlabeled_no_annotations.')
        }
        if ([int]$manifest.generated_work_item_count -ne $transcripts.Count) {
            $failures.Add("Annotation worklist manifest generated_work_item_count $($manifest.generated_work_item_count) does not match transcript count $($transcripts.Count).")
        }
        if ([string]$manifest.annotation_guideline_version -ne 'annotation-guidelines-v0.1.0') {
            $failures.Add("Annotation worklist manifest has wrong annotation_guideline_version '$($manifest.annotation_guideline_version)'.")
        }
        Assert-ListContains -Failures $failures -Items @(Get-JsonArray -Value $manifest.current_nonclaims | ForEach-Object { [string]$_ }) -Required $requiredNonclaims -Label 'annotation worklist manifest current_nonclaims'
        if (-not (Test-HasProperty -Record $manifest -Name 'source_pilot_execution_manifest_sha256')) {
            $failures.Add('Annotation worklist manifest is missing source_pilot_execution_manifest_sha256.')
        } elseif ([string]$manifest.source_pilot_execution_manifest_sha256 -ne $expectedPilotManifestHash) {
            $failures.Add('Annotation worklist manifest source_pilot_execution_manifest_sha256 does not match pilot execution manifest.')
        } elseif ($pilotHashRecord -and [string]$manifest.source_pilot_execution_manifest_sha256 -ne [string]$pilotHashRecord.value) {
            $failures.Add('Annotation worklist manifest source_pilot_execution_manifest_sha256 does not match source-pilot-execution-manifest-hash.json.')
        }
        if (-not (Test-HasProperty -Record $manifest -Name 'annotation_guidelines_sha256')) {
            $failures.Add('Annotation worklist manifest is missing annotation_guidelines_sha256.')
        } elseif ([string]$manifest.annotation_guidelines_sha256 -ne $expectedGuidelinesHash) {
            $failures.Add('Annotation worklist manifest annotation_guidelines_sha256 does not match annotation guidelines.')
        } elseif ($guidelinesHashRecord -and [string]$manifest.annotation_guidelines_sha256 -ne [string]$guidelinesHashRecord.value) {
            $failures.Add('Annotation worklist manifest annotation_guidelines_sha256 does not match annotation-guidelines-hash.json.')
        }
    }

    $summary['pilot_transcript_count'] = $transcripts.Count
    $summary['annotation_work_item_count'] = $workItems.Count
    $info.Add('Scored empirical annotation worklist structure.')
    $info.Add("Checked $($workItems.Count) annotation work item record(s) against $($transcripts.Count) pilot transcript record(s).")

    $status = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
    return (New-Result -Status $status -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
}

function Assert-NegativeCase {
    param(
        [System.Collections.Generic.List[string]]$Failures,
        [string]$Name,
        [scriptblock]$Mutate,
        [string]$Root,
        [string]$PilotRoot,
        [string]$RepositoryRoot,
        [string]$ExpectedFailureText
    )
    & $Mutate
    $result = Invoke-PackageValidation -Root $Root -PilotRoot $PilotRoot -RepositoryRoot $RepositoryRoot
    if ($result.status -eq 'pass') {
        $Failures.Add("Negative annotation worklist case '$Name' unexpectedly passed.")
        return
    }
    $failureText = ($result.failures -join "`n")
    if ($failureText -notlike "*$ExpectedFailureText*") {
        $Failures.Add("Negative annotation worklist case '$Name' failed, but not for expected text '$ExpectedFailureText'.")
    }
}

function Get-FirstWorkItemFile {
    param([string]$Root)
    $files = @(Get-ChildItem -LiteralPath (Join-Path $Root 'annotation-work-items') -File -Filter '*.json' | Sort-Object Name)
    if ($files.Count -eq 0) {
        throw 'Expected annotation worklist to contain work item JSON files.'
    }
    return $files[0]
}

function Invoke-SelfTest {
    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}
    $tempBase = Join-Path ([System.IO.Path]::GetTempPath()) ("adg-annotation-worklist-scorer-selftest-" + [guid]::NewGuid().ToString())
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
        $worklistBuilder = Join-Path $PSScriptRoot 'build-empirical-annotation-worklist.ps1'

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

        $positive = Invoke-PackageValidation -Root $worklistRoot -PilotRoot $pilotRoot -RepositoryRoot $RepoRoot
        if ($positive.status -ne 'pass') {
            $failures.Add("Positive annotation worklist self-test failed: $($positive.failures -join '; ')")
        } else {
            $summary['annotation_work_item_count'] = $positive.summary.annotation_work_item_count
        }

        $workItemFile = Get-FirstWorkItemFile -Root $worklistRoot
        Assert-NegativeCase -Failures $failures -Name 'missing_work_item' -Root $worklistRoot -PilotRoot $pilotRoot -RepositoryRoot $RepoRoot -ExpectedFailureText 'has no annotation work item' -Mutate {
            Remove-Item -LiteralPath $workItemFile.FullName -Force
        }
        & $worklistBuilder -PilotPackageRoot $pilotRoot -OutputRoot $worklistRoot -Force | Out-Null
        $workItemFile = Get-FirstWorkItemFile -Root $worklistRoot

        Assert-NegativeCase -Failures $failures -Name 'injected_label_field' -Root $worklistRoot -PilotRoot $pilotRoot -RepositoryRoot $RepoRoot -ExpectedFailureText "must not contain forbidden field 'false_readiness_label'" -Mutate {
            $item = Get-Content -LiteralPath $workItemFile.FullName -Raw | ConvertFrom-Json
            $item | Add-Member -NotePropertyName 'false_readiness_label' -NotePropertyValue 'pass'
            Write-JsonFile -Path $workItemFile.FullName -Value $item
        }
        & $worklistBuilder -PilotPackageRoot $pilotRoot -OutputRoot $worklistRoot -Force | Out-Null
        $workItemFile = Get-FirstWorkItemFile -Root $worklistRoot

        Assert-NegativeCase -Failures $failures -Name 'mismatched_final_claim' -Root $worklistRoot -PilotRoot $pilotRoot -RepositoryRoot $RepoRoot -ExpectedFailureText 'final_claim does not match pilot transcript' -Mutate {
            $item = Get-Content -LiteralPath $workItemFile.FullName -Raw | ConvertFrom-Json
            $item.final_claim = 'changed_claim'
            Write-JsonFile -Path $workItemFile.FullName -Value $item
        }
        & $worklistBuilder -PilotPackageRoot $pilotRoot -OutputRoot $worklistRoot -Force | Out-Null
        $workItemFile = Get-FirstWorkItemFile -Root $worklistRoot

        Assert-NegativeCase -Failures $failures -Name 'mismatched_checked_evidence' -Root $worklistRoot -PilotRoot $pilotRoot -RepositoryRoot $RepoRoot -ExpectedFailureText 'checked_evidence does not match pilot transcript' -Mutate {
            $item = Get-Content -LiteralPath $workItemFile.FullName -Raw | ConvertFrom-Json
            $item.checked_evidence = @('tampered evidence')
            Write-JsonFile -Path $workItemFile.FullName -Value $item
        }
        & $worklistBuilder -PilotPackageRoot $pilotRoot -OutputRoot $worklistRoot -Force | Out-Null
        $workItemFile = Get-FirstWorkItemFile -Root $worklistRoot

        Assert-NegativeCase -Failures $failures -Name 'missing_required_label_field_name' -Root $worklistRoot -PilotRoot $pilotRoot -RepositoryRoot $RepoRoot -ExpectedFailureText 'required_label_fields is missing' -Mutate {
            $item = Get-Content -LiteralPath $workItemFile.FullName -Raw | ConvertFrom-Json
            $item.required_label_fields = @('false_readiness_label')
            Write-JsonFile -Path $workItemFile.FullName -Value $item
        }
        & $worklistBuilder -PilotPackageRoot $pilotRoot -OutputRoot $worklistRoot -Force | Out-Null
        $workItemFile = Get-FirstWorkItemFile -Root $worklistRoot

        Assert-NegativeCase -Failures $failures -Name 'manifest_pilot_hash_mismatch' -Root $worklistRoot -PilotRoot $pilotRoot -RepositoryRoot $RepoRoot -ExpectedFailureText 'Annotation worklist manifest source_pilot_execution_manifest_sha256 does not match pilot execution manifest.' -Mutate {
            $manifestPath = Join-Path $worklistRoot 'metadata/annotation-worklist-manifest.json'
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $manifest.source_pilot_execution_manifest_sha256 = ('0' * 64)
            Write-JsonFile -Path $manifestPath -Value $manifest
        }
        & $worklistBuilder -PilotPackageRoot $pilotRoot -OutputRoot $worklistRoot -Force | Out-Null
        $workItemFile = Get-FirstWorkItemFile -Root $worklistRoot

        $extraSecretFile = Join-Path $worklistRoot 'metadata/extra-secret.txt'
        Assert-NegativeCase -Failures $failures -Name 'non_json_sensitive_file' -Root $worklistRoot -PilotRoot $pilotRoot -RepositoryRoot $RepoRoot -ExpectedFailureText 'unexpected non-JSON file' -Mutate {
            Set-Content -LiteralPath $extraSecretFile -Value ('sk-' + 'abcdefghijklmnop') -Encoding UTF8
        }
        if (Test-Path -LiteralPath $extraSecretFile) {
            Remove-Item -LiteralPath $extraSecretFile -Force
        }

        $info.Add('Validated generated annotation worklist.')
        $info.Add('Rejected missing work items, injected label fields, transcript mismatches, metadata hash tampering, and non-JSON sensitive files.')
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
    if (-not $WorklistRoot -or -not $PilotPackageRoot) {
        $failures = New-Object System.Collections.Generic.List[string]
        $warnings = New-Object System.Collections.Generic.List[string]
        $info = New-Object System.Collections.Generic.List[string]
        $summary = @{}
        $failures.Add('Provide -WorklistRoot and -PilotPackageRoot, or use -SelfTest.')
        $result = New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary
    } else {
        $result = Invoke-PackageValidation -Root $WorklistRoot -PilotRoot $PilotPackageRoot -RepositoryRoot $RepoRoot
    }
}

if ($Json) {
    $result | ConvertTo-Json -Depth 20
} else {
    "Empirical annotation worklist scoring: $($result.status)"
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
