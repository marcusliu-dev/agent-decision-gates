param(
    [string]$RunInputRoot,
    [string]$PreflightPath,
    [string]$RunnerScriptPath,
    [string]$RunnerLabel = 'local-runner-script',
    [string[]]$RequiredEnvVarName = @(),
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
    $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-FileHashHex {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-EnvironmentVariableName {
    param([string]$Name)
    return ([string]$Name) -match '^[A-Z][A-Z0-9_]{1,63}$'
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

function Test-IsPathInsideRoot {
    param(
        [string]$ChildPath,
        [string]$RootPath
    )
    $resolvedChild = (Resolve-Path -LiteralPath $ChildPath).Path
    $resolvedRoot = (Resolve-Path -LiteralPath $RootPath).Path.TrimEnd('\', '/')
    if ($resolvedChild.Equals($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    $prefix = $resolvedRoot + [System.IO.Path]::DirectorySeparatorChar
    return $resolvedChild.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Invoke-ReadinessCheck {
    param(
        [string]$InputRoot,
        [string]$PreflightFile,
        [string]$ScriptPath,
        [string]$ScriptLabel,
        [string[]]$RequiredEnvNames,
        [string]$RepositoryRoot
    )

    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}

    foreach ($requiredPath in @(
        (Join-Path $RepositoryRoot 'evals/empirical/pilot-execution-readiness-schema.yaml'),
        (Join-Path $RepositoryRoot 'docs/empirical-pilot-execution-readiness.md'),
        (Join-Path $RepositoryRoot 'scripts/score-empirical-run-inputs.ps1'),
        (Join-Path $RepositoryRoot 'scripts/score-empirical-execution-preflight.ps1'),
        (Join-Path $RepositoryRoot 'scripts/build-empirical-pilot-execution-package.ps1'),
        (Join-Path $RepositoryRoot 'scripts/score-empirical-pilot-execution-package.ps1')
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            $failures.Add("Missing repository artifact required for pilot execution readiness: $requiredPath")
        }
    }

    foreach ($pathEntry in @($InputRoot, $PreflightFile, $ScriptPath)) {
        if (-not $pathEntry -or -not (Test-Path -LiteralPath $pathEntry)) {
            $failures.Add("Missing required pilot execution readiness input: $pathEntry")
        }
    }
    if ([string]::IsNullOrWhiteSpace($ScriptLabel) -or $ScriptLabel -match '[\\/:]') {
        $failures.Add('RunnerLabel must be nonblank and contain no path separators.')
    }

    if ($failures.Count -eq 0) {
        $runnerItem = Get-Item -LiteralPath $ScriptPath
        if ($runnerItem.PSIsContainer) {
            $failures.Add('RunnerScriptPath must point to a file, not a directory.')
        } elseif (Test-IsPathInsideRoot -ChildPath $ScriptPath -RootPath $RepositoryRoot) {
            $failures.Add('RunnerScriptPath must stay outside the public repository for readiness checks.')
        } else {
            $summary['runner_script_sha256'] = Get-FileHashHex -Path $ScriptPath
        }
    }

    $envNames = @($RequiredEnvNames | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    $summary['required_env_var_count'] = $envNames.Count
    $presentEnvNames = New-Object System.Collections.Generic.List[string]
    if ($envNames.Count -eq 0) {
        $failures.Add('At least one required environment variable name must be provided for pilot execution readiness.')
    }
    foreach ($envName in $envNames) {
        if (-not (Test-EnvironmentVariableName -Name $envName)) {
            $failures.Add("Invalid required environment variable name '$envName'.")
            continue
        }
        $value = [Environment]::GetEnvironmentVariable($envName, 'Process')
        if ([string]::IsNullOrWhiteSpace($value)) {
            $failures.Add("Required environment variable '$envName' is not set for this process.")
        } else {
            $presentEnvNames.Add($envName) | Out-Null
        }
    }
    $summary['present_required_env_var_count'] = $presentEnvNames.Count
    $summary['checked_required_env_var_names'] = @($envNames)

    if ($failures.Count -eq 0) {
        try {
            $runInputScorer = Join-Path $RepositoryRoot 'scripts/score-empirical-run-inputs.ps1'
            $runInputOutput = & $runInputScorer -PackageRoot $InputRoot -RepoRoot $RepositoryRoot -Json 2>&1
            $runInputResult = Convert-JsonToolOutput -ScriptName 'score-empirical-run-inputs.ps1' -Output $runInputOutput -InvocationSucceeded $?
            $summary['run_input_score_status'] = [string]$runInputResult.status
        } catch {
            $failures.Add($_.Exception.Message)
        }
    }

    if ($failures.Count -eq 0) {
        try {
            $preflightScorer = Join-Path $RepositoryRoot 'scripts/score-empirical-execution-preflight.ps1'
            $preflightOutput = & $preflightScorer -RunInputRoot $InputRoot -PreflightPath $PreflightFile -RepoRoot $RepositoryRoot -Json 2>&1
            $preflightResult = Convert-JsonToolOutput -ScriptName 'score-empirical-execution-preflight.ps1' -Output $preflightOutput -InvocationSucceeded $?
            $summary['preflight_score_status'] = [string]$preflightResult.status
            $summary['preflight_sha256'] = Get-FileHashHex -Path $PreflightFile
        } catch {
            $failures.Add($_.Exception.Message)
        }
    }

    $info.Add('Checked empirical pilot execution readiness without executing the runner.')
    $info.Add('Environment variable values were not printed or written.')
    $info.Add('No model/API calls were made by this readiness checker.')

    $status = if ($failures.Count -eq 0) { 'pass' } else { 'fail' }
    return (New-Result -Status $status -Failures $failures -Warnings $warnings -Info $info -Summary $summary)
}

function Assert-NegativeCase {
    param(
        [System.Collections.Generic.List[string]]$Failures,
        [string]$Name,
        [string]$ExpectedFailureText,
        [scriptblock]$Run
    )
    $result = & $Run
    if ($result.status -eq 'pass') {
        $Failures.Add("Negative readiness case '$Name' unexpectedly passed.")
        return
    }
    $failureText = ($result.failures -join "`n")
    if ($failureText -notlike "*$ExpectedFailureText*") {
        $Failures.Add("Negative readiness case '$Name' failed, but not for expected text '$ExpectedFailureText'.")
    }
}

function Invoke-SelfTest {
    $failures = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $info = New-Object System.Collections.Generic.List[string]
    $summary = @{}
    $tempBase = Join-Path ([System.IO.Path]::GetTempPath()) ("adg-pilot-readiness-selftest-" + [guid]::NewGuid().ToString())
    $envName = 'ADG_REQUIRED_ENV_PRESENT'
    $oldEnvValue = [Environment]::GetEnvironmentVariable($envName, 'Process')
    try {
        New-Item -ItemType Directory -Force -Path $tempBase | Out-Null
        $runInputRoot = Join-Path $tempBase 'run-inputs'
        $preflightPath = Join-Path $tempBase 'execution-preflight.json'
        $runnerPath = Join-Path $tempBase 'fixture-runner.ps1'
        @'
param(
    [string]$RequestPath,
    [string]$ResponsePath
)
throw 'Self-test readiness checker must not execute this runner.'
'@ | Set-Content -LiteralPath $runnerPath -Encoding UTF8

        $runInputBuilder = Join-Path $RepoRoot 'scripts/build-empirical-run-inputs.ps1'
        $preflightBuilder = Join-Path $RepoRoot 'scripts/build-empirical-execution-preflight.ps1'
        $runInputOutput = & $runInputBuilder -OutputRoot $runInputRoot -Json 2>&1
        Convert-JsonToolOutput -ScriptName 'build-empirical-run-inputs.ps1' -Output $runInputOutput -InvocationSucceeded $? | Out-Null
        $preflightOutput = & $preflightBuilder -RunInputRoot $runInputRoot -OutputPath $preflightPath -Provider 'selftest-provider' -ModelNameOrAlias 'selftest-model' -RuntimeSurface 'selftest-local-runner' -MaxBudgetUsd 1.0 -Force -Json 2>&1
        Convert-JsonToolOutput -ScriptName 'build-empirical-execution-preflight.ps1' -Output $preflightOutput -InvocationSucceeded $? | Out-Null

        [Environment]::SetEnvironmentVariable($envName, 'present', 'Process')
        $positive = Invoke-ReadinessCheck -InputRoot $runInputRoot -PreflightFile $preflightPath -ScriptPath $runnerPath -ScriptLabel 'fixture-runner-v0' -RequiredEnvNames @($envName) -RepositoryRoot $RepoRoot
        if ($positive.status -ne 'pass') {
            $failures.Add("Positive readiness self-test failed: $($positive.failures -join '; ')")
        } else {
            $summary['required_env_var_count'] = $positive.summary.required_env_var_count
            $summary['present_required_env_var_count'] = $positive.summary.present_required_env_var_count
        }

        Assert-NegativeCase -Failures $failures -Name 'missing_required_env' -ExpectedFailureText 'is not set' -Run {
            Invoke-ReadinessCheck -InputRoot $runInputRoot -PreflightFile $preflightPath -ScriptPath $runnerPath -ScriptLabel 'fixture-runner-v0' -RequiredEnvNames @('ADG_REQUIRED_ENV_MISSING') -RepositoryRoot $RepoRoot
        }
        Assert-NegativeCase -Failures $failures -Name 'empty_required_env_names' -ExpectedFailureText 'At least one required environment variable name' -Run {
            Invoke-ReadinessCheck -InputRoot $runInputRoot -PreflightFile $preflightPath -ScriptPath $runnerPath -ScriptLabel 'fixture-runner-v0' -RequiredEnvNames @() -RepositoryRoot $RepoRoot
        }
        Assert-NegativeCase -Failures $failures -Name 'invalid_required_env_name' -ExpectedFailureText 'Invalid required environment variable name' -Run {
            Invoke-ReadinessCheck -InputRoot $runInputRoot -PreflightFile $preflightPath -ScriptPath $runnerPath -ScriptLabel 'fixture-runner-v0' -RequiredEnvNames @('bad-name') -RepositoryRoot $RepoRoot
        }
        Assert-NegativeCase -Failures $failures -Name 'repo_local_runner' -ExpectedFailureText 'must stay outside the public repository' -Run {
            Invoke-ReadinessCheck -InputRoot $runInputRoot -PreflightFile $preflightPath -ScriptPath (Join-Path $RepoRoot 'scripts/check-empirical-pilot-execution-readiness.ps1') -ScriptLabel 'fixture-runner-v0' -RequiredEnvNames @($envName) -RepositoryRoot $RepoRoot
        }
        Assert-NegativeCase -Failures $failures -Name 'bad_runner_label' -ExpectedFailureText 'RunnerLabel must be nonblank' -Run {
            Invoke-ReadinessCheck -InputRoot $runInputRoot -PreflightFile $preflightPath -ScriptPath $runnerPath -ScriptLabel 'bad/label' -RequiredEnvNames @($envName) -RepositoryRoot $RepoRoot
        }

        $info.Add('Validated empirical pilot execution readiness self-test.')
        $info.Add('Rejected missing required environment variable lists, missing required environment variables, invalid environment variable names, repo-local runner scripts, and bad runner labels.')
        $info.Add('Did not execute the fixture runner or call model/API routes.')
    } finally {
        if ($null -eq $oldEnvValue) {
            [Environment]::SetEnvironmentVariable($envName, $null, 'Process')
        } else {
            [Environment]::SetEnvironmentVariable($envName, $oldEnvValue, 'Process')
        }
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
    if (-not $RunInputRoot -or -not $PreflightPath -or -not $RunnerScriptPath) {
        $failures = New-Object System.Collections.Generic.List[string]
        $warnings = New-Object System.Collections.Generic.List[string]
        $info = New-Object System.Collections.Generic.List[string]
        $summary = @{}
        $failures.Add('Provide -RunInputRoot, -PreflightPath, and -RunnerScriptPath, or use -SelfTest.')
        $result = New-Result -Status 'fail' -Failures $failures -Warnings $warnings -Info $info -Summary $summary
    } else {
        $result = Invoke-ReadinessCheck -InputRoot $RunInputRoot -PreflightFile $PreflightPath -ScriptPath $RunnerScriptPath -ScriptLabel $RunnerLabel -RequiredEnvNames $RequiredEnvVarName -RepositoryRoot $RepoRoot
    }
}

if ($Json) {
    $result | ConvertTo-Json -Depth 20
} else {
    "Empirical pilot execution readiness: $($result.status)"
    if ($result.failures.Count -gt 0) {
        ''
        'Failures:'
        $result.failures | ForEach-Object { "  - $_" }
    }
    if ($result.warnings.Count -gt 0) {
        ''
        'Warnings:'
        $result.warnings | ForEach-Object { "  - $_" }
    }
    if ($result.info.Count -gt 0) {
        ''
        'Info:'
        $result.info | ForEach-Object { "  - $_" }
    }
}

if ($result.status -ne 'pass') {
    exit 1
}
