param(
    [string]$ResponsePath,
    [string]$RequestPath,
    [string]$SchemaPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'evals/empirical/runner-response-schema.yaml'),
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

function Has-JsonProperty {
    param(
        [object]$Object,
        [string]$Name
    )
    return ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name])
}

function Get-YamlList {
    param(
        [string]$Text,
        [string]$Field
    )
    $match = [regex]::Match($Text, "(?m)^$([regex]::Escape($Field)):\s*\r?\n(?<items>(?:^[ \t]+-[^\r\n]*(?:\r?\n|$))+)")
    if (-not $match.Success) {
        return @()
    }
    return @([regex]::Matches($match.Groups['items'].Value, '(?m)^\s+-\s+(.+?)\s*$') | ForEach-Object {
        $_.Groups[1].Value.Trim()
    })
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

function Assert-NonnegativeFiniteNumber {
    param(
        [System.Collections.Generic.List[string]]$Failures,
        [object]$Record,
        [string]$Field,
        [bool]$RequireInteger
    )
    if (-not (Has-JsonProperty -Object $Record -Name $Field)) {
        return
    }
    $rawValue = $Record.PSObject.Properties[$Field].Value
    if ($null -eq $rawValue) {
        $Failures.Add("Runner response field '$Field' must be numeric.")
        return
    }
    if ($rawValue -is [bool]) {
        $Failures.Add("Runner response field '$Field' must be numeric.")
        return
    }
    if ($rawValue -is [string] -and -not $rawValue.Trim()) {
        $Failures.Add("Runner response field '$Field' must be numeric.")
        return
    }
    $number = 0.0
    if ($rawValue -is [string]) {
        if (-not [double]::TryParse($rawValue.Trim(), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
            $Failures.Add("Runner response field '$Field' must be numeric.")
            return
        }
    } elseif ($rawValue -is [byte] -or $rawValue -is [sbyte] -or $rawValue -is [int16] -or $rawValue -is [uint16] -or $rawValue -is [int] -or $rawValue -is [uint32] -or $rawValue -is [long] -or $rawValue -is [uint64] -or $rawValue -is [single] -or $rawValue -is [double] -or $rawValue -is [decimal]) {
        $number = [double]$rawValue
    } else {
        $Failures.Add("Runner response field '$Field' must be numeric.")
        return
    }
    if ([double]::IsNaN($number) -or [double]::IsInfinity($number) -or $number -lt 0) {
        $Failures.Add("Runner response field '$Field' must be a finite nonnegative number.")
        return
    }
    if ($RequireInteger -and [math]::Floor($number) -ne $number) {
        $Failures.Add("Runner response field '$Field' must be an integer.")
    }
}

function Invoke-RunnerResponseValidation {
    param(
        [string]$ResponseFile,
        [string]$RequestFile,
        [string]$SchemaFile
    )
    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}

    if (-not $ResponseFile) {
        $failures.Add('Provide -ResponsePath, or use -SelfTest.')
        return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
    }
    if (-not (Test-Path -LiteralPath $ResponseFile)) {
        $failures.Add("ResponsePath not found: $ResponseFile")
        return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
    }
    if (-not (Test-Path -LiteralPath $SchemaFile)) {
        $failures.Add("SchemaPath not found: $SchemaFile")
        return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
    }

    $schemaText = Get-Content -LiteralPath $SchemaFile -Raw
    if ($schemaText -notmatch 'claim_boundary:\s*runner_response_contract_schema_only_no_execution_results') {
        $failures.Add('Runner response schema must declare runner_response_contract_schema_only_no_execution_results.')
    }
    $requiredFields = Get-YamlList -Text $schemaText -Field 'required_response_fields'
    $numericFields = Get-YamlList -Text $schemaText -Field 'numeric_fields'
    $integerFields = Get-YamlList -Text $schemaText -Field 'integer_numeric_fields'
    $forbiddenFields = Get-YamlList -Text $schemaText -Field 'forbidden_fields'

    $raw = Get-Content -LiteralPath $ResponseFile -Raw
    foreach ($hit in (Test-SensitiveText -Text $raw)) {
        $failures.Add("Runner response contains blocked sensitive pattern '$hit'.")
    }
    try {
        $response = $raw | ConvertFrom-Json
    } catch {
        $failures.Add("Runner response is not valid JSON: $($_.Exception.Message)")
        return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
    }
    if ($response -is [array]) {
        $failures.Add('Runner response must be a single JSON object, not an array.')
        return (New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
    }

    foreach ($field in $requiredFields) {
        if (-not (Has-JsonProperty -Object $response -Name $field)) {
            $failures.Add("Runner response is missing required field '$field'.")
        }
    }
    if (Has-JsonProperty -Object $response -Name 'final_answer') {
        if (-not ($response.final_answer -is [string]) -or -not ([string]$response.final_answer).Trim()) {
            $failures.Add("Runner response field 'final_answer' must be a nonempty string.")
        }
    }

    foreach ($field in $forbiddenFields) {
        if (Has-JsonProperty -Object $response -Name $field) {
            $failures.Add("Runner response must not contain forbidden field '$field'.")
        }
    }

    foreach ($field in $numericFields) {
        Assert-NonnegativeFiniteNumber -Failures $failures -Record $response -Field $field -RequireInteger ($integerFields -contains $field)
    }

    if (Has-JsonProperty -Object $response -Name 'transcript_messages') {
        $messages = @(Get-JsonArray -Value $response.transcript_messages)
        if ($messages.Count -eq 0) {
            $failures.Add("Runner response field 'transcript_messages' must be a nonempty array when present.")
        }
        foreach ($message in $messages) {
            if (-not (Has-JsonProperty -Object $message -Name 'role') -or -not ([string]$message.role).Trim()) {
                $failures.Add("Runner response transcript_messages entries must include nonempty 'role'.")
            }
            if (-not (Has-JsonProperty -Object $message -Name 'content') -or -not ([string]$message.content).Trim()) {
                $failures.Add("Runner response transcript_messages entries must include nonempty 'content'.")
            }
        }
    }
    if (Has-JsonProperty -Object $response -Name 'tool_calls') {
        $null = @(Get-JsonArray -Value $response.tool_calls)
    }
    if (Has-JsonProperty -Object $response -Name 'checked_evidence') {
        $evidenceItems = @(Get-JsonArray -Value $response.checked_evidence)
        if ($evidenceItems.Count -eq 0) {
            $failures.Add("Runner response field 'checked_evidence' must be a nonempty array when present.")
        }
        foreach ($item in $evidenceItems) {
            if (-not ([string]$item).Trim()) {
                $failures.Add("Runner response field 'checked_evidence' must contain only nonempty values.")
            }
        }
    }

    if ($RequestFile) {
        if (-not (Test-Path -LiteralPath $RequestFile)) {
            $failures.Add("RequestPath not found: $RequestFile")
        } else {
            try {
                $request = Get-Content -LiteralPath $RequestFile -Raw | ConvertFrom-Json
                if ((Has-JsonProperty -Object $response -Name 'run_input_id') -and (Has-JsonProperty -Object $request -Name 'run_input_id')) {
                    if ([string]$response.run_input_id -ne [string]$request.run_input_id) {
                        $failures.Add("Runner response run_input_id '$($response.run_input_id)' does not match request run_input_id '$($request.run_input_id)'.")
                    }
                }
                if (Has-JsonProperty -Object $request -Name 'run_input_id') {
                    $summary['request_run_input_id'] = [string]$request.run_input_id
                }
            } catch {
                $failures.Add("RequestPath is not valid JSON: $($_.Exception.Message)")
            }
        }
    }

    $summary['response_sha256'] = Get-FileHashHex -Path $ResponseFile
    $summary['final_answer_char_count'] = if (Has-JsonProperty -Object $response -Name 'final_answer') { ([string]$response.final_answer).Length } else { 0 }
    $summary['transcript_message_count'] = if (Has-JsonProperty -Object $response -Name 'transcript_messages') { @(Get-JsonArray -Value $response.transcript_messages).Count } else { 0 }
    $summary['has_request_path'] = [bool]$RequestFile

    $info.Add('Scored empirical runner response contract.')
    $info.Add('No hosted model/API calls are made by this scorer.')
    $status = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
    return (New-Result -Status $status -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
}

function Assert-NegativeCase {
    param(
        [System.Collections.Generic.List[string]]$Failures,
        [string]$Name,
        [string]$ExpectedFailureText,
        [scriptblock]$Mutate,
        [string]$ResponseFile,
        [string]$RequestFile,
        [string]$SchemaFile
    )
    & $Mutate
    $result = Invoke-RunnerResponseValidation -ResponseFile $ResponseFile -RequestFile $RequestFile -SchemaFile $SchemaFile
    if ($result.status -eq 'pass') {
        $Failures.Add("Negative runner response case '$Name' unexpectedly passed.")
        return
    }
    if (($result.failures -join "`n") -notlike "*$ExpectedFailureText*") {
        $Failures.Add("Negative runner response case '$Name' failed for an unexpected reason: $($result.failures -join '; ')")
    }
}

function Invoke-SelfTest {
    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}
    $tempBase = Join-Path ([System.IO.Path]::GetTempPath()) ("adg-runner-response-scorer-selftest-" + [guid]::NewGuid().ToString())
    try {
        New-Item -ItemType Directory -Force -Path $tempBase | Out-Null
        $requestPath = Join-Path $tempBase 'request.json'
        $responsePath = Join-Path $tempBase 'response.json'
        $request = [ordered]@{
            run_input_id = 'task001-no_gate-r1'
            input_prompt = 'Public synthetic prompt for runner response scorer self-test.'
        }
        $goodResponse = [ordered]@{
            run_input_id = 'task001-no_gate-r1'
            final_answer = 'Fixture runner response for contract scoring. This is a contract fixture only.'
            final_claim = 'pilot_execution_output_unlabeled_no_empirical_claim'
            checked_evidence = @('runner request', 'public synthetic task prompt')
            selected_claim_ceiling = 'pilot_execution_transcripts_present_unlabeled_no_results'
            stop_or_continue_decision = 'continue_to_annotation_after_package_validation'
            human_checkpoint_decision = 'not_evaluated_by_fixture_runner'
            transcript_messages = @(
                [ordered]@{
                    role = 'assistant'
                    content = 'Fixture runner response for contract scoring.'
                }
            )
            tool_calls = @()
            input_tokens = 12
            output_tokens = 18
            wall_time_ms = 1
            api_cost_usd = 0
            retry_count = 0
        }
        Write-JsonFile -Path $requestPath -Value $request
        Write-JsonFile -Path $responsePath -Value $goodResponse
        $positive = Invoke-RunnerResponseValidation -ResponseFile $responsePath -RequestFile $requestPath -SchemaFile $SchemaPath
        if ($positive.status -ne 'pass') {
            $failures.Add("Positive runner response self-test failed: $($positive.failures -join '; ')")
        } else {
            $summary['final_answer_char_count'] = $positive.summary.final_answer_char_count
            $summary['transcript_message_count'] = $positive.summary.transcript_message_count
        }

        Assert-NegativeCase -Failures $failures -Name 'missing_final_answer' -ExpectedFailureText "missing required field 'final_answer'" -ResponseFile $responsePath -RequestFile $requestPath -SchemaFile $SchemaPath -Mutate {
            $bad = [ordered]@{
                checked_evidence = @('runner request')
            }
            Write-JsonFile -Path $responsePath -Value $bad
        }

        Assert-NegativeCase -Failures $failures -Name 'credential_like_content' -ExpectedFailureText 'blocked sensitive pattern' -ResponseFile $responsePath -RequestFile $requestPath -SchemaFile $SchemaPath -Mutate {
            $bad = [ordered]@{
                final_answer = ('Fixture output with ' + 'Bear' + 'er abcdefghijklmnopqrstuvwxyz token-like text.')
            }
            Write-JsonFile -Path $responsePath -Value $bad
        }

        Assert-NegativeCase -Failures $failures -Name 'forbidden_result_field' -ExpectedFailureText "forbidden field 'paper_ready'" -ResponseFile $responsePath -RequestFile $requestPath -SchemaFile $SchemaPath -Mutate {
            $bad = [ordered]@{
                final_answer = 'Fixture output.'
                paper_ready = $true
            }
            Write-JsonFile -Path $responsePath -Value $bad
        }

        $measurementPhraseResponse = [ordered]@{
            run_input_id = 'task001-no_gate-r1'
            final_answer = 'The draft is not paper ready because labels, metrics, and limitations are missing.'
            final_claim = 'paper_ready'
            checked_evidence = @('runner request', 'public synthetic task prompt')
            selected_claim_ceiling = 'natural_language_model_output_preserved_for_annotation'
            stop_or_continue_decision = 'continue_to_annotation_after_package_validation'
            human_checkpoint_decision = 'not_evaluated_by_fixture_runner'
            input_tokens = 12
            output_tokens = 18
            wall_time_ms = 1
            api_cost_usd = 0
            retry_count = 0
        }
        Write-JsonFile -Path $responsePath -Value $measurementPhraseResponse
        $measurementPhrase = Invoke-RunnerResponseValidation -ResponseFile $responsePath -RequestFile $requestPath -SchemaFile $SchemaPath
        if ($measurementPhrase.status -ne 'pass') {
            $failures.Add("Runner response should preserve natural-language readiness/result phrases for downstream annotation, but failed: $($measurementPhrase.failures -join '; ')")
        }

        Assert-NegativeCase -Failures $failures -Name 'negative_numeric_field' -ExpectedFailureText "field 'api_cost_usd' must be a finite nonnegative number" -ResponseFile $responsePath -RequestFile $requestPath -SchemaFile $SchemaPath -Mutate {
            $bad = [ordered]@{
                final_answer = 'Fixture output.'
                api_cost_usd = -0.01
            }
            Write-JsonFile -Path $responsePath -Value $bad
        }

        Assert-NegativeCase -Failures $failures -Name 'blank_numeric_field' -ExpectedFailureText "field 'api_cost_usd' must be numeric" -ResponseFile $responsePath -RequestFile $requestPath -SchemaFile $SchemaPath -Mutate {
            $bad = [ordered]@{
                final_answer = 'Fixture output.'
                api_cost_usd = ''
            }
            Write-JsonFile -Path $responsePath -Value $bad
        }

        Assert-NegativeCase -Failures $failures -Name 'null_numeric_field' -ExpectedFailureText "field 'api_cost_usd' must be numeric" -ResponseFile $responsePath -RequestFile $requestPath -SchemaFile $SchemaPath -Mutate {
            $bad = [ordered]@{
                final_answer = 'Fixture output.'
                api_cost_usd = $null
            }
            Write-JsonFile -Path $responsePath -Value $bad
        }

        Assert-NegativeCase -Failures $failures -Name 'boolean_numeric_field' -ExpectedFailureText "field 'api_cost_usd' must be numeric" -ResponseFile $responsePath -RequestFile $requestPath -SchemaFile $SchemaPath -Mutate {
            $bad = [ordered]@{
                final_answer = 'Fixture output.'
                api_cost_usd = $false
            }
            Write-JsonFile -Path $responsePath -Value $bad
        }

        Assert-NegativeCase -Failures $failures -Name 'request_run_input_mismatch' -ExpectedFailureText 'does not match request run_input_id' -ResponseFile $responsePath -RequestFile $requestPath -SchemaFile $SchemaPath -Mutate {
            $bad = [ordered]@{
                run_input_id = 'different-run-input'
                final_answer = 'Fixture output.'
            }
            Write-JsonFile -Path $responsePath -Value $bad
        }

        $info.Add('Validated runner response contract self-test.')
        $info.Add('Rejected missing final_answer, credential-like content, forbidden result/readiness fields, null, blank, boolean, or negative numeric fields, and request/run_input mismatches.')
        $info.Add('Preserved natural-language readiness/result phrases and final_claim values for downstream annotation instead of rejecting model behavior before measurement.')
        $info.Add('No hosted model/API calls are made by this scorer.')
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
    $result = Invoke-RunnerResponseValidation -ResponseFile $ResponsePath -RequestFile $RequestPath -SchemaFile $SchemaPath
}

if ($Json) {
    $result | ConvertTo-Json -Depth 20
} else {
    "Empirical runner response scoring: $($result.status)"
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
