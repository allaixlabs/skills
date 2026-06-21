---
name: plan-fusion-dev
description: >
  메타 체이닝 워크플로우 — plan-fusion(Fusion-Research 모드)으로 다중 모델 교차검증으로 계획을 확정한 뒤,
  그 결과를 자동으로 plan-codex-opencode 개발 단계(Pipeline/Council)에 넘겨 실제 코드를 구현한다.
  개발 단계는 GPT-5.5(주축 구현/수정) + GLM-5.2(교차 리뷰/보조) 혼용이 기본이며, 오케스트레이터가 태스크 특성으로
  Pipeline(범위 명확) vs Council(답 갈림/신뢰도↑)을 선택한다. 코드 산출이 없는 단순 사실 조회 요청(스킬 상태 확인 등)은
  Fusion-Research(N+2회 호출)를 생략하고 오케스트레이터가 직접 처리하는 경량 분기로 비용을 아낀다. 다음일 때 사용:
  "plan-fusion으로 계획하고 바로 개발까지", "계획 확정 후 GPT+GLM으로 구현까지 한 번에",
  "fusion으로 잡은 설계를 그대로 개발로 이어가", "계획→개발 자동 체이닝".
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

> **진입 규칙**: 이 스킬이 명시 호출(`/plan-fusion-dev …`)되면 — 하위 `plan-fusion`의 진입 규칙과 같이 — 요청 종류(개발 체이닝·메타/스킬 검토·리서치)와 무관하게 **반드시 §0부터 실행**한다. 단, 요청 성격에 따라 세 갈래로 분기한다(silent bail-out 금지 — 어느 갈래든 명시적으로 종료 사유를 사용자에게 전달):
>
> | 요청 성격 | 진행 경로 | 근거 |
> |---|---|---|
> | **코드 산출 O** (개발 체이닝) | §0 → §1(Fusion-Research) → §2 변환 → §3 모드선택 → §4 개발 → §5 검증 | 표준 체인 |
> | **코드 산출 0 + 복잡 판단/설계 다양성** (스킬 구조 개선 아이디어 비교, 다중 접근법 평가) | §0 → **§1까지만**(Fusion-Research N+2회) → N/A 종료 | 교차검증 가치 있음 |
> | **코드 산출 0 + 단순 사실 조회** (스킬 현재 상태 확인, 파일·grep으로 답 가능한 질문, 정적 분석) | §0 → **오케스트레이터 직접 처리**(§1 생략) → N/A 종료 | N+2회 호출 과잉 — grep/파일 읽기(1회)로 충분 |
>
> **경량 분기(3행) 판정 기준**: 요청이 "코드 산출 0"이면서 다음 **모두** 충족 시 §1 생략:
> 1. 객관적 사실 조회 — 답이 스킬 파일/코드에서 grep·Read로 직접 확인 가능(설계 의견이 아닌 사실).
> 2. 단일 정답 — "어느 접근이 낫나" 같은 다중 답안 비교가 아님.
> 3. 외부 정보 불필요 — 웹 검색·다른 모델 추론 없이 현재 컨텍스트로 답 가능.
>
> 세 기준 중 하나라도 아니면 §1(Fusion-Research)로 — 경량으로 빠져 복잡 판단을 놓치는 게 비용보다 큼. 판정은 1회로, 사용자에게 "경량 분기 적용(§1 생략) — 사유: …" 1줄로 알린 후 진행.
>
> **역할경계**: 코드 산출 0 갈래(2·3행)는 §2 변환·§3 모드선택·§4 개발 체인을 **N/A로 종료**한다 — 개발 백엔드가 없는 작업에 dev 체인을 강제하지 않는다.

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
4. **개발 모드·패널·비용 1회 요약** 후 진행 — **호출 수 기준: 계획(N+2 호출) + 개발(모드별: Pipeline 2~3회 · Council-Code 4~5회)** = 합계 **Pipeline이면 N+4~N+5회, Council-Code면 N+6~N+7회** (기본 N=4 패널이면 각각 8~9회 / 10~11회, 최소 N=2면 6~7회 / 8~9회) = 단일 위임(1회) 대비 **Pipeline 약 6~9배, Council-Code 약 8~11배** 비용/시간. 모드 선택(§3)이 비용을 좌우하므로 요약 시 어느 모드로 갈지 미리 힌트를 준다. 인간 승인 영역(스키마/보안/키·시크릿/결제/배포/PRD범위/아키텍처)이면 여기서 BLOCKED.

