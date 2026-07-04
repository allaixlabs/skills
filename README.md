# allaix skills

> **Claude Code · Codex · opencode를 위한, 실측 검증된 에이전트 스킬 모음.**
> Claude는 분석·계획·검증을 맡고 실제 실행은 외부 모델 CLI에 위임한다 — 그 **위임 · 검증 · 합성 루프**를 재사용 가능한 스킬로 패키징했다.

대화할 때마다 즉흥으로 구성하면 품질이 흔들리는 워크플로우(완료 기준 강제, 멀티모델 교차검증, 패널 핸드오프)를 **고정된 스킬**로 만든다. 모든 CLI 사용법은 추정이 아니라 **실측 버전**(codex 0.139 · opencode 1.16 · omo 4.10 · agy 1.0.10 · claude 2.1.x)으로 검증했다.

스킬은 네 갈래다:

- **거버넌스** — [`loop-md`](skills/loop-md/README.md)(완료 기준 강제) · [`cmux-handoff`](skills/cmux-handoff/README.md)(멈춘 패널 이어받기): 작업의 **품질·연속성**을 지킨다.
- **멀티모델 위임** — [`plan-then-codex`](skills/plan-then-codex/README.md) · [`plan-then-opencode`](skills/plan-then-opencode/README.md) · [`plan-codex-opencode`](skills/plan-codex-opencode/README.md) · [`plan-fusion`](skills/plan-fusion/README.md): **"Claude=두뇌, 외부 CLI=손"** split-brain으로 한 모델 또는 여러 모델 패밀리에 구현을 맡기고 교차검증·종합한다.
- **체이닝** — [`plan-fusion-dev`](skills/plan-fusion-dev/README.md): plan-fusion으로 계획을 확정한 뒤 그 결과를 **자동으로** plan-codex-opencode 개발(GPT 주축 + GLM 보조)로 넘기는 메타 스킬. 계획→개발을 한 번에.
- **보안** — [`plan-fusion-secu`](skills/plan-fusion-secu/README.md) · [`plan-fusion-dev-secu`](skills/plan-fusion-dev-secu/README.md): plan-fusion/plan-fusion-dev에 **시큐어 코딩 검증 3계층**(L1 정적분석 + L2 LLM 루브릭 + L3 강제 보안 백엔드)을 통합한 변형. 진입 즉시 L1+L2 강제. codeSecurity 프리셋·심층 작업 시 L3 추가.
- **유틸리티** — [`img-maker-codex`](skills/img-maker-codex/README.md): 로컬 Codex CLI의 `image_generation` 도구를 구동해 ChatGPT Plus/Pro 구독 한도 내에서 이미지를 생성·편집한다. 별도 API 키·과금 없이 단일 작업을 수행한다.

## 스킬 한눈에

| 스킬 | 한 줄 | 대표 트리거 | 필요 외부 CLI |
|------|-------|-------------|---------------|
| **delegate** | `plan-*` 진입점이 헷갈릴 때 분류 후 선택 sibling 실행 | "어느 위임 스킬 쓰지?", "delegate로 골라줘" | 선택 스킬의 전제 |
| **loop-md** | 완료 선언 전 3단계 DoD 검증 강제 (Setup/Verify) | "DoD 루프 세팅", "완료 전 검증" | 없음 (bash·git) |
| **cmux-handoff** | 멈춘 에이전트 패널 읽기·요약·이어받기 | "옆 cmux 패널 codex 작업 이어받아" | cmux |
| **plan-then-codex** | Claude 계획 → **Codex 단일** 구현 위임 | "구현은 codex gpt5.5 xhigh로" | codex |
| **plan-then-opencode** | Claude 계획 → **omo 에이전트** 구현 위임 | "구현은 omo sisyphus로 위임해" | opencode + omo |
| **plan-codex-opencode** | 여러 모델 패밀리 **Council/Pipeline** 교차검증 | "codex·glm·kimi로 교차검증해 정리" | codex + opencode + omo |
| **plan-fusion** | 멀티 CLI 독립 실행 → **Judge→Synth** 합성 | "GPT·Gemini·GLM·Kimi로 풀고 Opus 판정·GPT 종합" | codex + agy + opencode + omo + claude |
| **plan-fusion-dev** | **계획(plan-fusion) → 자동 개발(plan-codex-opencode)** 체이닝 | "fusion으로 계획 잡고 GPT+GLM으로 개발까지 한 번에" | codex + opencode + (agy/claude 권장) |
| **plan-fusion-secu** | plan-fusion + **시큐어 코딩 검증 3계층**(L1 정적분석 + L2 루브릭, 진입 즉시 강제) | "보안 검증 포함해 fusion으로", "시큐어 코딩 점검하며 교차검증" | codex + agy + opencode + claude + semgrep/gitleaks |
| **plan-fusion-dev-secu** | **보안 체이닝**(계획 plan-fusion-secu → 자동 개발, 양쪽에 보안 게이트) | "보안 검증 포함 계획→개발 한 번에", "codeSecurity로 잡고 보안 개발로" | 위 둘의 합 |
| **img-maker-codex** | 로컬 Codex `image_generation` 도구로 이미지 생성·편집 | "ChatGPT 구독으로 이미지 생성해", "imagegen으로 편집" | codex (+ python3) |

