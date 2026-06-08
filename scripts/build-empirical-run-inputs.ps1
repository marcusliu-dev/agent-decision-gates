param(
    [string]$OutputRoot,
    [switch]$SelfTest,
    [switch]$Force,
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
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-FileHashHex {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
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

function Split-YamlEntries {
    param(
        [string[]]$Lines,
        [string]$StartPattern
    )
    $entries = New-Object System.Collections.Generic.List[object]
    $current = $null
    foreach ($line in $Lines) {
        if ($line -match $StartPattern) {
            if ($null -ne $current) {
                $entries.Add($current) | Out-Null
            }
            $current = New-Object System.Collections.Generic.List[string]
        }
        if ($null -ne $current) {
            $current.Add($line) | Out-Null
        }
    }
    if ($null -ne $current) {
        $entries.Add($current) | Out-Null
    }
    return @($entries | ForEach-Object { ,@($_.ToArray()) })
}

function Get-EntryScalar {
    param(
        [string[]]$EntryLines,
        [string]$Field
    )
    $pattern = "^\s+(?:-\s+)?$([regex]::Escape($Field)):\s*(.+?)\s*$"
    foreach ($line in $EntryLines) {
        if ($line -match $pattern) {
            return $Matches[1].Trim()
        }
    }
    return $null
}

function Get-EntryList {
    param(
        [string[]]$EntryLines,
        [string]$Field
    )
    $items = New-Object System.Collections.Generic.List[string]
    $inList = $false
    foreach ($line in $EntryLines) {
        if ($line -match "^\s+$([regex]::Escape($Field)):\s*$") {
            $inList = $true
            continue
        }
        if ($inList) {
            if ($line -match '^\s{4}\S' -and $line -notmatch '^\s{6}-\s+') {
                break
            }
            if ($line -match '^\s{6}-\s*(.+?)\s*$') {
                $items.Add($Matches[1].Trim()) | Out-Null
            }
        }
    }
    return @($items)
}

function Get-EntryBlock {
    param(
        [string[]]$EntryLines,
        [string]$Field
    )
    $items = New-Object System.Collections.Generic.List[string]
    $inBlock = $false
    foreach ($line in $EntryLines) {
        if ($line -match "^\s+$([regex]::Escape($Field)):\s*\|\s*$") {
            $inBlock = $true
            continue
        }
        if ($inBlock) {
            if ($line -match '^\s{4}\S') {
                break
            }
            if ($line -match '^\s{6}(.*)$') {
                $items.Add($Matches[1]) | Out-Null
            } elseif ($line.Trim().Length -eq 0) {
                $items.Add('') | Out-Null
            }
        }
    }
    return ($items -join "`n").Trim()
}

function Get-TaskDefinitions {
    param([string]$Path)
    $lines = Get-Content -LiteralPath $Path
    $entries = Split-YamlEntries -Lines $lines -StartPattern '^\s{2}-\s+id:\s*'
    return @($entries | ForEach-Object {
        [ordered]@{
            id = Get-EntryScalar -EntryLines $_ -Field 'id'
            family = Get-EntryScalar -EntryLines $_ -Field 'family'
            prompt = Get-EntryBlock -EntryLines $_ -Field 'prompt'
            expected_failure_modes = Get-EntryList -EntryLines $_ -Field 'expected_failure_modes'
            required_conditions = Get-EntryList -EntryLines $_ -Field 'required_conditions'
            forbidden_claims = Get-EntryList -EntryLines $_ -Field 'forbidden_claims'
        }
    })
}

function Get-ConditionPrompts {
    param([string]$Path)
    $lines = Get-Content -LiteralPath $Path
    $entries = Split-YamlEntries -Lines $lines -StartPattern '^\s{2}-\s+condition:\s*'
    return @($entries | ForEach-Object {
        [ordered]@{
            condition = Get-EntryScalar -EntryLines $_ -Field 'condition'
            prompt_version = Get-EntryScalar -EntryLines $_ -Field 'prompt_version'
            instruction = Get-EntryBlock -EntryLines $_ -Field 'instruction'
            expected_controls = Get-EntryList -EntryLines $_ -Field 'expected_controls'
        }
    })
}

function ConvertTo-SafeFileName {
    param([string]$Value)
    return ([regex]::Replace($Value, '[^a-zA-Z0-9_.-]', '-')).ToLowerInvariant()
}

function Assert-OutputRootWritable {
    param(
        [string]$Root,
        [bool]$AllowOverwrite
    )
    $resolvedParent = Split-Path -Parent $Root
    if ($resolvedParent -and -not (Test-Path -LiteralPath $resolvedParent)) {
        New-Item -ItemType Directory -Force -Path $resolvedParent | Out-Null
    }
    if (-not (Test-Path -LiteralPath $Root)) {
        return
    }
    $children = @(Get-ChildItem -LiteralPath $Root -Force)
    if ($children.Count -eq 0) {
        return
    }
    if (-not $AllowOverwrite) {
        throw 'OutputRoot already exists and is not empty. Use an empty directory or pass -Force to replace a generated run-input package.'
    }
    $unexpected = @(Get-ChildItem -LiteralPath $Root -Force | Where-Object { $_.Name -notin @('run-inputs', 'metadata') })
    if ($unexpected.Count -gt 0) {
        throw 'Refusing to overwrite OutputRoot because it contains files outside the run-input package directories.'
    }
    Remove-Item -LiteralPath (Join-Path $Root 'run-inputs') -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $Root 'metadata') -Recurse -Force -ErrorAction SilentlyContinue
}

function New-InputPrompt {
    param(
        [hashtable]$Task,
        [hashtable]$Condition,
        [string[]]$OutputFields
    )
    return @"
Task id: $($Task.id)
Task family: $($Task.family)

Task prompt:
$($Task.prompt)

Condition: $($Condition.condition)
Prompt version: $($Condition.prompt_version)

Condition instruction:
$($Condition.instruction)

Measurement output fields:
$($OutputFields -join ', ')

Privacy boundary:
Use only public synthetic or redacted fixtures. Do not include private paths, credentials, or unpublished private documents.
"@.Trim()
}

function New-RunInputPackage {
    param(
        [string]$Root,
        [bool]$AllowOverwrite
    )
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $taskSuitePath = Join-Path $repoRoot 'evals/empirical/agent-decision-gates-task-suite.yaml'
    $promptPackPath = Join-Path $repoRoot 'evals/empirical/condition-prompt-pack.yaml'
    $manifestPath = Join-Path $repoRoot 'evals/empirical/experiment-run-manifest.yaml'

    $taskSuiteText = Get-Content -LiteralPath $taskSuitePath -Raw
    $promptPackText = Get-Content -LiteralPath $promptPackPath -Raw
    $manifestText = Get-Content -LiteralPath $manifestPath -Raw

    $taskSuiteVersion = Get-Scalar -Text $taskSuiteText -Field 'version'
    $promptPackVersion = Get-Scalar -Text $promptPackText -Field 'prompt_pack_version'
    $manifestVersion = Get-Scalar -Text $manifestText -Field 'version'
    $repeatCount = [int](Get-Scalar -Text $manifestText -Field 'planned_repeats_per_task_condition')
    $manifestConditions = Get-TopLevelList -Text $manifestText -Field 'conditions'
    $outputFields = Get-TopLevelList -Text $promptPackText -Field 'required_record_fields'
    $privacyBoundary = @(
        'public_synthetic_task_suite_only',
        'no_private_paths',
        'no_credentials',
        'no_unpublished_private_documents'
    )

    $tasks = Get-TaskDefinitions -Path $taskSuitePath
    $conditions = Get-ConditionPrompts -Path $promptPackPath
    $conditionMap = @{}
    foreach ($condition in $conditions) {
        $conditionMap[$condition.condition] = $condition
    }

    if ($tasks.Count -eq 0) {
        throw 'No task definitions were parsed from the task suite.'
    }
    if ($conditions.Count -ne $manifestConditions.Count) {
        throw "Condition prompt count $($conditions.Count) does not match manifest condition count $($manifestConditions.Count)."
    }
    foreach ($conditionName in $manifestConditions) {
        if (-not $conditionMap.ContainsKey($conditionName)) {
            throw "Condition prompt pack is missing manifest condition '$conditionName'."
        }
    }

    Assert-OutputRootWritable -Root $Root -AllowOverwrite $AllowOverwrite
    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'run-inputs') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'metadata') | Out-Null

    $taskSuiteHash = Get-FileHashHex -Path $taskSuitePath
    $promptPackHash = Get-FileHashHex -Path $promptPackPath
    $manifestHash = Get-FileHashHex -Path $manifestPath
    $recordCount = 0

    foreach ($task in $tasks) {
        foreach ($conditionName in $manifestConditions) {
            $condition = $conditionMap[$conditionName]
            for ($repeat = 1; $repeat -le $repeatCount; $repeat++) {
                $runInputId = "ri-$((ConvertTo-SafeFileName -Value $task.id))-$((ConvertTo-SafeFileName -Value $conditionName))-r$repeat"
                $record = [ordered]@{
                    run_input_id = $runInputId
                    task_id = $task.id
                    condition = $conditionName
                    repeat_index = $repeat
                    task_suite_version = $taskSuiteVersion
                    prompt_pack_version = $promptPackVersion
                    manifest_version = $manifestVersion
                    task_family = $task.family
                    task_prompt = $task.prompt
                    condition_instruction = $condition.instruction
                    input_prompt = New-InputPrompt -Task $task -Condition $condition -OutputFields $outputFields
                    expected_failure_modes = @($task.expected_failure_modes)
                    required_conditions = @($task.required_conditions)
                    forbidden_claims = @($task.forbidden_claims)
                    output_record_fields = @($outputFields)
                    privacy_boundary = @($privacyBoundary)
                    task_suite_sha256 = $taskSuiteHash
                    prompt_pack_sha256 = $promptPackHash
                    manifest_sha256 = $manifestHash
                    redaction_status = 'public_synthetic_no_private_material'
                }
                Write-JsonFile -Path (Join-Path $Root "run-inputs/$runInputId.json") -Value $record
                $recordCount++
            }
        }
    }

    Write-JsonFile -Path (Join-Path $Root 'metadata/run-input-manifest.json') -Value ([ordered]@{
        builder = 'build-empirical-run-inputs.ps1'
        builder_version = $BuilderVersion
        claim_boundary = 'run_input_package_only_no_model_api_execution'
        generated_record_count = $recordCount
        task_count = $tasks.Count
        condition_count = $manifestConditions.Count
        repeat_count = $repeatCount
        task_suite_version = $taskSuiteVersion
        prompt_pack_version = $promptPackVersion
        manifest_version = $manifestVersion
        current_nonclaims = @(
            'no_model_api_eval_execution',
            'no_transcripts',
            'no_annotations',
            'no_cost_latency_results',
            'no_human_llm_judge_agreement_results',
            'no_empirical_results',
            'no_paper_readiness'
        )
    })
    Write-JsonFile -Path (Join-Path $Root 'metadata/task-suite-hash.json') -Value ([ordered]@{ algorithm = 'sha256'; path = 'evals/empirical/agent-decision-gates-task-suite.yaml'; value = $taskSuiteHash })
    Write-JsonFile -Path (Join-Path $Root 'metadata/prompt-pack-hash.json') -Value ([ordered]@{ algorithm = 'sha256'; path = 'evals/empirical/condition-prompt-pack.yaml'; value = $promptPackHash })
    Write-JsonFile -Path (Join-Path $Root 'metadata/experiment-manifest-hash.json') -Value ([ordered]@{ algorithm = 'sha256'; path = 'evals/empirical/experiment-run-manifest.yaml'; value = $manifestHash })
    Write-JsonFile -Path (Join-Path $Root 'metadata/builder-version.json') -Value ([ordered]@{ builder = 'build-empirical-run-inputs.ps1'; builder_version = $BuilderVersion })

    return [ordered]@{
        record_count = $recordCount
        task_count = $tasks.Count
        condition_count = $manifestConditions.Count
        repeat_count = $repeatCount
        task_suite_hash = $taskSuiteHash
        prompt_pack_hash = $promptPackHash
        manifest_hash = $manifestHash
    }
}

