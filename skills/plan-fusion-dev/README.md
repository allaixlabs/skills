# plan-fusion-dev

**계획은 plan-fusion(다중 모델 교차검증 → Judge → Synth)으로 확정하고, 실제 코드는 그 결과를 자동으로 plan-codex-opencode(Pipeline/Council-Code)에 넘겨 구현** — "fusion으로 잡은 설계를 GPT+GLM으로 바로 개발까지" 류 **체이닝 메타 스킬**. 두 하위 스킬 사이의 변환 단계만 오케스트레이터가 조율한다.

> 핵심 전제: plan-fusion의 계획 확정(설계 다양성)과 plan-codex-opencode의 개발(GPT+GLM 교차검증)을 **한 번에** 끝내되, 각 단계는 하위 스킬의 검증된 절차를 그대로 따른다. 이 스킬은 체인을 잇고 변환만 담당한다 — 오케스트레이터가 프로덕션 코드를 직접 수정하지 않는 건 다른 위임 스킬과 같다.

## 존재 이유 (한 줄)

plan-fusion으로 계획을 확정한 뒤, 그 `final.md`를 코드용 HANDOFF로 변환해 plan-codex-opencode 개발 단계로 **자동 진입**시킨다. 두 스킬을 따로따로 호출하고 중간 산출물을 수동으로 옮기는 비용을 없앤다.

## 왜 이 구조인가

- **계획 단계는 다양성이 가치** — 여러 모델 패밀리가 독립 풀이 → Judge·Synth로 합성 → 편향 감소. 이건 plan-fusion이 이미 잘 한다.
- **개발 단계는 cost-performance가 가치** — 벤치마크상 루틴 구현은 GPT 주축 + GLM 보조가 합리적(Opus 대비 GLM이 3~5배 저렴, SWE-bench 격차는 ~8%p). 동족 회피(계획 단계) 대신 **패널 내 교차검증**(개발 단계)으로 GPT↔GLM 독립성을 확보한다.
- **변환은 구조적 갭** — plan-fusion `final.md`는 자유형 분석 답변이라 Baseline·파일별 지시·AC·빌드 명령이 없다. 그래서 이 스킬은 **체이닝 전용 Synth 템플릿**으로 final.md가 처음부터 코드 스펙을 담게 하고, 오케스트레이터는 read-only로만 캡처할 수 있는 3개(Baseline·명령·dev URL)만 보강한다.

## 무엇을 하나

1. **메타 사전 점검**(§0) — `scripts/check-fusion-dev.sh`가 두 형제 스킬의 점검(check-fusion.sh + check-panels.sh)을 묶어 실행. `FUSION_DEV_PLAN_READY`(계획) · `FUSION_DEV_DEV_READY`(개발) · `FUSION_DEV_CAPABILITY`(full/plan-only/dev-only/none).
2. **계획 단계**(§1) — plan-fusion **Fusion-Research 모드**를 그대로 실행. 유일한 차이: **체이닝 전용 Synth 템플릿**(`fusion-synth-code.md.tmpl`)으로 산출 `final.md`가 코드 스펙까지 담음.
3. **변환 단계**(§2) — `HANDOFF-chain.md.tmpl` 기준으로 final.md → `$RUN_PCO/handoff.md`. 오케스트레이터는 Baseline(`git status`/`rev-parse HEAD`)·빌드/테스트/린트 명령(매니페스트에서 식별)·dev URL만 보강. `$TODO_*` 자리표시자 치환 검증.
4. **개발 모드 선택**(§3) — 오케스트레이터가 태스크 특성으로 **Pipeline**(범위 명확·기본) vs **Council-Code**(답 갈림·신뢰도↑) 결정. 인간 승인 영역이면 BLOCKED.
5. **개발 단계**(§4) — plan-codex-opencode 절차를 `$RUN_PCO`에서 실행(§1 ANALYZE·§2 PLAN은 변환이 대신했으므로 §3 DELEGATE부터). Pipeline 기본: 구현 GPT-5.5 xhigh + 리뷰 GLM-5.2 + 수정 GPT resume.
6. **검증·REPORT**(§5) — 하위 스킬 검증(직접 실행 증거)에 위임 + 체이닝 추가 검증(개발 결과가 계획 설계와 충돌 안 하는지) + 양쪽 worktree 누수 점검.

## 모드·패널 가이드

### 개발 모드 자동 선택 (§3)

| 신호 | 모드 | 이유 |
|---|---|---|
| 스키마/보안/결제/배포/아키텍처 | **BLOCKED** | 인간 승인 영역 |
| 답 갈릴 수 있는 설계·구현 + 신뢰도↑ | **Council-Code** | GPT+GLM 병렬 → 교차리뷰 → 채택/합성 |
| 범위 명확 + 구현 품질 검증 | **Pipeline** | GPT 구현+수정, GLM 리뷰(역할 분리) |
| 모호(기본) | **Pipeline** | 비용 효율 + "개발엔 고스펙 불필요" 철학 부합 |

### Pipeline 기본 라인업 (GPT 비중 높게)

