# Test data for the unlock and delete flows: creates the files below and holds
# an exclusive lock on them (FileShare.None - what a text editor or a second
# PowerShell session does) until you press Enter.
#
#   <Root>\target.txt                 - file behind a short path
#   <Root>\<long folders>\target.txt  - target.txt behind a 258 char path, the
#                                       case the Restart Manager cannot see
#
# While the script waits, run rmx against either path from another window:
#   .\rmx.exe --unlock -v <path>      - CLI: kills the locking process
#   .\rmx.exe --unlock --gui <path>   - GUI: lists the locking processes
#   .\rmx.exe --gui -f <path>         - GUI: deletion fails and shows why
#
# rmx --unlock kills this PowerShell process; the files stay on disk, only the
# locks are released.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\scripts\create-locked-files.ps1
#   powershell -ExecutionPolicy Bypass -File .\scripts\create-locked-files.ps1 -Root D:\test

param(
    [string]$Root = 'C:\test'
)

$ErrorActionPreference = 'Stop'

# The deep file sits at 258 characters under C:\test, and anything longer needs
# the \\?\ prefix for the Win32 calls below.
function Get-LongPath([string]$Path) {
    if ($Path.Length -ge 250 -and -not $Path.StartsWith('\\?\')) {
        return "\\?\$Path"
    }
    $Path
}

$deepFolder = Join-Path $Root 'target.txttarget.txttarget.txttarget.txttarget.txttarget'
$deepFolder = Join-Path $deepFolder 'target.txttarget.txttarget.txttarget.txttarget.txttarget'
$deepFolder = Join-Path $deepFolder 'target.txttarget.txttarget.txttarget.txttarget.txttargettarget.txttarget.txttarget.txttarget.txttarget.txttargettarget.txttar'

$shortFile = Join-Path $Root 'target.txt'
$longFile = Join-Path $deepFolder 'target.txt'

New-Item -ItemType Directory -Path (Get-LongPath $deepFolder) -Force | Out-Null
[IO.File]::WriteAllText((Get-LongPath $shortFile), 'rmx locked test file')
[IO.File]::WriteAllText((Get-LongPath $longFile), 'rmx locked test file')

try {
    $locks = @(
        [IO.File]::Open((Get-LongPath $shortFile), 'Open', 'Read', 'None')
        [IO.File]::Open((Get-LongPath $longFile), 'Open', 'Read', 'None')
    )
} catch {
    throw "Cannot lock the files, another process holds them already: $($_.Exception.Message)"
}

Write-Host 'created and locked by this process:'
Write-Host ('  {0}  ({1} chars)' -f $shortFile, $shortFile.Length)
Write-Host ('  {0}  ({1} chars)' -f $longFile, $longFile.Length)
Write-Host ('  locking process: powershell, PID {0}' -f $PID)

# A second open of a file this process holds exclusively has to fail with a
# sharing violation - that is the lock other programs see. Report it here, so a
# missing lock is never silent.
foreach ($file in @($shortFile, $longFile)) {
    try {
        $probe = [IO.File]::Open((Get-LongPath $file), 'Open', 'Read', 'None')
        $probe.Dispose()
        Write-Warning ('not locked: {0}' -f $file)
    } catch {
        Write-Host ('  locked: {0}' -f $file)
    }
}
Write-Host ''

try {
    if ([Console]::IsInputRedirected) {
        Write-Host 'No console to read from: the files stay locked until this process is killed.'
        while ($true) {
            Start-Sleep -Seconds 1
        }
    } else {
        Read-Host 'Press Enter to release the locks (rmx --unlock kills this process instead)' | Out-Null
    }
} finally {
    foreach ($lock in $locks) {
        $lock.Dispose()
    }
    Write-Host 'locks released; the files stay on disk.'
}
