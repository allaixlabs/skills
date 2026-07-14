# GLM ZCode-Agent Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 오케스트레이터=GLM일 때 plan 계열 스킬의 GLM 참가자 슬롯을 외부 opencode/omo 프로세스 대신 ZCode Agent 도구 dispatch로 라우팅한다(부모 GLM-5.2 상속). 비-GLM 오케스트레이터는 기존 경로 유지(이식성).

**Architecture:** SSOT(`models.yaml`)에 `backend_zcode_agent` 필드를 추가 → `check-fusion.sh`가 `GLM_VIA_AGENT` 신호 출력 → `.src` 템플릿(GLM 참가자 호출 블록)에 prose 분기 추가. 출력 캡처는 Agent 응답 → `result.md` Write → 기존 `extract_answer()` 0순위 경로로 호환(파서 수정 0). Judge·Synth는 동족회피로 이미 빠지므로 참가자 슬롯만.

**Tech Stack:** Bash(awk 파서·check 스크립트) · YAML SSOT · Markdown `.src` 템플릿(`@@TOKEN@@` 치환). 런타임 테스트 스택 없음 — 게이트는 `scripts/loop-gates.sh`(G1 shell-syntax·G4 YAML) + `check-models.sh` + `sync-models.sh --check`.

**Spec:** `docs/superpowers/specs/2026-07-14-glm-zcode-agent-routing-design.md`

---

## File Structure

| 파일 | 역할 | 변경 유형 |
|---|---|---|
| `models.yaml` | SSOT. GLM 엔트리에 `backend_zcode_agent` 추가 | 필드 1줄 추가 |
| `models.lib.sh` | 자동생성(`M_GLM_BACKEND_ZCODE_AGENT`) | sync-models.sh 재실행 (수동금지) |
| `sync-models.sh` | awk 파서가 `backend_zcode_agent` 키 인식 | L89 정규식 확장 |
| `skills/plan-fusion/scripts/check-fusion.sh` | `GLM_VIA_AGENT` 신호 출력 + Judge 체인 GLM 제거 | 신규 블록 |
| `skills/plan-fusion/references/fusion.md.src` | GLM 참가자 §2 분기 + §3-2 Judge 체인 정리 | prose 분기 |
| `skills/plan-codex-opencode/references/council.md.src` | GLM 패널 분기 | prose 분기 |
| `skills/plan-then-opencode/SKILL.md` | DELEGATE 분기 (src 아님 — 직접 수정) | prose 분기 |
| `skills/plan-then-opencode/references/omo-cli.md.src` | GLM_VIA_AGENT 분기 문서 | 섹션 추가 |
| `skills/plan-fusion-dev/scripts/check-fusion-dev.sh` | `GLM_VIA_AGENT` passthrough | passthrough |
| `skills/plan-fusion-secu/scripts/check-fusion-secu.sh` | 동일 | passthrough |
| `skills/plan-fusion/references/routing-fusion.md.src` | GLM 변형표 행 추가 | 표 행 |
| `skills/plan-fusion/references/cli-fusion-map.md.src` | zcode-agent 백엔드 추가 | 표 행 |
| `skills/plan-fusion/SKILL.md.src` | 동족 경고·omo 폴백 인용에 분기 언급 | 주석 보강 |

---

## Task 1: models.yaml SSOT 필드 추가

**Files:**
- Modify: `models.yaml:39-46` (GLM 엔트리)

- [ ] **Step 1: GLM 엔트리에 backend_zcode_agent 필드 추가**

`models.yaml`의 `glm:` 엔트리(`backend: opencode` 줄 바로 아래)에 한 줄 추가:

```yaml
  glm:
    family: glm
    backend: opencode
    backend_zcode_agent: yes      # ORCH_FAMILY=glm일 때 ZCode Agent 도구 dispatch 활성 (부모 GLM 상속)
    aliases: [glm5.2, "glm 5.2"]
    cli_model: zai-coding-plan/glm-5.2
    variant_flag: --variant high
    dir_flag: -d
    dir_flag_alt: --dir
```

- [ ] **Step 2: YAML 문법 검증**

Run: `python3 -c "import yaml; yaml.safe_load(open('models.yaml'))" && echo OK`
Expected: `OK` (예외 없음)

- [ ] **Step 3: 커밋**

```bash
git add models.yaml
git commit -m "feat(models): GLM backend_zcode_agent 필드 — ORCH=glm ZCode Agent dispatch 활성"
```

---

## Task 2: sync-models.sh awk 파서 확장

`sync-models.sh`의 awk 파서는 현재 `[a-zA-Z_]+:` 패턴으로 키를 인식한다(L89). `backend_zcode_agent`는 이 패턴에 이미 매칭되지만, 값이 `yes`/`no` 같은 boolean 문자열로 들어오는지 확인하고, `M_GLM_BACKEND_ZCODE_AGENT` 변수가 생성되는지 검증해야 한다.

