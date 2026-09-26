#Requires -Version 7.2
<#
.SYNOPSIS
    One-click, hash-checked mirror of the CeDo Simulator project (git-ignored files included)
    to Google Drive, using a pinned rclone.

.DESCRIPTION
    Local : %USERPROFILE%\Documents\CeDo_Simulator            (-LocalPath at -Install overrides)
    Drive : My Drive/Priority Docs/CeDo Simulator/CeDo_Simulator (exact mirror)

    Every run is `rclone sync --checksum`: size + MD5 of every local file against the MD5 Drive
    stores, so only new or changed files upload. Anything the mirror would delete or overwrite
    is first moved server-side to CeDo_Simulator_versions/<run stamp>/, never lost. Version
    folders older than VersionsKeepDays go to the Drive trash. .git folders are excluded
    (GitHub has them); everything else, .godot/ and assets/ included, is mirrored.

    Guards before anything changes on Drive:
      - project.godot must say config/name="CeDo Simulator" (wrong/empty folder = no sync)
      - shrink guard: a top-level folder that lost >= 50 % of its files since the last good sync
        (the 2026-09-21 assets/ wipe) stops the run until you type YES
      - rclone --max-delete: more than 100 deletions stop the run until you type YES

    -Install    One-time setup, safe to re-run: rclone v1.75.1 (SHA-256 checked), a Google Drive
                remote (reuses a working one from your rclone.conf, else opens the Google login
                once), the Drive folders, config.json, and the desktop shortcut.
    (no switch) One sync. This is what the desktop shortcut runs.
    -DryRun     Show what a sync would change; change nothing.
    -Uninstall  Remove the shortcut and %LOCALAPPDATA%\CeDoDriveSync. Drive data and the rclone
                remote are left alone.

.NOTES
    Install folder: %LOCALAPPDATA%\CeDoDriveSync (script, config.json, state.json, logs\, bin\).
    Tunables live in config.json (Mode, MaxDeletePerRun, VersionsKeepDays, ...); -Install keeps them.
    Source: tools/drive_sync/ in the CeDo-Sim repo (README.md; Linux tests in test/). The desktop
    button runs the installed copy, so re-run -Install after pulling a newer one.