## 위임 스킬, 어느 것을 쓰나

일곱 위임 스킬은 트리거가 일부 겹친다. **모델 수**와 **종합 주체**, 그리고 **계획→개발 자동화 여부**·**보안 검증 필요 여부**로 고른다:

```
진입점이 헷갈리는가?                    → delegate (분류 후 선택 sibling 실행)

한 모델로 충분한가?
├─ OpenAI/GPT 한 모델            → plan-then-codex
└─ 멀티프로바이더 / 에이전트 선택 → plan-then-opencode  (Prometheus/Sisyphus/Hephaestus)

여러 모델로 교차검증할 것인가?
├─ Claude가 직접 종합            → plan-codex-opencode  (Council 병렬 / Pipeline 구현→리뷰)
└─ 종합도 CLI에 위임(Judge→Synth)
   + Gemini·Opus까지 패밀리 확장 → plan-fusion

시큐어 코딩 검증도 필요한가?
├─ 계획·평가만                   → plan-fusion-secu  (L1 정적분석 + L2 루브릭, 진입 즉시 강제)
└─ 계획(fusion-secu) → 자동 개발 → plan-fusion-dev-secu  (양쪽에 보안 게이트)

계획(fusion)을 잡고 바로 개발까지 한 번에?
└─ 계획 확정 → 자동으로 GPT+GLM 개발 체이닝 → plan-fusion-dev
```

| | plan-then-codex | plan-then-opencode | plan-codex-opencode | plan-fusion | plan-fusion-dev | **plan-fusion-secu** | **plan-fusion-dev-secu** |
|-|-----------------|--------------------|---------------------|-------------|---------------------|---|---|
| 모델 수 | 1 (GPT) | 1 (omo 에이전트) | 2~3+ 패밀리 | 4~5 패밀리 | fusion패널 + GPT+GLM | 4~5 패밀리 (codeSecurity 추천) | 위 둘의 합 |
| 백엔드 | codex | opencode/omo | codex + opencode | + agy(Gemini) + claude(Opus) | 위 둘의 합 | 동일 + semgrep/gitleaks | 위 둘의 합 |
| 종합 주체 | — (단일) | — (단일) | **Claude 직접** | **Judge CLI → Synth CLI** | 단계별 해당 스킬 방식 | Judge+Synth(보안 루브릭) | 단계별 |
| 격리 | workspace-write | 풀 파일시스템 | 패널별 worktree | 참가자별 worktree | 계획/개발 각 worktree | 동일 | 동일 |
| 계획→개발 자동 | X | X | X | X | **O (변환 단계 포함)** | X | **O (보안 매핑 게이트)** |
| 보안 검증 | X | X | X | X | X | **L1+L2 강제, L3 조건** | **L1+L2+L3 (양쪽)** |
| 대략 비용 | 1× | 1× | N× | (N+2)× | **6~9× / 8~11×** | (N+2)× + L1 도구 | **8~11× / 10~13×** |

> **단일 위임이 가장 가볍다.** 모델을 늘릴수록 토큰·시간이 N배 이상으로 든다 — 신뢰도가 정말 필요한 분기에서만 council/fusion을, 보안 검증이 본질인 작업에서만 -secu 변형을 쓴다.

