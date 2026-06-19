# loop-md

작업을 "완료"로 선언하기 전, **3단계 완료 기준(Definition of Done)** 을 강제하는 에이전트 프레임워크.
AI가 눈앞의 Task에만 매몰되어 전체 맥락·완료 기준을 잃는 것을 막는 **감독관(`loop.md`)** 패턴을 패키징했다.

> **멀티 에이전트 포맷** — Claude Code(스킬) · ZCode/opencode · Codex CLI 등 `AGENTS.md` 자동 로드 에이전트에서 **같은 `loop.md`** 로 동작한다.

## 무엇을 하나

- **Setup 모드**: 프로젝트 스택을 자동 감지(Ruby·Node/TS·Python·Go)해 빌드/타입/테스트/린트 명령이 채워진 `loop.md`를 생성. 참조 문서 스텁·감시 루프 가이드·다중 에이전트 어댑터는 선택.
- **Verify 모드**: "완료" 선언 직전 3단계 검증을 강제.
  - **① Pass/Fail 게이트** — 실제 실행 + **exit code·로그·시각 증거 필수**(증거 없는 ✅ = FAIL)
  - **② 정량 측정** — 커버리지·번들 크기·에러율
  - **③ 정성 평가** — 1~5점. **독립 서브에이전트 채점 권장**(자기 출력 자기비판 취약성 회피 — `loop.md`+diff+로그만 제공), 불가 시 자기평가 + 감점 **근거+액션 필수**
- **연속 학습 루프**: FAIL마다 검증된 원인을 `docs/loop-md/lessons.md`에 규칙으로 증류(distill — git 추적이라 **워크트리 간 공유**·히스토리 보존), 다음 검증이 먼저 읽음(consult). 증류는 `chore(loop): lesson` **전용 커밋으로 즉시 분리**(작업 커밋에 안 섞임 — 가드가 docs/loop-md/ 전용 커밋은 면제). 동일 게이트 **연속 3회 실패 시 루프 중단**·사용자 보고.
- **R&R 가드레일**: AI 자동 처리 vs 인간 승인 경계. 자가치유 푸시는 코드로 집행(브랜치 화이트리스트 + 민감경로 diff 검사).

## 지원 에이전트 · 자산 경로

스킬 자산(scripts/templates/reference)은 **실제 설치된 위치**를 사용한다 — `~/.claude/skills/loop-md/` 하드코딩 금지. Setup 0에서 아래 순서로 탐침해 `$SKILL_DIR`을 정한다(첫 존재 경로):

```
~/.claude/skills/loop-md → ~/.zcode/skills/loop-md → ~/.agents/skills/loop-md → ~/.config/opencode/skills/loop-md
```

| 에이전트 | 감지 신호 | 글로벌 지침 파일 | `/loop` 내장 스케줄러 |
|---|---|---|---|
| **Claude Code** | `~/.claude/` 존재 | `~/.claude/CLAUDE.md` | 있음(충돌 주의 — SKILL.md §"`/loop`") |
| **Codex CLI** | `~/.codex/` 존재 | `~/.codex/AGENTS.md` | 없음 |
| **ZCode**(opencode 포크) | `~/.zcode/` 또는 `~/.config/opencode/opencode.json` | `~/.config/opencode/loop-md-guard.md` + `opencode.json` `instructions` 배열 | 미확증(보수적으로 금지 권장) |
| **opencode**(비-ZCode) | `~/.config/opencode/opencode.json` (ZCode 부재) | 〃 (ZCode와 동일) | 미확증 |

> ZCode는 opencode 포크라 `~/.config/opencode/opencode.json`의 `instructions` 배열이 글로벌 지침 로드 메커니즘(실측: ZCode `config.json`이 `opencode.ai/config.json` 스키마 사용). 가드는 별도 파일(`loop-md-guard.md`)로 만들고 그 경로를 배열에 추가한다.

## 설치

### npx skills (권장)
```bash
npx skills add allaixlabs/skills --skill loop-md --agent claude-code   # --agent 생략 시 감지된 모든 에이전트에 설치됨
```

