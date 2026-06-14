<#
.SYNOPSIS
    One-step Symbian build + self-signed SIS packaging for on-device testing.
.DESCRIPTION
    Runs build-symbian.ps1 then package-symbian.ps1 with the same parameters,
    producing build-symbian/<arch>-<config>/Xyz_selfsigned.sis ready to transfer
    to the device (e.g. over Bluetooth). Stops if the build step fails.
.USAGE
    pwsh scripts/build-sis.ps1
    pwsh scripts/build-sis.ps1 -Config Release -Arch armv5 -Clean
    pwsh scripts/build-sis.ps1 -Force            # regenerate the self-signed cert
.NOTES
    Thin wrapper: build-symbian.ps1 / package-symbian.ps1 remain usable on their
    own. Each step runs in its own PowerShell process so its `exit` doesn't tear
    down this wrapper and its exit code is captured.
#>
param(
    [ValidateNotNullOrEmpty()][string]$QtSdkRoot = 'C:\Symbian\QtSDK',
    [string]$SymbianSdkRoot,
    [ValidateSet('Debug','Release')][string]$Config = 'Debug',
    [ValidateSet('armv5','armv6')][string]$Arch = 'armv5',
    # forwarded to build-symbian.ps1
    [string]$QmakePath,
    [string]$MakePath,
    [switch]$Clean,
    [switch]$VerboseMake,
    # forwarded to package-symbian.ps1
    [string]$CertPath,
    [string]$KeyPath,
    [string]$CertPassword = 'xyzpass',
    [string]$PkgTemplatePath,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info([string]$message) { Write-Host "[INFO] $message" -ForegroundColor Cyan }
function Write-Err([string]$message)  { Write-Host "[ERR ] $message" -ForegroundColor Red }

# Which wrapper params each child script understands.
$buildParamNames   = @('QtSdkRoot','SymbianSdkRoot','Config','Arch','QmakePath','MakePath','Clean','VerboseMake')
$packageParamNames = @('QtSdkRoot','SymbianSdkRoot','Config','Arch','CertPath','KeyPath','CertPassword','PkgTemplatePath','Force')

# Build a -Name value / -Name (switch) argument list from the params the caller
# actually passed. ($bound is the script's $PSBoundParameters, passed in because a
# function's own $PSBoundParameters would shadow it.)
function Get-ForwardArgs([string[]]$names, $bound) {
    $list = @()
    foreach ($name in $names) {
        if (-not $bound.ContainsKey($name)) { continue }
        $value = $bound[$name]
        if ($value -is [System.Management.Automation.SwitchParameter]) {
            if ($value.IsPresent) { $list += "-$name" }
        } else {
            $list += "-$name"
            $list += [string]$value
        }
    }
    return ,$list
}

try {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $buildScript   = Join-Path $scriptDir 'build-symbian.ps1'
    $packageScript = Join-Path $scriptDir 'package-symbian.ps1'
    foreach ($s in @($buildScript, $packageScript)) {
        if (-not (Test-Path -LiteralPath $s)) { throw ("Required script not found: {0}" -f $s) }
    }

    # Re-invoke with the same PowerShell host that is running this wrapper.
    $psExe = (Get-Process -Id $PID).Path
    if (-not $psExe) { $psExe = (Get-Command pwsh -ErrorAction SilentlyContinue).Source }
    if (-not $psExe) { $psExe = (Get-Command powershell -ErrorAction SilentlyContinue).Source }
    if (-not $psExe) { throw 'Could not resolve the PowerShell executable to run the sub-steps.' }

    Write-Info "=== Step 1/2: build-symbian ($Config / $Arch) ==="
    $buildArgs = @('-NoProfile','-File', $buildScript) + (Get-ForwardArgs $buildParamNames $PSBoundParameters)
    & $psExe @buildArgs
    if ($LASTEXITCODE -ne 0) { throw ("Build step failed (exit {0}); skipping packaging." -f $LASTEXITCODE) }

    Write-Info "=== Step 2/2: package-symbian ($Config / $Arch) ==="
    $packageArgs = @('-NoProfile','-File', $packageScript) + (Get-ForwardArgs $packageParamNames $PSBoundParameters)
    & $psExe @packageArgs
    if ($LASTEXITCODE -ne 0) { throw ("Packaging step failed (exit {0})." -f $LASTEXITCODE) }

    $repoRoot = (Resolve-Path (Join-Path $scriptDir '..')).Path
    $finalSis = Join-Path $repoRoot ("build-symbian\{0}-{1}\Xyz_selfsigned.sis" -f $Arch, $Config.ToLowerInvariant())
    Write-Host ""
    if (Test-Path -LiteralPath $finalSis) {
        Write-Info ("Done. Self-signed SIS ready: {0}" -f $finalSis)
        Write-Info "Transfer this .sis to the device (e.g. over Bluetooth) and install."
    } else {
        Write-Info ("Done, but expected SIS not found at {0} - check the packaging output above." -f $finalSis)
    }
}
catch {
    Write-Err $_.Exception.Message
    exit 1
}
