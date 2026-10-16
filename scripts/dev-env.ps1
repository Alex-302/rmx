# Activates the portable build environment for rmx in the current session.
#
# All toolchains live in one shared folder (override the root with RMX_TOOLS_ROOT):
#   <root>\BuildTools      - MSVC + Windows SDK (devcmd.ps1)
#   <root>\Rust\rustup     - RUSTUP_HOME (toolchains)
#   <root>\Rust\cargo      - CARGO_HOME (cargo, registry and git caches)
#
# Usage (dot-source, so the variables stay in your session):
#   . .\scripts\dev-env.ps1

$toolsRoot = if ($env:RMX_TOOLS_ROOT) { $env:RMX_TOOLS_ROOT } else { 'C:\Work\Dev' }

$msvcCandidates = @(
    $env:RMX_MSVC_DIR,
    (Join-Path $toolsRoot 'BuildTools')
)
$msvcDir = $msvcCandidates | Where-Object { $_ -and (Test-Path (Join-Path $_ 'devcmd.ps1')) } | Select-Object -First 1

if ($msvcDir) {
    . (Join-Path $msvcDir 'devcmd.ps1')
} else {
    Write-Warning 'MSVC environment not found. Tried:'
    $msvcCandidates | Where-Object { $_ } | ForEach-Object { Write-Warning "  $_" }
    Write-Warning 'Run scripts\setup-local-build.ps1 or set RMX_MSVC_DIR.'
}

$rustRoot = Join-Path $toolsRoot 'Rust'
$env:RUSTUP_HOME = Join-Path $rustRoot 'rustup'
$env:CARGO_HOME = Join-Path $rustRoot 'cargo'
$cargoBin = Join-Path $env:CARGO_HOME 'bin'
if (Test-Path $cargoBin) {
    $env:PATH = "$cargoBin;$env:PATH"
}

function Show-ToolPath([string]$name) {
    $command = Get-Command $name -ErrorAction SilentlyContinue
    if ($command) {
        Write-Host ("  {0,-9}: {1}" -f $name, $command.Source)
    } else {
        Write-Host ("  {0,-9}: not found" -f $name)
    }
}

Write-Host 'rmx portable build environment'
Show-ToolPath 'cl.exe'
Show-ToolPath 'link.exe'
Show-ToolPath 'fxc.exe'
Show-ToolPath 'cargo.exe'
