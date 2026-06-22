---
name: plan-fusion-secu
description: >
  보안 중심 CLI Fusion 워크플로우 — plan-fusion의 구조(참가자 → Judge → Synthesizer → 검증)에
  시큐어 코딩 검증 3계층(L1 정적분석 + L2 LLM 체크리스트 + L3 강제 보안 백엔드)을 통합한다.
  진입 즉시 L1+L2가 강제된다(별도 -secu 스킬 = 보안 의도). codeSecurity 프리셋 또는 사용자 명시 시 L3 추가 발동.
  체크리스트는 OWASP Top 10(2021/2025 병기) + OWASP LLM Top 10 + CWE/SANS Top 25 = 43개 항목(SSOT: references/secure-coding.md).
  다음일 때 사용: "보안 검증 포함해서 fusion으로", "시큐어 코딩 검사하면서 다중 모델로 풀어",
  "취약점 점검하며 교차검증", "codeSecurity 프리셋으로", "secure fusion", "보안 코드리뷰 여러 모델로".
  보안 검증 없는 일반 다중 모델 작업이면 plan-fusion을, 개발까지 체이닝이면 plan-fusion-dev-secu를 쓴다.
---

# plan-fusion-secu — 보안 통합 CLI Fusion (plan-fusion + 시큐어 코딩 3계층)

**plan-fusion의 보안 특화 변형.** 동일한 워크플로우(참가자 → Judge → Synthesizer → 검증)에 **시큐어 코딩 검증**을 끼워넣는다. 기존 `plan-fusion`과의 차이는 단 한 가지 — **모든 단계에 보안 게이트가 추가**된다.

## 핵심 구조

```
/plan-fusion-secu <task>
  │
  ├─ §0 사전점검: check-fusion-secu.sh (기반 check-fusion.sh + SECURE_MODE + L1 도구 감지)
  │
  ├─ §1 ANALYZE: 코드 분석 + 보안 민감 영역 식별(auth/payment/secret/사용자입력)
  │     → SECURE_SCOPE 결정(전수 검사 vs 부분)
  │
  ├─ §2 PLAN: HANDOFF 작성 — secure-coding.md 체크리스트(43개) 주입
  │
  ├─ §3 DELEGATE: 참가자 병렬 (동일 plan-fusion 절차 + 각자 보안 평가)
  │
  ├─ §4 FUSE: Judge(Secure 루브릭) → Synthesizer
  │     └─ L1 정적 분석(run-secure-l1.sh) 병렬 실행
  │
  └─ §5 VERIFY: L1 게이트(exit code 객관 판정) + L2(Judge) + L3(조건) 종합
```

## 자산 참조 (SSOT — 복제 아님)

이 스킬은 형제 스킬 `plan-fusion/`의 자산을 **상대참조**한다(같은 레포에 있어야 함 — check-fusion-secu.sh가 검증):

- **기반 워크플로우**: `../plan-fusion/SKILL.md` (§0~§5 본문 — 이 스킬은 그것을 "상속"하고 보안 게이트만 추가)
- **격리·Judge·Synth 상세**: `../plan-fusion/references/fusion.md` (extract_answer(), judge-input 조립, 폴백 체인 — 전부 재사용)
- **라우팅·CLI 경로**: `../plan-fusion/references/routing-fusion.md`, `cli-fusion-map.md`, `codex-cli.md`, `opencode-cli.md`
- **worktree 관리**: `../plan-fusion/scripts/council-worktrees.sh`

**이 스킬만의 고유 자산**:
- `references/secure-coding.md` — **체크리스트 SSOT** (43개 항목 + L1/L2/L3 분배 매트릭스 + 루브릭)
- `scripts/check-fusion-secu.sh` — 기반 check-fusion.sh 래퍼 + SECURE_MODE 강제 + L1 도구 감지
- `scripts/run-secure-l1.sh` — L1 정적 분석 러너(semgrep/gitleaks/audit)
- `templates/fusion-judge-secu.md.tmpl` — 보안 루브릭(L2) 주입된 Judge 템플릿
- `templates/fusion-synth-secu.md.tmpl` — 보안 위험·AC 산출 Synth 템플릿
- `templates/HANDOFF-secu.md.tmpl` — 보안 AC 섹션 포함 HANDOFF

