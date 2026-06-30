# =====================================================================
#  AI 분할 워크스페이스 헬퍼  (pane / work / zwork)
#  생성: 2026-06-28  ·  $PROFILE 에서 dot-source 됨
#  목적: 4분할 패널마다 "어떤 폴더에서 어떤 작업"인지 라벨을 붙인다.
#    - work  : Windows Terminal 네이티브 4분할 (탭 색상 + 패널별 고정 제목)
#    - zwork : Zellij 4분할 (패널 프레임에 제목 = 진짜 "소제목줄")
#    - pane  : 현재 패널 라벨 변경 (zellij/tmux/WT 자동 감지)
#  기존 tmux용 title/tt/aititle 함수와 충돌하지 않음 (이름이 다름).
# =====================================================================

# --- 내부 유틸 --------------------------------------------------------

function ConvertTo-Rgb {
    param([string]$Hex)
    $h = $Hex.TrimStart('#')
    $r = [Convert]::ToInt32($h.Substring(0, 2), 16)
    $g = [Convert]::ToInt32($h.Substring(2, 2), 16)
    $b = [Convert]::ToInt32($h.Substring(4, 2), 16)
    "$r;$g;$b"
}

function Get-ProjectColor {
    # 프로젝트 이름 -> 항상 같은 색 (탭 색상 일관성 유지)
    param([string]$Name)
    $palette = @('#1f6feb', '#238636', '#8957e5', '#da3633', '#bf8700', '#1f9ede', '#db61a2', '#3fb950')
    $sum = 0
    foreach ($c in $Name.ToLower().ToCharArray()) { $sum += [int]$c }
    $palette[$sum % $palette.Count]
}

function Resolve-ProjectDir {
    # 'channeldock' 같은 짧은 입력 -> D:\01_Projects\01_ChannelDock 전체 경로
    param([string]$Query)
    $root = 'D:\01_Projects'
    if (-not (Test-Path $root)) { return $null }
    $dirs = Get-ChildItem $root -Directory
    $m = $dirs | Where-Object { $_.Name -ieq $Query } | Select-Object -First 1
    if (-not $m) { $m = $dirs | Where-Object { ($_.Name -replace '^\d+_', '') -ieq $Query } | Select-Object -First 1 }
    if (-not $m) { $m = $dirs | Where-Object { $_.Name -ilike "*$Query*" } | Select-Object -First 1 }
    if ($m) { return $m.FullName }
    $null
}

function Show-PaneBanner {
    # 패널이 열릴 때 1회 출력되는 라벨 (스크롤되면 사라지지만 시작 표식 역할)
    param([string]$Project, [string]$Role, [string]$Color = '#1f6feb')
    $e = [char]27
    $rgb = ConvertTo-Rgb $Color
    Write-Host ""
    Write-Host ("{0}[48;2;{1}m{0}[1;97m  {2} . {3}  {0}[0m" -f $e, $rgb, $Project, $Role)
    Write-Host ("{0}[38;2;{1}m  > {0}[0m{0}[90m{2}{0}[0m" -f $e, $rgb, (Get-Location).Path)
    Write-Host ""
}

# --- 공개 명령 --------------------------------------------------------

function pane {
    # 현재 패널의 '작업 요약' 라벨을 수동으로 지정. 환경 자동 감지(zellij/tmux/WT).
    #   AI 작업중/대기 색(🟡/🟢/🔴)은 Claude hook 이 자동으로 갱신 — 여기선 작업 요약 텍스트만 바꿈.
    #   상태 스크립트(pane-status.ps1)를 그대로 호출해 hook 과 동일 로직/저장소를 공유.
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Label)
    $text = ($Label -join ' ').Trim()
    $statusScript = Join-Path $env:USERPROFILE '.claude\hooks\pane-status.ps1'
    if (-not (Test-Path $statusScript)) { Write-Host "상태 스크립트 없음: $statusScript" -ForegroundColor Red; return }
    if (-not $text) { Write-Host 'Usage: pane "현재 작업 설명"' -ForegroundColor Yellow; return }
    pwsh -NoProfile -File $statusScript -State idle -Tool '' -Label $text
    Write-Host "  pane: $text" -ForegroundColor Green
    if (-not $env:ZELLIJ -and -not $env:TMUX) {
        Write-Host "  (순수 WT는 statusline/상태창에 표시 / 패널 색은 zwork=Zellij에서)" -ForegroundColor DarkGray
    }
}

