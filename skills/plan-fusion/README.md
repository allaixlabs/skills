# plan-fusion

**Claude = 두뇌(분석·계획·검증·사실확인), 여러 AI 모델 패밀리 CLI = 손, 합성 = Judge·Synthesizer CLI** — "GPT·Gemini·GLM·Kimi로 각각 풀고 Opus가 판정·GPT가 종합해" 류 **CLI Fusion** 요청을 표준 워크플로우로 패키징한 Claude Code 스킬.

> 핵심 전제: 참가자 CLI들은 Claude의 대화 컨텍스트를 모른다. 위임 품질은 **자기완결 HANDOFF**가, 교차검증 가치는 **서로 다른 모델 패밀리**가 결정한다.
> CLI 사용법은 추정이 아니라 **codex 0.139.0 · opencode 1.16.2 · omo 4.10.0 · agy 1.0.8 · claude 2.1.x 실측**으로 검증했다(agy `--print` 헤드리스 채팅·파일쓰기 스모크 통과 포함).

## 존재 이유 (한 줄)

단일 위임도, Claude가 직접 종합하는 단순 교차검증도 아니라 — **서로 다른 모델 5개(백엔드 4: codex·agy·opencode·claude; GPT·Gemini·GLM·Kimi·Opus)를 각자 CLI로 독립 실행 → Judge CLI가 후보 평가 → Synthesizer CLI가 최종 합성 → Claude가 검증**하는 **CLI Fusion** 구조. 종합 자체를 모델에 위임해 Claude의 단일 관점 편향을 줄이고, Claude는 **실행 증거 기반 검증**에 집중한다.

## plan-codex-opencode와의 차이
아래 비교표의 왼쪽 열은 부모 스킬 `plan-codex-opencode` 설명이다.

| | plan-codex-opencode | **plan-fusion** |
|-|-|-|
| 백엔드 | codex · opencode · omo (2 백엔드) | **+ agy(Gemini) + claude(Opus) = 모델 최대 5 / 백엔드 4** |
| 종합 주체 | **Claude 직접** | **Judge CLI → Synthesizer CLI** 위임 |
| Claude 역할 | 분석·계획·종합·검증 | 분석·계획·**검증·사실확인**(종합 위임) |
| 주 모드 | Council / Pipeline | **Fusion-Research / Fusion-Code** |

종합을 CLI에 위임할 필요가 없으면 plan-codex-opencode가 가볍다. plan-fusion은 **명시적 Judge→Synth 합성 + Gemini/Opus까지 패밀리 확장**이 목적일 때.

## 무엇을 하나

1. **사전 점검** — `scripts/check-fusion.sh`(read-only)로 codex·agy·opencode·claude 가용성 + provider 인증 + `PARTICIPANT_FAMILIES`/`FUSION_CAPABILITY` 확인. 호명 정규화, 없으면 기본 4개 모델(백엔드 3) 패널 추천.
2. **모드 선택** — Fusion-Research(비코드 분석) / Fusion-Code(구현·신뢰도↑).
3. **계획(HANDOFF)** — 모든 참가자가 공유하는 단일 자기완결 스펙.
4. **참가자 위임** — Fusion-Code는 worktree 격리 병렬, Research는 read-only 병렬. 전부 백그라운드 + 참가자별 manifest.
5. **FUSE** — 후보 묶음 → **Judge CLI**(기본 Opus) 평가 → **Synthesizer CLI**(기본 GPT) 합성.
6. **검증·리포트** — Claude가 직접 실행/​grep 증거로 검증(result·final 주장은 근거 아님), loop-md 연동, 근거 보고.

## 모드 가이드

| 모드 | 토폴로지 | 언제 |
|---|---|---|
| **Fusion-Research** | 동일 질문 → N 패밀리 read-only → Judge → Synth → Claude 사실확인 | 분석·리서치·설계 '정리'(비코드) |
| **Fusion-Code** | 동일 HANDOFF → N 패밀리 격리 병렬 → 교차리뷰·Judge → Synth 합성지시 → 백엔드 구현 → Claude 검증 | 답 갈릴 수 있는 구현, 신뢰도↑ |

## 패널·라우팅 가이드

| 호명 | 백엔드 | 모델 경로 |
|---|---|---|
| codex / gpt5.5 [xhigh] | `codex exec` | `gpt-5.5` (기본 Synthesizer) |
| gemini / "gemini pro" / flash | `agy --print` | `"Gemini 3.1 Pro (High)"` · `"Gemini 3.5 Flash (Medium)"` |
| opus / claude | `claude --print` | `opus` (기본 Judge) |
| glm5.2 / kimi k2.7 / deepseek … | opencode (omo/직접) | `zai-coding-plan/glm-5.2` · `opencode-go/kimi-k2.7-code` |

