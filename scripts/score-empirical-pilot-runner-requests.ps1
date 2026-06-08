param(
    [string]$PackageRoot,
    [string]$RunInputRoot,
    [string]$PreflightPath,
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

function Assert-ExactFields {
    param(
        [System.Collections.Generic.List[string]]$Failures,
        [object]$Record,
        [string[]]$AllowedFields,
        [string]$Label
    )
    if ($null -eq $Record) {
        return
    }
    $allowed = @{}
    foreach ($field in $AllowedFields) {
        $allowed[$field] = $true
    }
    foreach ($property in $Record.PSObject.Properties.Name) {
        if (-not $allowed.ContainsKey($property)) {
            $Failures.Add("$Label contains unexpected field '$property'.")
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

function Test-SameStringArray {
    param(
        [object]$Actual,
        [object]$Expected
    )
    $actualItems = @(Get-JsonArray -Value $Actual | ForEach-Object { [string]$_ })
    $expectedItems = @(Get-JsonArray -Value $Expected | ForEach-Object { [string]$_ })
    if ($actualItems.Count -ne $expectedItems.Count) {
        return $false
    }
    for ($index = 0; $index -lt $expectedItems.Count; $index++) {
        if ($actualItems[$index] -ne $expectedItems[$index]) {
            return $false
        }
    }
    return $true
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

function Read-JsonFile {
    param(
        [System.Collections.Generic.List[string]]$Failures,
        [string]$Path,
        [string]$Label
    )
    try {
        $raw = Get-Content -LiteralPath $Path -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) {
            $Failures.Add("Could not parse JSON file '$Label': file is blank.")
            return $null
        }
        return ($raw | ConvertFrom-Json)
    } catch {
        $Failures.Add("Could not parse JSON file '$Label': $($_.Exception.Message)")
        return $null
    }
}

function Get-RelativePackagePath {
    param(
        [string]$Root,
        [string]$Path
    )
    $resolvedRoot = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\', '/')
    return $Path.Substring($resolvedRoot.Length).TrimStart('\', '/').Replace('\', '/')
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

function Invoke-PilotRunnerRequestScoring {
    param(
        [string]$Root,
        [string]$InputRoot,
        [string]$PreflightFile,
        [string]$RepositoryRoot
    )

    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}

    foreach ($requiredPath in @($Root, $InputRoot, $PreflightFile)) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            $failures.Add("Required path not found: $requiredPath")
        }
    }
    if ($failures.Count -gt 0) {
        return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
    }

    try {
        Invoke-InputScorers -InputRoot $InputRoot -PreflightFile $PreflightFile -RepositoryRoot $RepositoryRoot
    } catch {
        $failures.Add($_.Exception.Message)
        return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
    }

    $requestDir = Join-Path $Root 'requests'
    $metadataDir = Join-Path $Root 'metadata'
    $manifestPath = Join-Path $metadataDir 'pilot-runner-request-manifest.json'
    $sourcePreflightHashPath = Join-Path $metadataDir 'source-preflight-hash.json'
    $sourceRunInputManifestHashPath = Join-Path $metadataDir 'source-run-input-manifest-hash.json'
    foreach ($requiredPath in @($requestDir, $metadataDir, $manifestPath, $sourcePreflightHashPath, $sourceRunInputManifestHashPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            $failures.Add("Missing required request-package path: $requiredPath")
        }
    }
    foreach ($forbiddenDir in @('transcripts', 'cost-latency', 'annotations', 'results', 'metrics')) {
        if (Test-Path -LiteralPath (Join-Path $Root $forbiddenDir)) {
            $failures.Add("Pilot runner request package must not contain forbidden output directory '$forbiddenDir'.")
        }
    }
    if ($failures.Count -gt 0) {
        return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
    }

    $preflight = Read-JsonFile -Failures $failures -Path $PreflightFile -Label 'execution preflight'
    if ($null -eq $preflight) {
        return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
    }
    $selectedIds = @(Get-JsonArray -Value $preflight.selected_run_input_ids | ForEach-Object { [string]$_ })
    $runInputRecords = @{}
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $InputRoot 'run-inputs') -File -Filter '*.json')) {
        $record = Read-JsonFile -Failures $failures -Path $file.FullName -Label ("run-inputs/" + $file.Name)
        if ($null -eq $record) {
            continue
        }
        $runInputRecords[[string]$record.run_input_id] = $record
    }
    if ($failures.Count -gt 0) {
        return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
    }

    $knownRelativePaths = @{}
    foreach ($id in $selectedIds) {
        $knownRelativePaths["requests/pilot-request-$id.json"] = $true
    }
    foreach ($relative in @(
        'metadata/pilot-runner-request-manifest.json',
        'metadata/source-preflight-hash.json',
        'metadata/source-run-input-manifest-hash.json'
    )) {
        $knownRelativePaths[$relative] = $true
    }

    $forbiddenFields = @(
        'raw_runner_response',
        'runner_response',
        'final_answer',
        'transcript_text',
        'response_text',
        'output_text',
        'input_tokens',
        'output_tokens',
        'api_cost_usd',
        'latency_ms',
        'annotation_label',
        'agreement_rate',
        'aggregate_metrics',
        'pass_rate',
        'win_rate',
        'paper_ready',
        'production_ready'
    )

    foreach ($file in @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force)) {
        $relativePath = Get-RelativePackagePath -Root $Root -Path $file.FullName
        $raw = Get-Content -LiteralPath $file.FullName -Raw
        foreach ($hit in (Test-SensitiveText -Text $raw)) {
            $failures.Add("Package file '$relativePath' contains blocked sensitive pattern '$hit'.")
        }
        if ($file.Extension -eq '.json') {
            Assert-NoForbiddenJsonFields -Failures $failures -RawJson $raw -ForbiddenFields $forbiddenFields -Label $relativePath
        }
        if (-not $knownRelativePaths.ContainsKey($relativePath)) {
            $failures.Add("Pilot runner request package contains unexpected file '$relativePath'.")
        }
    }

    $manifestRaw = Get-Content -LiteralPath $manifestPath -Raw
    $manifest = Read-JsonFile -Failures $failures -Path $manifestPath -Label 'metadata/pilot-runner-request-manifest.json'
    $sourcePreflightHash = Read-JsonFile -Failures $failures -Path $sourcePreflightHashPath -Label 'metadata/source-preflight-hash.json'
    $sourceRunInputManifestHash = Read-JsonFile -Failures $failures -Path $sourceRunInputManifestHashPath -Label 'metadata/source-run-input-manifest-hash.json'
    if ($null -eq $manifest -or $null -eq $sourcePreflightHash -or $null -eq $sourceRunInputManifestHash) {
        return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
    }
    $preflightHash = Get-FileHashHex -Path $PreflightFile
    $runInputManifestPath = Join-Path $InputRoot 'metadata/run-input-manifest.json'
    $runInputManifestHash = Get-FileHashHex -Path $runInputManifestPath

    $manifestFields = @(
        'builder',
        'builder_version',
        'claim_boundary',
        'request_count',
        'source_preflight_id',
        'source_preflight_sha256',
        'source_run_input_manifest_sha256',
        'runner_label',
        'request_records',
        'current_nonclaims'
    )
    $hashSidecarFields = @('algorithm', 'value')
    Assert-ExactFields -Failures $failures -Record $manifest -AllowedFields $manifestFields -Label 'metadata/pilot-runner-request-manifest.json'
    Assert-ExactFields -Failures $failures -Record $sourcePreflightHash -AllowedFields $hashSidecarFields -Label 'metadata/source-preflight-hash.json'
    Assert-ExactFields -Failures $failures -Record $sourceRunInputManifestHash -AllowedFields $hashSidecarFields -Label 'metadata/source-run-input-manifest-hash.json'

    Assert-RequiredFields -Failures $failures -Record $manifest -Fields $manifestFields -Label 'pilot-runner-request manifest'
    if ([string]$manifest.builder -ne 'build-empirical-pilot-runner-requests.ps1') {
        $failures.Add("Pilot-runner-request manifest builder must be build-empirical-pilot-runner-requests.ps1.")
    }
    if ([string]$manifest.claim_boundary -ne 'pilot_runner_request_package_no_runner_execution') {
        $failures.Add("Pilot-runner-request manifest claim_boundary must be pilot_runner_request_package_no_runner_execution.")
    }
    if ([string]$manifest.source_preflight_id -ne [string]$preflight.preflight_id) {
        $failures.Add("Pilot-runner-request manifest source_preflight_id does not match execution preflight.")
    }
    if ([string]$manifest.source_preflight_sha256 -ne $preflightHash) {
        $failures.Add("Pilot-runner-request manifest source_preflight_sha256 does not match the preflight file hash.")
    }
    if ([string]$manifest.source_run_input_manifest_sha256 -ne $runInputManifestHash) {
        $failures.Add("Pilot-runner-request manifest source_run_input_manifest_sha256 does not match the run-input manifest hash.")
    }
    if ([string]$sourcePreflightHash.algorithm -ne 'sha256' -or [string]$sourcePreflightHash.value -ne $preflightHash) {
        $failures.Add('source-preflight-hash.json value does not match the preflight file hash.')
    }
    if ([string]$sourceRunInputManifestHash.algorithm -ne 'sha256' -or [string]$sourceRunInputManifestHash.value -ne $runInputManifestHash) {
        $failures.Add('source-run-input-manifest-hash.json value does not match the run-input manifest hash.')
    }
    if ([string]::IsNullOrWhiteSpace([string]$manifest.runner_label) -or [string]$manifest.runner_label -match '[\\/:]') {
        $failures.Add('Pilot-runner-request manifest runner_label must be nonblank and contain no path separators.')
    }
    Assert-ListContains -Failures $failures -Items @(Get-JsonArray -Value $manifest.current_nonclaims | ForEach-Object { [string]$_ }) -Required @(
        'no_runner_execution',
        'no_model_api_eval_execution',
        'no_runner_responses',
        'no_real_transcripts',
        'no_real_cost_latency_results',
        'no_annotations',
        'no_aggregate_metrics',
        'no_empirical_effectiveness_claim',
        'no_paper_readiness'
    ) -Label 'pilot-runner-request manifest current_nonclaims'

    $requestFiles = @(Get-ChildItem -LiteralPath $requestDir -File -Filter '*.json' | Sort-Object Name)
    if ($requestFiles.Count -ne $selectedIds.Count) {
        $failures.Add("Pilot runner request file count $($requestFiles.Count) does not match selected run-input count $($selectedIds.Count).")
    }
    if ([int]$manifest.request_count -ne $requestFiles.Count) {
        $failures.Add("Pilot-runner-request manifest request_count $($manifest.request_count) does not match request file count $($requestFiles.Count).")
    }
    $manifestRequestRecords = @(Get-JsonArray -Value $manifest.request_records)
    if ($manifestRequestRecords.Count -ne $requestFiles.Count) {
        $failures.Add("Pilot-runner-request manifest request_records count $($manifestRequestRecords.Count) does not match request file count $($requestFiles.Count).")
    }
    $manifestRecordByFile = @{}
    foreach ($record in $manifestRequestRecords) {
        Assert-ExactFields -Failures $failures -Record $record -AllowedFields @('request_file', 'request_sha256') -Label 'pilot-runner-request manifest request_records entry'
        $manifestRecordByFile[[string]$record.request_file] = $record
    }

    $requestFields = @(
        'request_id',
        'run_id',
        'run_input_id',
        'task_id',
        'condition',
        'repeat_index',
        'task_suite_version',
        'prompt_pack_version',
        'input_prompt',
        'expected_failure_modes',
        'required_conditions',
        'forbidden_claims',
        'preflight_id',
        'model_provider',
        'model_name_or_alias',
        'runtime_surface',
        'runner_label'
    )

    $seenRunInputIds = New-Object System.Collections.Generic.HashSet[string]
    foreach ($id in $selectedIds) {
        if (-not $runInputRecords.ContainsKey($id)) {
            $failures.Add("Selected run_input_id '$id' is missing from the run-input package.")
            continue
        }
        $requestPath = Join-Path $requestDir "pilot-request-$id.json"
        if (-not (Test-Path -LiteralPath $requestPath)) {
            $failures.Add("Missing expected request file requests/pilot-request-$id.json.")
            continue
        }
        $relativePath = "requests/pilot-request-$id.json"
        $rawRequest = Get-Content -LiteralPath $requestPath -Raw
        Assert-NoForbiddenJsonFields -Failures $failures -RawJson $rawRequest -ForbiddenFields $forbiddenFields -Label $relativePath
        try {
            $request = $rawRequest | ConvertFrom-Json
        } catch {
            $failures.Add("Could not parse request file '$relativePath': $($_.Exception.Message)")
            continue
        }
        Assert-ExactFields -Failures $failures -Record $request -AllowedFields $requestFields -Label $relativePath
        Assert-RequiredFields -Failures $failures -Record $request -Fields $requestFields -Label $relativePath

        $seenRunInputIds.Add([string]$request.run_input_id) | Out-Null
        if ([string]$request.request_id -ne "pilot-request-$id") {
            $failures.Add("$relativePath request_id does not match its selected run_input_id.")
        }
        if ([string]$request.run_id -ne "pilot-run-$id") {
            $failures.Add("$relativePath run_id does not match its selected run_input_id.")
        }
        if ([string]$request.run_input_id -ne $id) {
            $failures.Add("$relativePath run_input_id does not match its file name.")
        }
        if ([string]$request.preflight_id -ne [string]$preflight.preflight_id) {
            $failures.Add("$relativePath preflight_id does not match execution preflight.")
        }
        if ([string]$request.model_provider -ne [string]$preflight.provider) {
            $failures.Add("$relativePath model_provider does not match execution preflight.")
        }
        if ([string]$request.model_name_or_alias -ne [string]$preflight.model_name_or_alias) {
            $failures.Add("$relativePath model_name_or_alias does not match execution preflight.")
        }
        if ([string]$request.runtime_surface -ne [string]$preflight.runtime_surface) {
            $failures.Add("$relativePath runtime_surface does not match execution preflight.")
        }
        if ([string]$request.runner_label -ne [string]$manifest.runner_label) {
            $failures.Add("$relativePath runner_label does not match request manifest.")
        }

        $runInput = $runInputRecords[$id]
        foreach ($field in @('task_id', 'condition', 'task_suite_version', 'prompt_pack_version', 'input_prompt')) {
            if ([string]$request.$field -ne [string]$runInput.$field) {
                $failures.Add("$relativePath does not match source run input field '$field'.")
            }
        }
        if ([int]$request.repeat_index -ne [int]$runInput.repeat_index) {
            $failures.Add("$relativePath does not match source run input field 'repeat_index'.")
        }
        foreach ($arrayField in @('expected_failure_modes', 'required_conditions', 'forbidden_claims')) {
            if (-not (Test-SameStringArray -Actual $request.$arrayField -Expected $runInput.$arrayField)) {
                $failures.Add("$relativePath does not match source run input field '$arrayField'.")
            }
        }

        if (-not $manifestRecordByFile.ContainsKey($relativePath)) {
            $failures.Add("Pilot-runner-request manifest is missing request_records entry '$relativePath'.")
        } else {
            $expectedHash = Get-FileHashHex -Path $requestPath
            if ([string]$manifestRecordByFile[$relativePath].request_sha256 -ne $expectedHash) {
                $failures.Add("Pilot-runner-request manifest request_sha256 for '$relativePath' does not match the request file.")
            }
        }
    }

    foreach ($requestFile in $requestFiles) {
        $relativePath = Get-RelativePackagePath -Root $Root -Path $requestFile.FullName
        $request = Read-JsonFile -Failures $failures -Path $requestFile.FullName -Label $relativePath
        if ($null -eq $request) {
            continue
        }
        if ($selectedIds -notcontains [string]$request.run_input_id) {
            $failures.Add("$relativePath contains run_input_id '$($request.run_input_id)' not selected by execution preflight.")
        }
    }

    $summary = @{
        request_count = $requestFiles.Count
        selected_run_count = $selectedIds.Count
        runner_label = [string]$manifest.runner_label
        source_preflight_hash = $preflightHash
        source_run_input_manifest_hash = $runInputManifestHash
    }
    if ($failures.Count -eq 0) {
        $info.Add('Validated empirical pilot runner request package.')
        $info.Add('Checked request files, source hashes, manifest entries, source run-input joins, and preflight runtime joins.')
        $info.Add('No runner script was executed and no model/API calls were made by this request scorer.')
    }
    $status = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
    return (New-Result -Status $status -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
}

