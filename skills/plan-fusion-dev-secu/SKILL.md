---
name: plan-fusion-dev-secu
description: >
  보안 중심 메타 체이닝 워크플로우 — plan-fusion-secu(Fusion-Research 모드, 보안 체크리스트 주입)로
  다중 모델 교차검증으로 계획을 확정한 뒤, 그 결과를 자동으로 plan-codex-opencode 개발 단계에 넘겨
  실제 코드를 구현한다. 계획 단계에서 L1+L2 보안 검증이 강제되고, 개발 단계에서 L1 게이트가 재실행된다.
  codeSecurity 프리셋/심층 작업 시 L3 보안 백엔드가 계획 단계에 추가 발동.
  다음일 때 사용: "보안 검증 포함해서 계획하고 바로 개발까지", "시큐어 코딩 점검하며 체이닝",
  "codeSecurity로 잡은 설계를 그대로 보안 개발로 이어가", "보안 fusion 계획→개발 자동 체이닝".
  계획+보안만 필요하면 plan-fusion-secu, 개발만(보안 없이) 필요하면 plan-fusion-dev를,
  단일 모델 보안 개발이면 plan-then-codex / plan-then-opencode를 쓴다.
---

# plan-fusion-dev-secu — 보안 체이닝 (plan-fusion-secu 계획 → 보안 개발)

**오케스트레이터 = 체이닝 조율자.** 두 하위 스킬을 순차로 이어 실행하고, 그 사이 **변환 단계**만 직접 수행한다. **보안 게이트가 양쪽 단계에 모두 적용**된다는 게 `plan-fusion-dev`와의 유일한 차이.

## 핵심 구조

```
/plan-fusion-dev-secu <task>
  │
  ├─ ① 계획: plan-fusion-secu Fusion-Research 모드 실행
  │     └─ 다중 모델 독립 풀이 + L1 정적분석(병렬) + Judge(보안 루브릭) → Synth(체이닝+보안 전용 템플릿)
  │     산출: $RUN_PF/final.md (확정 설계 + 코드 스펙 + 보안 판정 + SECURE_SCOPE)
  │
  ├─ ② 변환: final.md → 코드용 HANDOFF ($RUN_PCO/handoff.md)
  │     └─ 보안 AC + SECURE_CHECKLIST 를 handoff로 매핑 (누락 시 변환 중단)
  │
  ├─ ③ 개발 모드 선택: Pipeline(범위 명확) vs Council-Code(답 갈림/신뢰도↑)
  │
  └─ ④ 개발: plan-codex-opencode 절차 실행 → 🔒 L1 게이트 재실행 → 검증 → REPORT
```

`SKILL_DIR` = 이 SKILL.md가 있는 디렉토리. `$RUN_PF` = 계획 단계 격리 폴더. `$RUN_PCO` = 개발 단계 격리 폴더.

## 자산 참조 (SSOT)

- **기반 워크플로우**: `../plan-fusion-dev/SKILL.md` (§0~§5 본문 — 체이닝 구조 상속)
- **보안 체크리스트**: `../plan-fusion-secu/references/secure-coding.md` (43개 항목 SSOT)
- **계획 단계**: `../plan-fusion-secu/SKILL.md` (L1+L2 강제, 보안 Judge/Synth)
- **개발 단계**: `../plan-codex-opencode/SKILL.md` (Pipeline/Council)
- **격리·worktree**: `../plan-fusion/scripts/council-worktrees.sh`

**이 스킬만의 고유 자산**:
- `templates/fusion-synth-code-secu.md.tmpl` — 체이닝+보안 Synth 템플릿(final.md에 보안 AC + SECURE_SCOPE 포함)
- `templates/HANDOFF-chain-secu.md.tmpl` — 보안 AC 매핑 + L1 게이트 지시 포함 HANDOFF

> **의존**: 형제 스킬 3개(`plan-fusion-secu/`, `plan-fusion-dev/`, `plan-codex-opencode/`)가 같은 레포에 있어야 한다.

---

## 0. 사전점검 + 보안 강제