`SKILL_DIR` = 이 SKILL.md가 있는 디렉토리. `$RUN` = 이번 위임의 격리 폴더.

> **진입 규칙**: `/plan-fusion-secu`로 명시 호출되면 task 내용과 무관하게 반드시 §0부터 실행한다(bail-out 금지). 기존 plan-fusion의 진입 규칙을 그대로 상속.

---

## 0. 사전점검 + SECURE_MODE 강제

`bash "$SKILL_DIR/scripts/check-fusion-secu.sh"` 실행:
- **기반 check-fusion.sh 출력 통과** (오케스트레이터 감지·백엔드 가용성·Judge/Synth 후보·폴백체인 — 전부 동일)
- **추가 출력**: `SECURE_MODE=yes`(항상), `SECURE_L1_CAPABILITY`(도구 감지 결과)

⚠️ **SECURE_MODE는 항상 yes** — 기존 plan-fusion과 달리 "조건부 발동"이 아니다. 별도 -secu 스킬로 들어온 시점 자체가 보안 검증 의도이므로 L1+L2가 항상 가동된다(사용자가 결정하는 게 아니라 스킬 진입이 결정).

**L1 도구 감지 결과에 따른 분기**:
- `SECURE_L1_CAPABILITY=full` → L1 정상 가동(semgrep/gitleaks/의존성 스캐너 조합)
- `SECURE_L1_CAPABILITY=minimal` → L1 도구 0개. WARN(차단 아님) — L2만으로 보안 평가(L1 없으면 객관 exit code가 없어 품질 저하). 설치 안내 표시.

차단 게이트는 기반과 동일(`EFFECTIVE_BACKENDS<2`면 exit 1).

## 0.5 패널·모드 확정 (plan-fusion과 동일 + codeSecurity 기본 권장)

기존 plan-fusion §0.2.5 패널 확정 게이트를 그대로 따른다. 단, 이 스킬의 목적상:
- **기본 추천 프리셋**: `codeSecurity`(gpt·opus·gemini·glm·kimi 5모델 / 독립패밀리 4 / 호출 7) — 보안 작업에 특화된 패널. 단 사용자가 다른 프리셋을 명시하면 따름.
- **모드**: 코드 산출 O → Fusion-Code, 코드 산출 0(보안 평가/리서치) → Fusion-Research.

격리 폴더 생성(`$RUN`)·manifest 작성은 기존과 동일(`../plan-fusion/SKILL.md` §0.4 참조). 단 manifest에 추가:
```bash
printf 'secure_mode=%s\nsecure_l1_capability=%s\n' "yes" "<check-fusion-secu.sh 출력값>" >> "$RUN/manifest"
```

## 1. ANALYZE + 보안 민감 영역 식별

기존 plan-fusion §1 ANALYZE를 수행하되, 추가로 **보안 민감 영역**을 식별한다:
- **인증/인가 코드** (auth middleware, JWT, 세션, 권한 검사)
- **결제/금융 로직** (트랜잭션, 금액 계산)
- **시크릿/키 처리** (.env, API key, 암호화)
- **사용자 입력 처리** (폼, API 입력, 파일 업로드)
- **외부 통신** (HTTP 요청, SQL 쿼리, 명령 실행)

이 영역들을 `SECURE_SCOPE`로 정의해 HANDOFF에 명시 — L2 평가가 이 영역에 집중하도록. 전체 코드베이스가 보안 민감이면 `SECURE_SCOPE=all`.

## 2. PLAN — 보안 체크리스트 주입된 HANDOFF