## 스킬 상세

### 🧭 loop-md — 완료 기준 감독관 (DoD)
작업을 "완료"로 선언하기 전 **3단계 검증**을 강제한다: **① Pass/Fail 게이트**(실제 실행 + exit code·로그·시각 증거 필수, 증거 없는 ✅=FAIL) · **② 정량 측정** · **③ 정성 평가**(독립 서브에이전트 채점 권장). FAIL은 `docs/loop-md/lessons.md`에 규칙으로 증류해 다음 루프가 먼저 읽는다. **듀얼 포맷** — Claude Code(스킬)와 Codex(`AGENTS.md`)가 **같은 `loop.md`** 로 동작하고, **hard 가드**(옵트인)로 검증 마커 없는 `git commit`을 차단할 수 있다. → [상세](skills/loop-md/README.md)

### 🔗 cmux-handoff — 멈춘 패널 이어받기
cmux의 Unix 소켓 CLI로 다른 터미널 패널(Claude/Codex/opencode/셸)의 **보이는 상태를 캡처**하고, 후속 지시를 보내고, 작업을 넘겨받는다. 경계 원칙이 핵심 — **모델의 숨은 컨텍스트·툴 상태는 복구 불가**, 모든 판단은 스크롤백 텍스트로 한정하고 읽은 것/추론한 것/보낸 것을 구분 보고한다. → [상세](skills/cmux-handoff/README.md)

### 🧭 delegate — 위임 스킬 단일 진입점
5개 `plan-*` 위임 스킬의 진입점이 헷갈릴 때, 사용자 요청을 분류해 **선택된 sibling 스킬의 `SKILL.md`를 런타임에 읽고 같은 세션에서 그 절차를 실행**한다. 절차를 복제하지 않고 sibling이 단일 진실원. 라우팅 우선순위: 명시 스킬명 > 체이닝 신호(plan-fusion-dev) > 모델 수/다양성(plan-fusion·plan-codex-opencode) > 명시 백엔드(plan-then-*) > 기본값(모호 요청은 경량 단일 위임 plan-then-codex). 사전점검은 선택 스킬의 check 1개만(route-first). → [상세](skills/delegate/README.md)

### ⚙️ plan-then-codex — Claude 계획 × Codex 구현
"분석은 claude, 구현은 codex"를 표준화한 split-brain. Claude가 **자기완결 HANDOFF**(파일별 지시·Baseline·BLOCKED 프로토콜·Acceptance Criteria)를 쓰고 `codex exec`에 위임, baseline diff와 직접 실행 증거로 검증한다(최대 3라운드). Claude는 검증 중 발견한 문제도 직접 안 고치고 Codex에 되돌린다. → [상세](skills/plan-then-codex/README.md)

### 🛠️ plan-then-opencode — Claude 계획 × omo 구현
구현을 **oh-my-openagent(omo)** 에이전트에 위임한다. 태스크 특성에 따라 **Prometheus**(전략 플래너) · **Sisyphus**(병렬 오케스트레이터, 기본) · **Hephaestus**(자율 심층 작업자)를 Claude가 선택. codex 대비 **멀티프로바이더**(anthropic/openai/google/kimi 등)와 Team Mode 자동 병렬이 강점. → [상세](skills/plan-then-opencode/README.md)

### 🧩 plan-codex-opencode — 멀티모델 Council/Pipeline
서로 다른 모델 패밀리(GPT·GLM·Kimi·DeepSeek 등)를 패널로 묶어 **Council**(동일 HANDOFF → worktree 격리 병렬 → 비교·교차리뷰·채택/합성) 또는 **Pipeline**(구현→타모델 리뷰→수정→종합)으로 돌리고, Claude가 합의/충돌/고유통찰을 `synthesis.md`로 종합한다. `codex exec review`로 **다른 패밀리가 교차리뷰**해 독립성을 보장. → [상세](skills/plan-codex-opencode/README.md)

