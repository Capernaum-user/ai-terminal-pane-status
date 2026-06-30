<#
====================================================================
  AI 터미널 패널 상태 시스템 — 설치 (배포용 견고판)
  분할 터미널에서 각 패널의 "어느 폴더 · 무슨 작업" 을
  Claude 하단 상태줄 + aistatus 상태창으로 표시.
--------------------------------------------------------------------
  사용:   pwsh -ExecutionPolicy Bypass -File .\install.ps1
  옵션:   -NoZellij        Zellij 설정 건너뜀
          -AutoStatusPane  Windows Terminal 부팅 시 하단 상태창 자동
          -Uninstall       설치 되돌리기(주입 내용 제거, .bak 보존)
  필수: Windows + PowerShell 7(pwsh) + Windows Terminal + Claude Code
  선택: Zellij, codex / gemini (README 참고)
  안전: hooks 는 기존 보존 병합 / statusLine·$PROFILE·CLAUDE.md·Zellij·WT설정 은 최초 1회 .bak 후 적용.
====================================================================
#>
param([switch]$NoZellij, [switch]$AutoStatusPane, [switch]$Uninstall)
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "이 설치기는 PowerShell 7(pwsh)이 필요합니다. 현재: $($PSVersionTable.PSVersion)" -ForegroundColor Yellow
    Write-Host "  → winget install Microsoft.PowerShell  설치 후" -ForegroundColor Yellow
    Write-Host "  → pwsh -ExecutionPolicy Bypass -File .\install.ps1  로 다시 실행" -ForegroundColor Yellow
    return
}

