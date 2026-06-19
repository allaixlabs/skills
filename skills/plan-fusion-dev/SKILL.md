---
name: plan-fusion-dev
description: >
  메타 체이닝 워크플로우 — plan-fusion(Fusion-Research 모드)으로 다중 모델 교차검증으로 계획을 확정한 뒤,
  그 결과를 자동으로 plan-codex-opencode 개발 단계(Pipeline/Council)에 넘겨 실제 코드를 구현한다.
  개발 단계는 GPT-5.5(주축 구현/수정) + GLM-5.2(교차 리뷰/보조) 혼용이 기본이며, 오케스트레이터가 태스크 특성으로
  Pipeline(범위 명확) vs Council(답 갈림/신뢰도↑)을 선택한다. 다음일 때 사용: "plan-fusion으로 계획하고 바로 개발까지",
  "계획 확정 후 GPT+GLM으로 구현까지 한 번에", "fusion으로 잡은 설계를 그대로 개발로 이어가", "계획→개발 자동 체이닝".
  계획만 필요하면 plan-fusion, 개발만 필요하면 plan-codex-opencode를, 단일 모델이면 plan-then-* 을 쓴다.
---

# plan-fusion-dev — 계획(plan-fusion) → 자동 개발(plan-codex-opencode) 체이닝

**오케스트레이터 = 체이닝 조율자**. 두 하위 스킬을 순차로 이어 실행하고, 그 사이 **변환 단계**만 직접 수행한다.
실제 분석·합성·구현·리뷰는 항상 하위 스킬과 그 백엔드가 한다. **오케스트레이터는 프로덕션 코드를 직접 수정하지 않는다.**

## 핵심 구조

```
/plan-fusion-dev <task>
  │
  ├─ ① 계획: plan-fusion Fusion-Research 모드 실행
  │     └─ 다중 모델 독립 풀이 → Judge → Synth(체이닝 전용 템플릿)
  │     산출: $RUN_PF/final.md (확정 설계 + 코드 스펙 포함)
  │
  ├─ ② 변환: final.md → 코드용 HANDOFF ($RUN_PCO/handoff.md)
  │     └─ Synth 템플릿이 대부분 채움. 오케스트레이터는 3개만 직접 보강:
  │        Baseline(git status) · 빌드/테스트/린트 명령 · dev 서버 URL(해당 시)
  │
  ├─ ③ 개발 모드 선택: 오케스트레이터가 태스크 특성으로 Pipeline vs Council 결정
  │
  └─ ④ 개발: plan-codex-opencode 절차 실행 → 검증 → REPORT
        └─ Pipeline 기본: 구현 GPT-5.5 xhigh(메인) + 리뷰 GLM-5.2(교차검증) + 수정 GPT resume
```

`SKILL_DIR` = 이 SKILL.md가 있는 디렉토리. `$RUN_PF` = 계획 단계 격리 폴더. `$RUN_PCO` = 개발 단계 격리 폴더(별도).

> **의존**: 두 형제 스킬이 같은 레포에 있어야 한다 — `plan-fusion/`, `plan-codex-opencode/`. 사전점검 스크립트가 이를 검증한다.

---

## 0. 사전 점검 + 모드/패널 결정

1. **메타 점검**(read-only): `bash "$SKILL_DIR/scripts/check-fusion-dev.sh"` → `FUSION_DEV_PLAN_READY` · `FUSION_DEV_DEV_READY` · `FUSION_DEV_CAPABILITY`.
   - `full`(양쪽 가용) → 진행. `plan-only`(계획만) → 개발은 plan-then-codex 등으로 안내 후 사용자 결정. `dev-only`/`none` → exit 1, 안내·중단.
   - 두 하위 스크립트(check-fusion.sh · check-panels.sh)의 출력(오케스트레이터 패밀리·Judge/Synth 기본·패널 가용성·GLM 인증)이 같이 나오니 숙지한다.
