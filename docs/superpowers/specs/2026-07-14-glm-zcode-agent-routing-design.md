# Design: GLM ZCode-Agent Routing (오케스트레이터=GLM 조건부)

**Date:** 2026-07-14
**Status:** Approved (pending implementation plan)
**Scope:** `models.yaml` SSOT · `check-fusion.sh` · plan-fusion/council fusion docs · `plan-then-opencode` · derived secu/dev variants (상속)

---

## 1. 목적과 배경

### 현황
plan 계열 스킬(plan-fusion, plan-codex-opencode, plan-then-opencode)에서 GLM 역할은 항상
**외부 프로세스**로 실행된다.

- omo 경로: `omo run --agent Sisyphus -m zai-coding-plan/glm-5.2 -d <dir> --json "<handoff>"`
- opencode 직접 경로: `opencode run -m zai-coding-plan/glm-5.2 --variant high --format json --dir <dir> "<handoff>""`

두 경로 모두 별도의 Z.AI 인증을 필요로 하며, ZCode 세션(오케스트레이터)의 컨텍스트·인증과
분리된다.

### 목표
오케스트레이터가 이미 GLM-5.2로 실행 중일 때(`ORCH_FAMILY=glm`), GLM 참가자 슬롯을
외부 opencode/omo 프로세스 대신 **ZCode Agent 도구 dispatch**로 실행한다.
부모(=오케스트레이터 자신 = GLM-5.2) 모델을 상속하므로, 별도 CLI·별도 인증 없이
"ZCode의 GLM"을 재사용한다.

### 비목표
- GLM이 아닌 다른 모델(kimi/deepseek/gpt/gemini/opus)의 라우팅 변경
- 오케스트레이터 ≠ GLM 환경에서의 라우팅 변경 (기존 opencode/omo 경로 유지 = 이식성)
- Judge·Synth 역할의 GLM Agent dispatch (동족회피 원칙 유지 — §4)

---

## 2. 핵심 제약 — Agent 도구 모델 상속

이 설계의 전제이자 가장 중요한 기술적 사실.

| 항목 | 사실 |
|---|---|
| Agent 도구 `model` 파라미터 허용값 | `sonnet` / `opus` / `haiku` 3종만 (또는 생략) |
| GLM을 `model`로 직접 지정 | **불가능** |
| `model` 생략 시 | **부모(오케스트레이터) 모델 상속** |
| 오케스트레이터 = GLM-5.2 (이 세션) | Agent dispatch = GLM-5.2 ✓ |
| 오케스트레이터 = GPT/Codex (이식 환경) | Agent dispatch = GPT ✗ "GLM" 아님 |

**결론:** "ZCode의 GLM via Agent dispatch"는 **오케스트레이터가 GLM일 때만** 의미가 있다.
따라서 라우팅 분기는 `ORCH_FAMILY=glm`을 조건으로 한다.

---

## 3. 라우팅 분기

```
GLM 참가자 역할 필요
 ├─ ORCH_FAMILY=glm  → Agent 도구 dispatch (신규, 부모 GLM-5.2 상속)
 └─ ORCH_FAMILY≠glm → 기존 opencode/omo 경로 (변경 없음, 폴백 보존)
```

동일한 분기가 3개 스킬의 GLM 참가자 호출 사이트에 적용된다.

---

## 4. 역할별 적용 범위

| 역할 | ORCH=glm일 때 처리 | 근거 |
|---|---|---|
| **참가자** (Code/Research) | ✅ **Agent dispatch로 전환** | 주 대상. fresh context로 오케스트레이터 자신의 추론과 별개 2차 풀이 제공 |
| **cross-review reviewer** | ✅ Agent dispatch | council.md의 GLM 리뷰 슬롯. 참가자와 동일 취급 |
| **Judge 폴백** (`opencode:*glm*`) | ❌ **폐기 → `orchestrator-self`에 합체** | Judge는 "참가자 간 차이 비교"가 본질. 오케스트레이터-self와 동일 → 이미 체인 종착지 존재. 중복 슬롯만 늘림 |
| **Synth 폴백** | ❌ **변경 없음** (ORCH=glm이면 이미 비동족 codex/agy 우선) | Synth 기본값 회피 로직이 이미 동족 GLM을 피함. GLM은 최후 폴백인데 self와 동일 |