**Files:**
- Modify: `sync-models.sh:89` (awk 정규식 — 이미 호환 예상)
- Test: `sync-models.sh` 재실행 후 `models.lib.sh` 확인

- [ ] **Step 1: awk 파서 호환성 사전 검증**

현재 L89 정규식 `/^[[:space:]]+[a-zA-Z_]+:/`가 `backend_zcode_agent:` 키를 잡는지 확인. 콜론 뒤 값 추출(L92)도 `yes`를 그대로 가져오는지.

Run: `grep -n 'a-zA-Z_' sync-models.sh | head -5`
Expected: L89가 `/^[[:space:]]+[a-zA-Z_]+:/` 형태 — `backend_zcode_agent`는 `[a-zA-Z_]+`에 매칭됨(이미 호환).

- [ ] **Step 2: sync-models.sh 실행하여 models.lib.sh 재생성**

Run: `bash sync-models.sh`
Expected 출력에 다음 포함:
- `── 1. models.lib.sh 변환 (awk) ──` + `✓ 생성`
- `── 2. 스킬별 복제` 7스킬 모두 `✓`
- `── 2.5. 마크다운 템플릿 치환` — `.src` 파일들 렌더
- `── 3. 드리프트 검증` + `OK: models SSOT 동기화 완료`

- [ ] **Step 3: M_GLM_BACKEND_ZCODE_AGENT 변수 생성 확인**

Run: `grep 'BACKEND_ZCODE_AGENT' models.lib.sh`
Expected: `M_GLM_BACKEND_ZCODE_AGENT="yes"` 한 줄 존재.

변수가 없으면(awk가 누락) — L89 키 인식이 안 된 것. 이 경우 sync-models.sh L89 정규식을 점검하되, `[a-zA-Z_]+`가 이미 밑줄을 포함하므로 호환되어야 함. 문제면 awk 디버그: `awk -v yaml=models.yaml -v gen_at=test -f <(sed -n '/^generate_lib/,/^}$/p' sync-models.sh | sed '1d;$d') models.yaml | grep ZCODE`.

- [ ] **Step 4: check-models.sh 게이트 통과 확인**

Run: `bash check-models.sh`
Expected: `exit 0` — 드리프트 없음, 미정의 모델명 없음. `zai-coding-plan/glm-5.2`가 유지돼 2b 슬래시 형식 검증 통과.

- [ ] **Step 5: 루트 게이트 통과 확인**

Run: `bash scripts/loop-gates.sh`
Expected: `exit 0` (G1 shell-syntax·G2 frontmatter·G3 링크·G4 YAML·G5 시크릿 전부 PASS).

- [ ] **Step 6: 커밋**

```bash
git add sync-models.sh models.lib.sh skills/*/models.yaml skills/*/models.lib.sh
git commit -m "feat(models): sync-models.sh — GLM backend_zcode_agent 변수 생성 + 복제"
```

---

## Task 3: check-fusion.sh GLM_VIA_AGENT 신호 + Judge 체인 정리

check-fusion.sh가 (a) `GLM_VIA_AGENT=yes|no` 신호를 출력하고, (b) Judge 폴백 체인에서 `ORCH_FAMILY=glm`일 때 `opencode:*glm*` 후보를 제거하도록 수정.

**Files:**
- Modify: `skills/plan-fusion/scripts/check-fusion.sh` (L460 근처 GLM_MANDATORY_PARTICIPANT 블록 + Judge 체인 구성부)

- [ ] **Step 1: check-fusion.sh에서 GLM_MANDATORY_PARTICIPANT 블록 위치 확인**

Run: `grep -n 'GLM_MANDATORY_PARTICIPANT\|PARTICIPANT_CONFLICT_RISK\|JUDGE_FALLBACK_CHAIN' skills/plan-fusion/scripts/check-fusion.sh`
Expected: L460-466 근처(GLM 예외 신호) + Judge 체인 구성부(L507-638 영역).

- [ ] **Step 2: GLM_VIA_AGENT 신호 출력 추가**

`skills/plan-fusion/scripts/check-fusion.sh`의 `GLM_MANDATORY_PARTICIPANT`/`PARTICIPANT_CONFLICT_RISK` echo 블록(L460-466) 바로 뒤에 신규 블록 삽입. 먼저 해당 블록을 읽어 정확한 삽입점 파악:

`read_model glm BACKEND_ZCODE_AGENT`로 SSOT 값을 읽어 `ORCH_FAMILY=glm`과 결합.

