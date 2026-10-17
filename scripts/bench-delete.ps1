# Regression benchmark: deleting a folder that holds many zero-byte files.
#
# Creates <Count> empty files and deletes the folder twice, printing timings:
#   1. rmx.exe          - the tool under test
#   2. SHFileOperation  - the same shell machinery Explorer uses to delete
#
# The benchmark folder defaults to .\rmx-bench next to the current directory.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\scripts\bench-delete.ps1
#   powershell -ExecutionPolicy Bypass -File .\bench-delete.ps1 -Count 10000
#   powershell -ExecutionPolicy Bypass -File .\bench-delete.ps1 -Root D:\bench -Rmx C:\test\rmx.exe
#   powershell -ExecutionPolicy Bypass -File .\bench-delete.ps1 -Recycle   # shell uses the Recycle Bin

param(
    [int]$Count = 200000,
    [string]$Root = (Join-Path (Get-Location).Path 'rmx-bench'),
    [string]$Rmx = (Join-Path (Split-Path -Parent $PSScriptRoot) 'target\release\rmx.exe'),
    [switch]$Recycle
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Rmx)) {
    throw "rmx.exe not found at $Rmx - build it or pass -Rmx <path>"
}

$fullRoot = [IO.Path]::GetFullPath($Root)
if ($fullRoot -match '^[A-Za-z]:\\?$') {
    throw "Refusing to use a drive root as the benchmark folder: $fullRoot"
}

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Threading.Tasks;

public static class BenchFiles
{
    public static int Create(string dir, int count)
    {
        Directory.CreateDirectory(dir);
        Parallel.For(0, count, i =>
        {
            using (File.Create(Path.Combine(dir, "f" + i + ".tmp"))) { }
        });
        return Directory.GetFiles(dir).Length;
    }
}
'@

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class ShellDelete
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct SHFILEOPSTRUCT
    {
        public IntPtr hwnd;
        public uint wFunc;
        public string pFrom;
        public string pTo;
        public ushort fFlags;
        public bool fAnyOperationsAborted;
        public IntPtr hNameMappings;
        public string lpszProgressTitle;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHFileOperation(ref SHFILEOPSTRUCT fileOp);

    public static int Remove(string path, bool recycle)
    {
        const uint FO_DELETE = 0x0003;
        const ushort FOF_SILENT = 0x0004;
        const ushort FOF_NOCONFIRMATION = 0x0010;
        const ushort FOF_ALLOWUNDO = 0x0040;
        const ushort FOF_NOCONFIRMMKDIR = 0x0200;
        const ushort FOF_NOERRORUI = 0x0400;

        ushort flags = (ushort)(FOF_SILENT | FOF_NOCONFIRMATION | FOF_NOCONFIRMMKDIR | FOF_NOERRORUI);
        if (recycle)
        {
            flags |= FOF_ALLOWUNDO;
        }

        var op = new SHFILEOPSTRUCT
        {
            wFunc = FO_DELETE,
            pFrom = path + "\0",
            fFlags = flags,
        };
        return SHFileOperation(ref op);
    }
}
'@

function New-BenchFolder {
    if (Test-Path -LiteralPath $fullRoot) {
        # The folder is deleted before the run, so only remove what this script
        # could have created: a flat set of f*.tmp files.
        $unexpected = Get-ChildItem -LiteralPath $fullRoot -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.PSIsContainer -or $_.Name -notlike 'f*.tmp' }
        if ($unexpected) {
            throw "Refusing to delete '$fullRoot': it holds files that are not part of the benchmark. Pass -Root to a dedicated folder."
        }
        Remove-Item -LiteralPath $fullRoot -Recurse -Force
    }

    $created = [BenchFiles]::Create($fullRoot, $Count)
    Write-Host ("  created {0:N0} files" -f $created)
    return $created
}

function Show-Result {
    param([string]$Name, [double]$Seconds, [int]$Files)
    $perSecond = if ($Seconds -gt 0) { [math]::Round($Files / $Seconds) } else { 0 }
    Write-Host ("  {0,-6} {1,8:N2} s   {2,12:N0} files/s" -f $Name, $Seconds, $perSecond)
}

function Show-Leftover {
    if (Test-Path -LiteralPath $fullRoot) {
        $left = (Get-ChildItem -LiteralPath $fullRoot -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object).Count
        Write-Host ("  folder left: yes ({0} items)" -f $left)
    } else {
        Write-Host '  folder left: no'
    }
}

Write-Host ("Benchmark folder: {0}" -f $fullRoot)
Write-Host ("File count:       {0:N0}" -f $Count)

Write-Host ''
Write-Host 'rmx:'
$created = New-BenchFolder
$watch = [Diagnostics.Stopwatch]::StartNew()
& $Rmx -rf $fullRoot | Out-Null
$watch.Stop()
Show-Result -Name 'rmx' -Seconds $watch.Elapsed.TotalSeconds -Files $created
Show-Leftover

Write-Host ''
$shellMode = if ($Recycle) { 'Recycle Bin' } else { 'permanent delete' }
Write-Host ("shell (SHFileOperation, {0}):" -f $shellMode)
$created = New-BenchFolder
$watch = [Diagnostics.Stopwatch]::StartNew()
$result = [ShellDelete]::Remove($fullRoot, $Recycle.IsPresent)
$watch.Stop()
if ($result -ne 0) {
    Write-Host ("  SHFileOperation returned {0}" -f $result)
}
Show-Result -Name 'shell' -Seconds $watch.Elapsed.TotalSeconds -Files $created
Show-Leftover