function label {
    # 이 패널의 작업 라벨을 직접 지정(= pane). statusline·상태창에 고정 표시.
    pane @args
}

function panedemo {
    # AI 재시작 없이 상태색을 눈으로 확인 — 현재 패널 제목을 🟢→🟡→🔴→🟢 으로 순환.
    $s = Join-Path $env:USERPROFILE '.claude\hooks\pane-status.ps1'
    if (-not (Test-Path $s)) { Write-Host "상태 스크립트 없음: $s" -ForegroundColor Red; return }
    if (-not $env:ZELLIJ -and -not $env:TMUX) {
        Write-Host "※ 색 프레임은 zellij/tmux 패널에서 보입니다. 순수 WT면 포커스된 탭 제목만 바뀝니다." -ForegroundColor Yellow
    }
    $steps = @(
        @{ State = 'start'; Task = '데모 준비'; Label = '🟢 대기' },
        @{ State = 'working'; Task = 'AI가 생각하는 중(데모)'; Label = '🟡 작업 중' },
        @{ State = 'attention'; Task = '확인 필요(데모)'; Label = '🔴 확인 필요' },
        @{ State = 'idle'; Task = '완료 — 대기(데모)'; Label = '🟢 대기' }
    )
    foreach ($st in $steps) {
        pwsh -NoProfile -File $s -State $st.State -Tool claude -Task $st.Task
        Write-Host ("  → 지금 제목/색: " + $st.Label) -ForegroundColor Cyan
        Start-Sleep -Seconds 2
    }
    Write-Host "데모 끝. 실제로는 claude/codex/gemini 활동에 따라 이게 자동으로 바뀝니다." -ForegroundColor Green
}

function aistatus {
    # 모든 AI 세션의 작업중/대기/확인 상태창(대시보드). 분할 화면 한 칸에 띄워두면 됨.
    param([int]$Interval = 2, [switch]$Once)
    $d = Join-Path $env:USERPROFILE '.claude\hooks\ai-dashboard.ps1'
    if (-not (Test-Path $d)) { Write-Host "대시보드 없음: $d" -ForegroundColor Red; return }
    if ($Once) { & $d -IntervalSec $Interval -Once } else { & $d -IntervalSec $Interval }
}

function work {
    # Windows Terminal 네이티브 4분할 탭 열기 (탭 색상 + 패널별 고정 제목)
    #   work channeldock
    #   work guesthouse -Roles claude,codex,shell
    #   work mark -NewWindow
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][string]$Project,
        [string[]]$Roles = @('claude', 'codex', 'gemini', 'shell'),
        [switch]$NewWindow
    )
    $dir = Resolve-ProjectDir $Project
    if (-not $dir) {
        Write-Host "프로젝트를 못 찾음: $Project" -ForegroundColor Red
        Write-Host "후보:" -ForegroundColor DarkGray
        (Get-ChildItem 'D:\01_Projects' -Directory).Name -replace '^\d+_', '' | Sort-Object | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
        return
    }
    $name = (Split-Path -Leaf $dir) -replace '^\d+_', ''   # 숫자 접두사 제거(표시용)
    $color = Get-ProjectColor $name
    if ($Roles.Count -lt 1) { $Roles = @('shell') }
    $Roles = $Roles | Select-Object -First 4

    $enc = {
        param($p, $r, $c)
        [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("Show-PaneBanner -Project '$p' -Role '$r' -Color '$c'"))
    }

    $a = [System.Collections.Generic.List[string]]::new()
    if (-not $NewWindow) { $a.AddRange([string[]]@('-w', '0')) }

    # 패널0 (좌상)
    $a.AddRange([string[]]@('new-tab', '--title', "$name.$($Roles[0])", '--tabColor', $color, '--suppressApplicationTitle', '-d', $dir, 'pwsh', '-NoExit', '-EncodedCommand', (& $enc $name $Roles[0] $color)))
    if ($Roles.Count -ge 2) {
        # 패널1 (우상)
        $a.Add(';'); $a.AddRange([string[]]@('split-pane', '-V', '--title', "$name.$($Roles[1])", '--suppressApplicationTitle', '-d', $dir, 'pwsh', '-NoExit', '-EncodedCommand', (& $enc $name $Roles[1] $color)))
    }
    if ($Roles.Count -ge 3) {
        $a.Add(';'); $a.AddRange([string[]]@('move-focus', 'left'))
        # 패널2 (좌하)
        $a.Add(';'); $a.AddRange([string[]]@('split-pane', '-H', '--title', "$name.$($Roles[2])", '--suppressApplicationTitle', '-d', $dir, 'pwsh', '-NoExit', '-EncodedCommand', (& $enc $name $Roles[2] $color)))
    }
    if ($Roles.Count -ge 4) {
        $a.Add(';'); $a.AddRange([string[]]@('move-focus', 'right'))
        # 패널3 (우하)
        $a.Add(';'); $a.AddRange([string[]]@('split-pane', '-H', '--title', "$name.$($Roles[3])", '--suppressApplicationTitle', '-d', $dir, 'pwsh', '-NoExit', '-EncodedCommand', (& $enc $name $Roles[3] $color)))
    }

    & wt @a
    Write-Host "  work: $name  ($color)  ->  $($Roles -join ' | ')" -ForegroundColor Green
}