| 역할 | 백엔드/모델 | 비고 |
|---|---|---|
| 구현(메인) | codex `gpt-5.5` xhigh | HANDOFF로 위임, SESSION_A 추출 |
| 리뷰 | opencode `glm-5.2` | 구현자와 **다른 패밀리**(Pipeline 필수) |
| 수정 | codex `gpt-5.5` resume | 리뷰 지적 반영 |
| 종합 | 오케스트레이터 | plan-codex-opencode §4 종합 |

> 역방향(GLM 구현 + GPT 리뷰)도 허용 — 비용 민감한 대량 루틴 코드에 적합. 오케스트레이터가 태스크로 판단.

## 다른 스킬과의 차이

| | plan-fusion | plan-codex-opencode | **plan-fusion-dev** |
|-|-|-|-|
| 범위 | 계획만(Research) / 구현도(Fusion-Code) | 개발만(Council-Code/Pipeline) | **계획 → 자동 개발 체이닝** |
| 종합 주체 | Judge→Synth CLI | 오케스트레이터 직접 | 단계별로 해당 스킬 방식 |
| 개발 모델 | 다양성 우선 | GPT+GLM 등 패널 | **GPT 주축 + GLM 보조(기본)** |
| 자동 체이닝 | X | X | **O(변환 단계 포함)** |
| 대략 비용 | (N+2)× | N× | **(N+2 + 개발)× — Pipeline 2~3 → 6~9× / Council-Code 4~5 → 8~11× 단일 위임** |

## 전제조건

두 형제 스킬의 전제를 **모두** 가져야 한다:
- **plan-fusion 전제**: EFFECTIVE_BACKENDS ≥ 2(codex+agy+opencode+claude 중 비-동족 2개 이상). ⚠️ **GLM 예외**: 오케스트레이터=glm이면 opencode(GLM)가 동족이어도 참가자에 필수 포함(`GLM_MANDATORY_PARTICIPANT=yes`) — 계획 패널이 codex·agy·glm 3종(N=3)이 되어 게이트가 자동 full로 통과.
- **plan-codex-opencode 전제**: codex(GPT) + opencode(GLM, zai 인증) 둘 다 가용 — 개발 혼용의 전제.
- **오케스트레이터**: ZCode(GLM)·Codex CLI(GPT)·AGY(Gemini)·Claude Code(Opus) 중 하나. `PLAN_FUSION_ORCHESTRATOR` env로 명시 권장.

사전 점검:
```bash
PLAN_FUSION_ORCHESTRATOR=glm bash scripts/check-fusion-dev.sh
# FUSION_DEV_PLAN_READY · FUSION_DEV_DEV_READY · FUSION_DEV_CAPABILITY(full=진행 가능) 출력
```

> ⚠️ **비용·시간**: 계획(N+2 호출) + 개발 = **모드별 차이** — Pipeline(2~3 호출) 또는 Council-Code(4~5 호출). 합계 **Pipeline이면 N+4~N+5회, Council-Code면 N+6~N+7회**(기본 N=4 패널이면 각각 8~9회 / 10~11회; ⚠️ GLM 오케스트레이터는 GLM 예외로 계획 패널 3종이라 N=3 → 7~8회 / 9~10회, N=2면 6~7회 / 8~9회) = 단일 위임(1회) 대비 **Pipeline 약 6~9배, Council-Code 약 8~11배**. 백그라운드 + 완료 알림으로 관리. 사소·저위험 작업엔 과함 — plan-then-* 단일 위임이나 오케스트레이터 단독이 낫다. **답이 갈릴 수 있고 틀리면 비용이 큰 복잡 구현·판단**에만 의미.

## 설치

### macOS / Linux
```bash
git clone https://github.com/allaixlabs/skills.git ~/project/skills   # 이미 있으면 생략
ln -s ~/project/skills/skills/plan-fusion-dev ~/.claude/skills/plan-fusion-dev
```
> 두 형제 스킬(`plan-fusion/`, `plan-codex-opencode/`)도 같은 레포에 있어야 한다 — 사전점검 스크립트가 `../../plan-fusion`, `../../plan-codex-opencode` 경로로 소스한다.

### Windows
bash + Unix CLI에 의존 → **WSL2 권장**(WSL 안에서 위 절차 그대로 사용).

새 세션부터 자연어 트리거 또는 `/plan-fusion-dev` 명시 호출로 인식.

## 사용법

자연어 트리거:
```
plan-fusion으로 이 기능 설계 확정하고, 그대로 GPT랑 GLM으로 개발까지 한 번에
fusion으로 잡은 계획을 바로 개발로 이어가줘 — GPT 주축에 GLM 리뷰로
이 복잡한 리팩토링, 계획을 여러 모델로 검증하고 구현까지 자동 체이닝해
```
명시 호출: `/plan-fusion-dev <작업 내용>`

## loop-md 연동

루트 `loop.md`가 있으면: **plan-codex-opencode의 loop-md 연동 절차를 그대로** 수행(완료 결과를 사용자에게 먼저 보고한 뒤 별도로 loop-md Verify) — council 교차리뷰가 ③정성의 독립 검증을 자연 충족. 메타 스킬이 추가로 하는 건 없다. 루트 `loop.md` 없으면 N/A.