function Invoke-SelfTest {
    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}
    $tempBase = Join-Path ([System.IO.Path]::GetTempPath()) ("adg-run-input-builder-selftest-" + [guid]::NewGuid().ToString())
    try {
        $summary = New-RunInputPackage -Root $tempBase -AllowOverwrite $false
        if ([int]$summary.record_count -ne 324) {
            $failures.Add("Expected 324 run-input records; found $($summary.record_count).")
        }
        if ([int]$summary.task_count -ne 12) {
            $failures.Add("Expected 12 tasks; found $($summary.task_count).")
        }
        if ([int]$summary.condition_count -ne 9) {
            $failures.Add("Expected 9 conditions; found $($summary.condition_count).")
        }
        if ([int]$summary.repeat_count -ne 3) {
            $failures.Add("Expected 3 repeats; found $($summary.repeat_count).")
        }
        $allJson = (Get-ChildItem -LiteralPath $tempBase -Recurse -File -Filter '*.json' | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
        foreach ($forbidden in @('paper_ready', 'production_ready', 'empirical_effectiveness_proven')) {
            if ([regex]::IsMatch($allJson, "(?m)^\s*`"$([regex]::Escape($forbidden))`"\s*:")) {
                $failures.Add("Generated run-input package contains result field '$forbidden'.")
            }
        }
        $info.Add('Generated a 324-record run-input package from the public task suite and condition prompt pack.')
        $info.Add('Recorded task-suite, prompt-pack, and manifest SHA256 hashes.')
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
    if (-not $OutputRoot) {
        $failures.Add('Provide -OutputRoot to build a run-input package or -SelfTest for the builder self-test.')
    } else {
        try {
            $summary = New-RunInputPackage -Root $OutputRoot -AllowOverwrite ([bool]$Force)
            $info.Add('Generated empirical run-input package at the requested OutputRoot.')
        } catch {
            $failures.Add($_.Exception.Message)
        }
    }
    $status = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
    $result = New-Result -Status $status -Failures $failures -Warnings $warnings -Info $info -Summary $summary
}

if ($Json) {
    $result | ConvertTo-Json -Depth 20
} else {
    "Empirical run-input builder: $($result.status)"
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