2. **오케스트레이터 패밀리 확인**: `PLAN_FUSION_ORCHESTRATOR=glm|gpt|gemini|claude` env(없으면 argv/탐침). 동족 회피 룰이 계획 단계에 자동 적용된다(check-fusion.sh). **개발 단계는 이 제약을 받지 않는다** — 계획에서 빠진 패밀리도 개발 패널엔 들어간다(예: 오케스트레이터=glm이면 계획엔 GLM이 안 들어가지만 개발엔 GLM이 리뷰어로 들어감).
3. **격리 폴더 2개 생성**:
   ```bash
   slug=$(printf '%s' "<task 한단어>" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | cut -c1-20)
   RUN_PF=$(umask 077; mktemp -d "${TMPDIR:-/tmp}/pfd.plan.${slug}.XXXXXX") || { echo "RUN_PF 생성 실패" >&2; exit 1; }
   RUN_PCO=$(umask 077; mktemp -d "${TMPDIR:-/tmp}/pfd.dev.${slug}.XXXXXX")  || { echo "RUN_PCO 생성 실패" >&2; exit 1; }
   [ -d "$RUN_PF" ] && [ -d "$RUN_PCO" ] || { echo "RUN 생성 실패" >&2; exit 1; }
   # manifest는 $RUN_PCO 안에 — 두 RUN은 mktemp 접미어(XXXXXX)로 고유하므로 slug 충돌 없고,
   # 개발 단계가 $RUN_PCO에서 실행되니 추적도 자연스럽다.
   printf 'plan_run=%s\ndev_run=%s\nslug=%s\n' "$RUN_PF" "$RUN_PCO" "$slug" > "$RUN_PCO/manifest"
   echo "RUN_PF=$RUN_PF"; echo "RUN_PCO=$RUN_PCO"
   ```
4. **개발 모드·패널·비용 1회 요약** 후 진행 — 계획(N+2 호출) + 개발(2~3 호출) = 단일 위임의 **3~5배** 비용/시간. 인간 승인 영역(스키마/보안/키·시크릿/결제/배포/PRD범위/아키텍처)이면 여기서 BLOCKED.

---

## 1. 계획 단계 — plan-fusion Fusion-Research 실행

하위 스킬 `plan-fusion/SKILL.md`의 **Fusion-Research 모드** 절차를 `$RUN_PF`에서 그대로 수행한다. 이 스킬이 재구현하지 않고 위임한다.

**유일한 차이 — 체이닝 전용 Synth 템플릿 사용**: plan-fusion의 Synth CLI 호출 시 기본 `templates/fusion-synth.md.tmpl` 대신 **이 스킬의 `templates/fusion-synth-code.md.tmpl`** 을 쓴다. 이 템플릿은 Synth에게 "분석 결론만"이 아니라 **코드용 스펙(Mission·Context·설계결정·변경 지시 파일별·Out of scope·Acceptance Criteria·위험)** 까지 산출하도록 지시한다. 결과적으로 `$RUN_PF/final.md`가 자유형 답변이 아니라 준정형 구현 스펙이 된다.

- 참가자 패널·Judge·Synth 백엔드는 plan-fusion의 게이트(SKILL.md §0.2.5)가 결정한 대로. 단, 이 스킬의 목적상 **최종 구현이 GPT+GLM 혼용**이므로, 가능하면 Synth 백엔드가 개발 주축과 충돌하지 않게 두는 게 깔끔하다(강제 아님 — 동족 룰이 우선).
- 검증(plan-fusion §5): final.md의 위험·미검증 주장은 오케스트레이터가 grep으로 사실 판정. 이 단계에서 검증된 설계만 다음으로 넘긴다.
- 산출물: `$RUN_PF/final.md`(코드 스펙 포함), `$RUN_PF/judge.md`, `$RUN_PF/synthesis.md`.

---

## 2. 변환 단계 — final.md → 코드용 HANDOFF

이 스킬의 **핵심 차별점**. final.md의 준정형 스펙을 plan-codex-opencode 입력(handoff.md)으로 옮긴다.

**`templates/HANDOFF-chain.md.tmpl`** 을 기준으로 `$RUN_PCO/handoff.md`를 작성:

1. **복사(재구성 최소)**: final.md 섹션 → handoff 대응 섹션으로 1:1 매핑 — `Mission` → Mission, `설계 결정`(채택·근거·기각대안) → 설계 결정, `Context`(루트/스택) → Context, `변경 지시(파일별)` → 변경 지시(파일별), `Out of scope` → Out of scope, `위험·미검증` → 위험·미검증(계획 단계 검증 결과를 같이 기입), `Acceptance Criteria` → Acceptance Criteria. 체이닝 메타데이터(상위 RUN 경로·Judge/Synth 주체)는 handoff 상단에 채운다.
2. **오케스트레이터가 직접 보강하는 3개** (final.md엔 없는 read-only 캡처 정보):
   - **Baseline**: `git -C "<root>" status --short` + `git -C "<root>" rev-parse HEAD` 실행 → 결과를 handoff의 Baseline 섹션에 기입.
   - **빌드/테스트/린트 명령**: 프로젝트에서 식별(package.json scripts · Makefile · Gemfile · Cargo.toml 등). final.md의 `$TODO_BUILD`/`$TODO_TEST`/`$TODO_LINT` 자리표시자를 실제 명령으로 치환. Acceptance Criteria 안의 자리표시자도 같이 치환.
   - **dev 서버 URL**(해당 시): 실행 중이면 캡처, 아니면 N/A 표시.
3. **치환 검증**: `grep -nE '\$TODO_|<.*>|{{' "$RUN_PCO/handoff.md"` 로 미치환 자리표시자/placeholder가 0인지 확인. 남아 있으면 채운다.

⚠️ **역할경계**: 변환은 문서 작성만. 이 단계에서 코드를 직접 수정하지 않는다. Baseline/명령 캡처는 read-only 조회(`git status`/매니페스트 읽기)만.

---

## 3. 개발 모드 자동 선택

오케스트레이터가 태스크 특성·final.md의 설계 결정을 보고 모드를 정한다. **강제가 아니라 추천** — 사용자가 명시하면 따른다.

| 신호 | 모드 | 이유 |
|---|---|---|
| 스키마/보안/결제/배포/아키텍처 변경 | **BLOCKED** | 인간 승인 영역 — 자동 진행 금지 |
| 답이 갈릴 수 있는 설계·구현 + 신뢰도↑ | **Council** | GPT+GLM 병렬 구현 → 교차리뷰 → 채택/합성 |
| 범위 명확 + 구현 품질 검증 깊이 | **Pipeline** | GPT-5.5 구현+수정, GLM-5.2 리뷰(역할 분리, 비용 효율) |
| 모호(기본) | **Pipeline** | 비용 효율 + "개발엔 고스펙 불필요" 철학과 GPT 주축 부합 |

선택 시 1줄 근거를 사용자에게 표시하고 진행.

---

## 4. 개발 단계 — plan-codex-opencode 절차 실행

하위 스킬 `plan-codex-opencode/SKILL.md`의 절차를 `$RUN_PCO`에서 그대로 수행한다. 이 스킬은 §1 ANALYZE(코드 분석)·§2 PLAN(handoff 작성)를 **이미 변환 단계(§2)가 대신했으므로 건너뛰고** §3 DELEGATE부터 진입한다.

- **패널(기본 라인업)**: codex `gpt-5.5`(effort xhigh 또는 high) + opencode `glm-5.2`. 둘 다 이 스킬 사전점검(check-fusion-dev.sh)에서 가용 확인됨.
- **Pipeline 모드 시 역할 분배**(SKILL.md plan-codex-opencode §3 Pipeline):
  - 구현(메인): codex `gpt-5.5` xhigh — `$RUN_PCO`의 handoff로 위임, SESSION_A 추출.
  - 리뷰: 구현자와 다른 패밀리 = opencode `glm-5.2`. (codex 구현이면 리뷰는 omo/opencode로 — 역방향도 허용.)
  - 수정: codex `gpt-5.5` resume — 리뷰 지적 반영.
  - 종합: 오케스트레이터(plan-codex-opencode §4 종합).
- **Council 모드 시**: 두 패널이 각자 worktree에서 병렬 구현 → 교차리뷰 → 채택/합성. 비용 2배지만 독립성 최대.
- ⚠️ **오케스트레이터 동족 주의**: 오케스트레이터=glm(ZCode)이면, 개발 단계에 GLM이 들어가는 게 "동족"이 될 수 있다. 단 **개발 단계는 계획 단계와 다르다** — 여기선 GLM이 "리뷰어/견제" 역할로 GPT 구현을 교차검증하므로, 오케스트레이터의 분석·검증과 GLM 리뷰가 같은 패밀리여도 *패널 내* 교차검증(GPT↔GLM)은 유효하다. synthesis에 "오케스트레이터-GLM 동족"을 표기만 하고 진행(계획 단계의 엄격 동족 제거와 다른 정책).

---

