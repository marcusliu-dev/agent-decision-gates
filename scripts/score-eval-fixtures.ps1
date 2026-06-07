param(
    [string]$EvalDir = (Join-Path (Split-Path -Parent $PSScriptRoot) 'evals/consult'),
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

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

function Get-YamlList {
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

function Get-BlockScalar {
    param(
        [string]$Text,
        [string]$Field
    )
    $items = New-Object System.Collections.Generic.List[string]
    $lines = $Text -split "`r?`n"
    $inBlock = $false
    foreach ($line in $lines) {
        if ($line -match "^$([regex]::Escape($Field)):\s*[>|]\s*$") {
            $inBlock = $true
            continue
        }
        if ($inBlock) {
            if ($line -match '^\S') {
                break
            }
            $items.Add($line.Trim()) | Out-Null
        }
    }
    return ($items -join "`n").Trim()
}

$requiredIds = @(
    'consult-public-happy-path',
    'consult-public-must-counter-review',
    'consult-public-must-reclaim-thread-capacity-before-inline-fallback',
    'consult-public-nonlocal-route-forbidden',
    'consult-public-objective-narrowing-full-chain',
    'consult-public-verifier-overclaim',
    'consult-public-draft-artifact-not-completion',
    'consult-public-stale-tracker-conflict',
    'consult-public-approval-spoofing',
    'consult-public-prompt-injection-in-reviewed-file',
    'consult-public-multiturn-scope-creep',
    'consult-public-subtle-nonlocal-route-pressure',
    'consult-public-unsafe-thread-reclaim',
    'consult-public-parent-framing-conflict'
)

$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$info = New-Object System.Collections.Generic.List[string]

if (-not (Test-Path -LiteralPath $EvalDir)) {
    $failures.Add("Eval directory not found: $EvalDir")
} else {
    $files = @(Get-ChildItem -LiteralPath $EvalDir -Filter '*.yaml' -File | Sort-Object Name)
    if ($files.Count -eq 0) {
        $failures.Add("No eval YAML files found in $EvalDir.")
    }

    $seenIds = New-Object System.Collections.Generic.HashSet[string]
    foreach ($file in $files) {
        $text = Get-Content -LiteralPath $file.FullName -Raw
        $id = Get-Scalar -Text $text -Field 'id'
        $skill = Get-Scalar -Text $text -Field 'skill'
        $type = Get-Scalar -Text $text -Field 'type'
        $description = Get-Scalar -Text $text -Field 'description'
        $prompt = Get-BlockScalar -Text $text -Field 'prompt'

        foreach ($pair in @(
            @('id', $id),
            @('skill', $skill),
            @('type', $type),
            @('description', $description)
        )) {
            if (-not $pair[1]) {
                $failures.Add("$($file.Name) is missing $($pair[0]).")
            }
        }

        if ($id) {
            if (-not $seenIds.Add($id)) {
                $failures.Add("Duplicate eval id '$id'.")
            }
        }
        if ($skill -ne 'consult') {
            $failures.Add("$($file.Name) must use skill: consult.")
        }
        if ($type -notin @('golden', 'misuse', 'trajectory')) {
            $failures.Add("$($file.Name) has unsupported type '$type'.")
        }
        if (-not $prompt) {
            $failures.Add("$($file.Name) must include a nonempty prompt block.")
        } elseif ($prompt -notlike '*$consult*') {
            $failures.Add("$($file.Name) prompt must explicitly invoke `$consult.")
        }

        if ($type -in @('golden', 'misuse')) {
            foreach ($field in @('expected_behavior', 'pass_conditions', 'failure_conditions')) {
                if ((Get-YamlList -Text $text -Field $field).Count -eq 0) {
                    $failures.Add("$($file.Name) must include nonempty $field.")
                }
            }
        }
        if ($type -eq 'trajectory') {
            foreach ($field in @('trajectory_requirements', 'failure_conditions')) {
                if ((Get-YamlList -Text $text -Field $field).Count -eq 0) {
                    $failures.Add("$($file.Name) must include nonempty $field.")
                }
            }
            if ((Get-YamlList -Text $text -Field 'allowed_verification_examples').Count -eq 0) {
                $warnings.Add("$($file.Name) has no allowed_verification_examples.")
            }
        }
    }

    foreach ($requiredId in $requiredIds) {
        if (-not $seenIds.Contains($requiredId)) {
            $failures.Add("Missing required eval id '$requiredId'.")
        }
    }

    $info.Add("Scored $($files.Count) consult eval fixture(s).")
}

$status = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
$result = [ordered]@{
    status = $status
    failures = @($failures)
    warnings = @($warnings)
    info = @($info)
}

if ($Json) {
    $result | ConvertTo-Json -Depth 5
} else {
    "Consult eval fixture scoring: $status"
    ''
    'Failures:'
    if ($failures.Count -eq 0) { '  none' } else { $failures | ForEach-Object { "  - $_" } }
    ''
    'Warnings:'
    if ($warnings.Count -eq 0) { '  none' } else { $warnings | ForEach-Object { "  - $_" } }
    ''
    'Info:'
    if ($info.Count -eq 0) { '  none' } else { $info | ForEach-Object { "  - $_" } }
}

if ($failures.Count -gt 0) {
    exit 1
}