#>
[CmdletBinding(DefaultParameterSetName = 'Sync')]
param(
    [Parameter(ParameterSetName = 'Install', Mandatory)][switch]$Install,
    [Parameter(ParameterSetName = 'Install')][string]$LocalPath,
    [Parameter(ParameterSetName = 'Install')][string]$DriveFolderId = '1DppntIc3JkDG_-1ExXGTnboueba9xtOZ',
    [Parameter(ParameterSetName = 'Install')][string]$RemoteName,
    [Parameter(ParameterSetName = 'Install')][string]$RcloneConfigPath,
    [Parameter(ParameterSetName = 'Install')][string]$Hotkey,
    [Parameter(ParameterSetName = 'Uninstall', Mandatory)][switch]$Uninstall,
    [Parameter(ParameterSetName = 'Sync')][switch]$DryRun,
    [Parameter(ParameterSetName = 'Sync')][switch]$AllowMassDelete,
    [Parameter(ParameterSetName = 'Sync')][switch]$NoPause
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# ---- pinned facts ------------------------------------------------------------------------------
$script:AppName = 'CeDoDriveSync'
$script:RcloneVersion = 'v1.75.1'
# From https://downloads.rclone.org/v1.75.1/SHA256SUMS, fetched 2026-09-25.
$script:RcloneSha256 = @{
    'windows-amd64' = '200eb602c126d82aa38b51e0f6b9ae837473ff99b51278d3f6f837574c494d6e'
    'windows-arm64' = 'c3c6cd0424dd49076ad179c30c3f9e5cde2c004ec07ea9fe6911f23e32eafe0f'
}
$script:ProjectName = 'CeDo Simulator'                          # project.godot config/name
$script:DefaultFolderId = '1DppntIc3JkDG_-1ExXGTnboueba9xtOZ'   # My Drive/Priority Docs/CeDo Simulator
$script:DefaultFolderLabel = 'My Drive/Priority Docs/CeDo Simulator'
$script:NewRemoteName = 'cedo-gdrive'
$script:ShortcutName = 'CeDo - Sync to Drive.lnk'
$script:StampFormat = "yyyyMMdd'T'HHmmsszzz"                   # 20260925T231500+0200
$script:Invariant = [System.Globalization.CultureInfo]::InvariantCulture
# rclone exit codes, https://rclone.org/docs/#list-of-exit-codes
$script:RcloneExitText = @{
    1 = 'error not otherwise categorised'; 2 = 'syntax or usage error'; 3 = 'directory not found'
    4 = 'file not found'; 5 = 'temporary error, a re-run may fix it'; 6 = 'less serious errors'
    7 = 'fatal error, retries will not fix it'; 8 = 'transfer limit reached'
    9 = 'no files transferred'; 10 = 'duration limit reached'
}

# ---- console helpers ---------------------------------------------------------------------------
function Write-Step([string]$Text) { Write-Host "== $Text" -ForegroundColor Cyan }
function Write-Good([string]$Text) { Write-Host "OK  $Text" -ForegroundColor Green }
function Write-Warn([string]$Text) { Write-Host "!!  $Text" -ForegroundColor Yellow }

function Format-Bytes([double]$Bytes) {
    $units = 'B', 'KiB', 'MiB', 'GiB', 'TiB'
    $i = 0
    while ($Bytes -ge 1024 -and $i -lt $units.Count - 1) { $Bytes /= 1024; $i++ }
    if ($i -eq 0) { return [string]::Format($script:Invariant, '{0:F0} {1}', $Bytes, $units[$i]) }
    [string]::Format($script:Invariant, '{0:F2} {1}', $Bytes, $units[$i])
}

function Format-Duration([double]$Seconds) {
    $t = [TimeSpan]::FromSeconds([math]::Max(0, $Seconds))
    if ($t.TotalHours -ge 1) { return '{0}h{1:D2}m' -f [int][math]::Floor($t.TotalHours), $t.Minutes }
    if ($t.TotalMinutes -ge 1) { return '{0}m{1:D2}s' -f $t.Minutes, $t.Seconds }
    '{0}s' -f [int][math]::Round($t.TotalSeconds)
}

# Tables via Out-String: Out-Host renders nothing when there is no console width (redirected output).
function Show-Table {
    param([Parameter(ValueFromPipeline)]$InputObject, [switch]$NoHeader)
    begin { $items = [System.Collections.Generic.List[object]]::new() }
    process { $items.Add($InputObject) }
    end {
        if ($items.Count -eq 0) { return }
        $text = $items | Format-Table -AutoSize -HideTableHeaders:$NoHeader | Out-String -Width 240
        Write-Host $text.Trim("`r", "`n")
        Write-Host ''
    }
}

function Get-LastLines([string]$Text, [int]$Count = 3) {
    $lines = @($Text -split "`r?`n" | Where-Object { $_.Trim() })
    ($lines | Select-Object -Last $Count) -join ' | '
}

function Confirm-Typed([string]$Prompt) {
    if ($NoPause) { return $false }   # unattended runs never confirm anything
    (Read-Host $Prompt) -ceq 'YES'
}

# ConvertFrom-Json turns ISO strings into [datetime]; print those back as ISO 8601, not culture format.
function Format-When($Value) {
    if ($Value -is [datetime]) { return $Value.ToLocalTime().ToString('yyyy-MM-ddTHH:mm:ss', $script:Invariant) }
    if ($Value -is [DateTimeOffset]) { return $Value.ToLocalTime().ToString('yyyy-MM-ddTHH:mm:ss', $script:Invariant) }
    [string]$Value
}

function ConvertTo-PSQuoted([string]$Text) { "'" + $Text.Replace("'", "''") + "'" }

function New-RunStamp {
    $now = [DateTimeOffset]::Now
    $now.ToString("yyyyMMdd'T'HHmmss", $script:Invariant) + $now.ToString('zzz', $script:Invariant).Replace(':', '')
}

function Save-JsonAtomic([Parameter(Mandatory)]$Object, [Parameter(Mandatory)][string]$Path) {
    $tmp = "$Path.tmp"
    $Object | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $tmp -Encoding utf8NoBOM
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

# ---- rclone plumbing ---------------------------------------------------------------------------
function Invoke-RcloneCapture {
    param([Parameter(Mandatory)][string]$Exe, [Parameter(Mandatory)][string[]]$Arguments)
    $errFile = [System.IO.Path]::GetTempFileName()
    $ErrorActionPreference = 'Continue'   # native stderr must never become a terminating error
    try {
        $out = & $Exe @Arguments 2> $errFile
        $code = $LASTEXITCODE
        [pscustomobject]@{
            Code = $code
            Out  = @($out | ForEach-Object { [string]$_ })
            Err  = [string](Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue)
        }
    } finally {
        Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
    }
}

# rclone attached straight to this console (live --progress, the OAuth prompt) and returning only
# its exit code. Via `&` its stdout would land in the caller's return value instead of on screen.
function Invoke-RcloneInteractive {
    param([Parameter(Mandatory)][string]$Exe, [Parameter(Mandatory)][string[]]$Arguments)
    $psi = [System.Diagnostics.ProcessStartInfo]::new($Exe)
    foreach ($x in $Arguments) { $psi.ArgumentList.Add($x) }   # per-argument quoting done by .NET
    $psi.UseShellExecute = $false
    $loc = Get-Location
    if ($loc.Provider.Name -eq 'FileSystem') { $psi.WorkingDirectory = $loc.ProviderPath }
    $p = [System.Diagnostics.Process]::Start($psi)
    try { $p.WaitForExit(); [int]$p.ExitCode } finally { $p.Dispose() }
}

# A drive remote re-rooted at one folder ID via rclone's connection-string syntax, so the target
# is that exact folder no matter what the remote's own root_folder_id is or how folders are named.
function Get-DriveSpec([string]$Remote, [string]$FolderId, [string]$Path) {
    '{0},root_folder_id={1}:{2}' -f $Remote, $FolderId, $Path
}

function Get-RclonePlatform {
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    switch ($arch) {
        'X64' { 'windows-amd64' }
        'Arm64' { 'windows-arm64' }
        default { throw "Unsupported Windows architecture '$arch' (pinned builds: X64, Arm64)." }
    }
}

function Test-RcloneVersion([string]$Exe) {
    if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) { return $false }
    $v = Invoke-RcloneCapture -Exe $Exe -Arguments @('version')
    $v.Code -eq 0 -and $v.Out.Count -gt 0 -and $v.Out[0].Trim() -eq "rclone $script:RcloneVersion"
}

function Install-PinnedRclone {
    param([Parameter(Mandatory)][string]$BinRoot, [Parameter(Mandatory)][string]$Platform)
    if (-not $script:RcloneSha256.ContainsKey($Platform)) { throw "No pinned SHA-256 for rclone $Platform." }
    $name = "rclone-$script:RcloneVersion-$Platform"
    $exeName = if ($Platform -like 'windows-*') { 'rclone.exe' } else { 'rclone' }
    $dstDir = Join-Path $BinRoot $name
    $exe = Join-Path $dstDir $exeName
    if (Test-RcloneVersion $exe) {
        Write-Good "rclone $script:RcloneVersion already installed: $exe"
        return $exe
    }
    New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
    $url = "https://downloads.rclone.org/$script:RcloneVersion/$name.zip"
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "$name-$([guid]::NewGuid().ToString('N'))"
    $zip = "$tmp.zip"
    try {
        Write-Step "Downloading $url"
        for ($attempt = 1; ; $attempt++) {
            try { Invoke-WebRequest -Uri $url -OutFile $zip; break }
            catch {
                if ($attempt -ge 3) { throw "Download failed 3x ($url): $($_.Exception.Message). Check the internet connection/proxy and re-run." }
                Write-Warn "Download attempt $attempt failed ($($_.Exception.Message)); retrying in 5 s"
                Start-Sleep -Seconds 5
            }
        }
        $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hash -ne $script:RcloneSha256[$Platform]) {
            throw "SHA-256 mismatch for $name.zip: got $hash, expected $($script:RcloneSha256[$Platform]). File discarded, nothing installed."
        }
        Write-Good "SHA-256 verified: $hash"
        Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
        $src = Join-Path (Join-Path $tmp $name) $exeName
        if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { throw "Unexpected zip layout: $src missing." }
        Copy-Item -LiteralPath $src -Destination $exe -Force
        if (-not $IsWindows) { & chmod 755 $exe }
    } finally {
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (-not (Test-RcloneVersion $exe)) { throw "Installed $exe does not report 'rclone $script:RcloneVersion'." }
    Write-Good "Installed rclone $script:RcloneVersion`: $exe"
    $exe
}

function Resolve-RcloneConfigPath {
    param([Parameter(Mandatory)][string]$PinnedExe, [string]$Explicit)
    if ($Explicit) {
        if (-not (Test-Path -LiteralPath $Explicit -PathType Leaf)) { throw "-RcloneConfigPath '$Explicit' does not exist." }
        return (Resolve-Path -LiteralPath $Explicit).ProviderPath
    }
    # An rclone already on PATH (e.g. the one your Documents-Backup job uses) knows its config
    # file; reuse it so its Drive remote works here without a new Google login.
    $exes = @(Get-Command rclone -CommandType Application -All -ErrorAction SilentlyContinue |
            ForEach-Object Source | Where-Object { $_ -and $_ -ne $PinnedExe } | Select-Object -Unique)
    foreach ($exe in @($exes + $PinnedExe)) {
        $r = Invoke-RcloneCapture -Exe $exe -Arguments @('config', 'file')
        $path = @($r.Out | Where-Object { $_.Trim() } | Select-Object -Last 1)
        if ($r.Code -eq 0 -and $path.Count -eq 1 -and (Test-Path -LiteralPath $path[0].Trim() -PathType Leaf)) {
            return $path[0].Trim()
        }
    }
    # No config file anywhere yet: the pinned rclone's default path, created with the first remote.
    $r = Invoke-RcloneCapture -Exe $PinnedExe -Arguments @('config', 'file')
    $path = @($r.Out | Where-Object { $_.Trim() } | Select-Object -Last 1)
    if ($r.Code -ne 0 -or $path.Count -ne 1) { throw "rclone config file failed: $(Get-LastLines $r.Err)" }
    $path[0].Trim()
}

function Test-DriveRemote {
    param([string]$Exe, [string]$ConfigPath, [string]$Remote, [string]$FolderId, [string]$MirrorFolder)
    $quick = @('--config', $ConfigPath, '--ask-password=false', '--contimeout', '15s', '--timeout', '30s',
        '--retries', '1', '--low-level-retries', '2')
    $r = Invoke-RcloneCapture -Exe $Exe -Arguments (@('lsf', '--max-depth', '1', '--dirs-only', (Get-DriveSpec $Remote $FolderId '')) + $quick)
    if ($r.Code -ne 0) { return "cannot open folder $FolderId (exit $($r.Code)): $(Get-LastLines $r.Err 2)" }
    # Creating the mirror folder doubles as the write-permission check (read-only scopes fail here).
    $r = Invoke-RcloneCapture -Exe $Exe -Arguments (@('mkdir', (Get-DriveSpec $Remote $FolderId $MirrorFolder)) + $quick)
    if ($r.Code -ne 0) { return "no write access (exit $($r.Code)): $(Get-LastLines $r.Err 2)" }
    ''
}

function Select-DriveRemote {
    param(
        [Parameter(Mandatory)][string]$Exe, [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][string]$FolderId, [Parameter(Mandatory)][string]$MirrorFolder,
        [string]$Explicit, [string]$Preferred, [string]$FolderLabel, [string[]]$RemoteTypes = @('drive')
    )
    $r = Invoke-RcloneCapture -Exe $Exe -Arguments @('listremotes', '--json', '--config', $ConfigPath, '--ask-password=false')
    if ($r.Code -ne 0) {
        throw "rclone listremotes failed (exit $($r.Code)): $(Get-LastLines $r.Err). An encrypted rclone.conf needs RCLONE_CONFIG_PASS set."
    }
    $all = @(($r.Out -join "`n") | ConvertFrom-Json)
    $candidates = @($all | Where-Object { $RemoteTypes -contains $_.type })
    if ($Explicit) {
        $candidates = @($candidates | Where-Object { $_.name -eq $Explicit })
        if ($candidates.Count -eq 0) { throw "Remote '$Explicit' is not a Google Drive remote in $ConfigPath." }
    } elseif ($Preferred) {
        $candidates = @($candidates | Sort-Object { $_.name -ne $Preferred })
    }
    foreach ($c in $candidates) {
        Write-Step "Checking rclone remote '$($c.name)' against $FolderLabel"
        $why = Test-DriveRemote -Exe $Exe -ConfigPath $ConfigPath -Remote $c.name -FolderId $FolderId -MirrorFolder $MirrorFolder
        if (-not $why) { Write-Good "Using remote '$($c.name)'"; return [string]$c.name }
        Write-Warn "Remote '$($c.name)' skipped: $why"
    }
    if ($Explicit) { throw "Remote '$Explicit' failed the access check (see above)." }

    $existing = @($all | ForEach-Object { $_.name })
    $name = $script:NewRemoteName
    for ($n = 2; $existing -contains $name; $n++) { $name = "$script:NewRemoteName-$n" }
    Write-Step "Creating rclone remote '$name' (full Drive scope)."
    Write-Host '    A browser tab opens: log in with the Google account that owns' -ForegroundColor Yellow
    Write-Host "    '$FolderLabel' and click Allow. This console waits for it." -ForegroundColor Yellow
    $code = Invoke-RcloneInteractive -Exe $Exe -Arguments @('config', 'create', $name, 'drive', 'scope=drive', '--config', $ConfigPath)
    if ($code -ne 0) { throw "rclone config create failed (exit $code)." }
    $why = Test-DriveRemote -Exe $Exe -ConfigPath $ConfigPath -Remote $name -FolderId $FolderId -MirrorFolder $MirrorFolder
    if ($why) {
        throw ("New remote '$name' still fails: $why. Usually the browser login used another Google account. " +
            "Fix: & '$Exe' config reconnect ${name}: --config '$ConfigPath' , then re-run -Install.")
    }
    Write-Good "Using new remote '$name'"
    $name
}

# ---- project checks ----------------------------------------------------------------------------
function Assert-CeDoProject([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "Project folder not found: $Path. Nothing was synced." }
    $pg = Join-Path $Path 'project.godot'
    if (-not (Test-Path -LiteralPath $pg -PathType Leaf)) {
        throw "No project.godot in $Path (wrong or emptied folder). Nothing was synced."
    }
    $hit = Select-String -LiteralPath $pg -Pattern '^\s*config/name\s*=\s*"(.*)"\s*$' | Select-Object -First 1
    $name = if ($hit) { $hit.Matches[0].Groups[1].Value } else { '' }
    if ($name -ne $script:ProjectName) {
        throw "project.godot in $Path has config/name=""$name"", expected ""$script:ProjectName"". Nothing was synced."
    }
}

# One pass over the tree: file count + bytes per top-level folder, plus the symlinks/junctions
# rclone will skip. Walks by hand so links are reported, never followed (.NET's recursive
# enumeration would follow junctions).
function Get-LocalTreeStats {
    param([Parameter(Mandatory)][string]$Root, [bool]$ExcludeGitDirs = $true)
    $opts = [System.IO.EnumerationOptions]::new()
    $opts.RecurseSubdirectories = $false
    $opts.AttributesToSkip = [System.IO.FileAttributes]::None   # default skips Hidden+System; rclone doesn't
    $opts.IgnoreInaccessible = $false
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $buckets = [ordered]@{}
    $links = [System.Collections.Generic.List[object]]::new()
    $unreadable = [System.Collections.Generic.List[string]]::new()
    $stack = [System.Collections.Generic.Stack[object]]::new()
    $stack.Push(@([System.IO.DirectoryInfo]::new($rootFull), $null))
    while ($stack.Count -gt 0) {
        $item = $stack.Pop()
        $dir = [System.IO.DirectoryInfo]$item[0]
        $bucket = $item[1]
        try {
            foreach ($e in $dir.EnumerateFileSystemInfos('*', $opts)) {
                if ($ExcludeGitDirs -and $e.Name -eq '.git') { continue }
                $isDir = $e -is [System.IO.DirectoryInfo]
                $b = if ($null -ne $bucket) { $bucket } elseif ($isDir) { $e.Name } else { '(root files)' }
                if ($null -ne $e.LinkTarget) {
                    $links.Add([pscustomobject]@{ Path = $e.FullName.Substring($rootFull.Length + 1); Target = $e.LinkTarget })
                    continue
                }
                if (-not $buckets.Contains($b)) { $buckets[$b] = [long[]]@(0, 0) }
                if ($isDir) { $stack.Push(@($e, $b)) }
                else { $buckets[$b][0]++; $buckets[$b][1] += ([System.IO.FileInfo]$e).Length }
            }
        } catch [System.UnauthorizedAccessException], [System.IO.IOException] {
            $unreadable.Add("$($dir.FullName): $($_.Exception.Message)")
        }
    }
    $rows = @(foreach ($k in $buckets.Keys) { [pscustomobject]@{ Name = [string]$k; Files = $buckets[$k][0]; Bytes = $buckets[$k][1] } })
    [pscustomobject]@{
        Buckets    = $rows
        TotalFiles = [long](($rows | Measure-Object -Property Files -Sum).Sum ?? 0)
        TotalBytes = [long](($rows | Measure-Object -Property Bytes -Sum).Sum ?? 0)
        Links      = $links.ToArray()
        Unreadable = $unreadable.ToArray()
    }
}

function Get-ShrinkAlarms {
    param([Parameter(Mandatory)]$Tree, $State, [long]$MinFiles, [double]$MaxLossRatio)
    if ($null -eq $State -or -not $State.PSObject.Properties['Buckets']) { return }
    $now = @{}
    foreach ($b in $Tree.Buckets) { $now[$b.Name] = [long]$b.Files }
    $rows = @(foreach ($p in @($State.Buckets)) { [pscustomobject]@{ Name = [string]$p.Name; Before = [long]$p.Files } })
    if ($State.PSObject.Properties['TotalFiles']) { $rows += [pscustomobject]@{ Name = '(whole project)'; Before = [long]$State.TotalFiles } }
    foreach ($p in $rows) {
        if ($p.Before -lt $MinFiles) { continue }
        $after = if ($p.Name -eq '(whole project)') { [long]$Tree.TotalFiles } elseif ($now.ContainsKey($p.Name)) { $now[$p.Name] } else { 0 }
        $loss = ($p.Before - $after) / [double]$p.Before
        if ($loss -ge $MaxLossRatio) {
            [pscustomobject]@{ Folder = $p.Name; FilesAtLastSync = $p.Before; FilesNow = $after; Lost = ('{0}%' -f [int][math]::Round($loss * 100)) }
        }
    }
}

function Read-State([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
    catch { Write-Warn "state.json unreadable ($($_.Exception.Message)); treating this as a first run."; $null }
}

# Summary from rclone's JSON log(s). Counts come from the final stats record; the split of
# archived files uses rclone's per-file messages ("Moved into backup dir" = deleted locally,
# a plain "Moved (server-side)" without it = previous version of a changed file).
function Read-RcloneRunLog {
    param([Parameter(Mandatory)][string[]]$Paths)
    $s = [ordered]@{
        HaveStats = $false; Uploaded = 0L; UploadedBytes = 0L; Checked = 0L; ArchivedDeleted = 0L
        ArchivedChanged = 0L; Renamed = 0L; LinksSkipped = 0L; Errors = 0L; ElapsedSec = 0.0
        MaxDeleteHit = $false; ErrorLines = [System.Collections.Generic.List[string]]::new()
    }
    for ($i = 0; $i -lt $Paths.Count; $i++) {
        if (-not (Test-Path -LiteralPath $Paths[$i] -PathType Leaf)) { continue }
        $isLast = $i -eq $Paths.Count - 1
        $moved = 0L; $intoBackup = 0L; $dryMoves = 0L; $statsLine = $null
        foreach ($line in [System.IO.File]::ReadLines($Paths[$i])) {
            if ($line.Contains('"stats":{')) { $statsLine = $line; continue }
            if ($line.Contains('"msg":"Moved into backup dir"')) { $intoBackup++ }
            elseif ($line.Contains('"msg":"Moved (server-side)"')) { $moved++ }
            elseif ($line.Contains('"msg":"Skipped move as --dry-run')) { $dryMoves++ }
            elseif ($line.Contains('"msg":"Renamed from')) { $s.Renamed++ }
            elseif ($line.Contains("Can't follow symlink")) { $s.LinksSkipped++ }
            if ($line.Contains('--max-delete threshold reached')) { $s.MaxDeleteHit = $true }
            if ($isLast -and $line.Contains('"level":"error"')) {
                $j = $line | ConvertFrom-Json
                $obj = if ($j.PSObject.Properties['object'] -and $j.object) { " [$($j.object)]" } else { '' }
                $s.ErrorLines.Add(([string]$j.msg).Trim() + $obj)
            }
        }
        $s.ArchivedChanged += [math]::Max(0, $moved - $intoBackup) + $dryMoves
        if ($statsLine) {
            $st = ($statsLine | ConvertFrom-Json).stats
            $s.HaveStats = $true
            $s.Uploaded += [long]$st.transfers
            $s.UploadedBytes += [long]$st.bytes
            $s.Checked += [long]$st.checks
            $s.ArchivedDeleted += [long]$st.deletes
            $s.ElapsedSec += [double]$st.elapsedTime
            if ($isLast) { $s.Errors = [long]$st.errors }
        } elseif ($isLast) {
            $s.Errors = [long]$s.ErrorLines.Count
        }
    }
    [pscustomobject]$s
}

function Get-DriveNumbers($Cfg, [string]$Command) {
    $spec = if ($Command -eq 'size') { Get-DriveSpec $Cfg.Remote $Cfg.DriveFolderId $Cfg.MirrorFolder } else { Get-DriveSpec $Cfg.Remote $Cfg.DriveFolderId '' }
    $a = @($Command, $spec, '--json', '--config', $Cfg.RcloneConfigPath, '--ask-password=false')
    if ($Command -eq 'size') { $a += '--fast-list' }
    $r = Invoke-RcloneCapture -Exe $Cfg.RcloneExe -Arguments $a
    if ($Command -eq 'size' -and $r.Code -eq 3) { return [pscustomobject]@{ count = 0; bytes = 0 } }
    if ($r.Code -ne 0) { Write-Warn "rclone $Command failed (exit $($r.Code)): $(Get-LastLines $r.Err 2)"; return $null }
    try { ($r.Out -join "`n") | ConvertFrom-Json } catch { $null }
}

function Invoke-RcloneTransfer {
    param($Cfg, [string]$Stamp, [string]$LogPath, [bool]$LiftDeleteLimit, [bool]$Preview, [bool]$Interactive)
    $verb = if ($Cfg.Mode -eq 'mirror') { 'sync' } else { 'copy' }
    $a = [System.Collections.Generic.List[string]]::new()
    $a.AddRange([string[]]@(
            $verb, $Cfg.LocalPath, (Get-DriveSpec $Cfg.Remote $Cfg.DriveFolderId $Cfg.MirrorFolder),
            '--backup-dir', (Get-DriveSpec $Cfg.Remote $Cfg.DriveFolderId "$($Cfg.VersionsFolder)/$Stamp"),
            '--checksum', '--fast-list', '--create-empty-src-dirs',
            '--drive-skip-gdocs', '--drive-skip-shortcuts', '--drive-stop-on-upload-limit', '--drive-chunk-size', '64M',
            '--config', $Cfg.RcloneConfigPath, '--ask-password=false',
            '--use-json-log', '--log-file', $LogPath, '--log-level', 'INFO'))
    if ($Cfg.ExcludeGitDirs) { $a.AddRange([string[]]@('--exclude', '.git/**', '--exclude', '.git')) }
    if ($verb -eq 'sync') {
        $a.Add('--track-renames')
        $a.AddRange([string[]]@('--max-delete', $(if ($LiftDeleteLimit) { '-1' } else { [string][int]$Cfg.MaxDeletePerRun })))
    }
    if ($Preview) { $a.Add('--dry-run') }
    if ($Interactive) { $a.Add('--progress') }
    Invoke-RcloneInteractive -Exe $Cfg.RcloneExe -Arguments $a.ToArray()
}

function Remove-OldVersionFolders($Cfg) {
    $keep = [int]$Cfg.VersionsKeepDays
    if ($keep -le 0) { return }
    $spec = Get-DriveSpec $Cfg.Remote $Cfg.DriveFolderId $Cfg.VersionsFolder
    $common = @('--config', $Cfg.RcloneConfigPath, '--ask-password=false')
    $r = Invoke-RcloneCapture -Exe $Cfg.RcloneExe -Arguments (@('lsf', '--dirs-only', '--max-depth', '1', $spec) + $common)
    if ($r.Code -eq 3) { return }
    if ($r.Code -ne 0) { Write-Warn "Could not list $($Cfg.VersionsFolder) for pruning: $(Get-LastLines $r.Err 2)"; return }
    $cutoff = [DateTimeOffset]::Now.AddDays(-$keep)
    foreach ($line in $r.Out) {
        $name = $line.Trim().TrimEnd('/')
        $ts = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParseExact($name, $script:StampFormat, $script:Invariant, [System.Globalization.DateTimeStyles]::None, [ref]$ts)) { continue }
        if ($ts -ge $cutoff) { continue }
        $p = Invoke-RcloneCapture -Exe $Cfg.RcloneExe -Arguments (@('purge', "$spec/$name") + $common)
        if ($p.Code -eq 0) { Write-Good "Versions older than $keep days: $($Cfg.VersionsFolder)/$name moved to the Drive trash" }
        else { Write-Warn "Could not remove $($Cfg.VersionsFolder)/${name}: $(Get-LastLines $p.Err 2)" }
    }
}

function Set-KeepAwake([bool]$On) {
    if (-not $IsWindows) { return }
    if (-not ('CeDoDriveSync.Power' -as [type])) {
        Add-Type -Namespace CeDoDriveSync -Name Power -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);'
    }
    # ES_CONTINUOUS 0x80000000 (+ ES_SYSTEM_REQUIRED 0x1 while syncing): the PC doesn't sleep mid-upload.
    $flags = if ($On) { [uint32]2147483649 } else { [uint32]2147483648 }
    [void][CeDoDriveSync.Power]::SetThreadExecutionState($flags)
}