`templates/HANDOFF-secu.md.tmpl`로 `$RUN/handoff.md` 작성:
- 기존 HANDOFF 내용(Mission·Context·Baseline·Out-of-scope·BLOCKED·AC) + **보안 섹션**:
  - **SECURE_SCOPE**: §1에서 식별한 보안 민감 영역
  - **SECURE_CHECKLIST**: `references/secure-coding.md`의 매트릭스 중 SECURE_SCOPE에 해당하는 항목만 발췌 (전체 43개를 항상 다 담으면 산출이 비대해짐 — 스코프 기반 필터)
  - **L1 도구 지시**: run-secure-l1.sh가 돌릴 도구 목록(check-fusion-secu.sh 감지값)
  - **L2 루브릭 참조**: `references/secure-coding.md` §9의 묶음 A/B/C

자기완결성: 참가자는 대화 컨텍스트를 모른다. 보안 체크리스트 전문(또는 스코프 발췌)을 HANDOFF에 담아야 참가자가 독립 평가 가능.

## 3. DELEGATE — 참가자 병렬 (plan-fusion과 동일)

기존 plan-fusion §3 절차를 그대로 수행(`../plan-fusion/SKILL.md` §3 + `../plan-fusion/references/fusion.md` §2):
- Fusion-Code면 worktree 격리 병렬, Fusion-Research면 read-only 사본에서.
- 각 참가자는 HANDOFF(보안 체크리스트 주입됨)를 받아 **자기 담당 L2 항목**(묶음 A/B/C 중 하나 배정, 또는 전체)을 평가.
- **L1은 참가자가 아닌 오케스트레이터가 병렬로 실행** — run-secure-l1.sh는 객관 도구라 참가자 교차검증 대상이 아님(같은 결과가 나와야 함).

## 4. FUSE — Judge(Secure 루브릭) → Synthesizer + L1 병렬

### 4.1 L1 정적 분석 (병렬)
참가자 위임과 동시에 `bash "$SKILL_DIR/scripts/run-secure-l1.sh" "<root>" "$RUN"` 실행:
- 결과: `$RUN/l1-findings.json`, `$RUN/l1-summary.json`, `$RUN/l1-raw/`(도구별 raw)
- exit code: 0=PASS, 1=FAIL(취약점 발견), 2=도구 오류(L2 폴백)

### 4.2 Judge (기존 + 보안 루브릭)
기존 plan-fusion §4 FUSE 절차를 따르되, Judge 템플릿으로 `templates/fusion-judge-secu.md.tmpl` 사용:
- 기존 Judge 임무(최강후보·합의·충돌·위험·공통맹점) + **L2 보안 루브릭 평가**(`references/secure-coding.md` §9)
- judge-input 조립은 **기존 extract_answer()를 그대로 소싱**(`../plan-fusion/references/fusion.md` §3-1 — 직접 파서 짜지 말 것, 방금 발견성 수정됨).

### 4.3 Synthesizer
`templates/fusion-synth-secu.md.tmpl` 사용 — 보안 위험·AC 산출 지시 추가.

## 5. VERIFY — 3계층 종합 검증 (오케스트레이터 불가양도)

### L1 게이트 (객관 — exit code로 판정)
- `run-secure-l1.sh` exit code가 1(FAIL)이면 **보안 게이트 차단** — 취약점이 발견된 것.
  - 단, 발견이 `secure-coding.md`의 **Out-of-scope**(예: dev 의존성의 정보성 경고)이면 판정 후 PASS 처리 가능(판정 근거 필수).
- exit 2(도구 오류)면 WARN — L2에 의존, 산출에 "L1 도구 오류로 객관 검증 누락" 명시.
- exit 0(PASS)이면 L1 통과.