삽입할 코드(L466 `fi` 직후):
```bash
# === GLM ZCode-Agent 라우팅 신호 ===
# ORCH_FAMILY=glm이고 models.yaml의 glm.backend_zcode_agent=yes면,
# GLM 참가자를 외부 opencode/omo 대신 ZCode Agent 도구 dispatch(부모 GLM 상속)로 실행.
# check-fusion 출력을 오케스트레이터가 읽어 fusion.md/council.md의 GLM 분기를 간다.
_glm_zcode_agent=no
if [ "$ORCH_FAMILY" = glm ]; then
  _zca=$(read_model glm BACKEND_ZCODE_AGENT)
  [ "$_zca" = yes ] && _glm_zcode_agent=yes
fi
echo "GLM_VIA_AGENT=$_glm_zcode_agent"
# GLM_VIA_AGENT=yes면 PARTICIPANT_CONFLICT_RISK 사유에 "Agent-dispatch(부모 상속)" 추가.
# (이미 위 GLM_MANDATORY_PARTICIPANT=yes일 때 partial 표기가 있으므로, 사유만 보강.)
if [ "$_glm_zcode_agent" = yes ]; then
  echo "GLM_ROUTING_NOTE=Agent-dispatch(parent-inherit) — family=zcode-agent는 quorum에서 orchestrator-self 취급"
fi
```

- [ ] **Step 3: Judge 폴백 체인에서 ORCH=glm일 때 opencode-glm 제거**

Judge 체인 구성부(check-fusion.sh L507-638 영역 — `JUDGE_FALLBACK_CHAIN`을 조립하는 곳)에서 `ORCH_FAMILY=glm`일 때 `opencode:*glm*` 후보를 체인에 넣지 않도록 조건 추가.

먼저 Judge 체인을 조립하는 정확한 코드를 확인:
Run: `grep -n 'JUDGE_FALLBACK_CHAIN\|judge_fallback\|opencode.*glm\|deepseek.*judge' skills/plan-fusion/scripts/check-fusion.sh | head -20`

체인 조립 로직에서 `opencode` 후보(glm/kimi 라우트) 추가 부분에 조건을 건다: `ORCH_FAMILY=glm && _zca=yes`면 해당 후보를 스킵(이미 체인 끝 `orchestrator-self`로 자연 합체되므로 별도 슬롯 불필요).

구체 수정은 체인 조립 코드를 읽은 후 적용 — `opencode-go/deepseek-v4-pro` 후보는 유지(deepseek는 별도 provider라 동족 아님), `glm/kimi` 라우트만 `ORCH=glm`이면 제외.

- [ ] **Step 4: shell-syntax 검증**

Run: `bash -n skills/plan-fusion/scripts/check-fusion.sh && echo OK`
Expected: `OK` (문법 에러 없음).

- [ ] **Step 5: check-fusion.sh dry-run (ORCH=glm 시뮬레이션)**

Run: `PLAN_FUSION_ORCHESTRATOR=glm bash skills/plan-fusion/scripts/check-fusion.sh 2>&1 | grep -E 'GLM_VIA_AGENT|GLM_ROUTING_NOTE|PARTICIPANT_CONFLICT'`
Expected:
- `GLM_VIA_AGENT=yes`
- `GLM_ROUTING_NOTE=Agent-dispatch(parent-inherit)...`
- `PARTICIPANT_CONFLICT_RISK=partial(...)` (이미 존재)

- [ ] **Step 6: check-fusion.sh dry-run (ORCH≠glm — 분기 비활성 확인)**

Run: `PLAN_FUSION_ORCHESTRATOR=gpt bash skills/plan-fusion/scripts/check-fusion.sh 2>&1 | grep 'GLM_VIA_AGENT'`
Expected: `GLM_VIA_AGENT=no` (기존 경로 유지 신호).

- [ ] **Step 7: 게이트 통과**

Run: `bash scripts/loop-gates.sh && bash check-models.sh`
Expected: 둘 다 `exit 0`.

- [ ] **Step 8: 커밋**

```bash
git add skills/plan-fusion/scripts/check-fusion.sh
git commit -m "feat(plan-fusion): GLM_VIA_AGENT 신호 + Judge 체인 ORCH=glm GLM 제거"
```

---

## Task 4: fusion.md.src §1·§2 GLM 참가자 분기

plan-fusion의 GLM 참가자 호출 블록 두 곳에 `GLM_VIA_AGENT` prose 분기를 추가: (a) §2 Code worktree 위임(L135-147), (b) §1 Research read-only 제네릭 opencode 블록(L105-106, id=glm일 때). 핵심: Agent 도구는 Bash 명령이 아니므로, 분기는 오케스트레이터가 "어느 도구를 쓸지 결정하는 지시"로 표현.

**Files:**
- Modify: `skills/plan-fusion/references/fusion.md.src:105-106` (§1 Research opencode 제네릭 블록)
- Modify: `skills/plan-fusion/references/fusion.md.src:135-147` (§2 Code GLM 참가자 블록)

- [ ] **Step 1: fusion.md.src의 GLM 참가자 블록 두 곳 정확히 읽기**

Run: `sed -n '100,170p' skills/plan-fusion/references/fusion.md.src`