### 🔀 plan-fusion — CLI Fusion (Judge → Synthesizer)
종합 자체를 모델에 위임한다: **참가자 CLI 독립 실행 → Judge CLI 후보 평가 → Synthesizer CLI 최종 합성 → Claude 검증**. `plan-codex-opencode`에 **agy(Gemini)·claude(Opus)** 를 더해 **백엔드 패밀리 4 / 대표 모델 5종**(기본 패널 GPT·Gemini·GLM·Kimi, Judge=Opus, Synth=GPT). Claude의 단일 관점 편향을 줄이고 검증·사실확인에 집중. → [상세](skills/plan-fusion/README.md)

### ⛓️ plan-fusion-dev — 계획 → 자동 개발 체이닝
plan-fusion(Fusion-Research)으로 계획을 확정한 뒤, 그 결과를 **자동으로** plan-codex-opencode 개발 단계로 넘긴다 — 변환 단계(체이닝 전용 Synth 템플릿 + HANDOFF-chain)만 오케스트레이터가 조율한다. 개발은 기본 **Pipeline**(구현 GPT-5.5 xhigh + 리뷰 GLM-5.2 교차검증, "개발엔 고스펙 불필요" 철학 반영)이되, 오케스트레이터가 태스크 특성으로 **Council**로 전환할 수 있다. 계획(N+2 호출) + 개발(Pipeline 2~3 / Council-Code 4~5) = 단일 위임의 **Pipeline 약 6~9배, Council-Code 약 8~11배** 비용이므로 복잡·고위험 작업에 한정. → [상세](skills/plan-fusion-dev/README.md)

### 🔒 plan-fusion-secu — 보안 통합 Fusion (L1+L2+L3)
`plan-fusion`의 워크플로우(참가자 → Judge → Synth → 검증)에 **시큐어 코딩 검증 3계층**을 통합한다. **진입 즉시 L1(정적분석: semgrep·gitleaks·npm/pip audit)+L2(LLM 루브릭) 강제** — 별도 `-secu` 스킬로 들어온 시점이 곧 보안 의도. `codeSecurity` 프리셋 또는 심층 작업 시 **L3(강제 보안 백엔드)** 가 추가 발동(PoC·공급망 평판·데이터 출처). 체크리스트는 **43개 항목**(OWASP Top 10 2021/2025 병기 + OWASP LLM Top 10 + CWE/SANS Top 25 + 누락 3개)을 `codeSecurity` 프리셋(7호출) 교차검증으로 매트릭스 자체를 검증했다. → [상세](skills/plan-fusion-secu/README.md)

### 🔒⛓️ plan-fusion-dev-secu — 보안 체이닝 (계획+보안 → 자동 개발)
`plan-fusion-dev`에 보안 검증을 통합한 변형 — 계획 단계(`plan-fusion-secu`)에서 L1+L2를, 변환 단계에서 보안 AC 매핑 게이트를, 개발 단계(`plan-codex-opencode`)에서 **L1 재실행**으로 신규 도입 취약점을 잡는다. 계획-개발 **보안 일관성**을 종합 검증. 단일 위임 대비 **Pipeline 약 8~11배, Council-Code 약 10~13배** 비용(보안 오버헤드로 plan-fusion-dev보다 +1~2배). 보안 민감 코드(auth·결제·시크릿)를 다룰 때 한정. → [상세](skills/plan-fusion-dev-secu/README.md)

### 🎨 img-maker-codex — Codex 기반 이미지 생성
별도 OpenAI API 키·과금 없이, 사용자의 **ChatGPT Plus/Pro 구독 한도** 내에서 로컬 `codex` CLI의 `image_generation` 도구로 이미지를 생성·편집한다. text-to-image, image-to-image(스타일 전이), 다중 참조 합성, 한 번에 여러 결과(`--count`)를 지원. Codex 0.139 실측 기반 rollout 파싱(saved_path 우선, base64 폴백, 다중 신원 병합)으로 세션을 격리하고, 시스템 디렉토리 거부·magic 헤더 검사로 안전하게 동작한다. 기존 `gpt-image-2` 스킬의 개선 후속작. → [상세](skills/img-maker-codex/README.md)

## 공통 설계 원칙