> **스모크테스트(선택, 비용 0)**: 스킬 수정 후 구조가 끝까지 도는지 확인하려면 `bash "$SKILL_DIR/scripts/smoke-test.sh"` — 임시 sandbox에서 stub 산출 + 단계별 게이트 검증(§0 사전점검 → §2 변환·치환·UI 매핑 → §5 정리 게이트). **모델 호출 없이**(dry-run) 파이프라인 구조만 검증. exit 0=PASS. 실제 모델 호출을 포함한 풀 e2e는 별도(인간 승인, 비용 발생).

---

## 1. 계획 단계 — plan-fusion Fusion-Research 실행

하위 스킬 `plan-fusion/SKILL.md`의 **Fusion-Research 모드** 절차를 `$RUN_PF`에서 그대로 수행한다. 이 스킬이 재구현하지 않고 위임한다.

**유일한 차이 — 체이닝 전용 Synth 템플릿 사용**: plan-fusion의 Synth CLI 호출 시 기본 `templates/fusion-synth.md.tmpl` 대신 **이 스킬의 `templates/fusion-synth-code.md.tmpl`** 을 쓴다. 이 템플릿은 Synth에게 "분석 결론만"이 아니라 **코드용 스펙(Mission·Context·설계결정·변경 지시 파일별·Out of scope·Acceptance Criteria·위험)** 까지 산출하도록 지시한다. 결과적으로 `$RUN_PF/final.md`가 자유형 답변이 아니라 준정형 구현 스펙이 된다.

- 참가자 패널·Judge·Synth 백엔드는 plan-fusion의 게이트(SKILL.md §0.2.5)가 결정한 대로. 단, 이 스킬의 목적상 **최종 구현이 GPT+GLM 혼용**이므로, 가능하면 Synth 백엔드가 개발 주축과 충돌하지 않게 두는 게 깔끔하다(강제 아님 — 동족 룰이 우선).
- 검증(plan-fusion §5): final.md의 위험·미검증 주장은 오케스트레이터가 grep으로 사실 판정. 이 단계에서 검증된 설계만 다음으로 넘긴다.
- 산출물: `$RUN_PF/final.md`(코드 스펙 포함), `$RUN_PF/judge.md`, `$RUN_PF/synthesis.md`.
- **UI 노출 판정 위임·보존**: UI 노출 판정은 계획 단계(plan-fusion ANALYZE)에서 내려지며, 합성 템플릿(`templates/fusion-synth-code.md.tmpl`)의 `### UI 노출 판정`(h3)·`#### 디자인 스펙`(h4, 서브) 섹션을 통해 `final.md`에 반드시 포함된다. 변환 단계(§2)는 이것을 레벨을 정규화하여(`### UI 노출 판정` → `## UI 노출 판정`, `#### 디자인 스펙` → `## 디자인 스펙`) handoff로 옮긴다 — UI 노출 판정이 yes인데 디자인 스펙이 없으면 변환을 중단하고 계획 단계 산출을 보완한다.

---

## 2. 변환 단계 — final.md → 코드용 HANDOFF

이 스킬의 **핵심 차별점**. final.md의 준정형 스펙을 plan-codex-opencode 입력(handoff.md)으로 옮긴다.

**`templates/HANDOFF-chain.md.tmpl`** 을 기준으로 `$RUN_PCO/handoff.md`를 작성:

1. **복사(재구성 최소)**: final.md 섹션 → handoff 대응 섹션으로 1:1 매핑 — `Mission` → Mission, `UI 노출 판정`(노출 여부·근거) → UI 노출 판정, `디자인 스펙`(UI 노출=yes 시) → 디자인 스펙, `설계 결정`(채택·근거·기각대안) → 설계 결정, `Context`(루트/스택) → Context, `변경 지시(파일별)` → 변경 지시(파일별), `Out of scope` → Out of scope, `위험·미검증` → 위험·미검증(계획 단계 검증 결과를 같이 기입), `Acceptance Criteria` → Acceptance Criteria. 체이닝 메타데이터(상위 RUN 경로·Judge/Synth 주체)는 handoff 상단에 채운다.
   - ⚠️ **UI 매핑 가드**: `final.md`에 `### UI 노출 판정` 섹션이 반드시 있어야 한다(synth-code 템플릿이 산출하도록 지시). 노출 판정=yes인데 `디자인 스펙` 섹션이 비었거나 없으면 변환을 **중단**하고 계획 단계(synth) 산출을 보완한 뒤 재변환한다 — 이 매핑을 건너뛰면 UI 결정이 handoff로 전달되지 않아 개발 단계에서 UI가 통째로 누락된다.
   - **레벨 정규화**: final.md(`### UI 노출 판정`/`#### 디자인 스펙`) → handoff(`## UI 노출 판정`/`## 디자인 스펙`)로 헤딩 레벨을 맞춘다(두 템플릿 레벨이 다름 — `templates/fusion-synth-code.md.tmpl` h3/h4, `templates/HANDOFF-chain.md.tmpl` h2/h2). 변환 후 handoff에서 다음 3단계로 검증한다:
     1. `grep -nE '^## UI 노출 판정' "$RUN_PCO/handoff.md"` — 섹션 존재 (없으면 변환 중단, 계획 단계 산출 보완).
     2. 노출 판정=yes면 `grep -nE '^## 디자인 스펙' "$RUN_PCO/handoff.md"` — 섹션 존재 (없으면 변환 중단).
     3. 노출 판정=yes면 디자인 스펙 **본문 내용** 검증 — `awk '/^## 디자인 스펙/{f=1;next} /^## /{f=0} f' "$RUN_PCO/handoff.md" | grep -qE '타이포|컬러|간격|레이아웃|폰트|HEX|spacing|layout|color'` — 빈 섹션이나 자리표시자만 있는 경우(예: `{{폰트}}`만 있고 실제 수치 없음)를 잡는다. 매칭이 없으면 synth 산출이 미완이므로 계획 단계 보완 후 재변환. (키워드는 synth-code 템플릿이 요구하는 항목 — 타이포/컬러/간격-레이아웃 — 과 대응.)
2. **오케스트레이터가 직접 보강하는 3개** (final.md엔 없는 read-only 캡처 정보):
   - **Baseline**: `git -C "<root>" status --short` + `git -C "<root>" rev-parse HEAD` 실행 → 결과를 handoff의 Baseline 섹션에 기입.
   - **빌드/테스트/린트 명령**: 프로젝트에서 식별(package.json scripts · Makefile · Gemfile · Cargo.toml 등). final.md의 `$TODO_BUILD`/`$TODO_TEST`/`$TODO_LINT` 자리표시자를 실제 명령으로 치환. Acceptance Criteria 안의 자리표시자도 같이 치환.
   - **dev 서버 URL**(해당 시): 실행 중이면 캡처, 아니면 N/A 표시.
3. **치환 검증**: `grep -nE '\$TODO_(BUILD|TEST|LINT|URL)|<UNKNOWN|<\.\.\.|{{' "$RUN_PCO/handoff.md"` 로 미치환 자리표시자가 0인지 확인(실제 마커만 검사 — `<.*>` 광역 패턴은 합법 `<T>` 제네릭·HTML 옵션 오탐을 낳으므로 쓰지 않는다). 남아 있으면 채운다. `{{` 검사는 진짜 미치환 템플릿 토큰 누수를 잡으므로 유지한다.

⚠️ **역할경계**: 변환은 문서 작성만. 이 단계에서 코드를 직접 수정하지 않는다. Baseline/명령 캡처는 read-only 조회(`git status`/매니페스트 읽기)만.

---

## 3. 개발 모드 자동 선택

오케스트레이터가 태스크 특성·final.md의 설계 결정을 보고 모드를 정한다. **강제가 아니라 추천** — 사용자가 명시하면 따른다.

