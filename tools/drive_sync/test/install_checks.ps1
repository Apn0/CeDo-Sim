# Checks for the installer half of CeDoDriveSync.ps1, dot-sourced (nothing Windows-only runs).
# run_tests.sh prepares $Work: pathdir/ (an rclone with an rclone.conf beside it, first on PATH),
# sel.conf (remotes: bad = alias to a missing dir, good and pref = local), cwd/ (the stand-in
# Drive folder, the working directory) and home/ ($HOME, so no real rclone.conf is seen).
param(
    [Parameter(Mandatory)][string]$Script,
    [Parameter(Mandatory)][string]$Work,
    [Parameter(Mandatory)][string]$RcloneSha
)
$ErrorActionPreference = 'Stop'
. $Script

$pass = 0; $fail = 0
function Check([string]$Name, [scriptblock]$Cond) {
    try {
        if (& $Cond) { "  PASS $Name"; $script:pass++ } else { "  FAIL $Name"; $script:fail++ }
    } catch { "  FAIL $Name ($($_.Exception.Message))"; $script:fail++ }
}
function Get-ErrorText([scriptblock]$Block) { try { & $Block | Out-Null; 'no error' } catch { $_.Exception.Message } }

# The pinned download, with the Linux build standing in for the Windows zip.
$script:RcloneSha256['linux-amd64'] = $RcloneSha
$exe = Install-PinnedRclone -BinRoot "$Work/bin" -Platform 'linux-amd64' 6>$null
Check 'download: SHA-256 verified, rclone v1.75.1 installed' { Test-RcloneVersion $exe }
Check 'download: a second install is a no-op' { (Install-PinnedRclone -BinRoot "$Work/bin" -Platform 'linux-amd64' 6>&1 | Out-String) -match 'already installed' }
$script:RcloneSha256['linux-amd64'] = '0' * 64
Check 'download: a wrong SHA-256 is refused' { (Get-ErrorText { Install-PinnedRclone -BinRoot "$Work/bin_bad" -Platform 'linux-amd64' 6>$null }) -match 'SHA-256 mismatch' }
Check 'download: nothing installed after a mismatch' { -not (Test-Path "$Work/bin_bad/rclone-v1.75.1-linux-amd64/rclone") }
Check 'download: an unknown platform is refused' { (Get-ErrorText { Install-PinnedRclone -BinRoot "$Work/bin_bad" -Platform 'plan9-amd64' }) -match 'No pinned SHA-256' }

# Which rclone.conf the installer adopts.
Check 'config: the rclone.conf of the rclone on PATH is reused' { (Resolve-RcloneConfigPath -PinnedExe $exe) -eq "$Work/pathdir/rclone.conf" }
Check 'config: an explicit path is honoured' { (Resolve-RcloneConfigPath -PinnedExe $exe -Explicit "$Work/sel.conf") -eq "$Work/sel.conf" }
Check 'config: a missing explicit path is refused' { (Get-ErrorText { Resolve-RcloneConfigPath -PinnedExe $exe -Explicit "$Work/nope.conf" }) -match 'does not exist' }
$savedPath = $env:PATH
$env:PATH = ''
Check 'config: no rclone on PATH and no config -> the pinned rclone default path' { (Resolve-RcloneConfigPath -PinnedExe $exe) -eq "$Work/home/.config/rclone/rclone.conf" }
$env:PATH = $savedPath

# Remote selection. Real runs only consider type drive; the local/alias types stand in here.
Push-Location "$Work/cwd"
$r = Select-DriveRemote -Exe $exe -ConfigPath "$Work/sel.conf" -FolderId 'X' -MirrorFolder 'CeDo_Simulator' -FolderLabel 'test' -RemoteTypes @('alias', 'local') 6>$null
Check 'remote: the failing remote is skipped, the working one returned' { $r -is [string] -and $r -eq 'good' }
Check 'remote: the write probe created the mirror folder' { Test-Path "$Work/cwd/CeDo_Simulator" -PathType Container }
Check 'remote: the preferred remote is tried first' { (Select-DriveRemote -Exe $exe -ConfigPath "$Work/sel.conf" -FolderId 'X' -MirrorFolder 'CeDo_Simulator' -FolderLabel 'test' -RemoteTypes @('alias', 'local') -Preferred 'pref' 6>$null) -eq 'pref' }
Check 'remote: an explicit name that is no drive remote is refused' { (Get-ErrorText { Select-DriveRemote -Exe $exe -ConfigPath "$Work/sel.conf" -FolderId 'X' -MirrorFolder 'm' -Explicit 'good' 6>$null }) -match 'not a Google Drive remote' }
Check 'remote: an explicit remote that fails the probe is refused' { (Get-ErrorText { Select-DriveRemote -Exe $exe -ConfigPath "$Work/sel.conf" -FolderId 'X' -MirrorFolder 'm' -Explicit 'bad' -RemoteTypes @('alias') 6>$null }) -match 'failed the access check' }
Pop-Location

# Helpers the summary and the guards print with.
Check 'helpers: Format-Bytes, IEC units, invariant decimal point' { (Format-Bytes 2018000000) -eq '1.88 GiB' }
Check 'helpers: the run stamp parses back' { $d = [DateTimeOffset]::MinValue; [DateTimeOffset]::TryParseExact((New-RunStamp), $script:StampFormat, $script:Invariant, [System.Globalization.DateTimeStyles]::None, [ref]$d) }
Check 'helpers: PowerShell quoting doubles apostrophes' { (ConvertTo-PSQuoted "C:\O'Brien\x") -eq "'C:\O''Brien\x'" }
Check 'helpers: the drive spec' { (Get-DriveSpec 'my drive' 'ID1' 'a/b') -eq 'my drive,root_folder_id=ID1:a/b' }
Check 'helpers: Format-When prints ISO 8601' { (Format-When ([datetime]'2026-09-25T21:15:00Z')) -match '^2026-09-2\dT\d\d:\d\d:\d\d$' }

# The shrink guard's arithmetic.
$tree = [pscustomobject]@{
    Buckets    = @([pscustomobject]@{ Name = 'assets'; Files = 0; Bytes = 0 }, [pscustomobject]@{ Name = 'src'; Files = 90; Bytes = 1 })
    TotalFiles = 90
}
$state = [pscustomobject]@{
    TotalFiles = 522
    Buckets    = @([pscustomobject]@{ Name = 'assets'; Files = 422 }, [pscustomobject]@{ Name = 'src'; Files = 100 }, [pscustomobject]@{ Name = 'tiny'; Files = 5 })
}
$alarms = @(Get-ShrinkAlarms -Tree $tree -State $state -MinFiles 20 -MaxLossRatio 0.5)
Check 'shrink: assets 422 -> 0 and the whole project flagged; src -10 % and a 5-file folder not' { ($alarms.Folder -join ',') -eq 'assets,(whole project)' -and $alarms[0].Lost -eq '100%' }
Check 'shrink: no state, no alarm' { @(Get-ShrinkAlarms -Tree $tree -State $null -MinFiles 20 -MaxLossRatio 0.5).Count -eq 0 }
$noTotal = [pscustomobject]@{ Buckets = @([pscustomobject]@{ Name = 'assets'; Files = 422 }) }
Check 'shrink: a state.json without TotalFiles still works' { (@(Get-ShrinkAlarms -Tree $tree -State $noTotal -MinFiles 20 -MaxLossRatio 0.5).Folder -join ',') -eq 'assets' }

"RESULT: $pass passed, $fail failed"
exit ([int]($fail -gt 0))