현재 구조 확인:
- §1 Research(L105-106): 제네릭 `opencode run -m <prov/model> ...` — id=glm일 때 분기 필요.
- §2 Code(L135-147): `OMO_RUN_READY` 분기(omo/opencode). 이 블록 전체를 `GLM_VIA_AGENT` 우선 분기로 감싼다.

- [ ] **Step 2: §1 Research opencode 제네릭 블록에 id=glm 분기 주석 추가**

fusion.md.src L105-106(opencode run 제네릭) 위에 주석 추가:
```
# ⚠️ id=glm && GLM_VIA_AGENT=yes면 이 opencode 호출 대신 Agent 도구 dispatch를 쓴다(§2 GLM 블록과 동일).
#    오케스트레이터가 Agent 도구로 handoff 위임 → 응답을 $RUN/$id/result.md에 Write → manifest:
#    round1_exit=0, family=zcode-agent. (이 opencode 라인은 GLM_VIA_AGENT=no일 때만 실행.)
```

- [ ] **Step 3: §2 Code GLM 참가자 블록을 GLM_VIA_AGENT 우선 분기로 재작성**

`skills/plan-fusion/references/fusion.md.src`의 L135-147 영역(주석 `# glm — OMO_RUN_READY...`부터 `echo "model=..." >> "$RUN/glm/manifest"`까지)을 아래로 교체:

```
# glm — GLM_VIA_AGENT(check-fusion 출력) 값으로 어느 도구를 쓸지 결정:
#   ⚠️ Agent 도구 호출은 Bash 명령이 아니다. 오케스트레이터가 GLM_VIA_AGENT=yes면
#   Bash가 아니라 Agent 도구를 직접 호출하고, 응답을 result.md로 Write한다.
#
# ▶ GLM_VIA_AGENT=yes (오케스트레이터=GLM, 부모 GLM-5.2 상속):
#   1. Agent 도구 호출: subagent_type=general-purpose, model 생략(부모 GLM-5.2 상속).
#      prompt = "$RUN/handoff.md" 내용 + "HANDOFF 스펙에 따라 독립적으로 풀고 결과를 마크다운으로 반환하라."
#      (run_in_background: true 옵션은 동시성 상한 MAX_PARALLEL에 맞춰 선택.)
#   2. Agent 응답 텍스트를 Write 도구로 "$RUN/glm/result.md"에 저장.
#   3. Bash로 manifest 기록:
#        echo "round1_exit=0" >> "$RUN/glm/manifest"
#        echo "family=zcode-agent" >> "$RUN/glm/manifest"   # quorum에서 orchestrator-self 취급(독립 패밀리 카운트 제외)
#        echo "model=parent(GLM-5.2)" >> "$RUN/glm/manifest"
#   → extract_answer()가 result.md를 0순위로 반환하므로 기존 파이프라인 100% 호환.
#
# ▶ GLM_VIA_AGENT=no (기존 경로, 비-GLM 오케스트레이터 — 변경 없음):
if [ "${OMO_RUN_READY:-no}" = yes ]; then
  OMO_BIN=$(command -v omo 2>/dev/null || echo "bunx oh-my-openagent")
  $OMO_BIN run --agent Sisyphus -m @@GLM_CLI@@ -d "$RUN/wt/glm" --json \
    "$(cat "$RUN/handoff.md")" > "$RUN/glm/round1.log" 2>&1
else   # OMO 미준비 → opencode 직접 경로 자동 폴백
  opencode run -m @@GLM_CLI@@ --variant high --format json \
    --dir "$RUN/wt/glm" "$(cat "$RUN/handoff.md")" > "$RUN/glm/round1.log" 2>&1
fi
echo "round1_exit=$?" >> "$RUN/glm/manifest"
echo "family=opencode" >> "$RUN/glm/manifest"   # GLM_VIA_AGENT=no 경로 — quorum에선 opencode 1 family
echo "model=@@GLM_CLI@@" >> "$RUN/glm/manifest"
```

- [ ] **Step 4: §2 규칙 블록에 family=zcode-agent 카운트 설명 추가**

fusion.md.src의 §2 규칙 블록(family= 카운트 설명 근처, L146 주석 `# glm은 opencode 백엔드 →...`)에 한 줄 보강:

`family=zcode-agent는 orchestrator-self와 동일 취급 — quorum distinct-family 카운트에서 제외(부모 모델 상속 = 오케스트레이터 자신). GLM_VIA_AGENT=yes일 때만.`

- [ ] **Step 5: fusion.md.src에서 §3-1 extract_answer result.md 0순위 주석 보강**

fusion.md.src의 `extract_answer()` 함수(L188-190 영역)의 `result.md` 0순위 라인에 주석 보강:

```bash
  if [ -f "$RUN/$id/result.md" ]; then cat "$RUN/$id/result.md"; return; fi
  # ↑ 0순위: result.md 있으면 즉시 반환. codex(-o)·GLM-via-Agent(Write) 모두 이 경로.
  #   GLM_VIA_AGENT=yes면 오케스트레이터가 Agent 응답을 result.md로 Write → jq/ANSI 파싱 불필요.
```