function zwork {
    # Zellij 4분할 세션 열기 (패널 프레임에 제목 = 네 개 라벨 동시 표시)
    #   zwork channeldock
    #   세션 재접속:  zellij attach <세션명>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true, Position = 0)][string]$Project)
    $dir = Resolve-ProjectDir $Project
    if (-not $dir) { Write-Host "프로젝트를 못 찾음: $Project" -ForegroundColor Red; return }
    $name = (Split-Path -Leaf $dir) -replace '^\d+_', ''   # 숫자 접두사 제거(표시용)
    $layout = Join-Path $env:APPDATA 'Zellij\config\layouts\ai4.kdl'
    if (-not (Test-Path $layout)) { Write-Host "레이아웃 없음: $layout" -ForegroundColor Red; return }
    $session = ($name -replace '[^A-Za-z0-9_-]', '-').Trim('-').ToLower()
    if (-not $session) { $session = 'ws' }
    Push-Location $dir
    try {
        Write-Host "  zellij 세션 '$session'  @ $dir" -ForegroundColor Green
        & zellij --session $session --layout $layout
    }
    finally { Pop-Location }
}

function wshelp {
    Write-Host @"

  AI 분할 워크스페이스 명령
  ---------------------------------------------------------------
  work <프로젝트> [-Roles a,b,c,d] [-NewWindow]
        Windows Terminal 4분할 탭 (탭 색상 + 패널별 고정 제목 · 정적)
  zwork <프로젝트>
        Zellij 4분할 세션 (프레임마다 제목 + AI 상태색 · 동적 권장)
  label "작업명"  (= pane "작업명")
        이 패널 작업 라벨 직접 지정 → statusline·상태창에 고정 표시(AI 자동 명명 덮어쓰기)
  panedemo
        (AI 재시작 없이) 현재 패널 제목을 🟢→🟡→🔴→🟢 순환해 색 확인
  aistatus
        모든 AI 세션의 작업중/대기 상태창(분할 한 칸에 띄워두면 실시간 표시)
  wshelp
        이 도움말
  ---------------------------------------------------------------
  AI 상태색(자동): 🟡 작업중 · 🟢 대기 · 🔴 확인필요
     Claude hook 이 제목 앞 신호등을 자동 갱신(zwork=Zellij에서 동작).
     강한 배경틴트도 원하면:  $env:PANE_STATUS_TINT='1'
  예) zwork channeldock      work guesthouse      pane "인증 버그 수정"

"@ -ForegroundColor Cyan
}

# --- 탭 자동완성 (work / zwork 의 프로젝트 이름) ----------------------
$wsProjectCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $root = 'D:\01_Projects'
    if (Test-Path $root) {
        Get-ChildItem $root -Directory |
            ForEach-Object { ($_.Name -replace '^\d+_', '') } |
            Where-Object { $_ -ilike "*$wordToComplete*" } | Sort-Object |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    }
}
Register-ArgumentCompleter -CommandName work, zwork -ParameterName Project -ScriptBlock $wsProjectCompleter
