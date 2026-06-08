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
        if ($field -eq 'tool_calls') {
            continue
        }
        if (Test-IsBlankValue -Value $Record.$field) {
            $Failures.Add("$Label has blank required field '$field'.")
        }
    }
}

function Test-IsJsonNumber {
    param([object]$Value)
    foreach ($type in @([byte], [sbyte], [int16], [uint16], [int], [uint32], [long], [uint64], [single], [double], [decimal])) {
        if ($Value -is $type) {
            return $true
        }
    }
    return $false
}

function Assert-JsonNumber {
    param(
        [System.Collections.Generic.List[string]]$Failures,
        [string]$Label,
        [string]$Field,
        [object]$Value,
        [double]$Minimum = 0
    )
    if (-not (Test-IsJsonNumber -Value $Value)) {
        $Failures.Add("$Label has nonnumeric $Field '$Value'.")
        return
    }
    $numeric = [double]$Value
    if ([double]::IsNaN($numeric) -or [double]::IsInfinity($numeric) -or $numeric -lt $Minimum) {
        $Failures.Add("$Label has invalid $Field '$Value'.")
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
        [string]$ExpectedValue = '',
        [string]$MismatchMessage = ''
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
    if ($ExpectedValue -and $value -ne $ExpectedValue) {
        if ($MismatchMessage) {
            $Failures.Add($MismatchMessage)
        } else {
            $Failures.Add("$Label value does not match expected sha256 digest.")
        }
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

function Invoke-UpstreamScorers {
    param(
        [string]$InputRoot,
        [string]$PreflightFile,
        [string]$RepositoryRoot
    )
    $runInputScorer = Join-Path $PSScriptRoot 'score-empirical-run-inputs.ps1'
    $preflightScorer = Join-Path $PSScriptRoot 'score-empirical-execution-preflight.ps1'
    $runInputOutput = & $runInputScorer -PackageRoot $InputRoot -RepoRoot $RepositoryRoot -Json 2>&1
    if (-not $?) {
        throw "Run-input scorer failed before pilot execution scoring: $($runInputOutput | Out-String)"
    }
    $preflightOutput = & $preflightScorer -RunInputRoot $InputRoot -PreflightPath $PreflightFile -RepoRoot $RepositoryRoot -Json 2>&1
    if (-not $?) {
        throw "Execution preflight scorer failed before pilot execution scoring: $($preflightOutput | Out-String)"
    }
}

function Invoke-PackageValidation {
    param(
        [string]$Root,
        [string]$InputRoot,
        [string]$PreflightFile,
        [string]$RepositoryRoot,
        [bool]$SkipUpstreamScorers = $false
    )
    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}

    foreach ($requiredPath in @(
        (Join-Path $RepositoryRoot 'evals/empirical/pilot-execution-package-schema.yaml'),
        (Join-Path $RepositoryRoot 'docs/empirical-pilot-execution-runner.md'),
        (Join-Path $RepositoryRoot 'scripts/build-empirical-pilot-execution-package.ps1')
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            $failures.Add("Missing repository artifact required for pilot execution scoring: $requiredPath")
        }
    }
    foreach ($requiredPath in @($Root, $InputRoot, $PreflightFile)) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            $failures.Add("Missing required pilot execution scoring input: $requiredPath")
        }
    }
    if ($failures.Count -gt 0) {
        return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
    }

    if (-not $SkipUpstreamScorers) {
        try {
            Invoke-UpstreamScorers -InputRoot $InputRoot -PreflightFile $PreflightFile -RepositoryRoot $RepositoryRoot
        } catch {
            $failures.Add($_.Exception.Message)
            return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
        }
    }

    $schemaText = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'evals/empirical/pilot-execution-package-schema.yaml') -Raw
    if ((Get-Scalar -Text $schemaText -Field 'claim_boundary') -ne 'pilot_execution_package_schema_only_no_empirical_results') {
        $failures.Add('Pilot execution package schema must declare pilot_execution_package_schema_only_no_empirical_results.')
    }
    $requiredTranscriptFields = Get-TopLevelList -Text $schemaText -Field 'required_transcript_fields'
    $requiredCostFields = Get-TopLevelList -Text $schemaText -Field 'required_cost_latency_fields'
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
            $failures.Add("Could not read pilot execution package file '$relative': $($_.Exception.Message)")
            continue
        }
        $packageTextParts.Add($raw) | Out-Null
        foreach ($hit in (Test-SensitiveText -Text $raw)) {
            $failures.Add("Pilot execution package file '$relative' contains blocked sensitive pattern '$hit'.")
        }
        if ($file.Extension -ne '.json') {
            $failures.Add("Pilot execution package contains unexpected non-JSON file '$relative'.")
        }
    }
    $packageText = $packageTextParts -join "`n"
    Assert-NoForbiddenJsonFields -Failures $failures -RawJson $packageText -ForbiddenFields $forbiddenFields -Label 'pilot execution package'
    foreach ($claim in $forbiddenFields) {
        if ([regex]::IsMatch($packageText, "(?i)(^|[^A-Za-z0-9_])$([regex]::Escape($claim))([^A-Za-z0-9_]|$)")) {
            $failures.Add("Pilot execution package contains unsupported claim text '$claim'.")
        }
    }

    $preflight = Get-Content -LiteralPath $PreflightFile -Raw | ConvertFrom-Json
    $selectedIds = @(Get-JsonArray -Value $preflight.selected_run_input_ids | ForEach-Object { [string]$_ })
    $runInputById = @{}
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $InputRoot 'run-inputs') -File -Filter '*.json')) {
        $record = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        $runInputById[[string]$record.run_input_id] = $record
    }

    foreach ($directory in @('transcripts', 'cost-latency', 'metadata')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root $directory))) {
            $failures.Add("Pilot execution package is missing required directory '$directory'.")
        }
    }
    $transcripts = @(Read-JsonRecords -Failures $failures -Directory (Join-Path $Root 'transcripts') -Label 'transcript')
    $costRecords = @(Read-JsonRecords -Failures $failures -Directory (Join-Path $Root 'cost-latency') -Label 'cost-latency')
    if ($failures.Count -gt 0) {
        return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
    }

    $transcriptByRunInputId = @{}
    $transcriptByRunId = @{}
    foreach ($transcript in $transcripts) {
        Assert-RequiredFields -Failures $failures -Record $transcript -Fields $requiredTranscriptFields -Label "transcript $($transcript.run_id)"
        foreach ($field in @('model_provider', 'model_name_or_alias', 'runtime_surface')) {
            $expected = switch ($field) {
                'model_provider' { [string]$preflight.provider }
                'model_name_or_alias' { [string]$preflight.model_name_or_alias }
                'runtime_surface' { [string]$preflight.runtime_surface }
            }
            if ([string]$transcript.$field -ne $expected) {
                $failures.Add("Transcript '$($transcript.run_id)' $field '$($transcript.$field)' does not match preflight '$expected'.")
            }
        }
        if ($transcript.redaction_status -ne 'public_synthetic_task_no_private_material') {
            $failures.Add("Transcript '$($transcript.run_id)' has unexpected redaction_status '$($transcript.redaction_status)'.")
        }
        $messages = @(Get-JsonArray -Value $transcript.transcript_messages)
        if ($messages.Count -lt 2) {
            $failures.Add("Transcript '$($transcript.run_id)' must contain at least user and assistant messages.")
        }
        $runInputId = [string]$transcript.run_input_id
        if ($transcriptByRunInputId.ContainsKey($runInputId)) {
            $failures.Add("Multiple transcripts found for run_input_id '$runInputId'.")
        } else {
            $transcriptByRunInputId[$runInputId] = $transcript
        }
        $transcriptByRunId[[string]$transcript.run_id] = $transcript
        if (-not $runInputById.ContainsKey($runInputId)) {
            $failures.Add("Transcript '$($transcript.run_id)' references missing run_input_id '$runInputId'.")
        } else {
            $runInput = $runInputById[$runInputId]
            if ($transcript.input_prompt -ne $runInput.input_prompt) {
                $failures.Add("Transcript '$($transcript.run_id)' input_prompt does not match source run input.")
            }
            foreach ($field in @('task_id', 'condition', 'repeat_index', 'task_suite_version')) {
                if ([string]$transcript.$field -ne [string]$runInput.$field) {
                    $failures.Add("Transcript '$($transcript.run_id)' $field does not match source run input.")
                }
            }
        }
    }

    foreach ($id in $selectedIds) {
        if (-not $transcriptByRunInputId.ContainsKey($id)) {
            $failures.Add("Selected run_input_id '$id' has no pilot transcript.")
        }
    }
    if ($transcripts.Count -ne $selectedIds.Count) {
        $failures.Add("Expected $($selectedIds.Count) transcript records from preflight selection; found $($transcripts.Count).")
    }

    $costById = @{}
    foreach ($cost in $costRecords) {
        Assert-RequiredFields -Failures $failures -Record $cost -Fields $requiredCostFields -Label "cost-latency $($cost.cost_latency_record_id)"
        foreach ($field in @('input_tokens', 'output_tokens', 'tool_call_count', 'wall_time_ms', 'api_cost_usd', 'retry_count')) {
            Assert-JsonNumber -Failures $failures -Label "cost-latency $($cost.cost_latency_record_id)" -Field $field -Value $cost.$field -Minimum 0
        }
        $costById[[string]$cost.cost_latency_record_id] = $cost
        if (-not $transcriptByRunId.ContainsKey([string]$cost.run_id)) {
            $failures.Add("Cost-latency '$($cost.cost_latency_record_id)' references missing transcript run_id '$($cost.run_id)'.")
        }
    }
    foreach ($transcript in $transcripts) {
        $costId = [string]$transcript.cost_latency_record_id
        if (-not $costById.ContainsKey($costId)) {
            $failures.Add("Transcript '$($transcript.run_id)' references missing cost_latency_record_id '$costId'.")
            continue
        }
        if ([string]$costById[$costId].run_id -ne [string]$transcript.run_id) {
            $failures.Add("Transcript '$($transcript.run_id)' cost_latency_record_id '$costId' joins to run_id '$($costById[$costId].run_id)'.")
        }
    }

    $manifestPath = Join-Path $Root 'metadata/pilot-execution-manifest.json'
    $preflightHashPath = Join-Path $Root 'metadata/source-preflight-hash.json'
    $runInputManifestHashPath = Join-Path $Root 'metadata/source-run-input-manifest-hash.json'
    $runnerHashPath = Join-Path $Root 'metadata/runner-script-hash.json'
    foreach ($metadataPath in @($manifestPath, $preflightHashPath, $runInputManifestHashPath, $runnerHashPath)) {
        if (-not (Test-Path -LiteralPath $metadataPath)) {
            $failures.Add("Missing required pilot execution metadata file: $metadataPath")
        }
    }
    $expectedPreflightHash = Get-FileHashHex -Path $PreflightPath
    $expectedRunInputManifestHash = Get-FileHashHex -Path (Join-Path $InputRoot 'metadata/run-input-manifest.json')
    $manifest = $null
    $preflightHashRecord = $null
    $runInputManifestHashRecord = $null
    $runnerHashRecord = $null
    if (Test-Path -LiteralPath $preflightHashPath) {
        $preflightHashRecord = Get-Content -LiteralPath $preflightHashPath -Raw | ConvertFrom-Json
        Assert-Sha256Record -Failures $failures -Record $preflightHashRecord -Label 'source-preflight-hash.json' -ExpectedValue $expectedPreflightHash -MismatchMessage 'source-preflight-hash.json does not match PreflightPath.'
    }
    if (Test-Path -LiteralPath $runInputManifestHashPath) {
        $runInputManifestHashRecord = Get-Content -LiteralPath $runInputManifestHashPath -Raw | ConvertFrom-Json
        Assert-Sha256Record -Failures $failures -Record $runInputManifestHashRecord -Label 'source-run-input-manifest-hash.json' -ExpectedValue $expectedRunInputManifestHash -MismatchMessage 'source-run-input-manifest-hash.json does not match run-input manifest.'
    }
    if (Test-Path -LiteralPath $runnerHashPath) {
        $runnerHashRecord = Get-Content -LiteralPath $runnerHashPath -Raw | ConvertFrom-Json
        Assert-Sha256Record -Failures $failures -Record $runnerHashRecord -Label 'runner-script-hash.json'
        if (-not (Test-HasProperty -Record $runnerHashRecord -Name 'label') -or [string]::IsNullOrWhiteSpace([string]$runnerHashRecord.label) -or [string]$runnerHashRecord.label -match '[\\/:]') {
            $failures.Add('runner-script-hash.json label must be nonblank and contain no path separators.')
        }
    }
    if (Test-Path -LiteralPath $manifestPath) {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        if ($manifest.claim_boundary -ne 'pilot_execution_package_unlabeled_no_empirical_results') {
            $failures.Add('Pilot execution manifest must declare pilot_execution_package_unlabeled_no_empirical_results.')
        }
        if ([int]$manifest.generated_run_count -ne $selectedIds.Count) {
            $failures.Add("Pilot execution manifest generated_run_count $($manifest.generated_run_count) does not match selected count $($selectedIds.Count).")
        }
        Assert-ListContains -Failures $failures -Items @(Get-JsonArray -Value $manifest.current_nonclaims | ForEach-Object { [string]$_ }) -Required $requiredNonclaims -Label 'pilot execution manifest current_nonclaims'
        if (-not (Test-HasProperty -Record $manifest -Name 'source_preflight_sha256')) {
            $failures.Add('Pilot execution manifest is missing source_preflight_sha256.')
        } elseif (-not (Test-IsSha256Hex -Value ([string]$manifest.source_preflight_sha256))) {
            $failures.Add('Pilot execution manifest source_preflight_sha256 must be a lowercase sha256 hex digest.')
        } elseif ([string]$manifest.source_preflight_sha256 -ne $expectedPreflightHash) {
            $failures.Add('Pilot execution manifest source_preflight_sha256 does not match PreflightPath.')
        } elseif ($preflightHashRecord -and [string]$manifest.source_preflight_sha256 -ne [string]$preflightHashRecord.value) {
            $failures.Add('Pilot execution manifest source_preflight_sha256 does not match source-preflight-hash.json.')
        }
        if (-not (Test-HasProperty -Record $manifest -Name 'source_run_input_manifest_sha256')) {
            $failures.Add('Pilot execution manifest is missing source_run_input_manifest_sha256.')
        } elseif (-not (Test-IsSha256Hex -Value ([string]$manifest.source_run_input_manifest_sha256))) {
            $failures.Add('Pilot execution manifest source_run_input_manifest_sha256 must be a lowercase sha256 hex digest.')
        } elseif ([string]$manifest.source_run_input_manifest_sha256 -ne $expectedRunInputManifestHash) {
            $failures.Add('Pilot execution manifest source_run_input_manifest_sha256 does not match run-input manifest.')
        } elseif ($runInputManifestHashRecord -and [string]$manifest.source_run_input_manifest_sha256 -ne [string]$runInputManifestHashRecord.value) {
            $failures.Add('Pilot execution manifest source_run_input_manifest_sha256 does not match source-run-input-manifest-hash.json.')
        }
        if (-not (Test-HasProperty -Record $manifest -Name 'runner_script_sha256')) {
            $failures.Add('Pilot execution manifest is missing runner_script_sha256.')
        } elseif (-not (Test-IsSha256Hex -Value ([string]$manifest.runner_script_sha256))) {
            $failures.Add('Pilot execution manifest runner_script_sha256 must be a lowercase sha256 hex digest.')
        } elseif ($runnerHashRecord -and [string]$manifest.runner_script_sha256 -ne [string]$runnerHashRecord.value) {
            $failures.Add('Pilot execution manifest runner_script_sha256 does not match runner-script-hash.json.')
        }
        if (-not (Test-HasProperty -Record $manifest -Name 'runner_script_label') -or [string]::IsNullOrWhiteSpace([string]$manifest.runner_script_label) -or [string]$manifest.runner_script_label -match '[\\/:]') {
            $failures.Add('Pilot execution manifest runner_script_label must be nonblank and contain no path separators.')
        } elseif ($runnerHashRecord -and [string]$manifest.runner_script_label -ne [string]$runnerHashRecord.label) {
            $failures.Add('Pilot execution manifest runner_script_label does not match runner-script-hash.json label.')
        }
    }

    $summary['selected_run_input_count'] = $selectedIds.Count
    $summary['transcript_count'] = $transcripts.Count
    $summary['cost_latency_count'] = $costRecords.Count
    $info.Add('Scored empirical pilot execution package structure.')
    $info.Add("Checked $($transcripts.Count) pilot transcript record(s) and $($costRecords.Count) cost-latency record(s).")

    $status = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
    return (New-Result -Status $status -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
}