**정리:** "GLM 전 역할 Agent 전환"의 실질적 범위는 **참가자 슬롯(+cross-review)** 으로 좁혀진다.
Judge·Synth는 동족회피 원칙 때문에 ORCH=glm일 때 GLM이 잡히지 않는 것이 이미 설계돼 있고,
이를 명시적으로 정리(opencode:*glm* Judge 후보 제거)하는 것만이 추가 변경이다.

---

## 5. 독립성 처리 (정직성 — 설계의 핵심)

GLM-via-Agent는 오케스트레이터와 **같은 GLM-5.2 모델**이다. 같은 가중치·같은 편향.
따라서:

1. **quorum "독립 패밀리" 카운트에서 제외**
   - manifest `family=zcode-agent` (기존 `opencode`와 구분)
   - §3-1 quorum 카운터가 `zcode-agent`를 `orchestrator-self`와 동일 취급 → distinct family에서 빠짐
2. **`PARTICIPANT_CONFLICT_RISK=partial`** 항상 표기 (이미 GLM 예외로 존재, 확정)
3. **synthesis/REPORT에 명시**: "GLM 참가자 = ZCode Agent dispatch (부모 모델 상속 = 오케스트레이터-self) — 동종할인"
4. **Fusion 성립 조건**: codex(GPT)·agy(Gemini)·kimi(opencode-go) 중 ≥2 생존 필요.
   GLM-via-Agent는 "fresh context 2차 의견"으로는 유효하나, 독립 패밀리로는 카운트 안 함.

**이것은 제거하려는 게 아니라 명시하는 것이다.** Fusion 자체는 여전히 성립 —
다른 패밀리들이 독립성을 담당하기 때문.

---

## 6. 출력 캡처 호환성 (가장 중요한 설계 결정)

### 현황 (opencode)
`--format json` → stdout 리다이렉트 → `$RUN/glm/round1.log` → `extract_answer()`가
1.5순위 jq(`.type=="text"`의 `.part.text`)로 파싱.

### 신규 (Agent dispatch)
Agent 도구는 결과 텍스트를 **도구 결과로 인라인 반환**한다 (파일도 exit code도 아님).
오케스트레이터가 받은 텍스트를 `$RUN/glm/result.md`로 Write.

### 호환성 포인트
`extract_answer()` (fusion.md L188-223)은 **0순위**로 `result.md` 존재를 확인한다:
```bash
if [ -f "$RUN/$id/result.md" ]; then cat "$RUN/$id/result.md"; return; fi
```
→ **`extract_answer()` 수정 불필요.** result.md를 Write하는 것만으로 기존 파이프라인과 100% 호환.

manifest 기록도 동일 형식:
```bash
echo "round1_exit=0" >> "$RUN/glm/manifest"
echo "family=zcode-agent" >> "$RUN/glm/manifest"
echo "model=zcode-agent(parent=GLM-5.2)" >> "$RUN/glm/manifest"
```

---

## 7. 변경 파일 목록 (구현 단위)

### 7-1. SSOT 계층
- **`models.yaml`** — GLM 엔트리에 `backend_zcode_agent` 필드 추가
  ```yaml
  glm:
    family: glm
    backend: opencode                    # 기본 (폴백·비-GLM 오케스트레이터)
    backend_zcode_agent: yes             # ORCH_FAMILY=glm일 때 Agent dispatch 활성 (신규)
    aliases: [glm5.2, "glm 5.2"]
    cli_model: zai-coding-plan/glm-5.2   # opencode 폴백용 유지
    variant_flag: --variant high
    dir_flag: -d
    dir_flag_alt: --dir
  ```
- **`sync-models.sh`** — awk 파서가 `backend_zcode_agent` 키를 인식해 `M_GLM_BACKEND_ZCODE_AGENT=yes` 생성
- **`models.lib.sh`** — 자동 재생성 (수동 금지)

