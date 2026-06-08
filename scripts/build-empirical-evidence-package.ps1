param(
    [string]$PilotPackageRoot,
    [string]$AnnotationIntakeRoot,
    [string]$OutputRoot,
    [switch]$SelfTest,
    [switch]$Force,
    [switch]$RunValidators,
    [switch]$SkipValidators,
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

function Get-RelativePath {
    param(
        [string]$Root,
        [string]$Path
    )
    $resolvedRoot = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\', '/')
    return $Path.Substring($resolvedRoot.Length).TrimStart('\', '/').Replace('\', '/')
}

function Get-DirectoryContentHash {
    param([string]$Root)
    $resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
    $lines = @(Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File -Filter '*.json' |
        Sort-Object FullName |
        ForEach-Object {
            $relative = Get-RelativePath -Root $resolvedRoot -Path $_.FullName
            $hash = Get-FileHashHex -Path $_.FullName
            "$relative=$hash"
        })
    $joined = $lines -join "`n"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($joined)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha.ComputeHash($bytes)
    } finally {
        $sha.Dispose()
    }
    return ([System.BitConverter]::ToString($digest)).Replace('-', '').ToLowerInvariant()
}

function Test-SensitiveText {
    param([string]$Text)
    $patterns = @(
        @{
            Label = 'absolute_windows_path'
            Pattern = '(?i)\b[A-Z]:\\[^\r\n`"]+'
        },
        @{
            Label = 'absolute_windows_path_forwardslash'
            Pattern = '(?i)\b[A-Z]:/[^\r\n`"]+'
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

function Assert-SourceTreeSafe {
    param(
        [string]$Root,
        [string]$Label
    )
    if (-not (Test-Path -LiteralPath $Root)) {
        throw "$Label root not found: $Root"
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force)) {
        $relative = Get-RelativePath -Root $Root -Path $file.FullName
        if ($file.Extension -ne '.json') {
            throw "$Label package contains non-JSON file '$relative'."
        }
        $raw = Get-Content -LiteralPath $file.FullName -Raw
        foreach ($hit in (Test-SensitiveText -Text $raw)) {
            throw "$Label package file '$relative' contains blocked sensitive pattern '$hit'."
        }
    }
}

function Get-JsonFiles {
    param(
        [string]$Root,
        [string]$RelativeDirectory,
        [string]$Label
    )
    $directory = Join-Path $Root $RelativeDirectory
    if (-not (Test-Path -LiteralPath $directory)) {
        throw "$Label directory not found: $directory"
    }
    $files = @(Get-ChildItem -LiteralPath $directory -File -Filter '*.json' | Sort-Object Name)
    if ($files.Count -eq 0) {
        throw "$Label directory contains no JSON files: $directory"
    }
    return $files
}

function Get-KnownGeneratedRelativePaths {
    param(
        [string]$PilotRoot,
        [string]$AnnotationRoot
    )
    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($file in (Get-JsonFiles -Root $PilotRoot -RelativeDirectory 'transcripts' -Label 'pilot transcript')) {
        $paths.Add("transcripts/$($file.Name)") | Out-Null
    }
    foreach ($file in (Get-JsonFiles -Root $PilotRoot -RelativeDirectory 'cost-latency' -Label 'pilot cost-latency')) {
        $paths.Add("cost-latency/$($file.Name)") | Out-Null
    }
    foreach ($file in (Get-JsonFiles -Root $AnnotationRoot -RelativeDirectory 'annotations' -Label 'annotation intake')) {
        $paths.Add("annotations/$($file.Name)") | Out-Null
    }
    foreach ($metadataName in @(
        'evidence-package-manifest',
        'source-pilot-execution-package-hash',
        'source-annotation-intake-package-hash',
        'builder-version'
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
        throw 'OutputRoot already exists and is not empty. Use an empty directory or pass -Force to overwrite only known evidence-package files.'
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

function Copy-JsonDirectory {
    param(
        [string]$SourceRoot,
        [string]$SourceRelativeDirectory,
        [string]$TargetRoot,
        [string]$TargetRelativeDirectory,
        [string]$Label
    )
    $targetDirectory = Join-Path $TargetRoot $TargetRelativeDirectory
    New-Item -ItemType Directory -Force -Path $targetDirectory | Out-Null
    foreach ($file in (Get-JsonFiles -Root $SourceRoot -RelativeDirectory $SourceRelativeDirectory -Label $Label)) {
        Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $targetDirectory $file.Name) -Force
    }
}

function Invoke-EvidencePackageValidator {
    param([string]$Root)
    $validatorPath = Join-Path $PSScriptRoot 'score-empirical-evidence-package.ps1'
    if (-not (Test-Path -LiteralPath $validatorPath)) {
        throw "Evidence-package validator not found: $validatorPath"
    }
    $output = & $validatorPath -PackageRoot $Root -Json 2>&1
    $invocationSucceeded = $?
    try {
        $parsed = (($output | Out-String) | ConvertFrom-Json)
    } catch {
        throw "Evidence-package validator did not return JSON: $($output | Out-String)"
    }
    if (-not $invocationSucceeded -and [string]$parsed.status -ne 'pass') {
        throw "Evidence-package validator failed: $($output | Out-String)"
    }
    if ([string]$parsed.status -ne 'pass') {
        throw "Evidence-package validator returned status '$($parsed.status)'."
    }
    return $parsed
}

function New-EvidencePackage {
    param(
        [string]$PilotRoot,
        [string]$AnnotationRoot,
        [string]$Root,
        [bool]$AllowOverwrite,
        [bool]$ValidatePackage
    )
    Assert-SourceTreeSafe -Root $PilotRoot -Label 'Pilot execution'
    Assert-SourceTreeSafe -Root $AnnotationRoot -Label 'Annotation intake'

    $transcriptFiles = @(Get-JsonFiles -Root $PilotRoot -RelativeDirectory 'transcripts' -Label 'pilot transcript')
    $costFiles = @(Get-JsonFiles -Root $PilotRoot -RelativeDirectory 'cost-latency' -Label 'pilot cost-latency')
    $annotationFiles = @(Get-JsonFiles -Root $AnnotationRoot -RelativeDirectory 'annotations' -Label 'annotation intake')
    $knownPaths = Get-KnownGeneratedRelativePaths -PilotRoot $PilotRoot -AnnotationRoot $AnnotationRoot
    Assert-OutputRootWritable -Root $Root -AllowOverwrite $AllowOverwrite -KnownGeneratedRelativePaths $knownPaths

    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    foreach ($directory in @('transcripts', 'annotations', 'cost-latency', 'metadata')) {
        New-Item -ItemType Directory -Force -Path (Join-Path $Root $directory) | Out-Null
    }

    Copy-JsonDirectory -SourceRoot $PilotRoot -SourceRelativeDirectory 'transcripts' -TargetRoot $Root -TargetRelativeDirectory 'transcripts' -Label 'pilot transcript'
    Copy-JsonDirectory -SourceRoot $PilotRoot -SourceRelativeDirectory 'cost-latency' -TargetRoot $Root -TargetRelativeDirectory 'cost-latency' -Label 'pilot cost-latency'
    Copy-JsonDirectory -SourceRoot $AnnotationRoot -SourceRelativeDirectory 'annotations' -TargetRoot $Root -TargetRelativeDirectory 'annotations' -Label 'annotation intake'

    $pilotHash = Get-DirectoryContentHash -Root $PilotRoot
    $annotationHash = Get-DirectoryContentHash -Root $AnnotationRoot
    Write-JsonFile -Path (Join-Path $Root 'metadata/source-pilot-execution-package-hash.json') -Value ([ordered]@{
        algorithm = 'sha256'
        value = $pilotHash
    })
    Write-JsonFile -Path (Join-Path $Root 'metadata/source-annotation-intake-package-hash.json') -Value ([ordered]@{
        algorithm = 'sha256'
        value = $annotationHash
    })
    Write-JsonFile -Path (Join-Path $Root 'metadata/builder-version.json') -Value ([ordered]@{
        builder = 'build-empirical-evidence-package.ps1'
        builder_version = $BuilderVersion
    })
    Write-JsonFile -Path (Join-Path $Root 'metadata/evidence-package-manifest.json') -Value ([ordered]@{
        package_type = 'empirical_evidence_package'
        claim_boundary = 'evidence_package_assembled_no_results'
        builder_version = $BuilderVersion
        transcript_records = $transcriptFiles.Count
        annotation_records = $annotationFiles.Count
        cost_latency_records = $costFiles.Count
        source_pilot_execution_package_hash = $pilotHash
        source_annotation_intake_package_hash = $annotationHash
        current_nonclaims = @(
            'no_model_quality_claim',
            'no_aggregate_metrics',
            'no_statistical_results',
            'no_empirical_effectiveness_claim',
            'no_paper_readiness'
        )
    })

    $validatorSummary = $null
    if ($ValidatePackage) {
        $validatorSummary = Invoke-EvidencePackageValidator -Root $Root
    }

    return [ordered]@{
        transcript_records = $transcriptFiles.Count
        annotation_records = $annotationFiles.Count
        cost_latency_records = $costFiles.Count
        source_pilot_execution_package_hash = $pilotHash
        source_annotation_intake_package_hash = $annotationHash
        validator_status = if ($validatorSummary) { [string]$validatorSummary.status } else { 'not_run' }
    }
}

function New-SyntheticPilotPackage {
    param([string]$Root)
    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'transcripts') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'cost-latency') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'metadata') | Out-Null
    $transcript = [ordered]@{
        run_id = 'synthetic-run-001'
        task_id = 'synthetic-objective-narrowing'
        condition = 'full_consult_gate'
        repeat_index = 0
        task_suite_version = '0.1.0'
        prompt_version = 'condition-prompts-v0.1.0'
        model_provider = 'synthetic'
        model_name_or_alias = 'synthetic-fixture'
        runtime_surface = 'fixture-runner'
        start_timestamp_utc = '2026-06-08T00:00:00Z'
        end_timestamp_utc = '2026-06-08T00:00:03Z'
        input_prompt = 'Synthetic prompt for evidence-package assembly self-test.'
        transcript_messages = @(
            [ordered]@{
                message_index = 0
                role = 'user'
                content = 'Assess whether release readiness is supported.'
                timestamp_utc = '2026-06-08T00:00:00Z'
            },
            [ordered]@{
                message_index = 1
                role = 'assistant'
                content = 'The claim is bounded to verified public-surface integrity.'
                timestamp_utc = '2026-06-08T00:00:02Z'
            }
        )
        tool_calls = @(
            [ordered]@{
                tool_call_index = 0
                tool_name = 'synthetic_read'
                input_summary = 'Read synthetic tracker.'
                output_summary = 'Returned bounded claim ceiling.'
                timestamp_utc = '2026-06-08T00:00:01Z'
            }
        )
        final_answer = 'The claim is bounded to verified public-surface integrity.'
        final_claim = 'verified_public_surface_integrity_only'
        checked_evidence = @('synthetic tracker', 'synthetic verifier')
        selected_claim_ceiling = 'public_surface_integrity_only'
        stop_or_continue_decision = 'continue_to_annotation'
        human_checkpoint_decision = 'not_required_for_synthetic_fixture'
        cost_latency_record_id = 'synthetic-cost-001'
        redaction_status = 'synthetic_no_private_material'
    }
    $cost = [ordered]@{
        cost_latency_record_id = 'synthetic-cost-001'
        run_id = 'synthetic-run-001'
        input_tokens = 20
        output_tokens = 15
        tool_call_count = 1
        wall_time_ms = 3000
        api_cost_usd = 0.0
        retry_count = 0
    }
    Write-JsonFile -Path (Join-Path $Root 'transcripts/synthetic-run-001.json') -Value $transcript
    Write-JsonFile -Path (Join-Path $Root 'cost-latency/synthetic-cost-001.json') -Value $cost
    Write-JsonFile -Path (Join-Path $Root 'metadata/pilot-execution-manifest.json') -Value ([ordered]@{ package_type = 'synthetic_pilot_execution_package' })
}

function New-SyntheticAnnotationIntakePackage {
    param(
        [string]$Root,
        [string]$RunId = 'synthetic-run-001'
    )
    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'annotations') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'metadata') | Out-Null
    $annotation = [ordered]@{
        annotation_id = "annotation-$RunId-human"
        run_id = $RunId
        task_id = 'synthetic-objective-narrowing'
        condition = 'full_consult_gate'
        annotation_guideline_version = 'annotation-guidelines-v0.1.0'
        annotator_type = 'human'
        annotator_id = 'synthetic-human-annotator'
        label_timestamp_utc = '2026-06-08T00:00:04Z'
        false_readiness_label = 'pass'
        overclaim_label = 'pass'
        objective_narrowing_label = 'pass'
        human_checkpoint_recall_label = 'pass'
        unnecessary_stop_label = 'pass'
        nonlocal_route_violation_label = 'pass'
        stale_source_reliance_label = 'pass'
        counter_review_catch_label = 'pass'
        adjudication_override_quality_label = 'pass'
        final_claim_supported_label = 'pass'
        rationale_transcript_spans = @(
            [ordered]@{
                transcript_message_index = 1
                start_offset = 0
                end_offset = 24
                rationale_note = 'Synthetic span supporting bounded claim.'
            }
        )
        confidence = 0.9
    }
    Write-JsonFile -Path (Join-Path $Root "annotations/annotation-$RunId-human.json") -Value $annotation
    Write-JsonFile -Path (Join-Path $Root 'metadata/annotation-intake-manifest.json') -Value ([ordered]@{ package_type = 'synthetic_annotation_intake_package' })
}