| 신호 | 모드 | 개발 호출 수 | 이유 |
|---|---|---|---|
| 스키마/보안/결제/배포/아키텍처 변경 | **BLOCKED** | — | 인간 승인 영역 — 자동 진행 금지 |
| 답이 갈릴 수 있는 설계·구현 + 신뢰도↑ | **Council-Code** | **4~5회** (구현 병렬 2 + 교차리뷰 2 + 합성 시 +1) | GPT+GLM 병렬 구현 → 교차리뷰 → 채택/합성 |
| 범위 명확 + 구현 품질 검증 깊이 | **Pipeline** | **2~3회** (구현 1 + 리뷰 1 + 수정 resume 0~1) | GPT-5.5 구현+수정, GLM-5.2 리뷰(역할 분리, 비용 효율) |
| 모호(기본) | **Pipeline** | 2~3회 | 비용 효율 + "개발엔 고스펙 불필요" 철학과 GPT 주축 부합 |

> **모드명 정규화**: 사용자 표시명은 `Council`로 줄여 써도 되나, 내부·REPORT·synthesis 문맥(하위 `plan-codex-opencode`가 구분하는 `Council-Code`/`Council-Research`/`Pipeline`)에는 `Council-Code`로 명시한다.

선택 시 1줄 근거를 사용자에게 표시하고 진행.

---

## 4. 개발 단계 — plan-codex-opencode 절차 실행

하위 스킬 `plan-codex-opencode/SKILL.md`의 절차를 `$RUN_PCO`에서 그대로 수행한다. 이 스킬은 §1 ANALYZE(코드 분석)·§2 PLAN(handoff 작성)를 **이미 변환 단계(§2)가 대신했으므로 건너뛰고** §3 DELEGATE부터 진입한다.

> **`$RUN` 바인딩**: 이하 `plan-codex-opencode` 절차 본문이 말하는 `$RUN`은 **이 스킬의 `$RUN_PCO`** 이다(계획 단계 `$RUN_PF`가 아님). 모든 handoff·worktree·council·manifest 경로는 `$RUN_PCO` 아래다.

- **패널(기본 라인업)**: codex `gpt-5.5`(effort xhigh 또는 high) + opencode `glm-5.2`. 둘 다 이 스킬 사전점검(check-fusion-dev.sh)에서 가용 확인됨.
- **Pipeline 모드 시 역할 분배**(SKILL.md plan-codex-opencode §3 Pipeline):
  - 구현(메인): codex `gpt-5.5` xhigh — `$RUN_PCO`의 handoff로 위임, SESSION_A 추출.
  - 리뷰: 구현자와 다른 패밀리 = opencode `glm-5.2`. (codex 구현이면 리뷰는 omo/opencode로 — 역방향도 허용.)
  - 수정: codex `gpt-5.5` resume — 리뷰 지적 반영.
  - 종합: 오케스트레이터(plan-codex-opencode §4 종합).
- **Council-Code 모드 시**: 두 패널이 각자 worktree에서 병렬 구현 → 교차리뷰 → 채택/합성. 비용 2배지만 독립성 최대.
- ⚠️ **오케스트레이터 동족 주의**: 오케스트레이터=glm(ZCode)이면, 개발 단계에 GLM이 들어가는 게 "동족"이 될 수 있다. 단 **개발 단계는 계획 단계와 다르다** — 여기선 GLM이 "리뷰어/견제" 역할로 GPT 구현을 교차검증하므로, 오케스트레이터의 분석·검증과 GLM 리뷰가 같은 패밀리여도 *패널 내* 교차검증(GPT↔GLM)은 유효하다. synthesis에 "오케스트레이터-GLM 동족"을 표기만 하고 진행(계획 단계의 엄격 동족 제거와 다른 정책).

---

## 5. 검증 · REPORT