function Assert-NegativeCase {
    param(
        [System.Collections.Generic.List[string]]$Failures,
        [string]$Name,
        [scriptblock]$Mutate,
        [string]$Root,
        [string]$InputRoot,
        [string]$PreflightFile,
        [string]$RepositoryRoot,
        [string]$ExpectedFailureText,
        [bool]$SkipUpstreamScorers = $false
    )
    & $Mutate
    $result = Invoke-PackageValidation -Root $Root -InputRoot $InputRoot -PreflightFile $PreflightFile -RepositoryRoot $RepositoryRoot -SkipUpstreamScorers $SkipUpstreamScorers
    if ($result.status -eq 'pass') {
        $Failures.Add("Negative pilot execution package case '$Name' unexpectedly passed.")
        return
    }
    $failureText = ($result.failures -join "`n")
    if ($failureText -notlike "*$ExpectedFailureText*") {
        $Failures.Add("Negative pilot execution package case '$Name' failed, but not for expected text '$ExpectedFailureText'.")
    }
}

function Get-FirstPilotRecordFiles {
    param([string]$Root)
    $transcriptFiles = @(Get-ChildItem -LiteralPath (Join-Path $Root 'transcripts') -File -Filter '*.json' | Sort-Object Name)
    $costFiles = @(Get-ChildItem -LiteralPath (Join-Path $Root 'cost-latency') -File -Filter '*.json' | Sort-Object Name)
    if ($transcriptFiles.Count -eq 0 -or $costFiles.Count -eq 0) {
        throw 'Expected pilot package to contain transcript and cost-latency JSON files.'
    }
    return [pscustomobject]@{
        Transcript = $transcriptFiles[0]
        Cost = $costFiles[0]
    }
}