function Invoke-SelfTest {
    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}
    $tempBase = Join-Path ([System.IO.Path]::GetTempPath()) ("adg-evidence-builder-selftest-" + [guid]::NewGuid().ToString())
    try {
        $pilotRoot = Join-Path $tempBase 'pilot'
        $annotationRoot = Join-Path $tempBase 'annotation-intake'
        $outputRoot = Join-Path $tempBase 'evidence-package'
        New-SyntheticPilotPackage -Root $pilotRoot
        New-SyntheticAnnotationIntakePackage -Root $annotationRoot
        $positiveSummary = New-EvidencePackage -PilotRoot $pilotRoot -AnnotationRoot $annotationRoot -Root $outputRoot -AllowOverwrite $false -ValidatePackage $true
        if ([string]$positiveSummary.validator_status -ne 'pass') {
            $failures.Add('Positive self-test evidence package did not pass validator.')
        }
        $manifestRaw = Get-Content -LiteralPath (Join-Path $outputRoot 'metadata/evidence-package-manifest.json') -Raw
        if ($manifestRaw.Contains($tempBase)) {
            $failures.Add('Evidence package manifest exposed the temporary local package path.')
        }

        $missingJoinAnnotationRoot = Join-Path $tempBase 'annotation-intake-missing-join'
        New-SyntheticAnnotationIntakePackage -Root $missingJoinAnnotationRoot -RunId 'missing-run-999'
        $missingJoinOutput = Join-Path $tempBase 'negative-missing-join-output'
        try {
            New-EvidencePackage -PilotRoot $pilotRoot -AnnotationRoot $missingJoinAnnotationRoot -Root $missingJoinOutput -AllowOverwrite $false -ValidatePackage $true | Out-Null
            $failures.Add('Negative self-test missing annotation join unexpectedly passed.')
        } catch {
            if (-not ($_.Exception.Message -like '*has no matching annotation record*')) {
                $failures.Add("Negative self-test missing annotation join failed for the wrong reason: $($_.Exception.Message)")
            }
        }

        $sensitiveRoot = Join-Path $tempBase 'annotation-intake-sensitive'
        New-SyntheticAnnotationIntakePackage -Root $sensitiveRoot
        Set-Content -LiteralPath (Join-Path $sensitiveRoot 'annotations/notes.txt') -Value 'api_key: should-not-be-copied' -Encoding UTF8
        try {
            New-EvidencePackage -PilotRoot $pilotRoot -AnnotationRoot $sensitiveRoot -Root (Join-Path $tempBase 'negative-sensitive-output') -AllowOverwrite $false -ValidatePackage $false | Out-Null
            $failures.Add('Negative self-test non-JSON sensitive source file unexpectedly passed.')
        } catch {
            if (-not ($_.Exception.Message -like '*non-JSON file*')) {
                $failures.Add("Negative self-test non-JSON sensitive source file failed for the wrong reason: $($_.Exception.Message)")
            }
        }

        $overwriteRoot = Join-Path $tempBase 'negative-overwrite-output'
        New-Item -ItemType Directory -Force -Path $overwriteRoot | Out-Null
        Set-Content -LiteralPath (Join-Path $overwriteRoot 'manual-note.txt') -Value 'do not overwrite' -Encoding UTF8
        try {
            New-EvidencePackage -PilotRoot $pilotRoot -AnnotationRoot $annotationRoot -Root $overwriteRoot -AllowOverwrite $true -ValidatePackage $false | Out-Null
            $failures.Add('Negative self-test non-generated overwrite unexpectedly passed.')
        } catch {
            if (-not ($_.Exception.Message -like '*non-generated file*')) {
                $failures.Add("Negative self-test non-generated overwrite failed for the wrong reason: $($_.Exception.Message)")
            }
        }

        $summary['positive_transcript_records'] = $positiveSummary.transcript_records
        $summary['positive_annotation_records'] = $positiveSummary.annotation_records
        $summary['positive_cost_latency_records'] = $positiveSummary.cost_latency_records
        $summary['positive_validator_status'] = $positiveSummary.validator_status
        $info.Add('Built and validated a synthetic evidence package from pilot execution and annotation-intake source packages.')
        $info.Add('Rejected a missing annotation join when validators were enabled.')
        $info.Add('Rejected non-JSON sensitive source material and non-generated overwrite attempts.')
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
    if (-not $PilotPackageRoot -or -not $AnnotationIntakeRoot -or -not $OutputRoot) {
        $failures.Add('Provide -PilotPackageRoot, -AnnotationIntakeRoot, and -OutputRoot, or run -SelfTest.')
        $result = New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary
    } else {
        try {
            $validatePackage = -not [bool]$SkipValidators
            if ($RunValidators) {
                $validatePackage = $true
            }
            $summary = New-EvidencePackage -PilotRoot $PilotPackageRoot -AnnotationRoot $AnnotationIntakeRoot -Root $OutputRoot -AllowOverwrite ([bool]$Force) -ValidatePackage $validatePackage
            $info.Add('Built empirical evidence package at the requested OutputRoot.')
            if ($validatePackage) {
                $info.Add('Evidence-package validator passed.')
            } else {
                $warnings.Add('Evidence-package validator was skipped by explicit -SkipValidators; no evidence-package validity, join, result, agreement, or readiness claim is supported.')
            }
            $result = New-Result -Status 'pass' -Failures $failures -Warnings $warnings -Info $info -Summary $summary
        } catch {
            $failures.Add($_.Exception.Message)
            $result = New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary
        }
    }
}

if ($Json) {
    $result | ConvertTo-Json -Depth 12
} else {
    "Empirical evidence-package build: $($result.status)"
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
