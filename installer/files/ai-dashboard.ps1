# =====================================================================
#  ai-dashboard.ps1  —  모든 AI 세션의 작업중/대기/확인 상태를 실시간 표로
#  hook 들이 기록한 상태 파일(%TEMP%\claude-pane-status\*.json)을 주기적으로 읽어 표시.
#  순수 Windows Terminal 에서도 동작(멀티플렉서 불필요). 한 칸을 이 창에 할당해 띄워두면 됨.
#  사용:  aistatus            (2초마다 갱신, Ctrl+C 종료)
#         aistatus -Interval 1
#         ai-dashboard.ps1 -Once   (한 번만 출력)
#  생성: 2026-06-28
# =====================================================================
param(
    [int]$IntervalSec = 2,
    [int]$StaleMin = 30,     # 이보다 오래 갱신 없는 세션은 숨김
    [switch]$Once
)
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$ErrorActionPreference = 'SilentlyContinue'

$store = Join-Path $env:TEMP 'claude-pane-status'
$dot = @{ working = ([char]0xD83D + [char]0xDFE1); idle = ([char]0xD83D + [char]0xDFE2); attention = ([char]0xD83D + [char]0xDD34); start = ([char]0xD83D + [char]0xDFE2) }
$lbl = @{ working = '작업중'; idle = '대기  '; attention = '확인! '; start = '대기  ' }

function Show-Once {
    $now = Get-Date
    $rows = @()
    if (Test-Path $store) {
        Get-ChildItem $store -Filter '*.json' -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $r = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
                $ts = [datetime]::Parse($r.ts)
                $age = ($now - $ts).TotalMinutes
                if ($age -le $StaleMin) {
                    $rows += [pscustomobject]@{ ts = $ts; age = $age; state = "$($r.state)"; tool = "$($r.tool)"; dir = "$($r.dir)"; task = "$(if ($r.label) { $r.label } else { $r.task })" }
                }
            }
            catch {}
        }
    }
    if (-not $Once) { Clear-Host }
    Write-Host (" AI 작업 현황    " + $now.ToString('HH:mm:ss') + "    (갱신 ${IntervalSec}s · Ctrl+C 종료)") -ForegroundColor Cyan
    Write-Host (" " + ('─' * 66)) -ForegroundColor DarkGray
    if (-not $rows) {
        Write-Host "  활성 세션 없음." -ForegroundColor DarkGray
        Write-Host "  claude/codex/gemini 를 실행하고 프롬프트를 보내면 여기 떠요." -ForegroundColor DarkGray
        return
    }
    # 작업중 먼저, 그다음 최신순
    foreach ($row in ($rows | Sort-Object @{e = { $_.state -ne 'working' } }, @{e = { $_.ts }; Descending = $true })) {
        $d = $dot[$row.state]; if (-not $d) { $d = '⚪' }
        $l = $lbl[$row.state]; if (-not $l) { $l = $row.state }
        $name = Split-Path -Leaf $row.dir
        $tool = if ($row.tool) { $row.tool } else { '-' }
        $age = if ($row.age -lt 1) { '방금' } elseif ($row.age -lt 60) { ('{0}분전' -f [int]$row.age) } else { '오래' }
        $col = switch ($row.state) { 'working' { 'Yellow' } 'attention' { 'Red' } default { 'Green' } }
        Write-Host ("  {0} {1}  {2,-8} {3,-6} {4}" -f $d, $l, $tool, $age, $name) -ForegroundColor $col
        if ($row.task) { Write-Host ("           ↳ " + $row.task) -ForegroundColor Gray }
        Write-Host ("           " + $row.dir) -ForegroundColor DarkGray
    }
}

if ($Once) { Show-Once; return }
try { while ($true) { Show-Once; Start-Sleep -Seconds $IntervalSec } }
catch { }