function Read-Config([string]$Dir) {
    $f = Join-Path $Dir 'config.json'
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) {
        throw ("No config.json next to this script ($f). Run the installer first: " +
            'pwsh -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\Documents\CeDo_Simulator\tools\drive_sync\CeDoDriveSync.ps1" -Install')
    }
    $c = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
    foreach ($k in 'LocalPath', 'RcloneExe', 'RcloneConfigPath', 'Remote', 'DriveFolderId', 'DriveFolderLabel',
        'MirrorFolder', 'VersionsFolder', 'Mode', 'ExcludeGitDirs', 'MaxDeletePerRun', 'ShrinkGuardMinFiles',
        'ShrinkGuardMaxLossRatio', 'VersionsKeepDays', 'LogsKeep') {
        if (-not $c.PSObject.Properties[$k]) { throw "config.json lacks '$k'. Re-run -Install." }
    }
    if ($c.Mode -notin 'mirror', 'add-only') { throw "config.json Mode must be 'mirror' or 'add-only', not '$($c.Mode)'." }
    if ([int]$c.MaxDeletePerRun -lt 1) { throw 'config.json MaxDeletePerRun must be >= 1 (the -AllowMassDelete switch lifts it per run).' }
    $c
}

# ---- sync (the desktop button) -----------------------------------------------------------------
function Invoke-Sync {
    $base = $PSScriptRoot
    $cfg = Read-Config $base
    $stateFile = Join-Path $base 'state.json'
    $logDir = Join-Path $base 'logs'
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    try { $Host.UI.RawUI.WindowTitle = 'CeDo -> Google Drive' } catch { Write-Verbose "No window title in this host: $($_.Exception.Message)" }

    $stamp = New-RunStamp
    $mirrorLabel = "$($cfg.DriveFolderLabel)/$($cfg.MirrorFolder)"
    $mirrorSpec = Get-DriveSpec $cfg.Remote $cfg.DriveFolderId $cfg.MirrorFolder
    Write-Host ''
    Write-Host ('CeDo -> Google Drive   {0}{1}' -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'), $(if ($DryRun) { '   DRY RUN: nothing will change' } else { '' })) -ForegroundColor White
    Write-Host "  from : $($cfg.LocalPath)"
    Write-Host "  to   : $mirrorLabel   (rclone remote '$($cfg.Remote)', mode $($cfg.Mode))"
    Write-Host "  old  : $($cfg.DriveFolderLabel)/$($cfg.VersionsFolder)/$stamp   (whatever this run deletes/overwrites)"
    Write-Host ''

    $mutex = [System.Threading.Mutex]::new($false, 'Local\CeDoDriveSync')
    $owned = $false
    try { $owned = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $owned = $true }
    if (-not $owned) { $mutex.Dispose(); throw 'Another CeDo Drive sync is already running (check your other windows).' }
    try {
        Set-KeepAwake $true
        Assert-CeDoProject $cfg.LocalPath
        if (-not (Test-RcloneVersion $cfg.RcloneExe)) { throw "rclone $script:RcloneVersion missing or broken at $($cfg.RcloneExe). Re-run -Install." }
        if (-not (Test-Path -LiteralPath $cfg.RcloneConfigPath -PathType Leaf)) { throw "rclone config not found: $($cfg.RcloneConfigPath). Re-run -Install." }
        $godot = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'Godot*' })
        if ($godot.Count -gt 0) {
            Write-Warn "Godot is running ($(($godot.ProcessName | Select-Object -Unique) -join ', ')). Files it writes mid-sync can be flagged 'source file is being updated'; the next run picks them up."
        }

        Write-Step 'Scanning local project'
        $tree = Get-LocalTreeStats -Root $cfg.LocalPath -ExcludeGitDirs ([bool]$cfg.ExcludeGitDirs)
        $tree.Buckets | Sort-Object Bytes -Descending |
            Select-Object @{ n = 'Folder'; e = { $_.Name } }, Files, @{ n = 'Size'; e = { Format-Bytes $_.Bytes } } |
            Show-Table
        Write-Host ("  total: {0} files, {1}{2}" -f $tree.TotalFiles, (Format-Bytes $tree.TotalBytes), $(if ($cfg.ExcludeGitDirs) { '   (.git folders excluded)' } else { '' }))
        foreach ($l in $tree.Links) { Write-Warn "Link NOT uploaded (rclone skips links): $($l.Path) -> $($l.Target)" }
        foreach ($u in $tree.Unreadable) { Write-Warn "Unreadable: $u" }

        $state = Read-State $stateFile
        $lift = [bool]$AllowMassDelete
        if ($cfg.Mode -eq 'mirror' -and -not $lift) {
            $alarms = @(Get-ShrinkAlarms -Tree $tree -State $state -MinFiles ([long]$cfg.ShrinkGuardMinFiles) -MaxLossRatio ([double]$cfg.ShrinkGuardMaxLossRatio))
            if ($alarms.Count -gt 0) {
                Write-Host ''
                $when = if ($state.PSObject.Properties['LastSuccess']) { Format-When $state.LastSuccess } else { 'unknown' }
                Write-Host "SHRINK GUARD: these lost >= $([int]([double]$cfg.ShrinkGuardMaxLossRatio * 100))% of their files since the last good sync ($when):" -ForegroundColor Red
                $alarms | Show-Table
                Write-Host "Syncing would move those files out of the mirror into $($cfg.VersionsFolder)/$stamp." -ForegroundColor Yellow
                Write-Host 'If this is a wipe (like assets/ on 2026-09-21), close this window and restore from Drive first:' -ForegroundColor Yellow
                foreach ($a in $alarms) {
                    if ($a.Folder -in '(root files)', '(whole project)') { continue }
                    $dst = Join-Path $cfg.LocalPath $a.Folder
                    Write-Host ('  & {0} copy {1} {2} --checksum -P --config {3}' -f (ConvertTo-PSQuoted $cfg.RcloneExe),
                        (ConvertTo-PSQuoted "$mirrorSpec/$($a.Folder)"), (ConvertTo-PSQuoted $dst), (ConvertTo-PSQuoted $cfg.RcloneConfigPath))
                }
                if ($DryRun) {
                    Write-Warn 'Dry run: continuing so the preview shows what those deletions would do.'
                } elseif (-not (Confirm-Typed 'Type YES to mirror these deletions anyway; anything else stops')) {
                    throw 'Stopped by the shrink guard. Nothing was changed on Drive.'
                }
                $lift = $true
            }
        }

        $about = Get-DriveNumbers $cfg 'about'
        if ($null -ne $about -and $about.PSObject.Properties['used']) {
            $total = if ($about.PSObject.Properties['total']) { Format-Bytes $about.total } else { 'unlimited' }
            $free = if ($about.PSObject.Properties['free']) { Format-Bytes $about.free } else { 'n/a' }
            Write-Host "  Drive: $(Format-Bytes $about.used) used of $total, $free free"
        }
        if ($null -eq $state) {
            $mirror = Get-DriveNumbers $cfg 'size'
            if ($null -ne $mirror) {
                $needBytes = [math]::Max(0, $tree.TotalBytes - [long]$mirror.bytes)
                $needFiles = [math]::Max(0, $tree.TotalFiles - [long]$mirror.count)
                Write-Host ("  First full run: ~{0} files / {1} still to upload. Drive creates ~2 files/s (rclone docs), so expect >= {2}." -f $needFiles, (Format-Bytes $needBytes), (Format-Duration ($needFiles / 2)))
                if ($null -ne $about -and $about.PSObject.Properties['free'] -and $needBytes -gt [long]$about.free) {
                    throw "Drive has $(Format-Bytes $about.free) free; this upload needs up to $(Format-Bytes $needBytes). Free up Drive space and run again."
                }
            }
        }

        Write-Host ''
        Write-Step $(if ($DryRun) { 'Previewing: size + MD5 of every file vs Drive' } else { 'Syncing: size + MD5 of every file vs Drive (only new/changed files upload)' })
        $logs = @(Join-Path $logDir "sync_$stamp.jsonl")
        $code = Invoke-RcloneTransfer -Cfg $cfg -Stamp $stamp -LogPath $logs[0] -LiftDeleteLimit $lift -Preview ([bool]$DryRun) -Interactive (-not $NoPause)
        $sum = Read-RcloneRunLog -Paths $logs
        if ($code -eq 7 -and $sum.MaxDeleteHit -and -not $DryRun) {
            Write-Host ''
            Write-Host "DELETE LIMIT: this run wants to remove more than $($cfg.MaxDeletePerRun) files from the mirror." -ForegroundColor Red
            Write-Host "rclone stopped there; the $($cfg.MaxDeletePerRun) already removed sit in $($cfg.VersionsFolder)/$stamp." -ForegroundColor Yellow
            if (Confirm-Typed "Type YES to finish (the rest also goes to $($cfg.VersionsFolder)/$stamp); anything else stops") {
                $logs += Join-Path $logDir "sync_${stamp}_2.jsonl"
                $code = Invoke-RcloneTransfer -Cfg $cfg -Stamp $stamp -LogPath $logs[-1] -LiftDeleteLimit $true -Preview $false -Interactive (-not $NoPause)
                $sum = Read-RcloneRunLog -Paths $logs
            }
        }

        $ok = $code -eq 0
        Write-Host ''
        $label = if ($DryRun) { @('Would upload (new + changed)', 'Would rename on Drive', 'Would archive old versions') }
        else { @('Uploaded (new + changed)', 'Renamed on Drive (no re-upload)', 'Archived old versions') }
        $rows = @(
            [pscustomobject]@{ Item = $label[0]; Value = "$($sum.Uploaded) files, $(Format-Bytes $sum.UploadedBytes)" }
            [pscustomobject]@{ Item = $label[1]; Value = "$($sum.Renamed)" }
            [pscustomobject]@{ Item = $label[2]; Value = "$($sum.ArchivedChanged) changed + $($sum.ArchivedDeleted) deleted -> $($cfg.VersionsFolder)/$stamp" }
            [pscustomobject]@{ Item = 'Compared with Drive (size + MD5)'; Value = "$($sum.Checked) files" }
            [pscustomobject]@{ Item = 'Links skipped'; Value = "$($sum.LinksSkipped)" }
            [pscustomobject]@{ Item = 'Errors'; Value = "$($sum.Errors)" }
            [pscustomobject]@{ Item = 'rclone time'; Value = (Format-Duration $sum.ElapsedSec) }
            [pscustomobject]@{ Item = 'Log'; Value = ($logs -join ', ') }
        )
        $rows | Show-Table -NoHeader
        if (-not $sum.HaveStats) { Write-Warn 'rclone stopped before writing its final stats; the log above is all there is.' }
        foreach ($e in ($sum.ErrorLines | Select-Object -First 15)) { Write-Host "  ERROR $e" -ForegroundColor Red }
        if ($sum.ErrorLines.Count -gt 15) { Write-Host "  ... $($sum.ErrorLines.Count - 15) more in the log" -ForegroundColor Red }

        if ($ok) {
            if (-not $DryRun) {
                Save-JsonAtomic -Path $stateFile -Object ([ordered]@{
                        SchemaVersion = 1
                        LastSuccess   = [DateTimeOffset]::Now.ToString('yyyy-MM-ddTHH:mm:sszzz', $script:Invariant)
                        RunStamp      = $stamp
                        TotalFiles    = $tree.TotalFiles
                        TotalBytes    = $tree.TotalBytes
                        Buckets       = @($tree.Buckets | Select-Object Name, Files, Bytes)
                    })
                Remove-OldVersionFolders $cfg
                Get-ChildItem -LiteralPath $logDir -Filter 'sync_*.jsonl' -File | Sort-Object LastWriteTime -Descending |
                    Select-Object -Skip ([int]$cfg.LogsKeep) | Remove-Item -Force -ErrorAction SilentlyContinue
            }
            Write-Host $(if ($DryRun) { 'DRY RUN OK: nothing was changed.' } else { "DONE: $mirrorLabel matches $($cfg.LocalPath) (size + MD5)." }) -ForegroundColor Green
        } else {
            $why = if ($script:RcloneExitText.ContainsKey($code)) { $script:RcloneExitText[$code] } else { 'unknown' }
            Write-Host "FAILED: rclone exit $code ($why). Files that did upload are safe; press the button again to continue." -ForegroundColor Red
            if ($cfg.Mode -eq 'mirror') { Write-Host '        On errors rclone skips all deletions, so nothing was removed from the mirror.' -ForegroundColor Red }
        }
        return $code
    } finally {
        Set-KeepAwake $false
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
}