### Claude Code (수동 설치)
```bash
git clone https://github.com/allaixlabs/skills.git ~/project/skills
ln -s ~/project/skills/skills/loop-md ~/.claude/skills/loop-md   # 심볼릭 링크 권장 (원본만 관리)
```
새 세션에서 `/loop-md` 호출. (description 트리거로 "DoD 루프 세팅", "완료 전 검증" 등으로도 작동.)

### ZCode / opencode
ZCode는 opencode 포크라 **스킬 자동 인식 + 글로벌 지침 로드** 메커니즘이 Claude Code와 다르다:
1. **스킬 설치**: `ln -s ~/project/skills/skills/loop-md ~/.zcode/skills/loop-md` (또는 `~/.config/opencode/skills/loop-md`). ZCode 세션에서 `/loop-md` 인식.
2. **글로벌 가드(권장, 1회)**: `~/.config/opencode/loop-md-guard.md` 파일 생성 + `~/.config/opencode/opencode.json`의 `instructions` 배열에 `"loop-md-guard.md"` 추가. `/loop-md` Setup 6이 이를 자동 확인·제안한다(실제 주입은 사용자 승인 후 — 글로벌 설정은 인간 승인 영역).
3. **프로젝트별**: `cp <SKILL_DIR>/templates/AGENTS.md.tmpl <프로젝트>/AGENTS.md` (Setup의 '다중 에이전트 어댑터' 선택지가 자동 수행).

ZCode는 `loop.md`가 없으면 `<SKILL_DIR>/scripts/detect-stack.sh`로 **직접 부트스트랩** 가능 — Setup·Verify를 Claude 없이 단독 수행한다. (단 `loop.md`를 써야 하므로 **쓰기 가능 샌드박스 실행**이 전제. read-only 실행에서는 감지·검증만 가능.)

### Codex CLI / 기타 에이전트
Codex는 **`AGENTS.md`** 만 읽는다(스킬 자동 인식은 Claude/ZCode 전용). 두 가지 방식:
- **글로벌 (권장)**: `~/.codex/AGENTS.md` 에 `dod-guard` 블록 1회 → **모든 프로젝트의 Codex 자동 적용**. `/loop-md` Setup 6이 Claude·Codex·ZCode 세 축을 함께 확인·설정한다.
- **프로젝트별**: `cp <SKILL_DIR>/templates/AGENTS.md.tmpl <프로젝트>/AGENTS.md` (Setup의 '다중 에이전트 어댑터' 선택지가 자동 수행)

Codex는 `loop.md`가 없으면 `<SKILL_DIR>/scripts/detect-stack.sh`로 **직접 부트스트랩**도 가능.

## 옵트인: hard 가드 (커밋 차단)

soft 가드(글로벌 지시)로 부족하면 **커밋 시점에 강제**한다. 같은 스크립트가 세 가지 모드를 지원한다:

**① Claude PreToolUse hook** — `~/.claude/settings.json` 의 `hooks.PreToolUse` 배열에 추가
(`git commit --no-verify` 도 명령 문자열 검사라서 잡는다). **ZCode/opencode는 hook 메커니즘이 다를 수 있어** ② git pre-commit 모드를 우선 쓴다:

JSON은 셸 변수를 확장하지 않으므로 절대 경로가 필요합니다. 먼저 경로를 확인한 뒤 복사하세요(Claude 환경):
```bash
echo "$HOME/.claude/skills/loop-md/scripts/precommit-guard.sh"
```
```json
{ "matcher": "Bash", "hooks": [
  { "type": "command", "command": "bash \"<위 명령 출력값>\"", "timeout": 5 } ] }
```

