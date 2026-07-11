# plan-codex-opencode

**Claude = 두뇌(분석·계획·패널선택·종합·검증), 여러 AI 모델 패밀리 = 손** — "codex랑 glm5.2, kimi k2.7 같은 여러 AI와 대화하여 정리해" 류 요청을 표준 워크플로우로 패키징한 Claude Code 스킬.

> 핵심 전제: 패널 모델들은 Claude의 대화 컨텍스트를 모른다. 위임 품질은 **자기완결적 HANDOFF**가 결정하고, 교차검증 가치는 **서로 다른 모델 패밀리**에서 나온다.
> CLI 사용법은 추정이 아니라 **codex-cli 0.139.0 · opencode 1.16.2 · omo 4.10.0 실측**(`exec review`, `opencode run` 직접 경로, worktree 격리, provider 인증 매트릭스)으로 검증했다.

## 존재 이유 (한 줄)

단일 모델 위임이 아니라, **서로 다른 모델 패밀리(GPT·GLM·Kimi·DeepSeek 등)를 패널로 묶어 Council(병렬 교차검증) 또는 Pipeline(구현→타모델 리뷰→종합)으로 돌리고, Claude가 합의·충돌·고유통찰을 종합**한다. `codex`와 `opencode`는 다른 패밀리라 같은 문제에서 다른 실수를 한다 → **교차검증 독립성이 구조적으로 보장**된다.

## 무엇을 하나

1. **사전 점검 + 파싱** — `scripts/check-panels.sh`(read-only)로 codex·opencode 두 백엔드 가용성 + provider 인증 매트릭스 확인. "codex·glm5.2·kimi" 호명을 `(backend, model, effort, dir 플래그)`로 정규화. 호명 없으면 **교차검증 독립성 기준 기본 패널** 추천.
2. **모드 선택** — Council(다양성) / Pipeline(검증깊이) / Council-Research(비코드 분석)를 작업 유형으로 분기.
3. **계획(HANDOFF)** — 모든 패널이 공유하는 **단일 자기완결 스펙** 작성(Baseline·Out-of-scope·BLOCKED·Acceptance Criteria).
4. **위임** — Council은 **git worktree 격리** 병렬, Pipeline은 구현→리뷰→수정 순차. 백그라운드 병렬 + 패널별 manifest + **능동 폴링(수동 대기 금지)**.
5. **종합** — 패널별 diff/답변 비교 → **교차리뷰**(`codex exec review`로 다른 패밀리가 리뷰) → 합의/충돌/고유통찰 + 판정 근거를 `synthesis.md`로. 코드면 채택/합성을 `apply --3way` 단일 시도로 메인 반영하고, 실패 시 `APPLY_CONFLICT`로 표면화해 수동 머지한다(plain `git apply` 재시도 없음).
6. **검증·리포트** — 직접 실행 증거로 검증(result 주장은 근거 아님), loop-md 연동, 패널·모드·근거 보고.

## 모드 가이드

| 모드 | 토폴로지 | 언제 |
|---|---|---|
| **Council-Code** | 동일 HANDOFF → N개 모델 격리 병렬 → 비교·교차리뷰·채택/합성 | 답이 갈릴 수 있는 구현, 신뢰도↑ |
| **Council-Research** | 동일 질문 → N개 모델 read-only 병렬 → 합의/충돌/고유통찰 종합 | 분석·리서치·설계 '정리'(비코드) |
| **Pipeline** | 구현(모델 A) → 리뷰(`codex exec review`/모델 B) → 수정 → 종합 | 범위 명확, 구현 품질 검증 깊이 |

## 패널·라우팅 가이드

| 사용자 호명 | 백엔드 | 모델 경로 |
|---|---|---|
| codex / gpt5.5 [xhigh] | `codex exec` | `gpt-5.6-sol` |
| glm5.2 | opencode (omo/직접) | `zai-coding-plan/glm-5.2` |
| kimi k2.7 | opencode | `opencode-go/kimi-k2.7-code` |
| deepseek / qwen / minimax / opus … | opencode | `opencode-go/…` · `dgrid/claude-opus-4-8` |

- **백엔드 선택**: 구현(쓰기) → `omo run`(Sisyphus 완수보장), 리뷰·분석(읽기·단발) → `opencode run` 직접. codex는 항상 `codex exec`.
- **기본 패널**(호명 없을 때): codex `gpt-5.6-sol` + `zai-coding-plan/glm-5.2`(2-패널), 고난도면 +`kimi-k2.7-code`. 동일 패밀리 조합 금지.
- 전체 라우팅·플래그 차이는 `references/routing.md` 참조.

## 전제조건

> **검증 환경(실측)**: codex-cli 0.139.0 · opencode 1.16.2 · omo 4.10.0 — CLI 플래그는 이 환경에서 확인했다. 아래는 동작을 기대하는 **최소 버전**이다.

