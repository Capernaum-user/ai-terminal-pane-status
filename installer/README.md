# AI 터미널 패널 상태 시스템 — 설치 번들

분할 터미널(Windows Terminal)에서 여러 AI CLI(claude·codex·gemini)를 띄워 작업할 때,
**각 패널이 "어느 폴더에서 · 무슨 작업을 · 작업중/대기인지"** 를 한눈에 보여주는 도구 모음입니다.

- **Claude 하단 상태줄** — `📁 폴더절대경로 · 🌿 git브랜치 · 모델 · +추가/-삭제 · mm:ss · ctx N% · 요청작업명(최대 12자)`
  - 둘째 줄(Pro/Max): `5h [████░░░░░░] 38% ↻2h13m   7d [█░░░░░░░░░] 19% ↻3d` 사용량 배터리
- **`aistatus` 상태창** — 모든 AI 세션의 🟡작업중 / 🟢대기 / 🔴확인 을 실시간 표로
  - Windows Terminal: **Alt+Shift+S** 로 하단에 즉시, 또는 설치 시 `-AutoStatusPane` 로 부팅 자동
- **AI 자동 라벨** — 작업을 시작하면 AI가 그 패널 작업명을 스스로 정함(`label "..."`로 수동 변경)
- (선택) **`zwork`** — Zellij 4분할 + 패널 프레임 색 라벨

---

## 요구사항

| 항목 | 필수 | 비고 |
|---|---|---|
| Windows + Windows Terminal | ✅ | UTF-8 콘솔 권장 |
| PowerShell 7 (`pwsh`, PATH 등록) | ✅ | `winget install Microsoft.PowerShell` |
| Claude Code CLI | ✅ | |
| Zellij 0.44+ / codex / gemini | 선택 | |

---

## 설치 (원클릭)

**단일파일** 받았으면:
```powershell
pwsh -ExecutionPolicy Bypass -File .\Install-AiPaneStatus.ps1
```
**폴더 번들**이면:
```powershell
pwsh -ExecutionPolicy Bypass -File .\install.ps1
```

- 옵션: `-AutoStatusPane`(WT 부팅 시 하단 상태창 자동) · `-NoZellij`(Zellij 건너뜀) · `-Uninstall`(되돌리기).
- **안전**: `settings.json` 의 hooks 는 **기존 보존 병합**. `statusLine`·`$PROFILE`·`CLAUDE.md`·Zellij·**WT 설정** 은 최초 1회 `.bak` 백업 후 적용.
- **이식성**: 경로는 자동 적응(공백 포함 경로도 따옴표 처리). 여러 번 실행해도 안전(멱등).

> 함수(`aistatus` 등)가 안 보이면: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.

설치 위치: `~\.local\bin\pane-workspace.ps1`, `~\.claude\hooks\{pane-status,claude-statusline,ai-dashboard}.ps1`, `~\.claude\settings.json`(hooks+statusLine), `~\.claude\CLAUDE.md`(라벨 규칙), (선택) Zellij·Windows Terminal 설정.

---

## 사용

1. **새 PowerShell 창**(또는 `. $PROFILE`).
2. **새 claude 세션**부터 하단 상태줄 + 자동 라벨.
3. 상태창: **Alt+Shift+S** (또는 부팅 자동).

```powershell
aistatus            # 모든 AI 세션 작업중/대기 실시간 표 (Ctrl+C 종료)
wshelp              # 전체 명령 도움말
label "결제 버그"    # 이 패널 작업명 수동 지정
zwork channeldock   # (Zellij) 4분할 색 라벨
```

---

## codex / gemini 도 상태창에 표시 (선택)

같은 `pane-status.ps1` 재사용. `<홈>` = `$env:USERPROFILE` 의 슬래시 경로(예 `C:/Users/이름`). **공백 있으면 큰따옴표 필수.**

- **codex** — `~\.codex\config.toml` 끝에 추가 후, 새 codex 세션에서 `/hooks` 신뢰 1회:
  ```toml
  [[hooks.UserPromptSubmit]]
  [[hooks.UserPromptSubmit.hooks]]
  type = "command"
  command = "pwsh -NoProfile -ExecutionPolicy Bypass -File \"<홈>/.claude/hooks/pane-status.ps1\" -Hook -State working -Tool codex"
  timeout = 10
  # Stop→idle, SessionStart(matcher \"startup|resume|clear|compact\")→start, PermissionRequest(matcher \".*\")→attention
  ```
- **gemini** — `~\.gemini\settings.json` 의 `"hooks"` 에 병합(재시작):
  ```json
  "BeforeAgent": [ { "matcher": "*", "hooks": [ { "type": "command", "command": "pwsh -NoProfile -ExecutionPolicy Bypass -File \"<홈>/.claude/hooks/pane-status.ps1\" -Hook -State working -Tool gemini", "timeout": 10000 } ] } ],
  "AfterAgent":  [ { "matcher": "*", "hooks": [ { "type": "command", "command": "pwsh -NoProfile -ExecutionPolicy Bypass -File \"<홈>/.claude/hooks/pane-status.ps1\" -Hook -State idle -Tool gemini", "timeout": 10000 } ] } ]
  ```

---

## 제거

```powershell
pwsh -ExecutionPolicy Bypass -File .\Install-AiPaneStatus.ps1 -Uninstall
```
스크립트 삭제 + settings.json/$PROFILE/CLAUDE.md/WT설정 에서 본 도구가 넣은 부분만 제거(다른 설정 보존). `.bak-paneinstall` 백업은 보존.

---

## 환경변수(선택)
- `PANE_STATUS_PATH=leaf|home|full` — 상태줄 폴더 표기(기본 full).
- `PANE_STATUS_TINT=1` — Zellij 작업중 패널 배경 틴트.