- [ ] **Step 6: sync-models.sh 렌더로 fusion.md 재생성**

Run: `bash sync-models.sh`
Expected: `fusion.md ← fusion.md.src` 렌더 로그 + 드리프트 0.

- [ ] **Step 7: 렌더 결과에서 @@GLM_CLI@@ 치환 확인**

Run: `grep '@@' skills/plan-fusion/references/fusion.md | head -3`
Expected: 빈 출력(미치환 토큰 0). `zai-coding-plan/glm-5.2`가 치환돼 있어야 함.

Run: `grep -c 'zai-coding-plan/glm-5.2' skills/plan-fusion/references/fusion.md`
Expected: 기존과 동일하거나 증가(분기 블록에도 남아있으므로).

- [ ] **Step 8: 게이트 통과**

Run: `bash scripts/loop-gates.sh && bash check-models.sh`
Expected: 둘 다 `exit 0`.

- [ ] **Step 9: 커밋**

```bash
git add skills/plan-fusion/references/fusion.md.src skills/plan-fusion/references/fusion.md
git commit -m "feat(plan-fusion): GLM 참가자 §2 GLM_VIA_AGENT 분기 — Agent 도구 dispatch 경로"
```

---

## Task 5: fusion.md.src §3-2 Judge 체인 GLM 주석 정리

Task 3의 check-fusion.sh 변경(Judge 체인에서 ORCH=glm GLM 제거)에 대응하여, fusion.md.src의 Judge 체인 설명(L300-397 영역)에 GLM-via-Agent 상황을 문서화. 이미 체인 끝 `orchestrator-self`가 종착지이므로, `opencode:*glm*` 후보가 ORCH=glm일 때 제거됨을 명시.

**Files:**
- Modify: `skills/plan-fusion/references/fusion.md.src:330-340` (Judge 체인 opencode arm) + L397 근처(GLM 예외 설명)

- [ ] **Step 1: Judge 체인 opencode arm 주석에 ORCH=glm 조건 추가**

fusion.md.src L337(`glm/kimi|glm|kimi)` arm) 근처에 주석 추가:

```
        # ⚠️ ORCH_FAMILY=glm && GLM_VIA_AGENT=yes면 check-fusion.sh가 이 후보(opencode-glm)를
        #    Judge 체인에서 제외한다 — Agent dispatch(부모 상속)는 Judge 역할에 부적합(동족self).
        #    체인 끝 orchestrator-self가 자연 종착지. deepseek(opencode-go) 후보는 별도 provider라 유지.
```

- [ ] **Step 2: L397 GLM 예외 설명에 Judge 제외 명시**

L397 근처 "GLM 예외 + DeepSeek 예외" 문단에 한 문장 추가:

`Judge·Synth 후보에서는 GLM이 ORCH=glm일 때 동족(자기자신)이므로 제외 — 참가자 필수 포함은 유지하되 Judge/Synth는 orchestrator-self가 종착지.`

- [ ] **Step 3: 렌더 + 게이트**

Run: `bash sync-models.sh && bash scripts/loop-gates.sh && bash check-models.sh`
Expected: 전부 통과.

- [ ] **Step 4: 커밋**

```bash
git add skills/plan-fusion/references/fusion.md.src skills/plan-fusion/references/fusion.md
git commit -m "docs(plan-fusion): Judge 체인 GLM ORCH=glm 제거 문서화"
```

---

## Task 6: council.md.src GLM 패널 분기

plan-codex-opencode의 GLM 패널(council.md.src L82-89)에 동일한 `GLM_VIA_AGENT` 분기 추가.

**Files:**
- Modify: `skills/plan-codex-opencode/references/council.md.src:82-89`

- [ ] **Step 1: council.md.src GLM 패널 블록 읽기**

Run: `sed -n '80,98p' skills/plan-codex-opencode/references/council.md.src`

- [ ] **Step 2: GLM 패널 블록을 GLM_VIA_AGENT 분기로 재작성**

L82-89(`# glm 패널` ~ `echo "round1_exit=..."`)을 아래로 교체:

```
# glm 패널 — GLM_VIA_AGENT(check-fusion 출력)로 분기:
#   ⚠️ Agent 도구는 Bash가 아니다 — 오케스트레이터가 도구를 직접 호출.
#
# ▶ GLM_VIA_AGENT=yes (오케스트레이터=GLM):
#   1. Agent 도구: subagent_type=general-purpose, model 생략(부모 GLM-5.2 상속),
#      prompt = "$RUN/handoff.md" 내용.
#   2. 응답 → Write 도구로 "$RUN/glm/result.md" 저장.
#   3. Bash로 manifest: round1_exit=0, family=zcode-agent, model=parent(GLM-5.2).
#
# ▶ GLM_VIA_AGENT=no (기존 — omo Sisyphus):
OMO_BIN=$(command -v omo 2>/dev/null || echo "bunx oh-my-openagent")
mkdir -p "$RUN/glm"
$OMO_BIN run --agent Sisyphus \
  -m @@GLM_CLI@@ -d "$RUN/wt/glm" --json \
  "$(cat "$RUN/handoff.md")" \
  > "$RUN/glm/round1.log" 2>&1
echo "round1_exit=$?" >> "$RUN/glm/manifest"
echo "family=opencode" >> "$RUN/glm/manifest"
```

