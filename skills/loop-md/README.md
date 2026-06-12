# loop-md

작업을 "완료"로 선언하기 전, **3단계 완료 기준(Definition of Done)** 을 강제하는 에이전트 프레임워크.
AI가 눈앞의 Task에만 매몰되어 전체 맥락·완료 기준을 잃는 것을 막는 **감독관(`loop.md`)** 패턴을 패키징했다.

> **듀얼 포맷** — Claude Code(스킬)와 Codex/기타 에이전트(`AGENTS.md`)에서 **같은 `loop.md`** 로 동작한다.

## 무엇을 하나

- **Setup 모드**: 프로젝트 스택을 자동 감지(Node·TS·Rust·Python·Go·Make)해 빌드/타입/테스트/린트 명령이 채워진 `loop.md`를 생성. 참조 문서 스텁·감시 루프 가이드·Codex 어댑터는 선택.
- **Verify 모드**: "완료" 선언 직전 3단계 검증을 강제.
  - **① Pass/Fail 게이트** — 실제 실행 + **exit code·로그·시각 증거 필수**(증거 없는 ✅ = FAIL)
  - **② 정량 측정** — 커버리지·번들 크기·에러율
  - **③ 정성 평가** — 1~5점. **독립 서브에이전트 채점 권장**(자기 출력 자기비판 취약성 회피 — `loop.md`+diff+로그만 제공), 불가 시 자기평가 + 감점 **근거+액션 필수**
- **연속 학습 루프**: FAIL마다 검증된 원인을 `docs/loop-md/lessons.md`에 규칙으로 증류(distill — git 추적이라 **워크트리 간 공유**·히스토리 보존), 다음 검증이 먼저 읽음(consult). 증류는 `chore(loop): lesson` **전용 커밋으로 즉시 분리**(작업 커밋에 안 섞임 — 가드가 docs/loop-md/ 전용 커밋은 면제). 동일 게이트 **연속 3회 실패 시 루프 중단**·사용자 보고.
- **R&R 가드레일**: AI 자동 처리 vs 인간 승인 경계. 자가치유 푸시는 코드로 집행(브랜치 화이트리스트 + 민감경로 diff 검사).

## 설치

### npx skills (권장)
```bash
npx skills add allaixlabs/skills --skill loop-md
```

### Claude Code (수동 설치)
```bash
git clone https://github.com/allaixlabs/skills.git ~/project/skills
ln -s ~/project/skills/skills/loop-md ~/.claude/skills/loop-md   # 심볼릭 링크 권장 (원본만 관리)
```
새 세션에서 `/loop-md` 호출. (description 트리거로 "DoD 루프 세팅", "완료 전 검증" 등으로도 작동.)

### Codex CLI / 기타 에이전트
Codex는 **`AGENTS.md`** 만 읽는다(스킬 자동 인식은 Claude 전용). 두 가지 방식:
- **글로벌 (권장)**: `~/.codex/AGENTS.md` 에 `dod-guard` 블록 1회 → **모든 프로젝트의 Codex 자동 적용**. Claude 글로벌(`~/.claude/CLAUDE.md`)과 대칭. `/loop-md` Setup 6번이 양쪽을 함께 확인·설정한다.
- **프로젝트별**: `cp templates/AGENTS.md.tmpl <프로젝트>/AGENTS.md` (Setup의 'Codex 어댑터' 선택지가 자동 수행)

Codex는 `loop.md`가 없으면 `~/.claude/skills/loop-md/scripts/detect-stack.sh`로 **직접 부트스트랩**도 가능 — Setup·Verify를 Claude 없이 단독 수행한다. (단 `loop.md`를 써야 하므로 **쓰기 가능 샌드박스 실행**이 전제다. read-only 실행에서는 감지·검증만 가능.)

## 옵트인: hard 가드 (커밋 차단)

soft 가드(글로벌 지시)로 부족하면 **커밋 시점에 강제**한다. 같은 스크립트가 두 모드를 지원한다:

**① Claude PreToolUse hook** — `~/.claude/settings.json` 의 `hooks.PreToolUse` 배열에 추가
(`git commit --no-verify` 도 명령 문자열 검사라서 잡는다):
```json
{ "matcher": "Bash", "hooks": [
  { "type": "command", "command": "bash \"/Users/<you>/.claude/skills/loop-md/scripts/precommit-guard.sh\"", "timeout": 5 } ] }
```

**② git pre-commit hook (에이전트 불문)** — Codex·Claude·사람 누구든 셸 `git commit` 시 발동
(Codex exec에서도 발동·차단됨을 실측 확인. 단 `--no-verify`는 git hook을 건너뛰므로 ①과 병행 권장):
```bash
printf '#!/bin/sh\nexec bash ~/.claude/skills/loop-md/scripts/precommit-guard.sh --git-hook\n' > .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

가드가 검사하는 것: 마커 존재 → **마커 HEAD = 현재 HEAD**(브랜치 전환/rebase 후 stale 마커 차단) →
**부분 스테이징 없음**(커밋 내용=검증 내용 보장) → 마커 이후 추적 소스 무변경(mtime, lockfile 포함).
- Verify 통과 시 마커에 검증 시점 HEAD가 기록되어 커밋이 허용된다.
- **우회**(자가치유·긴급): 커밋 메시지에 `[skip-loop]` 또는 `LOOP_SKIP=1` — 우회는 `.loop/bypass.log`에 감사 기록된다.
- 위협 모델: **부주의한 완료 선언 차단**이다. 리포트는 수동 규약이므로 악의적 증거 위조까지 기계적으로 막지는 않는다(자동 runner는 후속 과제).

## 구조

```
loop-md/
├── SKILL.md                # Claude Code 오케스트레이션 (Setup/Verify 분기)
├── reference/
│   ├── DOD.md              # 3단계 검증 상세 + 리포트 예시
│   ├── RNR.md              # AI 자동 vs 인간 승인 경계표 + 가드레일
│   └── WATCH-LOOP.md       # CI 폴링·자가치유(가드 포함)·리뷰반영
├── templates/
│   ├── loop.md.tmpl        # 감독관 DoD 문서 (체크포인트/롤백 포함)
│   ├── report.md.tmpl      # 실행 증거 강제 리포트 포맷
│   ├── AGENTS.md.tmpl      # Codex/에이전트 공통 지침 어댑터
│   └── *.stub.md           # PRD·유저플로우·UI·DB 참조 스텁
└── scripts/
    ├── detect-stack.sh     # 스택 자동 감지 (read-only, MANIFEST_PATHS·monorepo 경고)
    └── precommit-guard.sh  # hard 커밋 가드 (Claude PreToolUse / git pre-commit 듀얼 모드)
```

## 핵심 원칙

- Pass/Fail 게이트에 **타협 없음** — 하나라도 실패하면 완료 아님, 롤백.
- 정성 평가는 점수만으로 끝내지 않는다 — 감점엔 반드시 근거+액션.
- 인간 승인 영역(스키마·인증·결제·마이그레이션)은 **절대 자동 커밋하지 않는다**.