1. **메타 점검**(read-only): `bash "$SKILL_DIR/scripts/check-fusion-dev-secu.sh"` (또는 `../plan-fusion-dev/scripts/check-fusion-dev.sh` 래핑):
   - `FUSION_DEV_PLAN_READY`·`FUSION_DEV_DEV_READY`·`FUSION_DEV_CAPABILITY`
   - **추가**: `SECURE_MODE=yes`(강제), `SECURE_L1_CAPABILITY`(도구 감지) — `../plan-fusion-secu/scripts/check-fusion-secu.sh` 재사용.
2. **격리 폴더 2개**: `$RUN_PF`(계획), `$RUN_PCO`(개발) — 기존 plan-fusion-dev §0.3과 동일.
3. **비용 요약**: 계획(N+2 호출 + L1) + 개발(모드별) + (조건) L3 = 단일 위임 대비 **Pipeline 약 8~11배, Council-Code 약 10~13배**. 보안 검증 오버헤드로 plan-fusion-dev보다 +1~2배. 인간 승인 영역이면 BLOCKED.

---

## 1. 계획 단계 — plan-fusion-secu Fusion-Research

하위 스킬 `plan-fusion-secu/SKILL.md`의 Fusion-Research 모드를 `$RUN_PF`에서 수행한다. **유일한 차이 — 체이닝 전용 Synth 템플릿 사용**:

- 일반 plan-fusion-secu의 `templates/fusion-synth-secu.md.tmpl` 대신 **이 스킬의 `templates/fusion-synth-code-secu.md.tmpl`** 사용.
- 이 템플릿은 Synth에게 분석 결론 + 코드 스펙 + **보안 AC + SECURE_SCOPE + L1 결과 대조**까지 산출하도록 지시.
- 결과적으로 `$RUN_PF/final.md`는 준정형 구현 스펙 + 보안 판정을 모두 담는다.

**산출물**: `$RUN_PF/final.md`(코드 스펙 + 보안), `$RUN_PF/judge.md`, `$RUN_PF/synthesis.md`, `$RUN_PF/l1-findings.json`, `$RUN_PF/l1-summary.json`.

⚠️ **계획 단계 L1 FAIL 시**: 치명적 취약점이 이미 코드에 있으면 개발로 넘기기 전에 사용자에게 보고. 자동 패치 금지.

---

## 2. 변환 단계 — final.md → 코드용 HANDOFF (보안 매핑 게이트)

이 스킬의 핵심 차별점. `templates/HANDOFF-chain-secu.md.tmpl` 기준으로 `$RUN_PCO/handoff.md` 작성:

1. **복사(재구성 최소)**: final.md 섹션 → handoff 대응 섹션으로 1:1 매핑:
   - Mission → Mission · UI 노출 판정 → UI 노출 판정 · 설계 결정 → 설계 결정 · Context → Context
   - 변경 지시(파일별) → 변경 지시 · Out of scope → Out of scope · AC → AC
   - **🔒 SECURE_SCOPE** → SECURE_SCOPE (반드시 매핑 — 누락 시 변환 중단)
   - **🔒 SECURE_CHECKLIST** → SECURE_CHECKLIST
   - **🔒 보안 AC** → AC의 보안 항목으로 병합
   - **🔒 계획 단계 L1 결과** → "계획 단계에서 이미 식별된 취약점"으로 기록
2. **오케스트레이터가 직접 보강**: Baseline(git status), 빌드/테스트/린트 명령, dev URL, 전수 영향 분석(grep) — 기존 plan-fusion-dev §2와 동일.
3. **🔒 보안 매핑 게이트(필수)**:
   - `grep -nE '^## 🔒 SECURE_SCOPE' "$RUN_PCO/handoff.md"` — 섹션 존재 (없으면 변환 중단, 계획 단계 산출 보완).
   - SECURE_SCOPE 항목이 비어 있거나 placeholder(`{{}}`) 잔존하면 변환 중단.
   - 계획 단계 L1에서 발견된 취약점이 handoff에 전달됐는지 확인(전달 안 되면 개발 단계에서 재발 위험).
4. **치환 검증**: `grep -nE '\$TODO_(BUILD|TEST|LINT|URL)|<UNKNOWN|<\.\.\.|{{' "$RUN_PCO/handoff.md"` 로 미치환 0 확인.

⚠️ **역할경계**: 변환은 문서 작성만. 코드 직접 수정 금지.

---

## 3. 개발 모드 자동 선택