## 구조

```
plan-fusion-dev/
├── SKILL.md                              # 0~5단계 체이닝 오케스트레이션 (메인)
├── README.md                             # 이 문서
├── templates/
│   ├── fusion-synth-code.md.tmpl         # 체이닝 전용 Synth 프롬프트 — final.md가 코드 스펙까지 산출
│   └── HANDOFF-chain.md.tmpl             # 변환 결과 코드용 HANDOFF(체이닝 메타데이터 + plan-codex-opencode 호환)
└── scripts/
    ├── check-fusion-dev.sh               # 두 형제 스킬 점검 묶음 실행 (read-only)
    ├── check-cleanup.sh                  # worktree/branch/ro 정리 누수 점검 (read-only, REPORT 전)
    └── smoke-test.sh                     # 파이프라인 구조 end-to-end 검증 (dry-run, 비용 0)
```

> 변환·개발 절차의 상세(references)는 두 하위 스킬의 것을 재사용 — 이 스킬이 별도 references/를 두지 않는다. plan-fusion의 routing-fusion/fusion, plan-codex-opencode의 routing/council이 해당.

## 설계 결정 기록 (보존 결정 — 재제안 시 이 표를 먼저 볼 것)

다음 7개 후보는 Fusion-Research(codex·agy·claude → Judge → Synth) 합의로 **보존(미적용)** 이 확정됐다. 각 항목은 불변식 또는 의도적 설계 결정으로, **동일한 합의 수준(3패밀리 다수 합의 + Judge 합성 + 사실확인) 없이 번복 금지**. 미래 Fusion 라운드에서 재제안되면 아래 근거로 즉시 판정하라(재평가 루프 방지).

| # | 후보 (미적용) | 결정 | 근거 (불변식/합의 출처) | 번복 조건 |
|---|---|---|---|---|
| 1 | 심링크로 스킬 통일 | **보존** | `cd` 기반 경로(fusion.md §1·council-worktrees.sh)는 Windows/`core.symlinks=false` 배포 시 위임 전부 깨짐 → Judge §2-Q10 "전원 합의 금지". 실파일 복제 + DRIFT 가드로 신뢰성 이미 확보 | Windows 배포 공식 지원 + 심링크 없이 동등한 격리 방법 증명 |
| 2 | 개발 단계 GLM 금지 | **보존** | 계획 단계 동족회피 ≠ 개발 단계 패널 내 교차검증. 동족 비대칭은 README §"왜 이 구조인가"의 핵심 전제 → Judge §2-Q8 "전원 합의(합리적 설계)". 동결된 계획을 dev GLM이 재검하지 않음 | 비용·품질 벤치마크가 GLM 보조를 반박하는 새 근거 |
| 3 | placeholder 검증 삭제 | **보존(한정 적용됨)** | SKILL.md §0.2.5가 `<.*>` 광역 오탐을 실제 마커(`$TODO_*`·`<UNKNOWN`·`{{`)로 **한정**. 삭제가 아닌 한정 → Judge §2-Q7 합의 그대로 구현됨 | — (이미 올바른 형태로 적용됨) |
| 4 | .git/.env 제외 완화 | **보존** | fusion.md §1(L50-54) 보안 불변식: `.git` 제외 + `--safe-links` + `.env`/`.env.*` 삭제. 완화하면 skip-permissions 인젝션이 사본에서 `git push`/시크릿 유출 가능 → Judge §2-Q10 "must-avoid". **인간 승인 영역(보안)** | OS 수준 네트워크 격리 환경 도입 |
| 5 | Judge/Synth 축소 | **보존** | quorum(생존 패밀리 ≥2)이 교차검증 독립성의 최소 조건(fusion.md §2·§3-1). 축소 시 단일 패밀리 → Fusion 미성립 → Judge §2-Q10 "must-avoid" | — (스킬 존재 의미 훼손) |
| 6 | 동족회피 완화 | **보존** | check-fusion.sh §3-2 Judge 체인이 비동족 후보만 허용. 완화 시 오케스트레이터 패밀리가 자기 답 평가 → 확증편향 → Judge §2-Q10 "must-avoid" | — (교차검증 무의미) |
| 7 | self 폴백 제거 | **보존** | check-fusion.sh `orchestrator-self`가 Judge 체인 종착지. 제거 시 Judge 전 실패 → 마비(fusion.md §3-4 "절대 막히지 않음" 위반). 라벨은 이미 `${ORCH_FAMILY:-glm}`로 정정(커밋 ec3af89 ②-1) | — (마비 방어 불가결) |

> **재평가 원칙**: #4·#5·#6은 보안/독립성 불변식 → **사용자 승인 필수**(AGENTS.md 인간 승인 영역: 보안 로직). #1·#2는 아키텍처 원칙 → 번복 시 동등한 다중모델 설계 합의 필요. #3·#7은 이미 올바른 형태로 적용됐으므로 재논의 불필요.