function Copy-TestPackage {
    param(
        [string]$Source,
        [string]$Destination
    )
    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
}

function Invoke-NegativeCase {
    param(
        [System.Collections.Generic.List[string]]$Failures,
        [string]$Name,
        [string]$ExpectedFailureText,
        [scriptblock]$Mutate,
        [string]$PackageRootForCase,
        [string]$RunInputRootForCase,
        [string]$PreflightPathForCase,
        [string]$RepositoryRoot
    )
    try {
        & $Mutate | Out-Null
        $result = Invoke-PilotRunnerRequestScoring -Root $PackageRootForCase -InputRoot $RunInputRootForCase -PreflightFile $PreflightPathForCase -RepositoryRoot $RepositoryRoot
        if ($result.status -eq 'pass') {
            $Failures.Add("Negative request-package scorer case '$Name' unexpectedly passed.")
            return
        }
        $joinedFailures = ($result.failures -join "`n")
        if ($joinedFailures -notlike "*$ExpectedFailureText*") {
            $Failures.Add("Negative request-package scorer case '$Name' failed, but not for expected text '$ExpectedFailureText': $joinedFailures")
        }
    } catch {
        if ($_.Exception.Message -notlike "*$ExpectedFailureText*") {
            $Failures.Add("Negative request-package scorer case '$Name' threw unexpected error: $($_.Exception.Message)")
        }
    }
}

