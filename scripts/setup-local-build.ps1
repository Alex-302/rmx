# Sets up the portable build environment for rmx.
#
# All toolchains live in one shared folder (override the root with RMX_TOOLS_ROOT):
#   <root>\BuildTools      - MSVC + Windows SDK, installed by PortableBuildTools
#   <root>\Rust\rustup     - RUSTUP_HOME (toolchains)
#   <root>\Rust\cargo      - CARGO_HOME (cargo, registry and git caches)
#
# Nothing is written to the system: no admin rights, no registry, no %USERPROFILE%.
#
# Usage:
#   pwsh -File .\scripts\setup-local-build.ps1
#
# After it finishes:
#   . .\scripts\dev-env.ps1
#   cargo check

$ErrorActionPreference = 'Stop'

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$toolsRoot = if ($env:RMX_TOOLS_ROOT) { $env:RMX_TOOLS_ROOT } else { 'C:\Work\Dev' }
New-Item -ItemType Directory -Force -Path $toolsRoot | Out-Null

# --- MSVC + Windows SDK -----------------------------------------------------

$msvcCandidates = @(
    $env:RMX_MSVC_DIR,
    (Join-Path $toolsRoot 'BuildTools')
)
$msvcDir = $msvcCandidates | Where-Object { $_ -and (Test-Path (Join-Path $_ 'devcmd.ps1')) } | Select-Object -First 1

if ($msvcDir) {
    Write-Host "MSVC: already installed at $msvcDir"
} else {
    $msvcDir = $env:RMX_MSVC_DIR
    if (-not $msvcDir) { $msvcDir = Join-Path $toolsRoot 'BuildTools' }

    $pbtExe = Join-Path $toolsRoot 'PortableBuildTools.exe'
    if (-not (Test-Path $pbtExe)) {
        Write-Host 'MSVC: downloading PortableBuildTools...'
        Invoke-WebRequest -Uri 'https://github.com/Data-Oriented-House/PortableBuildTools/releases/latest/download/PortableBuildTools.exe' -OutFile $pbtExe
    }
    Write-Host "MSVC: installing into $msvcDir (about 1.5 GB, no admin rights needed)..."
    & $pbtExe accept_license target=x64 host=x64 env=none "path=$msvcDir"
    if ($LASTEXITCODE -ne 0) { throw "PortableBuildTools failed with exit code $LASTEXITCODE" }
}

# --- Rust -------------------------------------------------------------------

$rustRoot = Join-Path $toolsRoot 'Rust'
$env:RUSTUP_HOME = Join-Path $rustRoot 'rustup'
$env:CARGO_HOME = Join-Path $rustRoot 'cargo'
New-Item -ItemType Directory -Force -Path $env:RUSTUP_HOME | Out-Null
New-Item -ItemType Directory -Force -Path $env:CARGO_HOME | Out-Null

$rustupInit = Join-Path $rustRoot 'rustup-init.exe'
if (-not (Test-Path $rustupInit)) {
    Write-Host 'Rust: downloading rustup-init.exe...'
    Invoke-WebRequest -Uri 'https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe' -OutFile $rustupInit
}

Write-Host 'Rust: installing the stable toolchain (about 1 GB)...'
& $rustupInit -y --no-modify-path --default-toolchain stable --profile minimal --component clippy --component rustfmt --target x86_64-pc-windows-msvc
if ($LASTEXITCODE -ne 0) { throw "rustup-init failed with exit code $LASTEXITCODE" }

Write-Host ''
Write-Host 'Done. Next steps:'
Write-Host '  . .\scripts\dev-env.ps1'
Write-Host '  cargo check'