### 7-2. check 스크립트 계층
- **`skills/plan-fusion/scripts/check-fusion.sh`** — 신규 출력:
  - `GLM_VIA_AGENT=yes|no` (`ORCH_FAMILY=glm && M_GLM_BACKEND_ZCODE_AGENT=yes`일 때 yes)
  - Judge 폴백 체인 구성 시 `ORCH_FAMILY=glm`이면 `opencode:*glm*` 후보 제거 (→ 종착지 `orchestrator-self`로 자연 합체)
  - `PARTICIPANT_CONFLICT_RISK=partial` 이미 존재 (L462-465), `GLM_VIA_AGENT=yes`일 때 사유에 "Agent-dispatch(부모 상속)" 추가

### 7-3. 참가자 위임 사이트 (오케스트레이터가 읽는 글)

> **도구 경계 주의 (구현의 가장 미묘한 점):** 기존 fusion.md의 코드 블록은 모두
> **Bash 명령**(omo/opencode CLI 호출)이다. 그러나 Agent dispatch는 Bash 명령이 아니라
> **별도 도구(Agent 도구)** 호출이다. 따라서 GLM 분기는 단일 bash `if/else`가 아니라,
> 오케스트레이터가 `GLM_VIA_AGENT` 값을 읽고 **어느 도구를 쓸지 결정하는 prose 지시**로
> 표현돼야 한다.

- **`skills/plan-fusion/references/fusion.md` §2 (L137-147)** — GLM 참가자 호출을 조건부 prose로 재구성:
  ```
  GLM 참가자 위임 — check-fusion 출력의 GLM_VIA_AGENT 값으로 분기:

  ▶ GLM_VIA_AGENT=yes (오케스트레이터=GLM):
    Bash가 아니라 Agent 도구로 실행한다:
    1. Agent 도구 호출: subagent_type=general-purpose, model 생략(부모 GLM-5.2 상속),
       prompt = $RUN/handoff.md 내용 + "결과를 마크다운으로 반환하라" 지시.
       (background 옵션은 동시성 상한에 맞춰 선택 — §11 리스크 참조)
    2. Agent 응답 텍스트를 Write 도구로 $RUN/glm/result.md에 저장.
    3. Bash로 manifest 기록:
       echo "round1_exit=0" >> "$RUN/glm/manifest"
       echo "family=zcode-agent" >> "$RUN/glm/manifest"
       echo "model=parent(GLM-5.2)" >> "$RUN/glm/manifest"

  ▶ GLM_VIA_AGENT=no (기존 경로, 변경 없음):
    기존 OMO_RUN_READY 분기 (omo / opencode) — L137-144 그대로.
  ```
  - §2 규칙 블록에 `family=zcode-agent` 카운트 처리 설명 추가 (orchestrator-self와 동일 취급)
  - §3-1 `extract_answer` result.md 0순위 경로가 이미 호환 (수정 불필요, 주석만 보강)
- **`skills/plan-fusion/references/fusion.md` §1 (L105)** — Fusion-Research read-only opencode
  제네릭 블록도 GLM 참가자에 한해 같은 분기 적용 (ORCH=glm && id=glm)
- **`skills/plan-codex-opencode/references/council.md` L82-89** — 동일 분기 패턴 적용

### 7-4. 단일 위임 스킬
- **`skills/plan-then-opencode/SKILL.md` L79-92 (DELEGATE)** — §7-3과 동일한 prose 분기 패턴 적용:
  `GLM_VIA_AGENT=yes`면 오케스트레이터가 Agent 도구로 handoff를 위임하고 응답을
  `$RUN/round1.log`에 Write; `no`면 기존 omo CLI 호출.
- **`skills/plan-then-opencode/references/omo-cli.md`** — GLM_VIA_AGENT 분기 문서화
- **`skills/plan-then-opencode/scripts/check-omo.sh`** — `GLM_VIA_AGENT` 신호 통과 (source check-fusion.sh 또는 models.lib.sh 읽기)

### 7-5. 파생 스킬 (상속만, 직접 변경 최소)
- **plan-fusion-dev / secu / dev-secu** — check 스크립트가 부모 `GLM_VIA_AGENT` 신호를 읽도록 전달.
  실행 자체는 plan-fusion/council에 위임하므로 직접 GLM 명령 사이트 없음.
  - `scripts/check-fusion-dev.sh` / `check-fusion-secu.sh` — `GLM_VIA_AGENT` passthrough 추가