## 5. 검증 · REPORT

### 검증
- **하위 스킬 검증에 맡김**: plan-codex-opencode의 §4 VERIFY(직접 실행 증거 — 빌드/타입/테스트/린트 exit·출력, AC 대조, baseline·범위 확인)를 그대로 수행. result/final 주장은 근거 아님.
- **체이닝 추가 검증**: 개발 결과가 상위 plan-fusion의 `final.md` 설계 결정과 **충돌하지 않는지** 1회 대조(예: 기각한 대안이 구현에 들어갔는지). 충돌이면 synthesis.md에 명시.

### loop-md 연동
루트 `loop.md` 있으면: 개발 단계는 **plan-codex-opencode의 loop-md 연동 절차를 그대로** 수행 — `council_wt_adopt` 후 **메인 ROOT에서** Verify(①②③) 실행 → `.loop/last-verified`가 현재 HEAD인지 확인 → 커밋. council/Pipeline 교차리뷰가 ③정성의 독립 검증을 자연 충족. 계획 단계($RUN_PF)는 read-only라 `.loop/last-verified`와 무관하므로 마커 처리는 개발 단계($RUN_PCO)만 담당한다. 루트 `loop.md` 없으면 N/A.

### REPORT
최종 메시지에 포함:
- **체이닝 전체 요약**: 계획(plan-fusion 패널·Judge·Synth) → 개발(plan-codex-opencode 모드·패널) → 최종 변경
- 계획 단계: 참가자·Judge·Synth 백엔드 + 동족/비독립 여부 · 핵심 설계 결정
- 변환 단계: 보강한 3개(Baseline 출처·빌드/테스트/린트 명령 출처·dev URL) + 미치환 자리표시자 0 확인
- 개발 단계: 모드(Pipeline/Council)·패널·effort · 패널별 상태(DONE/BLOCKED/ORCHESTRATION_FAIL) · 종합(합의/충돌/판정 + 근거)
- **최종 변경 파일 목록 + 기준별 충족 증거**(실행 로그 요약)
- **BLOCKED 여부·적용한 기본 결정·남은 질문**(분리)
- 라운드 수(계획+개발 합산, `ORCHESTRATION_FAIL` 횟수)
- `$RUN_PF`·`$RUN_PCO` 경로(handoff/judge/final/synthesis/diff/xreview/manifest)
- UI면 before/after 스크린샷 경로
- **정리**: 두 단계의 worktree/branch/`ro/` 누수 점검 — plan-fusion은 `$RUN_PF`의 wt/council/ro, plan-codex-opencode은 `$RUN_PCO`의 wt/council/ro. 양쪽 다 잔존 0 확인(`git worktree list` · `git branch --list 'council/*'`).

---

## 역할 경계 (절대 규칙)

- 오케스트레이터는 **체이닝·변환·모드선택·검증**만. **프로덕션 코드를 직접 수정하지 않는다.**
- 실제 구현·리뷰·종합은 항상 하위 스킬의 백엔드. 변환 단계는 문서 작성·read-only 캡처만.
- 변환 단계에서 코드를 직접 고쳐야 할 유혹이 들면 → 그건 개발 백엔드의 일이다. handoff에 지시만 담아 넘긴다.
- 두 하위 스킬의 인간 승인 영역(BLOCKED) 규칙을 그대로 준수.
- plan-fusion의 동족 회피(엄격)와 plan-codex-opencode의 패널 교차검증(완화) 정책 차이를 존중 — 단계별로 해당 스킬의 룰을 따른다.

## 이 스킬을 쓰지 말아야 할 때

- **계획만 필요** → **plan-fusion** 단독. 개발까지 자동으로 가면 비용만 커진다.
- **개발만 필요**(계획이 이미 명확) → **plan-codex-opencode** 단독. plan-fusion 계획 단계는 낭비.
- **단일 모델 위임** → **plan-then-codex**(GPT) / **plan-then-opencode**(omo). 혼용 필요 없으면 훨씬 가볍다.
- **비용/시간이 가치를 못 넘을 때**: 계획(N+2) + 개발(2~3) = 단일 위임의 **3~5배**. 사소·저위험·되돌리기 쉬운 작업이거나 답이 갈릴 여지가 작으면 과하다. **답이 갈릴 수 있고 틀리면 비용이 큰 복잡 구현·판단**에만 의미.