$src = Join-Path $PSScriptRoot 'files'
$h = $env:USERPROFILE
$hs = ($h -replace '\\', '/')
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function BackupOnce($path) { if ((Test-Path $path) -and -not (Test-Path "$path.bak-paneinstall")) { Copy-Item $path "$path.bak-paneinstall" -Force } }
function HookEntry($state) { [pscustomobject]@{ hooks = @([pscustomobject]@{ type = 'command'; command = "pwsh -NoProfile -ExecutionPolicy Bypass -File `"$hs/.claude/hooks/pane-status.ps1`" -Hook -State $state -Tool claude"; timeout = 5 }) } }
$desired = [ordered]@{ UserPromptSubmit = 'working'; Stop = 'idle'; Notification = 'attention'; SessionStart = 'start'; SessionEnd = 'end' }
$scripts = @("$h\.local\bin\pane-workspace.ps1", "$h\.claude\hooks\pane-status.ps1", "$h\.claude\hooks\claude-statusline.ps1", "$h\.claude\hooks\ai-dashboard.ps1")
$paneName = ([char]0xD83D + [char]0xDFE2) + " AI 상태창"
$wtCands = @(
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
    "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
)

# Windows Terminal 에 상태창 프로필 + 단축키(+선택 부팅자동) 등록
function Add-StatusPane([bool]$auto) {
    $wt = $wtCands | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $wt) { Say "  • Windows Terminal 설정 없음 → 상태창 패널 등록 건너뜀" DarkGray; return }
    BackupOnce $wt
    try { $j = Get-Content $wt -Raw | ConvertFrom-Json } catch { Say "  ! WT settings.json 파싱 실패 → 상태창 패널 건너뜀(.bak 보존)" Yellow; return }
    $cmd = "pwsh.exe -NoExit -ExecutionPolicy Bypass -File `"$h\.claude\hooks\ai-dashboard.ps1`""
    if (-not $j.PSObject.Properties['profiles']) { $j | Add-Member profiles ([pscustomobject]@{ list = @() }) -Force }
    if (-not $j.profiles.PSObject.Properties['list']) { $j.profiles | Add-Member list @() -Force }
    $prof = $j.profiles.list | Where-Object { $_.name -eq $paneName }
    if (-not $prof) {
        $np = [pscustomobject]@{ name = $paneName; guid = ("{" + [guid]::NewGuid().ToString() + "}"); commandline = $cmd; icon = ([char]0xD83D + [char]0xDFE2); tabColor = '#0caf60'; suppressApplicationTitle = $true; hidden = $false }
        $j.profiles.list = @($j.profiles.list) + $np
    }
    else { $prof.commandline = $cmd }
    if (-not $j.PSObject.Properties['keybindings']) { $j | Add-Member keybindings @() -Force }
    if (-not ($j.keybindings | Where-Object { $_.keys -eq 'alt+shift+s' })) {
        $kb = [pscustomobject]@{ keys = 'alt+shift+s'; command = [pscustomobject]@{ action = 'splitPane'; split = 'down'; size = 0.25; profile = $paneName } }
        $j.keybindings = @($j.keybindings) + $kb
    }
    if ($auto) { $j | Add-Member startupActions ('new-tab ; split-pane -H -s 0.25 -p "' + $paneName + '" ; move-focus up') -Force }
    $j | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $wt -Encoding utf8
    Say ("  ✓ Windows Terminal: 상태창 프로필 + Alt+Shift+S" + $(if ($auto) { ' + 부팅 자동' } else { '' })) Green
}

# ───────────────────────── 제거 ─────────────────────────
if ($Uninstall) {
    Say "▶ 제거(되돌리기)" Yellow
    foreach ($f in $scripts) { if (Test-Path $f) { Remove-Item $f -Force; Say "  - 삭제 $f" } }
    $sf = "$h\.claude\settings.json"
    if (Test-Path $sf) {
        try {
            $o = Get-Content $sf -Raw | ConvertFrom-Json
            if ($o.PSObject.Properties['hooks']) {
                foreach ($evt in $desired.Keys) {
                    if ($o.hooks.PSObject.Properties[$evt]) {
                        $kept = @(@($o.hooks.$evt) | Where-Object { ($_ | ConvertTo-Json -Depth 12) -notmatch 'pane-status\.ps1' })
                        if ($kept.Count) { $o.hooks | Add-Member -NotePropertyName $evt -NotePropertyValue $kept -Force } else { $o.hooks.PSObject.Properties.Remove($evt) }
                    }
                }
                if (@($o.hooks.PSObject.Properties.Name).Count -eq 0) { $o.PSObject.Properties.Remove('hooks') }
            }
            if ($o.PSObject.Properties['statusLine'] -and "$($o.statusLine.command)" -match 'claude-statusline\.ps1') { $o.PSObject.Properties.Remove('statusLine') }
            $o | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $sf -Encoding utf8
            Say "  - settings.json 에서 본 도구 hooks/statusLine 제거"
        }
        catch { Say "  ! settings.json 자동정리 실패 — .bak-paneinstall 로 수동 복원" Yellow }
    }
    if (Test-Path $PROFILE) {
        $kept = Get-Content -LiteralPath $PROFILE | Where-Object { $_ -notmatch 'pane-workspace\.ps1' -and $_ -notmatch 'AI 분할 워크스페이스 헬퍼' }
        Set-Content -LiteralPath $PROFILE -Value $kept -Encoding utf8
        Say "  - `$PROFILE dot-source 제거"
    }
    $cm = "$h\.claude\CLAUDE.md"
    if (Test-Path $cm) {
        $t = Get-Content -LiteralPath $cm -Raw
        $t = [regex]::Replace($t, "(?s)\r?\n## AI 작업 라벨 — 분할 터미널 패널 표시.*?(?=\r?\n## |\z)", "")
        Set-Content -LiteralPath $cm -Value $t -Encoding utf8
        Say "  - CLAUDE.md 라벨 규칙 제거"
    }
    foreach ($wt in ($wtCands | Where-Object { Test-Path $_ })) {
        try {
            $j = Get-Content $wt -Raw | ConvertFrom-Json
            if ($j.PSObject.Properties['profiles'] -and $j.profiles.PSObject.Properties['list']) { $j.profiles.list = @($j.profiles.list | Where-Object { $_.name -ne $paneName }) }
            if ($j.PSObject.Properties['keybindings']) { $j.keybindings = @($j.keybindings | Where-Object { $_.keys -ne 'alt+shift+s' }) }
            if ($j.PSObject.Properties['startupActions'] -and "$($j.startupActions)" -match 'AI 상태창') { $j.PSObject.Properties.Remove('startupActions') }
            $j | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $wt -Encoding utf8
            Say "  - WT 상태창 프로필/단축키 제거"
        }
        catch {}
    }
    if (Test-Path "$env:TEMP\claude-pane-status") { Remove-Item "$env:TEMP\claude-pane-status" -Recurse -Force }
    Say "✅ 제거 완료. (원본 .bak-paneinstall 백업은 보존)" Green
    return
}

# ───────────────────────── 설치 ─────────────────────────
Say "▶ AI 패널 상태 시스템 설치" Cyan

$map = @{
    'pane-workspace.ps1'    = "$h\.local\bin\pane-workspace.ps1"
    'pane-status.ps1'       = "$h\.claude\hooks\pane-status.ps1"
    'claude-statusline.ps1' = "$h\.claude\hooks\claude-statusline.ps1"
    'ai-dashboard.ps1'      = "$h\.claude\hooks\ai-dashboard.ps1"
}
foreach ($k in $map.Keys) {
    $dest = $map[$k]; New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
    Copy-Item (Join-Path $src $k) $dest -Force
    Say "  ✓ $dest" Green
}

if (-not (Test-Path $PROFILE)) { New-Item -ItemType File -Force $PROFILE | Out-Null }
if (-not (Select-String -LiteralPath $PROFILE -SimpleMatch 'pane-workspace.ps1' -Quiet)) {
    BackupOnce $PROFILE
    Add-Content -LiteralPath $PROFILE -Value "" -Encoding utf8
    Add-Content -LiteralPath $PROFILE -Value "# AI 분할 워크스페이스 헬퍼 (work/zwork/pane/label/panedemo/aistatus/wshelp)" -Encoding utf8
    Add-Content -LiteralPath $PROFILE -Value '. "$env:USERPROFILE\.local\bin\pane-workspace.ps1"' -Encoding utf8
    Say "  ✓ `$PROFILE 에 dot-source 추가" Green
}
else { Say "  • `$PROFILE 이미 설정됨" DarkGray }

$sf = "$h\.claude\settings.json"
New-Item -ItemType Directory -Force (Split-Path $sf) | Out-Null
BackupOnce $sf
$s = if (Test-Path $sf) { try { Get-Content $sf -Raw | ConvertFrom-Json } catch { Say "  ! 기존 settings.json 파싱 실패 → 원본 .bak 보존, 새로 생성" Yellow; [pscustomobject]@{} } } else { [pscustomobject]@{} }
$existing = if ($s.PSObject.Properties['hooks']) { $s.hooks } else { [pscustomobject]@{} }
foreach ($evt in $desired.Keys) {
    $cur = @(); if ($existing.PSObject.Properties[$evt]) { $cur = @($existing.$evt) }
    $cur = @($cur | Where-Object { ($_ | ConvertTo-Json -Depth 12) -notmatch 'pane-status\.ps1' })
    $existing | Add-Member -NotePropertyName $evt -NotePropertyValue (@($cur) + (HookEntry $desired[$evt])) -Force
}
$s | Add-Member -NotePropertyName hooks -NotePropertyValue $existing -Force
if ($s.PSObject.Properties['statusLine'] -and "$($s.statusLine.command)" -notmatch 'claude-statusline\.ps1') { Say "  ! 기존 statusLine 발견 → 교체(원본 .bak 보존)" Yellow }
$s | Add-Member -NotePropertyName statusLine -NotePropertyValue ([pscustomobject]@{ type = 'command'; command = "pwsh -NoProfile -ExecutionPolicy Bypass -File `"$hs/.claude/hooks/claude-statusline.ps1`""; padding = 0 }) -Force
$s | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $sf -Encoding utf8
Say "  ✓ settings.json: hooks 병합(기존 보존) + statusLine" Green

$cm = "$h\.claude\CLAUDE.md"
if (-not (Test-Path $cm) -or -not (Select-String -LiteralPath $cm -SimpleMatch 'AI 작업 라벨 — 분할 터미널' -Quiet)) {
    if (Test-Path $cm) { BackupOnce $cm } else { New-Item -ItemType File -Force $cm | Out-Null }
    $rule = @'

## AI 작업 라벨 — 분할 터미널 패널 표시
새 작업/요청을 시작할 때, 그 작업을 3~6단어로 요약한 라벨을 현재 패널에 1회 기록한다:
    pwsh -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\hooks\pane-status.ps1" -Label "<짧은 작업명>" -Tool claude
- 작업 본질이 바뀌면 갱신. 사소한 후속/되묻기엔 갱신하지 않는다.
- 이 라벨은 Claude statusline(ctx 옆, 최대 12자)과 aistatus 상태창에 표시된다. 사용자가 `label "..."`로 덮어쓸 수 있다.
'@
    Add-Content -LiteralPath $cm -Value $rule -Encoding utf8
    Say "  ✓ CLAUDE.md 에 AI 자동 라벨 규칙 추가" Green
}
else { Say "  • CLAUDE.md 규칙 이미 있음" DarkGray }

if (-not $NoZellij -and (Get-Command zellij -ErrorAction SilentlyContinue)) {
    $zc = Join-Path $env:APPDATA 'Zellij\config'
    New-Item -ItemType Directory -Force (Join-Path $zc 'layouts') | Out-Null
    $zcfg = Join-Path $zc 'config.kdl'
    BackupOnce $zcfg
    Copy-Item (Join-Path $src 'zellij\config.kdl') $zcfg -Force
    Copy-Item (Join-Path $src 'zellij\ai4.kdl') (Join-Path $zc 'layouts\ai4.kdl') -Force
    Say "  ✓ Zellij 설정 설치 (기존 config.kdl 은 .bak)" Green
}
else { Say "  • Zellij 건너뜀(선택)" DarkGray }

Add-StatusPane ([bool]$AutoStatusPane)

Say ""
Say "✅ 설치 완료!" Green
Say "  1) 새 PowerShell 창 → wshelp / aistatus / label `"작업명`"" Gray
Say "  2) 새 claude 세션부터 하단 상태줄(폴더·작업명 12자) 적용" Gray
Say "  3) 상태창: Alt+Shift+S (또는 -AutoStatusPane 로 부팅 자동) — WT 재시작 후" Gray
Say "  4) 함수 안 보이면: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned" Gray
