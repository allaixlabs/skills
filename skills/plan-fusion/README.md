# plan-fusion

**오케스트레이터 = 두뇌(분석·계획·검증·사실확인), 여러 AI 모델 패밀리 CLI = 손, 합성 = Judge·Synthesizer CLI** — "GPT·Gemini·GLM·Kimi로 각각 풀고 Opus가 판정·GPT가 종합해" 류 **CLI Fusion** 요청을 표준 워크플로우로 패키징한 스킬.

> **오케스트레이터 자동감지**: 오케스트레이터는 **ZCode(GLM)·Codex CLI(GPT)·AGY(Gemini)·Claude Code(Opus)** 중 무엇이든 될 수 있다. `check-fusion.sh`가 env `PLAN_FUSION_ORCHESTRATOR=glm|gpt|gemini|claude`(argv 폴백)에서 감지해 `ORCHESTRATOR_FAMILY`로 내보낸다 — **감지된 패밀리는 동족(확증편향) 회피를 위해 참가자·Judge·Synth 후보에서 자동 제외**된다(상세 아래 [오케스트레이터 자동감지](#오케스트레이터-자동감지)).

> 핵심 전제: 참가자 CLI들은 오케스트레이터의 대화 컨텍스트를 모른다. 위임 품질은 **자기완결 HANDOFF**가, 교차검증 가치는 **서로 다른 모델 패밀리**가 결정한다.
> CLI 사용법은 추정이 아니라 **codex 0.139.0 · opencode 1.16.2 · omo 4.10.0 · agy 1.0.10 · claude 2.1.x 실측**으로 검증했다(agy `--print` 헤드리스 채팅·파일쓰기 스모크 통과 포함).

## 존재 이유 (한 줄)

단일 위임도, 오케스트레이터가 직접 종합하는 단순 교차검증도 아니라 — **서로 다른 모델을 각자 CLI로 독립 실행 → Judge CLI가 후보 평가 → Synthesizer CLI가 최종 합성 → 오케스트레이터가 검증**하는 **CLI Fusion** 구조. 지원 범위는 **백엔드 패밀리 4 / 대표 모델 5종**(codex·agy·opencode·claude; GPT·Gemini·GLM·Kimi·Opus)이고("최대 5"는 패밀리 기준 — fullPower처럼 같은 패밀리 다중 variant면 참가자 슬롯은 6까지 늘 수 있음), **기본 패널은 4모델/3백엔드**(GPT·Gemini·GLM·Kimi). 종합 자체를 모델에 위임해 오케스트레이터의 단일 관점 편향을 줄이고, 오케스트레이터는 **실행 증거 기반 검증**에 집중한다.

## plan-codex-opencode와의 차이
아래 비교표의 왼쪽 열은 부모 스킬 `plan-codex-opencode` 설명이다.

| | plan-codex-opencode | **plan-fusion** |
|-|-|-|
| 백엔드 | codex · opencode · omo (2 백엔드) | **+ agy(Gemini) + claude(Opus) = 대표 모델 5종 / 백엔드 4** |
| 종합 주체 | **오케스트레이터 직접** | **Judge CLI → Synthesizer CLI** 위임 |
| 오케스트레이터 역할 | 분석·계획·종합·검증 | 분석·계획·**검증·사실확인**(종합 위임) |
| 주 모드 | Council / Pipeline | **Fusion-Research / Fusion-Code** |

종합을 CLI에 위임할 필요가 없으면 plan-codex-opencode가 가볍다. plan-fusion은 **명시적 Judge→Synth 합성 + Gemini/Opus까지 패밀리 확장**이 목적일 때.

## 무엇을 하나

1. **오케스트레이터 감지**(§0.0) — `PLAN_FUSION_ORCHESTRATOR` env/argv로 오케스트레이터 패밀리 식별 → 동족 패밀리 자동 제거.
2. **사전 점검** — `scripts/check-fusion.sh`(read-only)로 codex·agy·opencode·claude 가용성 + provider 인증 + `ORCHESTRATOR_FAMILY`/`EXCLUDED_FAMILIES`/`PARTICIPANT_FAMILIES`/`FUSION_CAPABILITY` 확인. 호명 정규화, 없으면 비-동족 기본 패널 추천.
3. **모드 선택** — Fusion-Research(비코드 분석) / Fusion-Code(구현·신뢰도↑).
4. **계획(HANDOFF)** — 모든 참가자가 공유하는 단일 자기완결 스펙.
5. **참가자 위임** — Fusion-Code는 worktree 격리 병렬, Research는 read-only 병렬. 백그라운드 병렬 + 참가자별 manifest + **능동 폴링(수동 대기 금지)**.
6. **FUSE** — 후보 묶음 → **Judge CLI**(오케스트레이터 패밀리 회피) 평가 → **Synthesizer CLI**(동일) 합성.
7. **검증·리포트** — 오케스트레이터가 직접 실행/grep 증거로 검증(result·final 주장은 근거 아님), loop-md 연동, 근거 보고.

## 모드 가이드

| 모드 | 토폴로지 | 언제 |
|---|---|---|
| **Fusion-Research** | 동일 질문 → N 패밀리 read-only → Judge → Synth → 오케스트레이터 사실확인 | 분석·리서치·설계 '정리'(비코드) |
| **Fusion-Code** | 동일 HANDOFF → N 패밀리 격리 병렬 → 교차리뷰·Judge → Synth 합성지시 → 백엔드 구현 → 오케스트레이터 검증 | 답 갈릴 수 있는 구현, 신뢰도↑ |

## 오케스트레이터 자동감지

오케스트레이터는 4종 중 하나 — 감지 방식과 효과:

```bash
# env (cron/CI/헤드리스 권장)
export PLAN_FUSION_ORCHESTRATOR=glm      # ZCode(GLM)
# export PLAN_FUSION_ORCHESTRATOR=gpt    # Codex CLI(GPT)
# export PLAN_FUSION_ORCHESTRATOR=gemini # AGY(Gemini)
# export PLAN_FUSION_ORCHESTRATOR=claude # Claude Code(Opus)

# 또는 argv 폴백
bash scripts/check-fusion.sh glm
```

패밀리 매핑: `glm`→opencode(GLM/Kimi) · `gpt`→codex · `gemini`→agy · `claude`→claude(Opus).

감지되면 그 패밀리는 동족(확증편향) 회피를 위해 **참가자·Judge·Synth에서 자동 제외**된다(`EXCLUDED_FAMILIES`로 사유 표시). `JUDGE_DEFAULT`/`SYNTH_DEFAULT`도 오케스트레이터 패밀리를 회피한 차순위로 산출된다. **Judge 런타임 폴백**: claude(기본 Judge)가 런타임에 죽어도 즉시 self로 직행하지 않는다 — `JUDGE_FALLBACK_CHAIN`(claude→codex→agy→opencode-deepseek→opencode-glm/kimi→self, 총 6후보)이 차순위로 자동 전환한다. `ORCH_FAMILY=glm`이면 opencode는 *참가자*에서 제외되되 DeepSeek 라우트(`opencode-go/deepseek-v4-pro`)와 glm/kimi 라우트가 별도 후보로 Judge 폴백에 살아남는다(동종할인 `judge_conflict=partial` 경고 — synthesis에 명시).

### 오케스트레이터별 default 패널 변형

| `ORCHESTRATOR_FAMILY` | default 참가자 | Judge | Synth |
|---|---|---|---|
| `claude` | codex·agy·opencode-glm·opencode-kimi | 차순위(codex/agy/opencode 중 가용) | codex(GPT) |
| `glm` | codex·agy | claude(Opus) → 폴백: codex→agy→**opencode-deepseek**(동종할인)→self | codex(GPT) |
| `gpt` | agy·opencode-glm·opencode-kimi | claude(Opus) | 차순위(claude/agy/opencode) |
| `gemini` | codex·opencode-glm·opencode-kimi | claude(Opus) | codex(GPT) |
| `unknown` | codex·agy·opencode-glm·opencode-kimi | claude(Opus) | codex(GPT) |

> 변형 후 `EFFECTIVE_BACKENDS<2`면 `check-fusion.sh`가 exit 1(Fusion 불성립) → `plan-then-*` 단일 위임 또는 백엔드 추가 안내. `unknown`이면 동족 룰 비활성(모든 패밀리 가용 후보)이지만, 추정 가능하면 env로 명시 권장. 상세 분기는 `references/routing-fusion.md`의 변형표.

## 패널·라우팅 가이드

| 호명 | 백엔드 | 모델 경로 |
|---|---|---|
| codex / gpt5.5 [xhigh] | `codex exec` | `gpt-5.5` (오케스트레이터≠gpt일 때 Synthesizer) |
| gemini / "gemini pro" / flash | `agy -p` | `"Gemini 3.1 Pro (High)"` · `"Gemini 3.5 Flash (Medium)"` |
| opus / claude | `claude --print` | `opus` (오케스트레이터≠claude일 때 Judge) |
| glm5.2 / kimi k2.7 / deepseek … | opencode (omo/직접) | `zai-coding-plan/glm-5.2` · `opencode-go/kimi-k2.7-code` |

- **기본 패널**(호명 없을 때): 오케스트레이터 패밀리를 제외한 비-동족 패밀리들 — 위 [오케스트레이터별 변형표](#오케스트레이터별-default-패널-변형) 참조. 프리셋 highEnd/codeSecurity/fullPower/budget는 `references/routing-fusion.md`.
- ⚠️ **Gemini 모델명은 실측 문자열**(`gemini-3.5-pro`는 없음 — 실재는 3.1 Pro / 3.5 Flash). **Opus 4.8은 `claude` 직접 호출**.
- ⚠️ **동족 경고(일반화)**: 오케스트레이터 패밀리를 참가자·Judge·Synth에 또 쓰면 독립성↓. `check-fusion.sh`가 자동으로 제거하되, 호명이 명시적으로 그 패밀리를 다시 넣으려 하면 게이트가 노출하고 synthesis에 "비독립 할인" 명시.

## 전제조건

> **검증 환경(실측)**: codex 0.139.0 · opencode 1.16.2 · omo 4.10.0 · agy 1.0.10 · claude 2.1.x.

- **codex CLI** ≥ 0.139 (`exec review`) + `codex login` — 참가자(GPT) + 오케스트레이터≠gpt일 때 Synthesizer.
- **agy (Antigravity CLI)** — Gemini 참가자. `agy models`로 인증·모델 확인. (Google이 Gemini CLI를 Antigravity로 전환)
- **claude CLI** — 오케스트레이터≠claude일 때 기본 Judge(Opus). 오케스트레이터가 claude 패밀리면 동족이라 차순위 백엔드로 폴백.
- **opencode** ≥ 1.4 + 프로바이더 인증, **oh-my-openagent** ≥ 4.9(omo run 경로) — GLM/Kimi/DeepSeek 등.

> ⚠️ **비용·시간**: N참가자 + Judge 1 + Synth 1 = 단일 위임의 N+2배 이상. 고추론 fullPower(참가자 6슬롯 / 백엔드 4)는 수십 분 단위 → 백그라운드 + 완료 알림으로 관리. 단순 위임이면 plan-then-*가 더 가볍다.

사전 점검:
```bash
# 오케스트레이터 명시 권장(env). 미지정 시 unknown(동족 룰 비활성)
PLAN_FUSION_ORCHESTRATOR=glm bash scripts/check-fusion.sh
# ORCHESTRATOR_FAMILY · EXCLUDED_FAMILIES · PARTICIPANT_FAMILIES · JUDGE_DEFAULT/SYNTH_DEFAULT(+CONFLICT_RISK)
# · JUDGE_FALLBACK_CHAIN(런타임 Judge 폴백 — claude死 시 차순위 자동 전환) · MODEL_READY_DEEPSEEK · FUSION_CAPABILITY 출력
```
유효 백엔드(`EFFECTIVE_BACKENDS` = 비-오케스트레이터 참가자 패밀리 + 비-오케스트레이터 claude-as-participant 후보) 2개 이상이어야 Fusion 성립. ⚠️ 단 이 경우 **비-오케스트레이터 패밀리를 '참가자'로 써야** 교차검증 2패밀리가 된다 — Judge-only default로만 쓰면 실제 참가자는 1패밀리뿐이라 런타임 quorum이 'Fusion 미성립'으로 격하한다(그래서 `FUSION_CAPABILITY=conditional`로 표기). 1개뿐이면 교차검증 독립성이 없으니 plan-then-*로.

## 설치

### macOS / Linux
```bash
git clone https://github.com/allaixlabs/skills.git ~/project/skills   # 이미 있으면 생략
ln -s ~/project/skills/skills/plan-fusion ~/.claude/skills/plan-fusion
```

### Windows
이 스킬은 bash 스크립트 + Unix CLI(codex·agy·opencode)에 의존한다 → **WSL2 권장**(WSL 안에서는 위 macOS/Linux 절차를 그대로 사용).
네이티브로 설치하려면(PowerShell, 개발자 모드 또는 관리자 권한 필요):
```powershell
git clone https://github.com/allaixlabs/skills.git $HOME\project\skills
New-Item -ItemType SymbolicLink -Path "$HOME\.claude\skills\plan-fusion" `
  -Target "$HOME\project\skills\skills\plan-fusion"
# 심링크가 막히면 폴더 복사로 대체(단, 갱신 시 재복사 필요):
# Copy-Item -Recurse "$HOME\project\skills\skills\plan-fusion" "$HOME\.claude\skills\plan-fusion"
```
> repo 내부 `council-worktrees.sh`는 심링크가 아닌 실파일이라 `core.symlinks` 설정과 무관하게 정상 체크아웃된다(배포 호환). 다만 스크립트 실행·worktree·CLI는 결국 Unix 환경을 필요로 하므로 Windows는 WSL2가 가장 매끄럽다.

새 세션부터 자동 인식. **참가자 쪽 별도 설치 불필요** — HANDOFF가 stdin/인자로 전달되는 오케스트레이터 단독 구성이다.

## 사용법

자연어 트리거:
```
이 설계를 GPT, Gemini, GLM, Kimi로 각각 검토시키고 Opus가 판정·GPT가 종합해서 정리해줘
agy로 gemini도 패널에 넣어서 fusion으로 이 버그 원인 교차검증해
이 기능을 4개 모델로 구현시키고 Judge·Synthesizer로 제일 나은 합성을 만들어
```
명시 호출: `/plan-fusion <작업 내용>`

오케스트레이터가 claude가 아니면(ZCode/Codex CLI/AGY에서 호출 시) env로 명시하거나, 스킬 진입 인자로 넘긴다:
```bash
PLAN_FUSION_ORCHESTRATOR=glm   # ZCode 환경에서
```

## loop-md 연동

루트에 `loop.md`가 있으면 loop-md 연동은 **완료 결과를 사용자에게 먼저 보고한 뒤** 별도로 수행한다(지연 방지): `council_wt_adopt` → 결과 보고 → **메인 ROOT에서** loop-md Verify 전체 ①Pass/Fail·②정량·③정성 실행 → `.loop/last-verified`가 현재 HEAD인지 확인 → 커밋 순서로 고정한다. 패널 worktree 검증은 사전검증일 뿐 hard-guard 충족이 아니다. 루트에 `loop.md` 없으면 N/A.

Judge는 후보 비교용으로 loop-md ③정성(fresh-context 채점)과 입력·목적이 다르다. `loop.md` 감지 시 Judge 입력에 loop.md ③루브릭 + ①② 실행로그를 조건부 주입해 ③을 실제 충족하고, ②정량(커버리지 등)은 메인 검증 단계에서 loop.md 명령으로 직접 실행한다.

## 구조

```
plan-fusion/
├── SKILL.md                          # 0~5단계 Fusion 오케스트레이션(§0.0 감지→참가자→Judge→Synth→검증) (메인)
├── README.md                         # 이 문서
├── references/
│   ├── routing-fusion.md             # 호명→백엔드(+agy/claude) · 프리셋 · 오케스트레이터 패밀리 제거 변형 · 동족경고
│   ├── cli-fusion-map.md             # 5-CLI 실행경로 매트릭스 + agy·claude 상세(실측)
│   ├── codex-cli.md                  # codex exec — 참가자+Synth+exec review(교차리뷰)
│   ├── opencode-cli.md               # omo run + opencode run 직접 · session 추출
│   └── fusion.md                     # 격리 · 참가자 위임 · Judge→Synth 프로토콜 · 위험표
├── templates/
│   ├── HANDOFF.md.tmpl               # 코드 참가자 지시서(단일 공유 스펙)
│   ├── HANDOFF-research.md.tmpl      # 비코드 read-only 분석 브리프
│   ├── fusion-judge.md.tmpl          # Judge CLI 프롬프트(최강후보/합의/충돌/위험주장)
│   ├── fusion-synth.md.tmpl          # Synthesizer CLI 프롬프트(후보+judge→최종)
│   └── synthesis.md.tmpl             # 오케스트레이터의 Fusion 기록(Judge판정+Synth출력+검증증거)
└── scripts/
    ├── check-fusion.sh               # 오케스트레이터 감지 + codex+agy+opencode+claude 점검 + 동족 제거 (read-only)
    └── council-worktrees.sh          # worktree setup/cleanup/adopt 헬퍼 (cd 기반 — 전 백엔드 호환)
```
