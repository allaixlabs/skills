# makeskill

에이전트 스킬 소스 모음.

## 스킬

- `loop-md`: 작업을 완료로 선언하기 전 3단계 완료 기준을 강제하는 DoD 프레임워크.
- `cmux-handoff`: `cmux --help` 기반으로 패널 목록 조회, scrollback 캡처, 후속 지시 전송, pane piping을 수행해 멈춘 Claude/Codex 패널 작업을 이어받는 스킬. 상세: [`skills/cmux-handoff/README.md`](skills/cmux-handoff/README.md)
- `plan-then-codex`: Claude가 분석·계획·검증을 맡고 실제 구현은 `codex exec`에 위임하는 split-brain 워크플로우. "분석은 claude, 구현은 codex gpt5.5 xhigh" 류 요청 전용. 상세: [`skills/plan-then-codex/README.md`](skills/plan-then-codex/README.md)
- `plan-then-opencode`: Claude가 분석·계획·에이전트 선택·검증을 맡고 실제 구현은 `omo run`(oh-my-openagent)에 위임하는 split-brain 워크플로우. Prometheus·Sisyphus·Hephaestus 에이전트 선택 + 멀티 프로바이더 지원. 상세: [`skills/plan-then-opencode/README.md`](skills/plan-then-opencode/README.md)
- `plan-codex-opencode`: Claude가 분석·계획·패널선택·종합·검증을 맡고, 실제 실행은 **서로 다른 모델 패밀리**(codex/GPT · opencode·omo의 GLM·Kimi 등)에 위임해 **Council(병렬 교차검증)** 또는 **Pipeline(구현→타모델 리뷰→종합)**으로 돌리는 멀티모델 워크플로우. "codex랑 glm5.2, kimi k2.7로 교차검증해서 정리" 류 요청 전용. 상세: [`skills/plan-codex-opencode/README.md`](skills/plan-codex-opencode/README.md)

## loop-md

작업을 "완료"로 선언하기 전 **3단계 완료 기준(Definition of Done)** 을 강제하는 에이전트 프레임워크.
AI가 눈앞의 Task에만 매몰되어 전체 맥락·완료 기준을 잃는 것을 막는 **감독관(`loop.md`)** 패턴.

> **듀얼 포맷** — Claude Code(스킬)와 Codex/기타 에이전트(`AGENTS.md`)에서 **같은 `loop.md`** 로 동작.
> 스킬 상세 문서는 [`skills/loop-md/README.md`](skills/loop-md/README.md).

- **Setup 모드**: 프로젝트 스택을 자동 감지해 빌드/타입/테스트/린트 명령이 채워진 `loop.md`를 생성. 참조 스텁·감시 루프·Codex 어댑터는 선택.
- **Verify 모드**: "완료" 선언 전 3단계 검증 강제 — ① Pass/Fail 게이트(실행 증거 필수) ② 정량 측정 ③ 정성 평가(**독립 서브에이전트 채점 권장**, 불가 시 자기평가+근거·액션).
- **연속 학습 루프**: FAIL마다 검증된 원인을 `docs/loop-md/lessons.md`에 규칙으로 증류(전용 커밋 분리) → 다음 루프가 먼저 읽음. 동일 게이트 연속 3회 실패 시 중단·사용자 보고.
- **hard 가드(옵트인)**: 검증 마커(HEAD 기록) 없는 `git commit` 차단 — Claude PreToolUse + git pre-commit(에이전트 불문) 듀얼 모드.
- **R&R 가드레일**: AI 자동 처리 vs 인간 승인 경계. 자가치유 푸시는 브랜치·민감경로 가드로 코드 집행.

## 설치

### npx skills (권장)
[skills CLI](https://github.com/vercel-labs/skills)로 원하는 스킬만 골라 설치:
```bash
npx skills add allaixlabs/skills --skill loop-md
npx skills add allaixlabs/skills --skill cmux-handoff
npx skills add allaixlabs/skills --skill plan-then-codex
npx skills add allaixlabs/skills --skill plan-then-opencode
npx skills add allaixlabs/skills --skill plan-codex-opencode
npx skills add allaixlabs/skills --skill '*'   # 전부 설치
```
새 세션에서 `/loop-md` 등으로 호출.

### 수동 설치 (Claude Code)
```bash
git clone https://github.com/allaixlabs/skills.git ~/project/skills
ln -s ~/project/skills/skills/loop-md ~/.claude/skills/loop-md   # 심볼릭 링크 권장 (원본만 관리)
```

### Codex CLI / 기타 에이전트
- **글로벌(권장)**: `~/.codex/AGENTS.md`에 `dod-guard` 1회 → 모든 프로젝트의 Codex 자동 적용(Claude 글로벌과 대칭). `/loop-md` Setup이 양쪽 글로벌을 함께 관리.
- **프로젝트별**: Setup의 'Codex 어댑터' 선택 또는 `cp skills/loop-md/templates/AGENTS.md.tmpl <프로젝트>/AGENTS.md`.
Codex는 `loop.md`가 없으면 `detect-stack.sh`로 직접 부트스트랩(Setup+Verify 단독 수행)도 가능하다(쓰기 가능 샌드박스 실행 전제).

## 구조
```
skills/
├── loop-md/
│   ├── SKILL.md                # Claude Code 오케스트레이션 (Setup/Verify)
│   ├── README.md               # 스킬 상세 문서
│   ├── reference/              # DOD · RNR · WATCH-LOOP 상세
│   ├── templates/              # loop.md / report / AGENTS.md / 참조 스텁
│   └── scripts/                # detect-stack.sh(스택 감지) · precommit-guard.sh(hard 커밋 가드 듀얼 모드)
├── cmux-handoff/               # 멈춘 에이전트 패널 읽기·이어받기 — SKILL + README + cmux CLI 실측 노트
├── plan-then-codex/            # Claude 계획 → codex exec 구현 위임 — SKILL + README + HANDOFF 템플릿 + 사전점검
├── plan-then-opencode/         # Claude 계획 → omo run(oh-my-openagent) 위임 — Sisyphus/Hephaestus/Prometheus 에이전트 선택
└── plan-codex-opencode/        # Claude 계획 → 멀티모델 패널(codex+opencode) Council/Pipeline 교차검증 — 라우팅·worktree 격리·종합

```
