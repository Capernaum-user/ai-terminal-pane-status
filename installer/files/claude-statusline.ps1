# =====================================================================
#  claude-statusline.ps1  —  Claude Code 하단 상태줄 (정보 강화판)
#  한 줄에:  📁 폴더(절대경로) · 🌿 git브랜치 · 모델 · +추가/-삭제 · 세션시간 · 컨텍스트%
#  생성 2026-06-28 / 강화 2026-06-28
#  설계: git.exe 안 띄우고 .git/HEAD 직접 읽음(빠름). 어떤 오류에도 폴더만은 출력.
#        폴더 표시 모드: $env:PANE_STATUS_PATH = full(기본,절대경로) | leaf | home
# =====================================================================
$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

# --- git.exe 없이 현재 브랜치 읽기 (.git/HEAD) ---
function Get-GitBranchFast([string]$start) {
    $dir = $start; $git = $null
    while ($dir) {
        $c = Join-Path $dir '.git'
        if (Test-Path -LiteralPath $c) { $git = $c; break }
        $p = Split-Path $dir -Parent
        if (-not $p -or $p -eq $dir) { break }
        $dir = $p
    }
    if (-not $git) { return $null }
    if (Test-Path -LiteralPath $git -PathType Leaf) {
        # .git 이 파일(연결된 worktree/submodule): "gitdir: <경로>"
        $line = [IO.File]::ReadAllText($git).Trim()
        if ($line -notmatch '^gitdir:\s*(.+)$') { return $null }
        $gd = $Matches[1].Trim()
        if (-not [IO.Path]::IsPathRooted($gd)) { $gd = Join-Path $dir $gd }
        $gitDir = [IO.Path]::GetFullPath($gd)
    }
    else { $gitDir = $git }
    $head = Join-Path $gitDir 'HEAD'
    if (-not (Test-Path -LiteralPath $head)) { return $null }
    $h = [IO.File]::ReadAllText($head).Trim()
    if ($h -match '^ref:\s*refs/heads/(.+)$') { return $Matches[1] }
    elseif ($h -match '^[0-9a-fA-F]{7,40}$') { return '(' + $h.Substring(0, 7) + ')' }  # detached -> 짧은 SHA
    else { return $null }
}

$e = [char]27; $R = "$e[0m"
function C([int]$r, [int]$g, [int]$b) { "$e[38;2;$r;$g;${b}m" }
$cDir = C 97 175 239; $cGit = C 198 120 221; $cMod = C 86 182 194
$cAdd = C 152 195 121; $cDel = C 224 108 117; $cTim = C 130 137 151; $cCtx = C 229 192 123; $cLab = C 224 160 90
$sep = "$(C 90 96 110) · $R"
$fIcon = [char]0xD83D + [char]0xDCC1   # 📁
$bIcon = [char]0xD83C + [char]0xDF3F   # 🌿