### 7-6. 문서 동기화
- **`skills/plan-fusion/references/routing-fusion.md`** — GLM 변형표에 ORCH=glm 조건부 Agent dispatch 행 추가
- **`skills/plan-fusion/references/cli-fusion-map.md`** — 5-CLI 경로 맵에 zcode-agent 백엔드 추가
- **`skills/plan-fusion/SKILL.md` §0.2 동족 경고·L166 omo 폴백 인용** — Agent dispatch 분기 언급
- **`skills/plan-codex-opencode/SKILL.md` / README.md** — 동일
- **`skills/plan-then-opencode/SKILL.md`** — 동일

---

## 8. 게이트 검증 계획

| 게이트 | 영향 | 대응 |
|---|---|---|
| `loop-gates.sh` G1 (shell-syntax) | 신규/수정 `.sh` | `bash -n` 통과 보장 |
| `loop-gates.sh` G4 (YAML) | `models.yaml` 신규 필드 | awk 파서 호환 확인 |
| `check-models.sh` 2b (cli_model `provider/name`) | `zai-coding-plan/glm-5.2` 유지 | 통과 (변경 없음) |
| `check-models.sh` 복제본 드리프트 | sync-models.sh 재실행 | 7 스킬 복제본 갱신 |
| **신규 smoke-test (권장)** | GLM_VIA_AGENT=yes일 때 manifest `family=zcode-agent` 검증 | `skills/plan-fusion-dev/scripts/smoke-test.sh` 패턴 확장 |

---

## 9. 폴백 전략

1. **Agent 도구 호출 실패** (응답 없음·에러) → 오케스트레이터가 기존 opencode/omo 경로로 자동 폴백.
   `GLM_VIA_AGENT=yes`여도 Agent 결과가 비어있으면 `else` 분기(opencode)로 회귀.
2. **ORCH≠glm 환경** → `GLM_VIA_AGENT=no` → 기존 경로 100% (변경 0)
3. **opencode/omo 인증 만료** → 기존처럼 무응답 처리, quorum에서 GLM 제외. 다른 패밀리가 ≥2면 Fusion 유지

---

## 10. 구현 순서 (구현 계획으로 이관)

1. `models.yaml` 필드 추가 + `sync-models.sh` awk 파서 확장 + 재생성 + `check-models.sh` 통과
2. `check-fusion.sh` `GLM_VIA_AGENT` 신호 + Judge 체인 GLM 제거
3. `fusion.md` §1·§2 GLM 참가자 분기 (Code/Research)
4. `council.md` GLM 참가자 분기
5. `plan-then-opencode` 분기 + check-omo.sh
6. 파생 스킬(dev/secu) passthrough
7. 문서 동기화 (routing-fusion.md·cli-fusion-map.md·SKILL.md·README)
8. 게이트 전통: `bash scripts/loop-gates.sh` + `bash check-models.sh`
9. (권장) smoke-test 확장

---

## 11. 리스크와 한계

1. **독립성 감소**: GLM-via-Agent는 오케스트레이터-self와 같은 모델. fresh context라 2차 의견은 되나,
   독립 패밀리 카운트에서 빠짐(§5). Fusion은 다른 패밀리가 담당.
2. **ORCH=glm 전용**: 이식 환경(ORCH=gpt/gemini/claude)에서는 "GLM"이 아니게 됨(§2). 기존 경로가 폴백.
3. **교차검증 약화**: GLM 오케스트레이터 + GLM 참가자(via Agent) = 사실상 같은 모델 2회 풀이.
   다른 패밀리가 생존할 때만 의미. 표준 기본 패널(gpt+gemini+glm+kimi)은 다른 3패밀리가 커버.
4. **동기 실행**: Agent 도구 dispatch는 동기 반환. 기존 `run_in_background: true` 병렬 패턴과 다름 —
   오케스트레이터가 GLM Agent를 기다리는 동안 다른 참가자(opencode/omo)는 백그라운드로 진행 가능.
