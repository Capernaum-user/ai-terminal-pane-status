# =====================================================================
#  pane-status.ps1  —  AI 패널 상태(작업중/대기/확인) + 폴더 + 작업요약 표시
#  생성: 2026-06-28
#  호출처:
#    1) Claude/Codex/Gemini hook  (stdin 으로 JSON 받음)  예) ... -State working -Tool claude
#    2) 수동 pane "..." 명령        (-Task "내용" 으로 직접)
#  설계 원칙:
#    - stdout 에 절대 출력 안 함(UserPromptSubmit/SessionStart hook stdout 은 AI 컨텍스트로 들어감)
#    - 어떤 환경/오류에서도 throw 안 하고 조용히 exit 0
#    - 색 신호 = 제목의 이모지 신호등(🟡🟢🔴). zellij 면 rename-pane, tmux 면 border, 그 외엔 OSC(터미널 직접일 때만)
# =====================================================================
[CmdletBinding()]
param(
    [ValidateSet('working', 'idle', 'attention', 'start', 'end')][string]$State = 'idle',
    [string]$Tool = 'claude',
    [string]$Task = '',
    [string]$Label = '',   # 안정적 작업 라벨(AI 자동 명명 / 수동). task 와 별개로 유지
    [switch]$Hook   # hook(파이프로 JSON 투입)일 때만 지정 → stdin 읽음. 수동 호출은 미지정(블로킹 방지)
)
$ErrorActionPreference = 'SilentlyContinue'
try {
    # --- hook 모드면 stdin JSON 읽기 (수동 호출이면 절대 안 읽음 → 멈춤 방지) ---
    $cwd = $null; $prompt = $null; $sid = $null
    if ($Hook -and [Console]::IsInputRedirected) {
        $raw = [Console]::In.ReadToEnd()
        if ($raw) {
            $j = $raw | ConvertFrom-Json
            $cwd = $j.cwd; $prompt = $j.prompt; $sid = $j.session_id
        }
    }
    if (-not $cwd) { $cwd = (Get-Location).Path }
    # 폴더 표시 모드(환경변수 PANE_STATUS_PATH): full=절대경로(기본) · leaf=폴더명만 · home=홈을 ~로
    $pathMode = $env:PANE_STATUS_PATH; if (-not $pathMode) { $pathMode = 'full' }
    switch ($pathMode) {
        'leaf' { $folder = (Split-Path -Leaf $cwd) -replace '^\d+_', '' }
        'home' { $folder = if ($env:USERPROFILE) { $cwd -replace [regex]::Escape($env:USERPROFILE), '~' } else { $cwd } }
        default { $folder = $cwd }   # full: 실행된 폴더의 절대경로 그대로
    }

    # --- 세션별 레코드 키 (같은 패널의 hook/statusline/AI-도구호출/수동 pane 이 공유) ---
    $key = $env:ZELLIJ_PANE_ID
    if (-not $key) { $key = $env:TMUX_PANE }
    if (-not $key) { $key = $env:WT_SESSION }     # 순수 Windows Terminal: 같은 패널 모든 프로세스가 공유
    if (-not $key) { $key = $sid }
    if (-not $key) { $key = 'default' }
    $key = ($key -replace '[^A-Za-z0-9_-]', '')
    $store = Join-Path $env:TEMP 'claude-pane-status'
    [void][IO.Directory]::CreateDirectory($store)
    $recFile = Join-Path $store "$key.json"

    # 세션 종료(SessionEnd) → 레코드 삭제 후 종료
    if ($State -eq 'end') { Remove-Item -LiteralPath $recFile -ErrorAction SilentlyContinue; exit 0 }

    # 기존 레코드 로드
    $rec = $null
    if (Test-Path $recFile) { try { $rec = Get-Content -LiteralPath $recFile -Raw | ConvertFrom-Json } catch {} }

    # 작업요약(task): 자동 폴백. 수동 -Task > 프롬프트 자동추출 > 기존값
    if ($Task) { $taskText = $Task.Trim() }
    elseif ($State -eq 'working' -and $prompt) {
        # 시스템 주입 블록(<task-notification>/<system-reminder>/<command-...> 등) 제거 후 사용자 텍스트만
        $p = [regex]::Replace($prompt, '(?s)<[^>]+>.*?</[^>]+>', ' ')
        $p = [regex]::Replace($p, '(?s)<[^>]+>', ' ')
        $p = ($p -replace '\s+', ' ').Trim()
        if ($p) {
            if ($p.Length -gt 38) { $p = $p.Substring(0, 38) + '…' }
            $taskText = $p
        }
        elseif ($rec -and $rec.task) { $taskText = [string]$rec.task }   # 정제 후 비면 기존 유지
        else { $taskText = '' }
    }
    elseif ($rec -and $rec.task) { $taskText = [string]$rec.task }
    else { $taskText = '' }

    # 라벨(label): 안정적 표시명. 수동/AI -Label > 기존값. (task 와 별개 유지)
    if ($Label) { $labelText = $Label.Trim() }
    elseif ($rec -and $rec.label) { $labelText = [string]$rec.label }
    else { $labelText = '' }

    # 표시명 = 라벨 우선, 없으면 작업요약
    $displayText = if ($labelText) { $labelText } else { $taskText }

    # --- 레코드 저장 (state/tool/dir/task/label/ts) ---
    try {
        ([pscustomobject]@{ state = $State; tool = $Tool; dir = $cwd; task = $taskText; label = $labelText; ts = (Get-Date).ToString('o') }) |
            ConvertTo-Json -Compress | Set-Content -LiteralPath $recFile -Encoding utf8
    } catch {}

    # --- 신호등 + 제목 조립 ---
    $dot = switch ($State) {
        'working' { [char]0xD83D + [char]0xDFE1 }   # 🟡
        'attention' { [char]0xD83D + [char]0xDD34 } # 🔴
        default { [char]0xD83D + [char]0xDFE2 }     # 🟢 (idle/start)
    }
    $parts = @($folder)
    if ($displayText) { $parts += $displayText }
    if ($Tool) { $parts += $Tool }
    $title = "$dot " + ($parts -join ' · ')

    if ($env:PANE_STATUS_DEBUG) { [Console]::Error.WriteLine("PANE_STATUS[$State] => $title") }

    # --- 적용 ---
    if ($env:ZELLIJ) {
        $paneId = $env:ZELLIJ_PANE_ID
        if ($paneId) {
            & zellij action rename-pane --pane-id $paneId $title 2>$null | Out-Null
            if ($env:PANE_STATUS_TINT) {
                $bg = switch ($State) { 'working' { '#231d07' } 'attention' { '#280d12' } default { '#0c0c0c' } }
                & zellij action set-pane-color --pane-id $paneId --bg $bg 2>$null | Out-Null
            }
        }
        else { & zellij action rename-pane $title 2>$null | Out-Null }
    }
    elseif ($env:TMUX) {
        $st = switch ($State) { 'working' { 'busy' } 'attention' { 'attn' } default { 'idle' } }
        & tmux set -p '@ai_state' $st 2>$null | Out-Null
        & tmux select-pane -T $title 2>$null | Out-Null
    }
    elseif (-not $Hook) {
        # 순수 WT 등에서 '수동' 호출일 때만 OSC 로 탭 제목(=포커스 패널). hook 모드에선 stdout 이 tty 가 아니라 무의미하므로 생략
        [Console]::Write("$([char]27)]0;$title$([char]7)")
    }
}
catch { }
exit 0