# --- 레이트리밋 배터리(둘째 줄) 헬퍼 ---
function RlBar([double]$pct) {
    $n = 10; $f = [int][math]::Round($pct / 100 * $n)
    if ($f -lt 0) { $f = 0 } elseif ($f -gt $n) { $f = $n }
    (([char]0x2588).ToString() * $f) + (([char]0x2591).ToString() * ($n - $f))   # █ 채움 / ░ 빈칸
}
function RlColor([double]$pct) { if ($pct -ge 85) { C 224 108 117 } elseif ($pct -ge 60) { C 229 192 123 } else { C 152 195 121 } }
function RlReset([long]$epoch) {
    $s = $epoch - [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if ($s -le 0) { return 'now' }
    $d = [int]($s / 86400); $h = [int](($s % 86400) / 3600); $m = [int](($s % 3600) / 60)
    if ($d -gt 0) { "${d}d${h}h" } elseif ($h -gt 0) { "${h}h${m}m" } else { "${m}m" }
}
function RlExact([long]$epoch) {
    # 한국시간(KST, UTC+9) 정확한 초기화 시각: 2026/07/02 PM 10:00
    ([DateTimeOffset]::FromUnixTimeSeconds($epoch)).ToOffset([TimeSpan]::FromHours(9)).ToString('yyyy/MM/dd tt hh:mm', [Globalization.CultureInfo]::InvariantCulture)
}
function RlSeg([string]$label, $w) {
    $pct = [double]$w.used_percentage
    $rst = if ($null -ne $w.resets_at) { " $cTim" + ([char]0x21BB) + (RlReset ([long]$w.resets_at)) + " (" + (RlExact ([long]$w.resets_at)) + ")$R" } else { '' }
    "$cTim$label$R $(RlColor $pct)[$(RlBar $pct)] $([int][math]::Round($pct))%$R$rst"
}

try {
    $raw = ''
    if ([Console]::IsInputRedirected) { $raw = [Console]::In.ReadToEnd() }
    $j = if ($raw) { $raw | ConvertFrom-Json } else { $null }

    $cwd = $j.workspace.current_dir
    if (-not $cwd) { $cwd = $j.cwd }
    if (-not $cwd) { $cwd = (Get-Location).Path }

    $pathMode = $env:PANE_STATUS_PATH; if (-not $pathMode) { $pathMode = 'full' }
    switch ($pathMode) {
        'leaf' { $folder = Split-Path -Leaf $cwd }
        'home' { $folder = if ($env:USERPROFILE) { $cwd -replace [regex]::Escape($env:USERPROFILE), '~' } else { $cwd } }
        default { $folder = $cwd }
    }

    # 같은 패널 공유 레코드 읽기 (상태 점 + 작업 라벨 공용)
    $lk = $env:ZELLIJ_PANE_ID; if (-not $lk) { $lk = $env:TMUX_PANE }; if (-not $lk) { $lk = $env:WT_SESSION }; if (-not $lk) { $lk = $j.session_id }
    $lr = $null
    if ($lk) {
        $lk = ($lk -replace '[^A-Za-z0-9_-]', '')
        $lrf = Join-Path (Join-Path $env:TEMP 'claude-pane-status') "$lk.json"
        if (Test-Path $lrf) { try { $lr = Get-Content -LiteralPath $lrf -Raw | ConvertFrom-Json } catch { $lr = $null } }
    }

    # 상태 점(폴더명 맨 앞): 🟢 대기중(idle/start) · 🔴 확인요청(attention) · 작업중은 실시간 불가→회색
    $dot = ''
    if ($lr) {
        $ds = switch ("$($lr.state)") {
            'idle' { C 152 195 121 }        # 초록 · 대기중(내 차례)
            'start' { C 152 195 121 }       # 초록 · 새 세션 대기
            'attention' { C 224 108 117 }   # 빨강 · 확인요청
            default { C 90 96 110 }         # 회색 · 작업중/불명(실시간 아님)
        }
        $dot = "$ds" + ([char]0x25CF) + "$R "
    }

    $parts = @("$dot$cDir$fIcon $folder$R")

    $branch = Get-GitBranchFast $cwd
    if ($branch) { $parts += "$cGit$bIcon $branch$R" }

    if ($j.model.display_name) { $parts += "$cMod$($j.model.display_name)$R" }

    $add = [int]($j.cost.total_lines_added); $del = [int]($j.cost.total_lines_removed)
    if ($add -or $del) { $parts += "$cAdd+$add$R/$cDel-$del$R" }

    $ms = [double]($j.cost.total_duration_ms)
    if ($ms -gt 0) {
        $ts = [TimeSpan]::FromMilliseconds($ms)
        $parts += "$cTim$('{0:00}:{1:00}' -f [int]$ts.TotalMinutes, $ts.Seconds)$R"
    }

    $ctx = $j.context_window.used_percentage
    if ($null -ne $ctx) {
        $ci = [int]$ctx
        if ($ci -ge 90) { $cc = C 224 108 117; $warn = ' ' + ([char]0x26A0) + ' /compact!' }        # 빨강 · 급함
        elseif ($ci -ge 80) { $cc = C 224 160 90; $warn = ' ' + ([char]0x26A0) + ' /compact 권장' }   # 주황 · 권장
        else { $cc = $cCtx; $warn = '' }
        $parts += "$cc" + ("ctx {0}%" -f $ci) + $warn + "$R"
    }

    # AI 작업 라벨 (위에서 읽은 $lr 재사용, 최대 12자)
    if ($lr) {
        $lab = if ($lr.label) { $lr.label } elseif ($lr.task) { $lr.task } else { '' }
        if ($lab) {
            if ($lab.Length -gt 12) { $lab = $lab.Substring(0, 12) + '…' }
            $parts += "$cLab$lab$R"
        }
    }

    $line1 = ($parts -join $sep)

    # 둘째 줄: 사용량 배터리 (Pro/Max + 첫 API 응답 후에만 존재)
    $rl = @()
    if ($j.rate_limits) {
        if ($j.rate_limits.five_hour -and $null -ne $j.rate_limits.five_hour.used_percentage) { $rl += (RlSeg '5h' $j.rate_limits.five_hour) }
        if ($j.rate_limits.seven_day -and $null -ne $j.rate_limits.seven_day.used_percentage) { $rl += (RlSeg '7d' $j.rate_limits.seven_day) }
    }
    if ($rl.Count) { [Console]::Out.Write($line1 + "`n" + ($rl -join "   ")) }
    else { [Console]::Out.Write($line1) }
}
catch {
    try { [Console]::Out.Write("$cDir$fIcon $((Get-Location).Path)$R") } catch { [Console]::Out.Write('statusline') }
}