# ---- install / uninstall -----------------------------------------------------------------------
function New-DesktopShortcut {
    param([Parameter(Mandatory)][string]$ScriptPath, [string]$HotkeyText, [string]$Description)
    $pwsh = @(Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
    $pwshExe = if ($pwsh.Count -eq 1) { $pwsh[0] } else { Join-Path $PSHOME 'pwsh.exe' }
    if (-not (Test-Path -LiteralPath $pwshExe)) { throw "pwsh.exe not found (PATH and $PSHOME)." }
    $desktop = [Environment]::GetFolderPath('Desktop')
    if (-not $desktop -or -not (Test-Path -LiteralPath $desktop -PathType Container)) { throw "Desktop folder not found ('$desktop')." }
    $lnkPath = Join-Path $desktop $script:ShortcutName
    $shell = New-Object -ComObject WScript.Shell
    try {
        $lnk = $shell.CreateShortcut($lnkPath)
        $lnk.TargetPath = $pwshExe
        $lnk.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
        $lnk.WorkingDirectory = Split-Path -Parent $ScriptPath
        $lnk.WindowStyle = 1
        $lnk.Description = $Description
        if ($HotkeyText) { $lnk.Hotkey = $HotkeyText }
        $lnk.Save()
    } finally {
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    }
    if (-not (Test-Path -LiteralPath $lnkPath -PathType Leaf)) { throw "Shortcut was not written: $lnkPath" }
    $lnkPath
}

function Invoke-Install {
    if (-not $IsWindows) { throw '-Install is Windows-only (desktop shortcut, Windows rclone build).' }
    $local = if ($LocalPath) { $LocalPath } else { Join-Path $env:USERPROFILE 'Documents\CeDo_Simulator' }
    $local = [System.IO.Path]::GetFullPath($local).TrimEnd('\')
    Write-Step "Checking project folder $local"
    Assert-CeDoProject $local
    Write-Good "CeDo project found (project.godot config/name=""$script:ProjectName"")"

    $dir = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) $script:AppName
    New-Item -ItemType Directory -Path $dir, (Join-Path $dir 'logs'), (Join-Path $dir 'bin') -Force | Out-Null
    $installed = Join-Path $dir "$script:AppName.ps1"
    if ([System.IO.Path]::GetFullPath($PSCommandPath) -ne [System.IO.Path]::GetFullPath($installed)) {
        Copy-Item -LiteralPath $PSCommandPath -Destination $installed -Force
    }
    Unblock-File -LiteralPath $installed
    Write-Good "Script installed: $installed"

    $exe = Install-PinnedRclone -BinRoot (Join-Path $dir 'bin') -Platform (Get-RclonePlatform)
    $conf = Resolve-RcloneConfigPath -PinnedExe $exe -Explicit $RcloneConfigPath
    Write-Good "rclone config: $conf"

    $cfgPath = Join-Path $dir 'config.json'
    $prev = $null
    if (Test-Path -LiteralPath $cfgPath -PathType Leaf) {
        try { $prev = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json } catch { Write-Warn "Old config.json unreadable, replacing it." }
    }
    $label = if ($DriveFolderId -eq $script:DefaultFolderId) { $script:DefaultFolderLabel } else { "Drive folder id $DriveFolderId" }
    $mirrorFolder = Split-Path -Leaf $local
    $versionsFolder = "${mirrorFolder}_versions"
    $preferred = if ($null -ne $prev -and $prev.PSObject.Properties['Remote']) { [string]$prev.Remote } else { '' }
    $remote = Select-DriveRemote -Exe $exe -ConfigPath $conf -FolderId $DriveFolderId -MirrorFolder $mirrorFolder `
        -Explicit $RemoteName -Preferred $preferred -FolderLabel $label
    $r = Invoke-RcloneCapture -Exe $exe -Arguments @('mkdir', (Get-DriveSpec $remote $DriveFolderId $versionsFolder), '--config', $conf, '--ask-password=false')
    if ($r.Code -ne 0) { throw "Could not create $label/$versionsFolder (exit $($r.Code)): $(Get-LastLines $r.Err)" }
    Write-Good "Drive folders ready: $label/$mirrorFolder and $label/$versionsFolder"

    $cfg = [ordered]@{
        SchemaVersion           = 1
        LocalPath               = $local
        RcloneExe               = $exe
        RcloneConfigPath        = $conf
        Remote                  = $remote
        DriveFolderId           = $DriveFolderId
        DriveFolderLabel        = $label
        MirrorFolder            = $mirrorFolder
        VersionsFolder          = $versionsFolder
        Mode                    = 'mirror'   # or 'add-only': never delete on Drive
        ExcludeGitDirs          = $true
        MaxDeletePerRun         = 100
        ShrinkGuardMinFiles     = 20
        ShrinkGuardMaxLossRatio = 0.5
        VersionsKeepDays        = 30         # 0 = keep every version folder forever
        LogsKeep                = 60
    }
    if ($null -ne $prev) {
        foreach ($k in 'Mode', 'ExcludeGitDirs', 'MaxDeletePerRun', 'ShrinkGuardMinFiles', 'ShrinkGuardMaxLossRatio', 'VersionsKeepDays', 'LogsKeep') {
            if ($prev.PSObject.Properties[$k]) { $cfg[$k] = $prev.$k }
        }
    }
    Save-JsonAtomic -Object $cfg -Path $cfgPath
    Write-Good "Config written: $cfgPath"

    $lnk = New-DesktopShortcut -ScriptPath $installed -HotkeyText $Hotkey `
        -Description "Mirror $local to Google Drive ($label/$mirrorFolder), hash-checked"
    Write-Good "Desktop shortcut: $lnk$(if ($Hotkey) { "  (hotkey $Hotkey)" })"
    Write-Host ''
    Write-Host "Ready. Double-click 'CeDo - Sync to Drive' on the desktop. The first run uploads everything; later runs only new/changed files." -ForegroundColor Green
}

function Invoke-Uninstall {
    $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) $script:ShortcutName
    if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force; Write-Good "Removed $lnk" }
    $dir = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) $script:AppName
    if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force; Write-Good "Removed $dir" }
    Write-Host 'Left alone: the Drive folders and the rclone remote in rclone.conf.'
}

# ---- entry point (skipped when dot-sourced) ----------------------------------------------------
if ($MyInvocation.InvocationName -ne '.') {
    $prevEncoding = [Console]::OutputEncoding
    $exitCode = 1
    try {
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)   # rclone prints UTF-8
        switch ($PSCmdlet.ParameterSetName) {
            'Install' { Invoke-Install; $exitCode = 0 }
            'Uninstall' { Invoke-Uninstall; $exitCode = 0 }
            default { $exitCode = [int]@(Invoke-Sync)[-1] }
        }
    } catch {
        Write-Host ''
        Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  (line $($_.InvocationInfo.ScriptLineNumber) of $($_.InvocationInfo.ScriptName))" -ForegroundColor DarkGray
        $exitCode = 1
    } finally {
        [Console]::OutputEncoding = $prevEncoding
    }
    if ($PSCmdlet.ParameterSetName -eq 'Sync' -and -not $NoPause) { [void](Read-Host 'Press Enter to close') }
    exit $exitCode
}