- **기본 패널**(호명 없을 때): GPT+Gemini+GLM+Kimi 4개 모델(백엔드 3) · Judge=Opus · Synth=GPT. 프리셋 highEnd/codeSecurity/fullPower/budget는 `references/routing-fusion.md`.
- ⚠️ **Gemini 모델명은 실측 문자열**(`gemini-3.5-pro`는 없음 — 실재는 3.1 Pro / 3.5 Flash). **Opus 4.8은 `claude` 직접 호출**.
- ⚠️ **동족 경고**: 오케스트레이터가 Opus라 Opus를 참가자+Judge로 쓰면 독립성↓ — 기본은 Opus=Judge 전용.

## 전제조건

> **검증 환경(실측)**: codex 0.139.0 · opencode 1.16.2 · omo 4.10.0 · agy 1.0.8 · claude 2.1.x.

- **codex CLI** ≥ 0.139 (`exec review`) + `codex login` — 참가자(GPT) + 기본 Synthesizer.
- **agy (Antigravity CLI)** — Gemini 참가자. `agy models`로 인증·모델 확인. (Google이 Gemini CLI를 Antigravity로 전환)
- **claude CLI** — 기본 Judge(Opus). 오케스트레이터 자신과 동족이라 참가자로는 신중히.
- **opencode** ≥ 1.4 + 프로바이더 인증, **oh-my-openagent** ≥ 4.9(omo run 경로) — GLM/Kimi/DeepSeek 등.

> ⚠️ **비용·시간**: N참가자 + Judge 1 + Synth 1 = 단일 위임의 N+2배 이상. 고추론 5패밀리 fullPower는 수십 분 단위 → 백그라운드 + 완료 알림으로 관리. 단순 위임이면 plan-then-*가 더 가볍다.

사전 점검:
```bash
bash scripts/check-fusion.sh
# CODEX/AGY/OPENCODE/CLAUDE_BACKEND_READY · PARTICIPANT_FAMILIES · FUSION_CAPABILITY 출력
```
참가자 백엔드 2개 이상이어야 Fusion 성립(1개뿐이면 교차검증 독립성 없음 → plan-then-*).

## 설치

```bash
git clone https://github.com/allaixlabs/skills.git ~/project/skills   # 이미 있으면 생략
ln -s ~/project/skills/skills/plan-fusion ~/.claude/skills/plan-fusion
```
새 Claude Code 세션부터 자동 인식. **참가자 쪽 별도 설치 불필요** — HANDOFF가 stdin/인자로 전달되는 Claude Code 단독 오케스트레이션이다.

## 사용법

자연어 트리거:
```
이 설계를 GPT, Gemini, GLM, Kimi로 각각 검토시키고 Opus가 판정·GPT가 종합해서 정리해줘
agy로 gemini도 패널에 넣어서 fusion으로 이 버그 원인 교차검증해
이 기능을 4개 모델로 구현시키고 Judge·Synthesizer로 제일 나은 합성을 만들어
```
명시 호출: `/plan-fusion <작업 내용>`

## loop-md 연동

루트에 `loop.md`가 있으면 VERIFY에서 loop-md Verify 모드(①Pass/Fail·②정량·③정성). **③정성의 독립 검증자를 Judge·교차리뷰로 자연 충족**. 없으면 N/A.

## 구조

```
plan-fusion/
├── SKILL.md                          # 0~5단계 Fusion 오케스트레이션(참가자→Judge→Synth→검증) (메인)
├── README.md                         # 이 문서
├── references/
│   ├── routing-fusion.md             # 호명→백엔드(+agy/claude) · 프리셋 · disabledModels · 동족경고
│   ├── cli-fusion-map.md             # 5-백엔드 실행 매트릭스 + agy·claude 상세(실측)
│   ├── codex-cli.md                  # codex exec — 참가자+Synth+exec review(교차리뷰)
│   ├── opencode-cli.md               # omo run + opencode run 직접 · session 추출
│   └── fusion.md                     # 격리 · 참가자 위임 · Judge→Synth 프로토콜 · 위험표
├── templates/
│   ├── HANDOFF.md.tmpl               # 코드 참가자 지시서(단일 공유 스펙)
│   ├── HANDOFF-research.md.tmpl      # 비코드 read-only 분석 브리프
│   ├── fusion-judge.md.tmpl          # Judge CLI 프롬프트(최강후보/합의/충돌/위험주장)
│   ├── fusion-synth.md.tmpl          # Synthesizer CLI 프롬프트(후보+judge→최종)
│   └── synthesis.md.tmpl             # Claude의 Fusion 기록(Judge판정+Synth출력+검증증거)
└── scripts/
    ├── check-fusion.sh               # codex+agy+opencode+claude 점검 + 인증 매트릭스 (read-only)
    └── council-worktrees.sh          # worktree setup/cleanup/adopt 헬퍼 (cd 기반 — 전 백엔드 호환)
```