기존 plan-fusion-dev §3와 동일하되, **보안 민감 영역(auth/payment/crypto/secret)이 SECURE_SCOPE에 있으면 Council-Code 우선**(교차검증 강화):

| 신호 | 모드 | 이유 |
|---|---|---|
| 보안 민감 영역(auth/payment/secret) 포함 | **Council-Code** | GPT+GLM 병렬 구현 → 교차리뷰로 보안 결함 사전 차단 |
| 스키마/보안/결제/배포/아키텍처 변경 | **BLOCKED** | 인간 승인 영역 |
| 범위 명확 + 보안 영역 아님 | **Pipeline** | 비용 효율 |

---

## 4. 개발 단계 — plan-codex-opencode + 🔒 L1 게이트 재실행

하위 스킬 `plan-codex-opencode/SKILL.md` 절차를 `$RUN_PCO`에서 수행. §1 ANALYZE·§2 PLAN은 변환 단계가 대신했으므로 건너뛰고 §3 DELEGATE부터.

**🔒 보안 확장(이 스킬만의 추가)**:
1. **개발 완료 후 L1 재실행**: `bash "../plan-fusion-secu/scripts/run-secure-l1.sh" "$RUN_PCO/wt/<id>" "$RUN_PCO"` — 구현된 코드에 정적 분석 재적용.
   - 신규 도입된 취약점(계획 단계엔 없던 것)이 있는지 잡기 위함.
   - exit 1(FAIL)이면 백엔드 resume으로 취약점 수정 후 재검증.
2. **L2 자기 평가**: 백엔드가 HANDOFF의 SECURE_CHECKLIST로 자가 진단(필수 산출).
3. **계획-개발 보안 일관성**: 개발 결과가 계획 단계의 보안 판정과 충돌하지 않는지 대조(예: 계획에서 기각한 위험한 접근이 구현에 들어갔는지).

---

## 5. 검증 · REPORT

### 검증
- **하위 스킬 검증 상속**: plan-codex-opencode §4 VERIFY(실행 증거 — 빌드/타입/테스트/린트 exit·출력, AC 대조).
- **🔒 L1 게이트(필수)**: 개발 후 L1 재실행 결과가 exit 0이어야 PASS. exit 1이면 FAIL → 백엔드 재위임.
- **🔒 L2 종합**: Judge(또는 교차리뷰)가 SECURE_CHECKLIST 항목별 PASS/FAIL 판정.
- UI 노출 작업 시: 디자인 스펙 반영 + UI AC 충족 명시 대조.
- **체이닝 보안 회귀**: 개발 결과가 상위 plan-fusion-secu의 보안 판정과 충돌하지 않는지.

### loop-md 연동
루트 `loop.md` 있으면 기존 plan-fusion-dev §5 loop-md 연동 절차 + **보안 게이트 결과를 ①②③ 리포트에 포함**.

### REPORT
기존 plan-fusion-dev REPORT + 다음 추가:
- **🔒 SECURE_MODE**·**L1 게이트 결과**(계획·개발 양쪽 exit code + 발견 수)
- **🔒 L2 보안 평가 요약**(치명적 위험·경고·PASS 항목 수)
- **🔒 계획-개발 보안 일관성**(충돌 여부)
- `$RUN_PF/l1-*.json`·`$RUN_PCO/l1-*.json` 경로

---

## 역할 경계 (절대 규칙)

- 오케스트레이터는 체이닝·변환·모드선택·검증만. **프로덕션 코드 직접 수정 금지.**
- **보안 취약점 발견 시 자동 패치 금지** — 사용자에게 보고 후 승인. 수정은 백엔드가.
- 변환 단계에서 보안 AC 매핑 누락 시 **변환 중단**(게이트).
- 인간 승인 영역은 BLOCKED.

## 이 스킬을 쓰지 말아야 할 때

- **보안 검증 불필요한 개발 체이닝** → **plan-fusion-dev** (보안 오버헤드 없음).
- **계획+보안만 필요**(개발은 별도) → **plan-fusion-secu** 단독.
- **단일 모델 보안 개발** → plan-then-codex / plan-then-opencode에 보안 프롬프트.
- **비용이 가치를 못 넘을 때**: 단일 위임 대비 8~13배. 사소한 변경·되돌리기 쉬운 작업이면 과하다.
