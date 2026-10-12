#Requires -Version 7.2
<#
.SYNOPSIS
    Lints the module and runs the tests.

.PARAMETER Integration
    Also run the integration tests. They create a real shadow copy of C:\ and an SMB
    share, so they need an elevated session and are meant for disposable machines (CI).
#>
[CmdletBinding()]
param(
    [switch] $Integration
)

$ErrorActionPreference = 'Stop'

foreach ($module in @{ Name = 'Pester'; MinimumVersion = '5.5.0' }, @{ Name = 'PSScriptAnalyzer'; MinimumVersion = '1.21.0' }) {
    if (-not (Get-Module -ListAvailable -Name $module.Name | Where-Object Version -GE $module.MinimumVersion)) {
        Install-Module @module -Scope CurrentUser -Force -SkipPublisherCheck
    }
}

$findings = Invoke-ScriptAnalyzer -Path (Join-Path $PSScriptRoot 'src') -Recurse -Settings (Join-Path $PSScriptRoot 'PSScriptAnalyzerSettings.psd1')
if ($findings) {
    $findings | Format-Table -AutoSize RuleName, ScriptName, Line, Message | Out-String -Width 200 | Write-Host
    throw "PSScriptAnalyzer reported $(@($findings).Count) issue(s)."
}

Import-Module Pester -MinimumVersion 5.5.0
$configuration = New-PesterConfiguration
$configuration.Run.Path = Join-Path $PSScriptRoot 'tests'
$configuration.Run.Exit = $true
$configuration.Output.Verbosity = 'Detailed'
$configuration.TestResult.Enabled = $true
$configuration.TestResult.OutputPath = Join-Path $PSScriptRoot 'testResults.xml'
if ($Integration) {
    $env:RR_INTEGRATION = '1'
}
else {
    $configuration.Filter.ExcludeTag = 'Integration'
}
Invoke-Pester -Configuration $configuration