- [ ] **Step 3: 렌더 + 치환 확인**

Run: `bash sync-models.sh && grep '@@' skills/plan-codex-opencode/references/council.md | head -3`
Expected: 빈 출력(미치환 0).

- [ ] **Step 4: 게이트 통과**

Run: `bash scripts/loop-gates.sh && bash check-models.sh`
Expected: 둘 다 `exit 0`.

- [ ] **Step 5: 커밋**

```bash
git add skills/plan-codex-opencode/references/council.md.src skills/plan-codex-opencode/references/council.md
git commit -m "feat(plan-codex-opencode): GLM 패널 GLM_VIA_AGENT 분기 — Agent 도구 dispatch"
```

---

## Task 7: plan-then-opencode DELEGATE 분기

plan-then-opencode은 SKILL.md가 `.src`가 아니다(직접 수정). DELEGATE 섹션(L79-92)에 분기 추가.

**Files:**
- Modify: `skills/plan-then-opencode/SKILL.md:79-92`
- Modify: `skills/plan-then-opencode/references/omo-cli.md.src` (분기 문서화)
- Modify: `skills/plan-then-opencode/scripts/check-omo.sh` (GLM_VIA_AGENT passthrough — 필요 시)

- [ ] **Step 1: SKILL.md DELEGATE 섹션 읽기**

Run: `sed -n '75,95p' skills/plan-then-opencode/SKILL.md`

- [ ] **Step 2: DELEGATE 블록에 GLM_VIA_AGENT 분기 추가**

L79-92 영역의 omo 호출을 `GLM_VIA_AGENT` 우선 분기로 감싸기. 기존 omo 호출은 `else`(또는 no 경로)로:

기존:
```
$OMO_BIN run --agent "$AGENT" -d "<프로젝트 루트>" --json "$(cat "$RUN/handoff.md")" > "$RUN/round1.log" 2>&1
```

변경 후(분기 prose + 기존 유지):
```
# GLM_VIA_AGENT=yes(오케스트레이터=GLM)면 omo 대신 ZCode Agent 도구 dispatch(부모 GLM 상속):
#   1. Agent 도구: subagent_type=general-purpose, model 생략, prompt = "$RUN/handoff.md" 내용.
#   2. 응답 → Write 도구로 "$RUN/round1.log" 저장.
#   3. manifest: round1_exit=0, family=zcode-agent.
# GLM_VIA_AGENT=no면 기존 omo 경로:
$OMO_BIN run --agent "$AGENT" -d "<프로젝트 루트>" --json "$(cat "$RUN/handoff.md")" > "$RUN/round1.log" 2>&1
echo "round1_exit=$?" >> "$RUN/manifest"
```

- [ ] **Step 3: omo-cli.md.src에 GLM_VIA_AGENT 분기 섹션 추가**

`skills/plan-then-opencode/references/omo-cli.md.src` 끝에 섹션 추가:

```
## GLM_VIA_AGENT (오케스트레이터=GLM 조건부)

`PLAN_FUSION_ORCHESTRATOR=glm`이고 `models.yaml`의 `glm.backend_zcode_agent=yes`면,
check-fusion 출력의 `GLM_VIA_AGENT=yes` 신호를 받아 omo 대신 **ZCode Agent 도구 dispatch**로 전환한다.

- Agent 도구: `subagent_type=general-purpose`, `model` 생략(부모 GLM-5.2 상속).
- prompt = `$RUN/handoff.md` 내용.
- 응답 텍스트 → `$RUN/round1.log`로 Write.

이식성: `GLM_VIA_AGENT=no`(비-GLM 오케스트레이터)면 기존 omo Sisyphus 경로를 그대로 쓴다.
```

- [ ] **Step 4: check-omo.sh가 GLM_VIA_AGENT를 passthrough하는지 확인**

plan-then-opencode은 check-omo.sh를 쓴다. check-fusion.sh를 source 하거나 models.lib.sh를 읽어 GLM_VIA_AGENT를 계산해야 한다.