**② git pre-commit hook (에이전트 불문)** — Codex·ZCode·Claude·사람 누구든 셸 `git commit` 시 발동. **ZCode/opencode 환경의 기본 hard 가드**다:
```bash
SKILL_DIR=$(ls -d ~/.zcode/skills/loop-md ~/.agents/skills/loop-md ~/.config/opencode/skills/loop-md ~/.claude/skills/loop-md 2>/dev/null | head -1)
printf '#!/bin/sh\nexec bash "%s/scripts/precommit-guard.sh" --git-hook\n' "$SKILL_DIR" > .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

**③ git commit-msg hook (② 보완 — `[skip-loop]` 메시지 우회)** — ② pre-commit 은 커밋 메시지를
읽지 못해 `[skip-loop]` 우회가 무력하다. commit-msg hook은 커밋 직전(스테이징 후)에 메시지 파일을
읽으므로 셸 git commit 경로에서 `[skip-loop]` 가 작동한다. ②+③ 동시 설치 권장:
```bash
printf '#!/bin/sh\nexec bash "%s/scripts/precommit-guard.sh" --commit-msg "$1"\n' "$SKILL_DIR" > .git/hooks/commit-msg
chmod +x .git/hooks/commit-msg
```

가드가 검사하는 것: 마커 존재 → **마커 HEAD = 현재 HEAD**(브랜치 전환/rebase 후 stale 마커 차단) →
**부분 스테이징 없음**(커밋 내용=검증 내용 보장) → 마커 이후 추적 소스 무변경(mtime, lockfile 포함).
- Verify 통과 시 마커에 검증 시점 HEAD가 기록되어 커밋이 허용된다.
- **우회**(자가치유·긴급) — 모드별 지원 범위가 다르다:
  - `LOOP_SKIP=1` (환경변수) — **모든 모드**에서 작동.
  - `[skip-loop]` (커밋 메시지) — **① claude-hook · ③ commit-msg 모드**에서만 작동. **② pre-commit 모드는 메시지를 못 읽어 불가** → `LOOP_SKIP=1` 을 쓰거나 ③ commit-msg hook 을 설치.
  - 모든 우회는 `.loop/bypass.log`에 best-effort로 기록된다(기록 실패 시 stderr 경고, 우회는 진행).
- 위협 모델: **부주의한 완료 선언 차단**이다. 리포트는 수동 규약이므로 악의적 증거 위조까지 기계적으로 막지는 않는다(자동 runner는 후속 과제).

## worktree 격리 워크플로우 안에서 쓸 때

**plan-fusion** 등 worktree 격리 워크플로우 안에서 작업하면, 패널 worktree에서 실행한 Verify는 그 worktree의 `.loop/last-verified`만 갱신하고 **메인 작업트리의 마커는 갱신하지 못한다**(격리된 작업트리마다 `.loop/`가 별도). adopt 등으로 결과를 메인에 반영한 뒤, **메인 작업트리에서 Verify를 다시 실행**해야 메인의 `.loop/last-verified` 마커가 현재 HEAD로 갱신되어 hard 가드가 커밋을 허용한다. worktree 내 Verify는 사전검증일 뿐 hard-guard 충족이 아니다.

## 구조

```
loop-md/
├── SKILL.md                # 오케스트레이션 (§0 감지 → Setup/Verify 분기)
├── reference/
│   ├── DOD.md              # 3단계 검증 상세 + 리포트 예시
│   ├── RNR.md              # AI 자동 vs 인간 승인 경계표 + 가드레일
│   └── WATCH-LOOP.md       # CI 폴링·자가치유(가드 포함)·리뷰반영
├── templates/
│   ├── loop.md.tmpl        # 감독관 DoD 문서 (체크포인트/롤백 포함)
│   ├── report.md.tmpl      # 실행 증거 강제 리포트 포맷
│   ├── AGENTS.md.tmpl      # 다중 에이전트(Codex/ZCode/opencode) 공통 지침 어댑터
│   └── *.stub.md           # PRD·유저플로우·UI·DB 참조 스텁
└── scripts/
    ├── detect-stack.sh     # 스택 자동 감지 (read-only, MANIFEST_PATHS·monorepo 경고)
    └── precommit-guard.sh  # hard 커밋 가드 (claude-hook / git pre-commit / git commit-msg 세 모드 — 에이전트 불문)
```

## 핵심 원칙

- Pass/Fail 게이트에 **타협 없음** — 하나라도 실패하면 완료 아님, 롤백.
- 정성 평가는 점수만으로 끝내지 않는다 — 감점엔 반드시 근거+액션.
- 인간 승인 영역(스키마·인증·결제·마이그레이션)은 **절대 자동 커밋하지 않는다**.