### L2 평가 (Judge)
- Judge가 `fusion-judge-secu.md.tmpl`의 루브릭으로 평가한 항목별 PASS/FAIL + 근거 인용.
- ⚠️ **loop.md 정합**: L2는 "LLM이 봤다"가 아니라 **증거 생성 단계** — 항목별 PASS/FAIL·근거 파일 인용·모델 버전을 synthesis에 남겨야 객관 게이트가 검증 가능(secure-coding.md §0).

### L3 (조건 발동)
다음 중 하나면 별도 보안 백엔드 1회 추가 위임(`references/secure-coding.md` §10):
- codeSecurity 프리셋 선택 시
- 사용자 명시("보안 검증해줘", "PoC 확인", "공급망 조사")
- L1/L2에서 **공급망(T2-3)·데이터독성(T2-4)·벡터DB(T2-8)** 관련 위험이 식별된 경우

### 종합 판정
- **FAIL**: L1 exit 1(객관 취약점) **또는** L2에서 치명적 위험(인젝션·권한상승·시크릿 노출 등)이 식별된 경우.
  - → 백엔드 재위임(Fusion-Code) 또는 BLOCKED(Fusion-Research — 코드 수정이 아니므로 사용자에게 보고).
- **PASS**: L1 exit 0 + L2에서 치명적 위험 없음 + (L3 발동 시) L3에서 차단 발견 없음.

`templates/synthesis.md.tmpl`(`../plan-fusion/templates/`) 기반 + 보안 섹션 추가해 `$RUN/synthesis.md` 작성.

### loop-md 연동
루트 `loop.md` 있으면 기존 plan-fusion §5의 loop-md 연동 절차를 따르되, **보안 게이트 결과를 ①②③ 리포트에 포함**:
- ① L1 exit code + 발견 수 + 도구별 로그 꼬리 3~5줄
- ③ 보안 평가 항목(L2)을 정성 자기평가에 추가

## REPORT

기존 plan-fusion REPORT + 다음 추가:
- **SECURE_MODE**·**SECURE_L1_CAPABILITY**·**L1 exit code + 발견 수**
- **L2 보안 평가 요약**(치명적 위험·경고·PASS 항목 수)
- **L3 발동 여부**(발동 시 백엔드·조사 결과 요약)
- **종합 보안 판정**(PASS/FAIL + 근거)
- `$RUN/l1-findings.json`·`l1-summary.json`·`l1-raw/` 경로

---

## 역할 경계 (절대 규칙 — plan-fusion 상속 + 보안 확장)

- 오케스트레이터는 **분석·계획·검증·사실확인**만. L1 정적 분석은 도구가, L2 평가는 Judge/Synth가.
- **L1 발견 취약점의 수정은 항상 백엔드** — 오케스트레이터가 직접 코드를 고치지 않는다(L1은 진단 도구, 수정 도구 아님).
- 인간 승인 영역(스키마/보안/키·시크릿/결제/배포/PRD범위/아키텍처)은 자동 진행 금지 — BLOCKED.
- 보안 취약점이 식별되면 **자동으로 패치하지 않고** 사용자에게 보고 — 수정 여부·방법은 사용자 결정(보안 수정은 인간 승인 영역).

## 이 스킬을 쓰지 말아야 할 때

- **보안 검증이 필요 없는 일반 다중 모델 작업** → **plan-fusion** (보안 오버헤드 없음).
- **개발까지 체이닝** (계획 + 보안 + 구현 한 번에) → **plan-fusion-dev-secu**.
- **단일 모델 보안 검토** → plan-then-codex / plan-then-opencode에 보안 프롬프트 추가(가벼움).
- **L1 도구가 전혀 없는 환경** → SECURE_L1_CAPABILITY=minimal 경고. L2만으로 돌긴 하지만 객관 exit code가 없어 품질 저하 — 도구 설치 후 사용 권장.
- **비용이 가치를 못 넘을 때**: codeSecurity 7호출 + L1 도구 런타임 + (조건) L3 1회 = 단일 위임의 8배 이상. 사소한 변경·답이 갈릴 여지가 작으면 과하다.