Run: `grep -n 'source\|GLM_VIA_AGENT\|check-fusion\|models.lib' skills/plan-then-opencode/scripts/check-omo.sh`
- check-fusion.sh를 이미 source 하면 GLM_VIA_AGENT가 자동 통과.
- source 안 하면 check-omo.sh에 SSOT 읽기 추가:
```bash
# models.lib.sh source (이미 있으면 스킵)
_SELF=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
[ -f "$_SELF/../models.lib.sh" ] && . "$_SELF/../models.lib.sh"
# GLM_VIA_AGENT 계산 (ORCH_FAMILY는 env 또는 argv)
_orch="${PLAN_FUSION_ORCHESTRATOR:-${1:-unknown}}"
if [ "$_orch" = glm ] && [ "$(read_model glm BACKEND_ZCODE_AGENT)" = yes ]; then
  echo "GLM_VIA_AGENT=yes"
else
  echo "GLM_VIA_AGENT=no"
fi
```

- [ ] **Step 5: 렌더 + 게이트**

Run: `bash sync-models.sh && bash scripts/loop-gates.sh && bash check-models.sh`
Expected: 전부 통과.

- [ ] **Step 6: 커밋**

```bash
git add skills/plan-then-opencode/SKILL.md skills/plan-then-opencode/references/omo-cli.md.src skills/plan-then-opencode/references/omo-cli.md skills/plan-then-opencode/scripts/check-omo.sh skills/plan-then-opencode/models.yaml skills/plan-then-opencode/models.lib.sh
git commit -m "feat(plan-then-opencode): GLM_VIA_AGENT 분기 — Agent 도구 dispatch 경로"
```

---

## Task 8: 파생 스킬(dev/secu/dev-secu) GLM_VIA_AGENT passthrough

파생 스킬들은 check 스크립트가 부모 check-fusion.sh 출력을 읽는다. `GLM_VIA_AGENT`가 passthrough되는지 확인.

**Files:**
- Modify: `skills/plan-fusion-dev/scripts/check-fusion-dev.sh` (필요 시)
- Modify: `skills/plan-fusion-secu/scripts/check-fusion-secu.sh` (필요 시)

- [ ] **Step 1: 파생 check 스크립트가 부모 출력을 어떻게 읽는지 확인**

Run: `grep -n 'check-fusion\|MODEL_READY_GLM\|GLM_MANDATORY\|GLM_VIA_AGENT' skills/plan-fusion-dev/scripts/check-fusion-dev.sh skills/plan-fusion-secu/scripts/check-fusion-secu.sh`

- [ ] **Step 2: passthrough 확인 또는 추가**

부모 check-fusion.sh 출력을 변수로 잡아 특정 신호를 grep하는 패턴이면, `GLM_VIA_AGENT`도 같은 방식으로 passthrough:

check-fusion-dev.sh 예시(부모 출력을 `_base_out`에 잡는다면):
```bash
# 부모 check-fusion.sh 출력에서 GLM_VIA_AGENT 통과
_glm_via_agent=$(printf '%s\n' "$_base_out" | sed -n 's/^GLM_VIA_AGENT=//p' | head -1)
echo "GLM_VIA_AGENT=${_glm_via_agent:-no}"
```

이미 부모 출력을 통째로 forward하면 변경 불필요. 각 스크립트 구조에 따라 결정.

- [ ] **Step 3: shell-syntax + 게이트**

Run: `bash -n skills/plan-fusion-dev/scripts/check-fusion-dev.sh && bash -n skills/plan-fusion-secu/scripts/check-fusion-secu.sh && bash scripts/loop-gates.sh`
Expected: 전부 통과.

- [ ] **Step 4: 커밋**

```bash
git add skills/plan-fusion-dev/scripts/check-fusion-dev.sh skills/plan-fusion-secu/scripts/check-fusion-secu.sh
git commit -m "feat(plan-fusion-dev/secu): GLM_VIA_AGENT passthrough"
```

---

## Task 9: routing-fusion.md.src + cli-fusion-map.md.src 문서 동기화

GLM 변형표와 5-CLI 경로 맵에 `zcode-agent` 백엔드와 `GLM_VIA_AGENT` 분기를 문서화.

**Files:**
- Modify: `skills/plan-fusion/references/routing-fusion.md.src` (GLM 변형표 행)
- Modify: `skills/plan-fusion/references/cli-fusion-map.md.src` (백엔드 맵 행)
- Modify: `skills/plan-fusion/SKILL.md.src` (동족 경고·omo 폴백 인용)

- [ ] **Step 1: routing-fusion.md.src GLM 변형표에 행 추가**

GLM 행(opencode 계열) 근처에 조건부 행 추가:
```
| glm (ORCH=glm, GLM_VIA_AGENT=yes) | zcode-agent | parent(GLM-5.2 상속) | Agent 도구 dispatch | result.md Write | 동족(self) — partial |
```

- [ ] **Step 2: cli-fusion-map.md.src에 zcode-agent 백엔드 추가**

5-CLI 경로 맵에 행 추가:
```
| zcode-agent | ZCode Agent 도구 (subagent dispatch) | model 생략=부모 상속 | 동기/비동기(background 옵션) | result.md(Write) | 오케스트레이터 패밀리=GLM일 때만 |
```

