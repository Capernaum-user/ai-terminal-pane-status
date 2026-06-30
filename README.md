# AI Terminal Pane Status

> Windows Terminal을 여러 칸으로 쪼개 **claude·codex·gemini를 동시에** 돌릴 때, 각 패널이 **"어느 폴더에서 · 무슨 작업을 · 작업중/대기인지"** 를 한눈에 보여주는 도구.

여러 AI를 동시에 부리다 보면 검은 창들이 다 비슷해서 어느 칸이 무슨 일인지 헷갈립니다. 이 도구는 각 패널에 **폴더·git브랜치·요청작업명**을 붙이고, 모든 세션의 **🟡작업중 / 🟢대기 / 🔴확인** 을 실시간 상태창으로 보여줍니다. 순수 Windows Terminal에서 동작하고, **단일 파일로 원클릭 설치**됩니다.

---

## 미리보기

**Claude 하단 상태줄** (각 패널 자동)
```
📁 D:\01_Projects\01_ChannelDock · 🌿 audit-fixes · Opus 4.8 · +12/-3 · 05:21 · ctx 42% · 인증 흐름 리팩…
5h [████░░░░░░] 38% ↻2h13m   7d [█████████░] 86% ↻4d21h
```

**상태창 `aistatus`** (분할 한 칸에 띄워둠 / Windows Terminal은 `Alt+Shift+S`)
```
 AI 작업 현황    17:23:50
 ──────────────────────────────────────────────
  🟡 작업중  claude   방금    01_ChannelDock   ↳ 인증 흐름 리팩터
  🟢 대기    codex    1분전   01_ChannelDock   ↳ 결제 테스트
  🔴 확인!   gemini   방금    03_Guesthouse    ↳ 스키마 리서치
```

---

## 설치 (원클릭)

**PowerShell 7**에서 [`Install-AiPaneStatus.ps1`](Install-AiPaneStatus.ps1) 하나만 받아 실행:

```powershell
pwsh -ExecutionPolicy Bypass -File .\Install-AiPaneStatus.ps1
```

또는 한 줄로:
```powershell
$u='https://raw.githubusercontent.com/Capernaum-user/ai-terminal-pane-status/main/Install-AiPaneStatus.ps1'
$f="$env:TEMP\Install-AiPaneStatus.ps1"; irm $u -OutFile $f; pwsh -ExecutionPolicy Bypass -File $f
```

옵션: `-AutoStatusPane`(WT 부팅 시 상태창 자동) · `-NoZellij` · `-Uninstall`(되돌리기).

> **새 PowerShell 창**과 **새 claude 세션**부터 적용됩니다. 함수가 안 보이면: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.

---

## 기능

| 기능 | 설명 |
|---|---|
| **상태줄** | 각 claude 패널 하단에 `📁폴더 · 🌿브랜치 · 모델 · +/-라인 · 시간 · ctx% · 요청작업명(12자)` |
| **사용량 배터리** | Pro/Max: 5시간·7일 한도를 칸 막대 + 초기화까지 남은 시간 |
| **상태창 `aistatus`** | 모든 AI 세션의 🟡작업중/🟢대기/🔴확인 실시간 표 (2초 폴링) |
| **AI 자동 라벨** | 작업 시작 시 AI가 작업명을 스스로 기록(`label "..."`로 수동 변경) |
| **Windows Terminal 통합** | `Alt+Shift+S` 상태창 분할, `-AutoStatusPane`로 부팅 자동 |
| **Zellij(선택)** | `zwork`로 4분할 + 패널 프레임 색 라벨 |
| **claude·codex·gemini** | 세 도구 모두 같은 상태창에 표시(아래 참고) |

---

## 사용법

```powershell
aistatus            # 상태창 (Ctrl+C 종료) — WT는 Alt+Shift+S
wshelp              # 전체 명령 도움말
label "결제 버그"    # 이 패널 작업명 수동 지정
zwork channeldock   # (Zellij) 4분할 색 라벨
```

---

## 동작 원리

```
[claude/codex/gemini] ──hook(작업시작/끝/확인)──▶ pane-status.ps1
        │                                              │ 상태·폴더·작업명을 파일에 기록
        │                                              ▼
        │                          %TEMP%\claude-pane-status\<패널키>.json
        │                                              │ 2초 폴링
        ▼                                              ▼
 claude statusLine ──(.git/HEAD + 사용량)──▶ 하단 2줄        ai-dashboard.ps1 (aistatus) ──▶ 상태창 표
```
같은 패널의 모든 프로세스가 공유하는 키(`WT_SESSION`/`ZELLIJ_PANE_ID`)로 묶어, AI가 기록한 작업명을 상태줄이 정확히 같은 패널에서 읽습니다.

---

## codex / gemini 연동 (선택)

같은 `pane-status.ps1`을 재사용합니다. 자세한 설정은 [`installer/README.md`](installer/README.md) 참고.

## 요구사항

Windows + Windows Terminal + **PowerShell 7**(`pwsh`) + Claude Code. (선택: Zellij 0.44+, codex, gemini)

## 제거

```powershell
pwsh -ExecutionPolicy Bypass -File .\Install-AiPaneStatus.ps1 -Uninstall
```
설치 시 변경한 부분만 제거하고, 기존 설정은 `.bak-paneinstall` 백업으로 보존합니다.

## 라이선스

MIT — [LICENSE](LICENSE)