- **Split-brain handoff** — 위임 대상 CLI는 대화 컨텍스트를 모른다. 유일한 진실은 **자기완결 HANDOFF 문서**이며, 스킬이 그 작성·전달·검증 루프를 강제한다.
- **교차검증 독립성** — 서로 다른 모델 패밀리는 같은 문제에서 **다른 실수**를 한다 → 패널을 다른 패밀리로 구성할 때만 교차검증이 의미 있다(동족 조합 금지).
- **검증 우선** — `result`/`final` 주장은 근거가 아니다. Claude가 **직접 실행·grep 증거**로 검증한다.
- **loop-md 연동** — 루트에 `loop.md`가 있으면 모든 위임 스킬이 VERIFY 단계에서 DoD 3단계를 수행한다(없으면 N/A). council/fusion의 교차리뷰·Judge는 ③정성의 독립 검증자를 자연 충족한다.
- **비용·시간 가드** — 멀티모델 위임은 단일의 N배 이상 → 백그라운드 실행 + 완료 알림으로 관리한다.

## 전제조건 (외부 CLI)

스킬은 Claude Code 세션에 설치만 하면 인식되지만, **위임 대상 CLI**는 별도로 갖춰야 한다:

| CLI | 용도 | 설치 / 확인 | 쓰는 스킬 |
|-----|------|-------------|-----------|
| **codex** ≥ 0.139 | GPT 실행 · `exec review` 교차리뷰 · `image_generation` | `npm i -g @openai/codex` + `codex login` | plan-then-codex, plan-codex-opencode, plan-fusion, **plan-fusion-secu/dev-secu**, img-maker-codex |
| **opencode** ≥ 1.4 + **oh-my-openagent** ≥ 4.9 | GLM·Kimi·DeepSeek 등 | `npm i -g opencode oh-my-openagent` + provider 인증 (`bunx oh-my-openagent doctor`) | plan-then-opencode, plan-codex-opencode, plan-fusion, **plan-fusion-secu/dev-secu** |
| **agy** (Antigravity) | Gemini 참가자 | `agy models` 로 인증·모델 확인 | plan-fusion, **plan-fusion-secu/dev-secu** |
| **claude** | 기본 Judge(Opus) | Claude Code CLI | plan-fusion, **plan-fusion-secu** |
| **semgrep** + **gitleaks** | L1 정적 분석·시크릿 스캔 | `brew install semgrep gitleaks` (npm/pip/cargo audit은 각 스택 번들) | **plan-fusion-secu, plan-fusion-dev-secu** (없으면 L2로 폴백, 품질 저하) |
| **cmux** | 패널 핸드오프 | `cmux ping` → `PONG` | cmux-handoff |
| **python3** (stdlib만) | img-maker-codex rollout 파싱 | macOS·Linux 기본 포함, 없으면 `python3` 설치 | img-maker-codex |
| — (없음) | bash·git만 사용 | — | loop-md |

> 각 스킬은 동봉된 read-only 사전점검 스크립트(`scripts/check-*.sh`)로 가용성·인증을 먼저 확인한 뒤 동작한다.

## 설치

