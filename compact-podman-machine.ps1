#Requires -Version 5.1

<#
.SYNOPSIS
Stops Podman and WSL, compacts a Podman machine VHDX, and starts the machine.

.DESCRIPTION
Run this script from an elevated Windows PowerShell session. The VHDX is found
from the machine's WSL registration; -VhdPath is available as an override.

.EXAMPLE
.\compact-podman-machine.ps1

.EXAMPLE
.\compact-podman-machine.ps1 -MachineName podman-machine-default
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$MachineName = 'podman-machine-default',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$VhdPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $administrator = [Security.Principal.WindowsBuiltInRole]::Administrator

    if (-not $principal.IsInRole($administrator)) {
        throw 'VHDX compaction requires an elevated PowerShell session. Open PowerShell as Administrator and run this script again.'
    }
}

function Assert-Command {
    param([Parameter(Mandatory)][string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found."
    }
}

function Resolve-PodmanVhdPath {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$ExplicitPath
    )

    if ($ExplicitPath) {
        $resolved = Resolve-Path -LiteralPath $ExplicitPath -ErrorAction Stop
        return $resolved.ProviderPath
    }

    $candidates = [System.Collections.Generic.List[string]]::new()
    $lxssKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'

    if (Test-Path -LiteralPath $lxssKey) {
        Get-ChildItem -LiteralPath $lxssKey | ForEach-Object {
            $distro = Get-ItemProperty -LiteralPath $_.PSPath
            if ($distro.DistributionName -eq $Name -and $distro.BasePath) {
                $basePath = [string]$distro.BasePath
                if ($basePath.StartsWith('\\?\')) {
                    $basePath = $basePath.Substring(4)
                }
                $candidates.Add((Join-Path $basePath 'ext4.vhdx'))
            }
        }
    }

    $candidates.Add((Join-Path $env:USERPROFILE ".local\share\containers\podman\machine\wsl\wsldist\$Name\ext4.vhdx"))
    $candidates.Add((Join-Path $env:LOCALAPPDATA "containers\podman\machine\wsl\wsldist\$Name\ext4.vhdx"))

    $matches = @($candidates | Select-Object -Unique | Where-Object { Test-Path -LiteralPath $_ })
    if ($matches.Count -eq 0) {
        throw "Could not locate the VHDX for '$Name'. Supply its path with -VhdPath."
    }
    if ($matches.Count -gt 1) {
        throw "Found multiple possible VHDX files for '$Name'. Supply the intended one with -VhdPath: $($matches -join ', ')"
    }

    return (Resolve-Path -LiteralPath $matches[0]).ProviderPath
}

function Wait-VhdDetached {
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$TimeoutSeconds = 30
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        try {
            $stream = [System.IO.File]::Open(
                $Path,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None
            )
            $stream.Dispose()
            return
        }
        catch [System.IO.IOException] {
            Start-Sleep -Milliseconds 500
        }
    } while ([DateTime]::UtcNow -lt $deadline)

    throw "The VHDX is still in use after $TimeoutSeconds seconds: $Path"
}

function Invoke-VhdCompaction {
    param([Parameter(Mandatory)][string]$Path)

    $diskpartScript = New-TemporaryFile
    try {
        @(
            "select vdisk file=`"$Path`""
            'compact vdisk'
            'exit'
        ) | Set-Content -LiteralPath $diskpartScript.FullName -Encoding ASCII

        & diskpart.exe /s $diskpartScript.FullName
        if ($LASTEXITCODE -ne 0) {
            throw "DiskPart failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Remove-Item -LiteralPath $diskpartScript.FullName -Force -ErrorAction SilentlyContinue
    }
}

Assert-Administrator
Assert-Command podman
Assert-Command wsl.exe
Assert-Command diskpart.exe

# Inspect before stopping anything so a bad machine name fails without disruption.
$machine = @(podman machine inspect $MachineName | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0 -or $machine.Count -ne 1) {
    throw "Unable to inspect Podman machine '$MachineName'."
}

$resolvedVhdPath = Resolve-PodmanVhdPath -Name $MachineName -ExplicitPath $VhdPath
$beforeBytes = (Get-Item -LiteralPath $resolvedVhdPath).Length
$restartRequired = $false
$operationError = $null

Write-Host "Podman machine: $MachineName"
Write-Host "VHDX: $resolvedVhdPath"
Write-Host ('Size before: {0:N2} GiB' -f ($beforeBytes / 1GB))

try {
    Write-Host 'Stopping the Podman machine...'
    # Once shutdown work begins, always attempt the requested final start.
    $restartRequired = $true
    if ($machine[0].State -ne 'stopped') {
        & podman machine stop $MachineName
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to stop Podman machine '$MachineName' (exit code $LASTEXITCODE)."
        }
    }

    Write-Host 'Shutting down WSL...'
    & wsl.exe --shutdown
    if ($LASTEXITCODE -ne 0) {
        throw "WSL shutdown failed with exit code $LASTEXITCODE."
    }

    Write-Host 'Waiting for the VHDX to detach...'
    Wait-VhdDetached -Path $resolvedVhdPath

    Write-Host 'Compacting the VHDX...'
    Invoke-VhdCompaction -Path $resolvedVhdPath
}
catch {
    $operationError = $_
}

$restartError = $null
if ($restartRequired) {
    try {
        Write-Host 'Starting the Podman machine...'
        & podman machine start $MachineName
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to start Podman machine '$MachineName' (exit code $LASTEXITCODE)."
        }
    }
    catch {
        $restartError = $_
    }
}

if ($operationError) {
    if ($restartError) {
        Write-Error "The restart also failed: $($restartError.Exception.Message)" -ErrorAction Continue
    }
    throw $operationError
}
if ($restartError) {
    throw $restartError
}

$afterBytes = (Get-Item -LiteralPath $resolvedVhdPath).Length
$reclaimedBytes = [Math]::Max(0, $beforeBytes - $afterBytes)
Write-Host ('Size after:  {0:N2} GiB' -f ($afterBytes / 1GB))
Write-Host ('Reclaimed:   {0:N2} GiB' -f ($reclaimedBytes / 1GB))
Write-Host 'Podman machine compaction completed successfully.'