function Invoke-SelfTest {
    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}
    $tempBase = Join-Path ([System.IO.Path]::GetTempPath()) ("adg-pilot-runner-request-scorer-selftest-" + [guid]::NewGuid().ToString())
    try {
        New-Item -ItemType Directory -Force -Path $tempBase | Out-Null
        $runInputRoot = Join-Path $tempBase 'run-inputs'
        $preflightPath = Join-Path $tempBase 'execution-preflight.json'
        $requestRoot = Join-Path $tempBase 'pilot-runner-requests'
        $runInputBuilder = Join-Path $RepoRoot 'scripts/build-empirical-run-inputs.ps1'
        $preflightBuilder = Join-Path $RepoRoot 'scripts/build-empirical-execution-preflight.ps1'
        $requestBuilder = Join-Path $RepoRoot 'scripts/build-empirical-pilot-runner-requests.ps1'

        $runInputOutput = & $runInputBuilder -OutputRoot $runInputRoot -Json 2>&1
        Convert-JsonToolOutput -ScriptName 'build-empirical-run-inputs.ps1' -Output $runInputOutput -InvocationSucceeded $? | Out-Null
        $preflightOutput = & $preflightBuilder -RunInputRoot $runInputRoot -OutputPath $preflightPath -Provider 'selftest-provider' -ModelNameOrAlias 'selftest-model' -RuntimeSurface 'selftest-local-runner' -MaxBudgetUsd 1.0 -Force -Json 2>&1
        Convert-JsonToolOutput -ScriptName 'build-empirical-execution-preflight.ps1' -Output $preflightOutput -InvocationSucceeded $? | Out-Null
        $requestOutput = & $requestBuilder -RunInputRoot $runInputRoot -PreflightPath $preflightPath -OutputRoot $requestRoot -RunnerLabel 'fixture-runner-v0' -Json 2>&1
        Convert-JsonToolOutput -ScriptName 'build-empirical-pilot-runner-requests.ps1' -Output $requestOutput -InvocationSucceeded $? | Out-Null

        $positive = Invoke-PilotRunnerRequestScoring -Root $requestRoot -InputRoot $runInputRoot -PreflightFile $preflightPath -RepositoryRoot $RepoRoot
        if ($positive.status -ne 'pass') {
            $failures.Add("Positive pilot runner request package scoring failed: $($positive.failures -join '; ')")
        }
        $summary = $positive.summary

        $firstRequestFile = @(Get-ChildItem -LiteralPath (Join-Path $requestRoot 'requests') -File -Filter '*.json' | Sort-Object Name | Select-Object -First 1)[0]

        $missingRoot = Join-Path $tempBase 'missing-request'
        Copy-TestPackage -Source $requestRoot -Destination $missingRoot
        Invoke-NegativeCase -Failures $failures -Name 'missing_request_file' -ExpectedFailureText 'Missing expected request file' -PackageRootForCase $missingRoot -RunInputRootForCase $runInputRoot -PreflightPathForCase $preflightPath -RepositoryRoot $RepoRoot -Mutate {
            $target = Join-Path $missingRoot ("requests/$($firstRequestFile.Name)")
            Remove-Item -LiteralPath $target -Force
        }

        $mismatchRoot = Join-Path $tempBase 'request-source-mismatch'
        Copy-TestPackage -Source $requestRoot -Destination $mismatchRoot
        Invoke-NegativeCase -Failures $failures -Name 'request_source_mismatch' -ExpectedFailureText "does not match source run input field 'input_prompt'" -PackageRootForCase $mismatchRoot -RunInputRootForCase $runInputRoot -PreflightPathForCase $preflightPath -RepositoryRoot $RepoRoot -Mutate {
            $target = Join-Path $mismatchRoot ("requests/$($firstRequestFile.Name)")
            $record = Get-Content -LiteralPath $target -Raw | ConvertFrom-Json
            $record.input_prompt = 'tampered prompt'
            Write-JsonFile -Path $target -Value $record
        }

        $hashRoot = Join-Path $tempBase 'metadata-hash-tamper'
        Copy-TestPackage -Source $requestRoot -Destination $hashRoot
        Invoke-NegativeCase -Failures $failures -Name 'metadata_hash_tamper' -ExpectedFailureText 'source-preflight-hash.json value' -PackageRootForCase $hashRoot -RunInputRootForCase $runInputRoot -PreflightPathForCase $preflightPath -RepositoryRoot $RepoRoot -Mutate {
            $target = Join-Path $hashRoot 'metadata/source-preflight-hash.json'
            Write-JsonFile -Path $target -Value ([ordered]@{ algorithm = 'sha256'; value = ('0' * 64) })
        }

        $forbiddenRoot = Join-Path $tempBase 'forbidden-response-field'
        Copy-TestPackage -Source $requestRoot -Destination $forbiddenRoot
        Invoke-NegativeCase -Failures $failures -Name 'forbidden_response_field' -ExpectedFailureText "forbidden field 'final_answer'" -PackageRootForCase $forbiddenRoot -RunInputRootForCase $runInputRoot -PreflightPathForCase $preflightPath -RepositoryRoot $RepoRoot -Mutate {
            $target = Join-Path $forbiddenRoot ("requests/$($firstRequestFile.Name)")
            $record = Get-Content -LiteralPath $target -Raw | ConvertFrom-Json
            $record | Add-Member -NotePropertyName final_answer -NotePropertyValue 'unsupported response text'
            Write-JsonFile -Path $target -Value $record
        }

        $manifestForbiddenRoot = Join-Path $tempBase 'forbidden-manifest-field'
        Copy-TestPackage -Source $requestRoot -Destination $manifestForbiddenRoot
        Invoke-NegativeCase -Failures $failures -Name 'forbidden_manifest_field' -ExpectedFailureText "forbidden field 'final_answer'" -PackageRootForCase $manifestForbiddenRoot -RunInputRootForCase $runInputRoot -PreflightPathForCase $preflightPath -RepositoryRoot $RepoRoot -Mutate {
            $target = Join-Path $manifestForbiddenRoot 'metadata/pilot-runner-request-manifest.json'
            $record = Get-Content -LiteralPath $target -Raw | ConvertFrom-Json
            $record | Add-Member -NotePropertyName final_answer -NotePropertyValue 'unsupported manifest response text'
            Write-JsonFile -Path $target -Value $record
        }

        $unexpectedFieldRoot = Join-Path $tempBase 'unexpected-request-field'
        Copy-TestPackage -Source $requestRoot -Destination $unexpectedFieldRoot
        Invoke-NegativeCase -Failures $failures -Name 'unexpected_request_field' -ExpectedFailureText "unexpected field 'unexpected_but_not_forbidden'" -PackageRootForCase $unexpectedFieldRoot -RunInputRootForCase $runInputRoot -PreflightPathForCase $preflightPath -RepositoryRoot $RepoRoot -Mutate {
            $target = Join-Path $unexpectedFieldRoot ("requests/$($firstRequestFile.Name)")
            $record = Get-Content -LiteralPath $target -Raw | ConvertFrom-Json
            $record | Add-Member -NotePropertyName unexpected_but_not_forbidden -NotePropertyValue 'extra'
            Write-JsonFile -Path $target -Value $record
            $manifestPath = Join-Path $unexpectedFieldRoot 'metadata/pilot-runner-request-manifest.json'
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $relativePath = "requests/$($firstRequestFile.Name)"
            foreach ($entry in @(Get-JsonArray -Value $manifest.request_records)) {
                if ([string]$entry.request_file -eq $relativePath) {
                    $entry.request_sha256 = Get-FileHashHex -Path $target
                }
            }
            Write-JsonFile -Path $manifestPath -Value $manifest
        }

        $malformedManifestRoot = Join-Path $tempBase 'malformed-manifest-json'
        Copy-TestPackage -Source $requestRoot -Destination $malformedManifestRoot
        Invoke-NegativeCase -Failures $failures -Name 'malformed_manifest_json' -ExpectedFailureText "Could not parse JSON file 'metadata/pilot-runner-request-manifest.json'" -PackageRootForCase $malformedManifestRoot -RunInputRootForCase $runInputRoot -PreflightPathForCase $preflightPath -RepositoryRoot $RepoRoot -Mutate {
            Set-Content -LiteralPath (Join-Path $malformedManifestRoot 'metadata/pilot-runner-request-manifest.json') -Value '{ not valid json' -Encoding UTF8
        }

        $sensitiveRoot = Join-Path $tempBase 'sensitive-non-json'
        Copy-TestPackage -Source $requestRoot -Destination $sensitiveRoot
        Invoke-NegativeCase -Failures $failures -Name 'sensitive_non_json_file' -ExpectedFailureText 'blocked sensitive pattern' -PackageRootForCase $sensitiveRoot -RunInputRootForCase $runInputRoot -PreflightPathForCase $preflightPath -RepositoryRoot $RepoRoot -Mutate {
            Set-Content -LiteralPath (Join-Path $sensitiveRoot 'metadata/leak.txt') -Value ('api' + '_key = pretend-secret-value') -Encoding UTF8
        }

        $info.Add('Validated a 9-request pilot runner request package.')
        $info.Add('Rejected missing request files, request/source mismatches, metadata hash tampering, forbidden response fields, and sensitive non-JSON files.')
        $info.Add('Rejected rehashed unexpected request fields and malformed metadata JSON.')
        $info.Add('No runner script was executed and no model/API calls were made by this request scorer.')
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
    if (-not $PackageRoot -or -not $RunInputRoot -or -not $PreflightPath) {
        $failures = New-Object System.Collections.Generic.List[string]
        $warnings = New-Object System.Collections.Generic.List[string]
        $info = New-Object System.Collections.Generic.List[string]
        $failures.Add('Provide -PackageRoot, -RunInputRoot, and -PreflightPath, or use -SelfTest.')
        $result = New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary @{}
    } else {
        $result = Invoke-PilotRunnerRequestScoring -Root $PackageRoot -InputRoot $RunInputRoot -PreflightFile $PreflightPath -RepositoryRoot $RepoRoot
    }
}

if ($Json) {
    $result | ConvertTo-Json -Depth 20
} else {
    "Empirical pilot runner request package scorer: $($result.status)"
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