### npx skills (권장)
[skills CLI](https://github.com/vercel-labs/skills)로 원하는 스킬만, 원하는 에이전트에만 골라 설치:
```bash
npx skills add allaixlabs/skills --skill loop-md --agent claude-code
npx skills add allaixlabs/skills --skill cmux-handoff --agent claude-code
npx skills add allaixlabs/skills --skill plan-then-codex --agent claude-code
npx skills add allaixlabs/skills --skill plan-then-opencode --agent claude-code
npx skills add allaixlabs/skills --skill plan-codex-opencode --agent claude-code
npx skills add allaixlabs/skills --skill plan-fusion --agent claude-code
npx skills add allaixlabs/skills --skill delegate --agent claude-code
npx skills add allaixlabs/skills --skill plan-fusion-dev --agent claude-code
npx skills add allaixlabs/skills --skill plan-fusion-secu --agent claude-code
npx skills add allaixlabs/skills --skill plan-fusion-dev-secu --agent claude-code
npx skills add allaixlabs/skills --skill img-maker-codex --agent claude-code
npx skills add allaixlabs/skills --skill '*' --agent claude-code   # 전부 설치
```

> **`--agent`를 생략하면** 감지된 **모든 에이전트**(Cursor·Codex·Gemini CLI 등 십수 개)에 한꺼번에 설치된다 — 한 에이전트에만 깔려면 위처럼 `--agent`를 명시한다(대상이 다르면 `--agent codex`·`--agent cursor` 등으로 변경, 공백으로 복수 지정 가능). 기본은 심볼릭 링크 설치라 원본을 덮어쓰지 않는다.
새 세션에서 `/loop-md`, `/plan-fusion` 등으로 호출하거나, 각 스킬의 description 트리거(자연어)로 발동한다.

### 수동 설치 (Claude Code)
```bash
git clone https://github.com/allaixlabs/skills.git ~/project/skills
ln -s ~/project/skills/skills/loop-md ~/.claude/skills/loop-md   # 심볼릭 링크 권장 (원본만 관리)
```

### Codex CLI / 기타 에이전트
- **글로벌(권장)**: `~/.codex/AGENTS.md`에 `dod-guard` 1회 → 모든 프로젝트의 Codex 자동 적용(Claude 글로벌과 대칭). `/loop-md` Setup이 양쪽 글로벌을 함께 관리.
- **프로젝트별**: Setup의 'Codex 어댑터' 선택 또는 `cp skills/loop-md/templates/AGENTS.md.tmpl <프로젝트>/AGENTS.md`.

### Windows
스킬은 bash + Unix CLI에 의존한다 → **WSL2 권장**(WSL 안에서 위 macOS/Linux 절차를 그대로 사용). 네이티브 설치는 각 스킬 README의 PowerShell 안내 참조.

## 구조

```
skills/
├── loop-md/             # 완료 기준(DoD) 3단계 검증 — Setup/Verify, hard 커밋 가드, Codex 어댑터
├── cmux-handoff/        # 멈춘 에이전트 패널 읽기·이어받기 — cmux CLI 실측 노트
├── plan-then-codex/     # Claude 계획 → codex exec 단일 구현 위임
├── plan-then-opencode/  # Claude 계획 → omo run 위임 — Prometheus/Sisyphus/Hephaestus 선택
├── plan-codex-opencode/ # 멀티모델 패널 Council/Pipeline 교차검증 — worktree 격리·종합
├── plan-fusion/         # 멀티 CLI 독립 실행 → Judge→Synth 합성 — agy(Gemini)·claude(Opus) 포함
├── delegate/            # plan-* 위임 스킬 단일 진입점 — 분류 후 sibling SKILL.md 런타임 읽기 실행
├── plan-fusion-dev/     # 계획(plan-fusion) → 자동 개발(plan-codex-opencode) 체이닝 메타 스킬
├── plan-fusion-secu/    # 보안 통합 fusion — L1 정적분석 + L2 루브릭 + L3 강제 백엔드 (43개 체크리스트)
├── plan-fusion-dev-secu/ # 보안 체이닝 — 계획(fusion-secu) → 자동 개발, 양쪽에 보안 게이트
└── img-maker-codex/     # 로컬 Codex image_generation 도구 구동 — ChatGPT 구독 한도 내 이미지 생성·편집
```

각 스킬 폴더는 `SKILL.md`(오케스트레이션) · `README.md`(상세) · `references/`(CLI 실측 노트) · `templates/` · `scripts/`(사전점검)로 구성된다.

## 모델명 관리 (SSOT)

`plan-*` 오케스트레이션 스킬들이 라우팅하는 AI 모델명(`gpt-5.5`·`zai-coding-plan/glm-5.2`·
`"Gemini 3.1 Pro (High)"`·`opencode-go/kimi-k2.7-code`·`opus`·disabled 정책 `fable-5`/`mythos-5` 등)은
**`models.yaml`(레포 루트)이 단일 진실원(SSOT)**이다. 과거엔 모델명이 routing 문서·스크립트·SKILL.md·
템플릿에 각각 하드코딩돼 버전업 시 여러 곳을 손으로 고쳐야 했고(실제로 `plan-then-opencode`가 구버전으로
경직되는 버전 스큐가 발생), `check-fusion.sh`의 Judge 폴백 체인·동족 판정에도 라우팅 문서만 고쳐서는
반영되지 않는 하드코딩 family 분기가 박혀 있었다. **모델명(버전업)은 SSOT화가 완료**됐고, **family 분류
(ORCH 감지·동족 제거·partial-inbreed·폴백 체인)도 부분 데이터화** — `family`·`aliases`·`backend`·`cli_model`
필드에서 파생(신규 키 없음), 단 mandatory 예외·Judge/Synth 우선순위는 운영 정책이라 코드 상수로 두되
SSOT 존재 검증으로 drift를 잡는다. 백엔드 헬스체크(`codex login status`·`agy models` 등)는 절차적이라
YAML에 담지 않는다.

**버전업·모델명 변경·신규 모델 추가 절차**(루트에서):
```bash
# 1. models.yaml 만 편집 — 단일 편집점. (신규 모델 추가·버전 변경·disabled 정책 변경 모두 여기)
$EDITOR models.yaml

# 2. 변환 + 스킬별 복제 — models.lib.sh(bash source용) 재생성 + 각 스킬 폴더로 복제본 배치.
bash sync-models.sh

# 3. 정합 검증 — 문서·스크립트·템플릿의 모델명이 SSOT와 일치하는지(드리프트/미정의 토큰 잡기).
bash check-models.sh        # exit 0=정합, exit 1=드리프트(어느 파일·토큰인지 보고)
```

아키텍처:
- **`models.yaml`**(루트) — 편집 진실원. 스키마 제한(중첩 1단계·고정 키)으로 sync-models.sh 가 awk 로 파싱(yq 의존성 0).
- **`models.lib.sh`**(루트 + 각 스킬) — sync-models.sh 가 자동 생성. `check-fusion.sh` 등이 `source` 해 `$M_GPT_CLI`·`is_disabled_model` 헬퍼로 소비. **수동 수정 금지**.
- **스킬별 복제본** — `skills/<스킬>/models.yaml` + `models.lib.sh`. `npx skills add --skill X` 로 단일 스킬만 설치하는 사용자도 SSOT를 받도록(council-worktrees.sh·codex-cli.md 의 "실파일 복제 + cmp 드리프트 감지" 관례와 동일 — 심링크 회피, Windows 호환). `check-models.sh`가 루트 vs 복제본 정합을 검증.
- **마크다운 문서**(routing.md·routing-fusion.md·SKILL.md·README.md·council.md·템플릿) — 사람이 읽는 뷰. 값은 하드코딩하되 `check-models.sh`가 SSOT와 정합을 자동 검증(드리프트 시 FAIL).

> 게시 정책: 루트 `models.yaml`/`sync-models.sh`/`check-models.sh`는 `.gitignore` whitelist 때문에
> `npx skills add` 사용자에게 직접 배포되지 않는다. 대신 각 스킬 폴더의 복제본(`models.yaml`+`models.lib.sh`)이
> 게시되어 단일 스킬만 설치해도 SSOT를 갖는다. 복제본 드리프트는 `check-models.sh`가 잡는다.

## 만든 곳

**allaix skills**는 **Allaix Labs**와 **LETSECU(주식회사 렛시큐)** 가 함께 개발·관리하는 에이전트 스킬 모음이다.

| 회사 | 소개 | 링크 |
|------|------|------|
| **Allaix Labs** | "AI로 문제를 해결합니다" — 기획부터 개발·자동화·운영까지, 조직 문제 중심의 맞춤형 AI 시스템을 설계한다. | [allaix.kr](https://allaix.kr) · `allaixlabs@gmail.com` |
| **LETSECU** (주식회사 렛시큐) | "Human Insight × AI Engine" — AI 기반 정보보안 솔루션·컨설팅(보안 지침 설계, 웹 취약점 진단, 보안 컨설팅)을 제공한다. | [letsecu.com](https://letsecu.com) · [blog](https://blog.letsecu.com) |

**사업자 정보 — 주식회사 렛시큐 (LETSECU)**
- 대표 **김민호** · 사업자등록번호 **370-87-03101**
- 주소: 서울특별시 관악구 남부순환로 1677-20 (봉천동 949-14) 2층
- 전화 02-6941-0088 · 이메일 `int_x@letsecu.com`

문의: `allaixlabs@gmail.com` (Allaix Labs) · `int_x@letsecu.com` (LETSECU)

© 2026 Allaix Labs · LETSECU