- **codex CLI** ≥ 0.139 (`npm install -g @openai/codex`) + `codex login` — `exec review`(교차리뷰)가 0.139 신설이라 이게 최소.
- **opencode** ≥ 1.4 (`npm install -g opencode`) + 프로바이더 인증(`opencode providers login`). 단 `--variant` 등 일부 플래그는 1.16+ 실측이며, 1.4~1.15는 플래그 미지원 가능.
- **oh-my-openagent** ≥ 4.9 (omo run 경로용): `bunx oh-my-openagent install`, 별칭은 `npm i -g oh-my-openagent` (⚠️ `bunx omo`/`npx omo` 금지)

> ⚠️ **비용·시간**: N개 패밀리를 고추론으로 병렬 위임하면 토큰·시간이 단일 위임의 N배 이상이다. 3-패널 xhigh는 수십 분 단위가 될 수 있고 omo run은 자체 타임아웃이 없다 → 백그라운드 + 완료 알림으로 관리하고, 단순 위임이면 plan-then-codex/opencode가 더 가볍다.

사전 점검(read-only):
```bash
bash scripts/check-panels.sh
# CODEX_BACKEND_READY / OPENCODE_BACKEND_READY / PROVIDER_* / PANEL_CAPABILITY 출력
```
2개 백엔드가 이상적이지만, 1개 백엔드라도 그 안의 여러 모델(예: glm+kimi)로 council 가능.

## 설치

```bash
npx skills add allaixlabs/skills --skill plan-codex-opencode   # 권장
```

수동 설치:
```bash
git clone https://github.com/allaixlabs/skills.git ~/project/skills   # 이미 있으면 생략
ln -s ~/project/skills/skills/plan-codex-opencode ~/.claude/skills/plan-codex-opencode
```

새 Claude Code 세션부터 자동 인식된다. **패널 쪽 별도 설치 불필요** — HANDOFF가 stdin/인자로 전달되는 Claude Code 단독 오케스트레이션이다.

## 사용법

자연어 트리거:
```
이 기능을 codex랑 glm5.2, kimi k2.7로 각각 구현시키고 비교해서 제일 나은 걸로 정리해
이 아키텍처 설계를 codex·glm·kimi에 검토시키고 정리해줘
구현은 omo glm으로, 리뷰는 codex로 돌려서 종합해
여러 AI와 대화해서 이 버그 원인을 교차검증해
```

명시 호출: `/plan-codex-opencode <작업 내용>`

## 다른 스킬과의 선택 기준

| | plan-then-codex | plan-then-opencode | **plan-codex-opencode** |
|-|-|-|-|
| 모델 수 | 1 (codex) | 1 (omo 에이전트) | **2~3+ 패밀리 패널** |
| 목적 | 단일 위임 | 단일 위임 | **교차검증·다양성·종합** |
| 토폴로지 | 위임→검증 | 위임→검증 | **Council / Pipeline** |
| 격리 | workspace-write | 풀 파일시스템 | **Council-Code=패널별 worktree / Council-Research=읽기전용 사본** |

단일 모델로 충분하면 위 두 선행 스킬을 쓴다. 이 스킬은 **여러 모델 패밀리를 함께 돌릴 때**의 오케스트레이션이다.

## loop-md 연동

루트에 `loop.md`가 있으면 **완료 결과를 사용자에게 먼저 보고한 뒤** loop-md Verify 모드(①Pass/Fail·②정량·③정성)를 별도로 수행한다(완료 보고 지연 방지). **③정성의 독립 검증자를 council 교차리뷰로 자연 충족**한다. 없으면 N/A.

## 구조

```
plan-codex-opencode/
├── SKILL.md                          # 0~5단계 오케스트레이션 + 모드 분기 (메인)
├── README.md                         # 이 문서
├── references/
│   ├── routing.md                    # 호명→백엔드 라우팅 테이블 · effort/variant · 기본 패널 로직
│   ├── codex-cli.md                  # codex exec 실측 — exec review(교차리뷰)·read-only·resume·manifest
│   ├── opencode-cli.md               # omo run + opencode run 직접 경로 · session 추출 · 비코드 read-only
│   └── council.md                    # worktree 격리 · 교차리뷰 · 종합(synthesis) 프로토콜 · 위험표
├── templates/
│   ├── HANDOFF.md.tmpl               # 코드 멀티모델 지시서(단일 공유 스펙)
│   ├── HANDOFF-research.md.tmpl      # 비코드 read-only 분석 브리프
│   └── synthesis.md.tmpl             # 합의/충돌/고유통찰/판정+근거 종합
└── scripts/
    ├── check-panels.sh               # codex+opencode+omo 통합 점검 + provider 인증 매트릭스 (read-only)
    └── council-worktrees.sh          # worktree setup/cleanup/adopt 헬퍼 (누수 방지 · dry-run 자가점검 내장)
```