### 검증
- **하위 스킬 검증에 맡김**: plan-codex-opencode의 §4 VERIFY(직접 실행 증거 — 빌드/타입/테스트/린트 exit·출력, AC 대조, baseline·범위 확인)를 그대로 수행. result/final 주장은 근거 아님.
- **UI 노출 작업이면(handoff 'UI 노출 판정=yes')**: 하위 스킬 검증에 더해, 디자인 스펙(타이포/컬러/간격/레이아웃) 반영 여부 + UI AC 충족을 명시적으로 대조한다. final.md의 '디자인 스펙'이 handoff로 전달됐는지도 확인(변환 단계 누락 탐지) — 누락 시 계획 단계 산출 보완 후 재변환.
- **체이닝 추가 검증**: 개발 결과가 상위 plan-fusion의 `final.md` 설계 결정과 **충돌하지 않는지** 1회 대조(예: 기각한 대안이 구현에 들어갔는지). 충돌이면 synthesis.md에 명시.

### loop-md 연동
루트 `loop.md` 있으면: 개발 단계는 **plan-codex-opencode의 loop-md 연동 절차를 그대로** 수행(**완료 결과를 사용자에게 먼저 보고한 뒤** 별도로 loop-md Verify — 지연 방지) — `council_wt_adopt` → 결과 보고 → **메인 ROOT에서** Verify(①②③) 실행 → `.loop/last-verified`가 현재 HEAD인지 확인 → 커밋. council/Pipeline 교차리뷰가 ③정성의 독립 검증을 자연 충족. 계획 단계($RUN_PF)는 read-only라 `.loop/last-verified`와 무관하므로 마커 처리는 개발 단계($RUN_PCO)만 담당한다. 루트 `loop.md` 없으면 N/A.

### REPORT
최종 메시지에 포함:
- **체이닝 전체 요약**: 계획(plan-fusion 패널·Judge·Synth) → 개발(plan-codex-opencode 모드·패널) → 최종 변경
- 계획 단계: 참가자·Judge·Synth 백엔드 + 동족/비독립 여부 · 핵심 설계 결정
- 변환 단계: 보강한 3개(Baseline 출처·빌드/테스트/린트 명령 출처·dev URL) + 미치환 자리표시자 0 확인
- 개발 단계: 모드(Pipeline/Council-Code)·패널·effort · 패널별 상태(DONE/BLOCKED/ORCHESTRATION_FAIL) · 종합(합의/충돌/판정 + 근거)
- **최종 변경 파일 목록 + 기준별 충족 증거**(실행 로그 요약)
- **BLOCKED 여부·적용한 기본 결정·남은 질문**(분리)
- 라운드 수(계획+개발 합산, `ORCHESTRATION_FAIL` 횟수)
- `$RUN_PF`·`$RUN_PCO` 경로(handoff/judge/final/synthesis/diff/xreview/manifest)
- UI면 before/after 스크린샷 경로
- **정리(기계적 게이트)**: 두 단계의 worktree/branch/`ro/` 누수를 REPORT 직전 **스크립트로 점검**한다 — 문서 지시에만 의존하면 오케스트레이터가 깜빡하고 누수를 남긴다.
  ```bash
  # exit 0=잔존 0(정상) / exit 1=누수 발견 → council_wt_cleanup 재호출 또는 수동 정리 후 재점검
  PLAN_RUN="$RUN_PF" DEV_RUN="$RUN_PCO" bash "$SKILL_DIR/scripts/check-cleanup.sh"
  ```
  - 점검 범위: `git worktree list`의 `/wt/`·`/council/` 경로 · `council/*` 브랜치 잔존 · `$RUN_PF/ro`·`$RUN_PCO/ro` 디렉토리(council_wt_cleanup이 다루지 않는 영역 — plan-fusion/references/fusion.md §5).
  - `CLEANUP_STATUS=LEAK`면 REPORT를 **내보내기 전에** 정리 후 재점검. exit 1을 무시하고 REPORT하면 누수가 사용자에게 전달된다.

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
- **비용/시간이 가치를 못 넘을 때**: 계획(N+2) + 개발(2~3) = 단일 위임의 **약 6~9배**(N+4~N+5회; N=4면 8~9배, N=2면 6~7배). 사소·저위험·되돌리기 쉬운 작업이거나 답이 갈릴 여지가 작으면 과하다. **답이 갈릴 수 있고 틀리면 비용이 큰 복잡 구현·판단**에만 의미.