- [ ] **Step 3: SKILL.md.src 동족 경고·omo 폴백 인용에 분기 언급**

SKILL.md.src의 §0.2 동족 경고(GLM/KIMI 예외)와 L166 omo 폴백 인용 근처에 한 문장씩 추가:
- §0.2 근처: `ORCH_FAMILY=glm이면 GLM 참가자는 ZCode Agent 도구 dispatch(부모 상속)로 실행 — family=zcode-agent(quorum self 취급).`
- L166 근처 omo 폴백 인용: `GLM_VIA_AGENT=yes면 omo/opencode 경로 대신 Agent 도구 dispatch.`

- [ ] **Step 4: 렌더 + 게이트**

Run: `bash sync-models.sh && bash scripts/loop-gates.sh && bash check-models.sh`
Expected: 전부 통과.

- [ ] **Step 5: 커밋**

```bash
git add skills/plan-fusion/references/routing-fusion.md.src skills/plan-fusion/references/routing-fusion.md skills/plan-fusion/references/cli-fusion-map.md.src skills/plan-fusion/references/cli-fusion-map.md skills/plan-fusion/SKILL.md.src skills/plan-fusion/SKILL.md
git commit -m "docs(plan-fusion): zcode-agent 백엔드 + GLM_VIA_AGENT 분기 문서 동기화"
```

---

## Task 10: 최종 통합 검증

모든 변경이 게이트를 통과하고, SSOT 정합성이 유지되는지 최종 확인.

- [ ] **Step 1: 전체 sync-models.sh 재실행 (드리프트 0)**

Run: `bash sync-models.sh`
Expected: `OK: models SSOT 동기화 완료` + 드리프트 0.

- [ ] **Step 2: loop-gates 전체 통과**

Run: `bash scripts/loop-gates.sh`
Expected: `exit 0` (G1-G6 전부 PASS).

- [ ] **Step 3: check-models.sh 전체 통과**

Run: `bash check-models.sh`
Expected: `exit 0` — 드리프트 0, 미정의 모델명 0.

- [ ] **Step 4: ORCH=glm 시뮬레이션 end-to-end 신호 확인**

Run: `PLAN_FUSION_ORCHESTRATOR=glm bash skills/plan-fusion/scripts/check-fusion.sh 2>&1 | grep -E 'GLM_VIA_AGENT|GLM_ROUTING_NOTE|PARTICIPANT_CONFLICT|JUDGE_FALLBACK'`
Expected:
- `GLM_VIA_AGENT=yes`
- `GLM_ROUTING_NOTE=Agent-dispatch(parent-inherit)...`
- `PARTICIPANT_CONFLICT_RISK=partial(...)`
- `JUDGE_FALLBACK_CHAIN=...` — `opencode:*glm*` 후보가 빠져 있어야 함(deepseek는 유지).

- [ ] **Step 5: ORCH≠glm 분기 비활성 확인**

Run: `PLAN_FUSION_ORCHESTRATOR=gpt bash skills/plan-fusion/scripts/check-fusion.sh 2>&1 | grep 'GLM_VIA_AGENT'`
Expected: `GLM_VIA_AGENT=no`.

- [ ] **Step 6: git log 커밋 순서 확인**

Run: `git log --oneline -10`
Expected: Task 1-9 커밋이 순서대로, 각 메시지가 명확.

- [ ] **Step 7: docs 스펙/플랜 경로 README에 링크 (선택)**

이미 커밋된 spec + plan 경로를 팀 가시성을 위해 README나 docs 인덱스에 링크(옵션).

- [ ] **Step 8: 최종 커밋 (게이트 산출물만 남았으면)**

```bash
git status   # clean 확인
```

---

## 리스크 메모 (구현자 참고용)

1. **awk 파서 호환성(Task 2)**: `backend_zcode_agent` 키가 `[a-zA-Z_]+` 패턴에 매칭되어야 함. 매칭 안 되면 sync-models.sh L89 정규식 점검. 밑줄이 이미 포함되어 있으므로 예상과 달리 실패하면 awk 버전 차이 의심.
2. **도구 경계(Task 4·6·7)**: Agent 도구 호출은 Bash가 아님. 분기 블록에서 Bash `if/else` 안에 Agent 호출을 넣지 말 것 — prose 지시로 표현. 오케스트레이터가 GLM_VIA_AGENT 값을 읽고 어느 도구(Bash vs Agent)를 쓸지 결정.
3. **result.md Write 순서**: Agent 응답을 받은 *후*에 manifest를 기록. 응답 비어있으면 round1_exit=1로 무응답 처리 → 기존 quorum 로직이 자동 처리.
4. **동시성(선택)**: Agent 도구의 `run_in_background` 옵션은 동시성 상한(MAX_PARALLEL=3)에 맞춰 선택. 다른 참가자(opencode/omo)는 백그라운드 Bash로 진행 중이므로 조율 필요.