function Invoke-SelfTest {
    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}
    $tempBase = Join-Path ([System.IO.Path]::GetTempPath()) ("adg-pilot-execution-scorer-selftest-" + [guid]::NewGuid().ToString())
    try {
        New-Item -ItemType Directory -Force -Path $tempBase | Out-Null
        $runInputRoot = Join-Path $tempBase 'run-inputs-package'
        $preflightPath = Join-Path $tempBase 'execution-preflight.json'
        $packageRoot = Join-Path $tempBase 'pilot-execution-package'
        $runnerPath = Join-Path $tempBase 'fixture-runner.ps1'
        $runInputBuilder = Join-Path $PSScriptRoot 'build-empirical-run-inputs.ps1'
        $preflightBuilder = Join-Path $PSScriptRoot 'build-empirical-execution-preflight.ps1'
        $pilotBuilder = Join-Path $PSScriptRoot 'build-empirical-pilot-execution-package.ps1'

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
            $failures.Add("Run-input builder failed during pilot execution scorer self-test: $($runInputOutput | Out-String)")
            return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
        }
        $preflightOutput = & $preflightBuilder -RunInputRoot $runInputRoot -OutputPath $preflightPath -Provider 'self-test-provider' -ModelNameOrAlias 'self-test-model' -RuntimeSurface 'self-test-runner-script' -MaxBudgetUsd 1.0 2>&1
        if (-not $?) {
            $failures.Add("Execution preflight builder failed during pilot execution scorer self-test: $($preflightOutput | Out-String)")
            return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
        }
        $pilotOutput = & $pilotBuilder -RunInputRoot $runInputRoot -PreflightPath $preflightPath -OutputRoot $packageRoot -RunnerScriptPath $runnerPath -RunnerLabel 'fixture-runner-v0' -AllowRunnerScript 2>&1
        if (-not $?) {
            $failures.Add("Pilot execution builder failed during scorer self-test: $($pilotOutput | Out-String)")
            return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
        }

        $positive = Invoke-PackageValidation -Root $packageRoot -InputRoot $runInputRoot -PreflightFile $preflightPath -RepositoryRoot $RepoRoot
        if ($positive.status -ne 'pass') {
            $failures.Add("Positive pilot execution package self-test failed: $($positive.failures -join '; ')")
        } else {
            $summary['transcript_count'] = $positive.summary.transcript_count
            $summary['cost_latency_count'] = $positive.summary.cost_latency_count
        }

        $pilotFiles = Get-FirstPilotRecordFiles -Root $packageRoot

        Assert-NegativeCase -Failures $failures -Name 'missing_transcript' -Root $packageRoot -InputRoot $runInputRoot -PreflightFile $preflightPath -RepositoryRoot $RepoRoot -ExpectedFailureText 'has no pilot transcript' -SkipUpstreamScorers $true -Mutate {
            Remove-Item -LiteralPath $pilotFiles.Transcript.FullName -Force
        }
        & $pilotBuilder -RunInputRoot $runInputRoot -PreflightPath $preflightPath -OutputRoot $packageRoot -RunnerScriptPath $runnerPath -RunnerLabel 'fixture-runner-v0' -AllowRunnerScript -Force | Out-Null
        $pilotFiles = Get-FirstPilotRecordFiles -Root $packageRoot

        Assert-NegativeCase -Failures $failures -Name 'crossed_cost_latency_join' -Root $packageRoot -InputRoot $runInputRoot -PreflightFile $preflightPath -RepositoryRoot $RepoRoot -ExpectedFailureText 'references missing transcript run_id' -SkipUpstreamScorers $true -Mutate {
            $cost = Get-Content -LiteralPath $pilotFiles.Cost.FullName -Raw | ConvertFrom-Json
            $cost.run_id = 'pilot-run-missing'
            Write-JsonFile -Path $pilotFiles.Cost.FullName -Value $cost
        }
        & $pilotBuilder -RunInputRoot $runInputRoot -PreflightPath $preflightPath -OutputRoot $packageRoot -RunnerScriptPath $runnerPath -RunnerLabel 'fixture-runner-v0' -AllowRunnerScript -Force | Out-Null
        $pilotFiles = Get-FirstPilotRecordFiles -Root $packageRoot

        Assert-NegativeCase -Failures $failures -Name 'credential_like_content' -Root $packageRoot -InputRoot $runInputRoot -PreflightFile $preflightPath -RepositoryRoot $RepoRoot -ExpectedFailureText 'blocked sensitive pattern' -SkipUpstreamScorers $true -Mutate {
            $transcript = Get-Content -LiteralPath $pilotFiles.Transcript.FullName -Raw | ConvertFrom-Json
            $transcript.final_answer = ('fixture output with bearer-like text ' + 'Bear' + 'er abcdefghijklmnopqrstuvwxyz')
            Write-JsonFile -Path $pilotFiles.Transcript.FullName -Value $transcript
        }
        & $pilotBuilder -RunInputRoot $runInputRoot -PreflightPath $preflightPath -OutputRoot $packageRoot -RunnerScriptPath $runnerPath -RunnerLabel 'fixture-runner-v0' -AllowRunnerScript -Force | Out-Null
        $pilotFiles = Get-FirstPilotRecordFiles -Root $packageRoot

        Assert-NegativeCase -Failures $failures -Name 'provider_mismatch' -Root $packageRoot -InputRoot $runInputRoot -PreflightFile $preflightPath -RepositoryRoot $RepoRoot -ExpectedFailureText 'does not match preflight' -SkipUpstreamScorers $true -Mutate {
            $transcript = Get-Content -LiteralPath $pilotFiles.Transcript.FullName -Raw | ConvertFrom-Json
            $transcript.model_provider = 'wrong-provider'
            Write-JsonFile -Path $pilotFiles.Transcript.FullName -Value $transcript
        }
        & $pilotBuilder -RunInputRoot $runInputRoot -PreflightPath $preflightPath -OutputRoot $packageRoot -RunnerScriptPath $runnerPath -RunnerLabel 'fixture-runner-v0' -AllowRunnerScript -Force | Out-Null
        $pilotFiles = Get-FirstPilotRecordFiles -Root $packageRoot

        Assert-NegativeCase -Failures $failures -Name 'model_mismatch' -Root $packageRoot -InputRoot $runInputRoot -PreflightFile $preflightPath -RepositoryRoot $RepoRoot -ExpectedFailureText 'does not match preflight' -SkipUpstreamScorers $true -Mutate {
            $transcript = Get-Content -LiteralPath $pilotFiles.Transcript.FullName -Raw | ConvertFrom-Json
            $transcript.model_name_or_alias = 'wrong-model'
            Write-JsonFile -Path $pilotFiles.Transcript.FullName -Value $transcript
        }
        & $pilotBuilder -RunInputRoot $runInputRoot -PreflightPath $preflightPath -OutputRoot $packageRoot -RunnerScriptPath $runnerPath -RunnerLabel 'fixture-runner-v0' -AllowRunnerScript -Force | Out-Null
        $pilotFiles = Get-FirstPilotRecordFiles -Root $packageRoot

        Assert-NegativeCase -Failures $failures -Name 'runtime_mismatch' -Root $packageRoot -InputRoot $runInputRoot -PreflightFile $preflightPath -RepositoryRoot $RepoRoot -ExpectedFailureText 'does not match preflight' -SkipUpstreamScorers $true -Mutate {
            $transcript = Get-Content -LiteralPath $pilotFiles.Transcript.FullName -Raw | ConvertFrom-Json
            $transcript.runtime_surface = 'wrong-runtime'
            Write-JsonFile -Path $pilotFiles.Transcript.FullName -Value $transcript
        }
        & $pilotBuilder -RunInputRoot $runInputRoot -PreflightPath $preflightPath -OutputRoot $packageRoot -RunnerScriptPath $runnerPath -RunnerLabel 'fixture-runner-v0' -AllowRunnerScript -Force | Out-Null
        $pilotFiles = Get-FirstPilotRecordFiles -Root $packageRoot

        $extraSecretFile = Join-Path $packageRoot 'metadata/extra-secret.txt'
        Assert-NegativeCase -Failures $failures -Name 'non_json_sensitive_file' -Root $packageRoot -InputRoot $runInputRoot -PreflightFile $preflightPath -RepositoryRoot $RepoRoot -ExpectedFailureText 'unexpected non-JSON file' -SkipUpstreamScorers $true -Mutate {
            Set-Content -LiteralPath $extraSecretFile -Value ('sk-' + 'abcdefghijklmnop') -Encoding UTF8
        }
        if (Test-Path -LiteralPath $extraSecretFile) {
            Remove-Item -LiteralPath $extraSecretFile -Force
        }
        & $pilotBuilder -RunInputRoot $runInputRoot -PreflightPath $preflightPath -OutputRoot $packageRoot -RunnerScriptPath $runnerPath -RunnerLabel 'fixture-runner-v0' -AllowRunnerScript -Force | Out-Null
        $pilotFiles = Get-FirstPilotRecordFiles -Root $packageRoot

        Assert-NegativeCase -Failures $failures -Name 'manifest_preflight_hash_mismatch' -Root $packageRoot -InputRoot $runInputRoot -PreflightFile $preflightPath -RepositoryRoot $RepoRoot -ExpectedFailureText 'Pilot execution manifest source_preflight_sha256 does not match PreflightPath.' -SkipUpstreamScorers $true -Mutate {
            $manifestPath = Join-Path $packageRoot 'metadata/pilot-execution-manifest.json'
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $manifest.source_preflight_sha256 = ('0' * 64)
            Write-JsonFile -Path $manifestPath -Value $manifest
        }
        & $pilotBuilder -RunInputRoot $runInputRoot -PreflightPath $preflightPath -OutputRoot $packageRoot -RunnerScriptPath $runnerPath -RunnerLabel 'fixture-runner-v0' -AllowRunnerScript -Force | Out-Null
        $pilotFiles = Get-FirstPilotRecordFiles -Root $packageRoot

        Assert-NegativeCase -Failures $failures -Name 'manifest_run_input_hash_mismatch' -Root $packageRoot -InputRoot $runInputRoot -PreflightFile $preflightPath -RepositoryRoot $RepoRoot -ExpectedFailureText 'Pilot execution manifest source_run_input_manifest_sha256 does not match run-input manifest.' -SkipUpstreamScorers $true -Mutate {
            $manifestPath = Join-Path $packageRoot 'metadata/pilot-execution-manifest.json'
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $manifest.source_run_input_manifest_sha256 = ('1' * 64)
            Write-JsonFile -Path $manifestPath -Value $manifest
        }
        & $pilotBuilder -RunInputRoot $runInputRoot -PreflightPath $preflightPath -OutputRoot $packageRoot -RunnerScriptPath $runnerPath -RunnerLabel 'fixture-runner-v0' -AllowRunnerScript -Force | Out-Null
        $pilotFiles = Get-FirstPilotRecordFiles -Root $packageRoot

        Assert-NegativeCase -Failures $failures -Name 'manifest_runner_hash_mismatch' -Root $packageRoot -InputRoot $runInputRoot -PreflightFile $preflightPath -RepositoryRoot $RepoRoot -ExpectedFailureText 'Pilot execution manifest runner_script_sha256 does not match runner-script-hash.json.' -SkipUpstreamScorers $true -Mutate {
            $manifestPath = Join-Path $packageRoot 'metadata/pilot-execution-manifest.json'
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $manifest.runner_script_sha256 = ('2' * 64)
            Write-JsonFile -Path $manifestPath -Value $manifest
        }
        & $pilotBuilder -RunInputRoot $runInputRoot -PreflightPath $preflightPath -OutputRoot $packageRoot -RunnerScriptPath $runnerPath -RunnerLabel 'fixture-runner-v0' -AllowRunnerScript -Force | Out-Null
        $pilotFiles = Get-FirstPilotRecordFiles -Root $packageRoot

        Assert-NegativeCase -Failures $failures -Name 'source_preflight_hash_algorithm_mismatch' -Root $packageRoot -InputRoot $runInputRoot -PreflightFile $preflightPath -RepositoryRoot $RepoRoot -ExpectedFailureText 'source-preflight-hash.json algorithm must be sha256.' -SkipUpstreamScorers $true -Mutate {
            $recordPath = Join-Path $packageRoot 'metadata/source-preflight-hash.json'
            $record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
            $record.algorithm = 'sha1'
            Write-JsonFile -Path $recordPath -Value $record
        }
        & $pilotBuilder -RunInputRoot $runInputRoot -PreflightPath $preflightPath -OutputRoot $packageRoot -RunnerScriptPath $runnerPath -RunnerLabel 'fixture-runner-v0' -AllowRunnerScript -Force | Out-Null
        $pilotFiles = Get-FirstPilotRecordFiles -Root $packageRoot

        Assert-NegativeCase -Failures $failures -Name 'runner_hash_label_separator' -Root $packageRoot -InputRoot $runInputRoot -PreflightFile $preflightPath -RepositoryRoot $RepoRoot -ExpectedFailureText 'runner-script-hash.json label must be nonblank and contain no path separators.' -SkipUpstreamScorers $true -Mutate {
            $recordPath = Join-Path $packageRoot 'metadata/runner-script-hash.json'
            $record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
            $record.label = 'bad/label'
            Write-JsonFile -Path $recordPath -Value $record
        }
        & $pilotBuilder -RunInputRoot $runInputRoot -PreflightPath $preflightPath -OutputRoot $packageRoot -RunnerScriptPath $runnerPath -RunnerLabel 'fixture-runner-v0' -AllowRunnerScript -Force | Out-Null
        $pilotFiles = Get-FirstPilotRecordFiles -Root $packageRoot

        $schemaText = Get-Content -LiteralPath (Join-Path $RepoRoot 'evals/empirical/pilot-execution-package-schema.yaml') -Raw
        $forbiddenValueTokens = Get-TopLevelList -Text $schemaText -Field 'forbidden_fields'
        foreach ($forbiddenValueToken in $forbiddenValueTokens) {
            Assert-NegativeCase -Failures $failures -Name "unsupported_value_$forbiddenValueToken" -Root $packageRoot -InputRoot $runInputRoot -PreflightFile $preflightPath -RepositoryRoot $RepoRoot -ExpectedFailureText "unsupported claim text '$forbiddenValueToken'" -SkipUpstreamScorers $true -Mutate {
                $transcript = Get-Content -LiteralPath $pilotFiles.Transcript.FullName -Raw | ConvertFrom-Json
                $transcript.final_claim = $forbiddenValueToken
                Write-JsonFile -Path $pilotFiles.Transcript.FullName -Value $transcript
            }
            & $pilotBuilder -RunInputRoot $runInputRoot -PreflightPath $preflightPath -OutputRoot $packageRoot -RunnerScriptPath $runnerPath -RunnerLabel 'fixture-runner-v0' -AllowRunnerScript -Force | Out-Null
            $pilotFiles = Get-FirstPilotRecordFiles -Root $packageRoot
        }

        $info.Add('Validated generated pilot execution package.')
        $info.Add('Rejected missing transcript, crossed cost-latency join, credential-like content, provider/model/runtime mismatches, metadata hash tampering, non-JSON sensitive files, and unsupported result/readiness claim cases.')
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
        $summary = @{}
        $failures.Add('Provide -PackageRoot, -RunInputRoot, and -PreflightPath, or use -SelfTest.')
        $result = New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary
    } else {
        $result = Invoke-PackageValidation -Root $PackageRoot -InputRoot $RunInputRoot -PreflightFile $PreflightPath -RepositoryRoot $RepoRoot
    }
}

if ($Json) {
    $result | ConvertTo-Json -Depth 20
} else {
    "Empirical pilot execution package scoring: $($result.status)"
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
