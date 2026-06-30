---
name: plan-then-opencode
description: Split-brain 워크플로우 — Claude가 분석·계획·에이전트 선택·검증을 맡고 실제 구현은 oh-my-openagent(omo)를 통해 opencode 에이전트에 위임한다. Use when 사용자가 "분석/계획은 claude로 하고 구현은 opencode(omo)로", "sisyphus/hephaestus/prometheus에 위임", "omo로 구현해", "opencode 에이전트로 실행"처럼 Claude 계획 + omo 실행을 분리하는 요청을 할 때.
---

# plan-then-opencode — Claude 계획 × omo 실행

Claude = 두뇌(분석·계획·에이전트 선택·검증), omo = 손(구현·오케스트레이션).

`SKILL_DIR` = 이 SKILL.md가 있는 디렉토리. `$RUN` = 이번 위임의 격리 작업 폴더(0단계 생성).

---

## 에이전트 선택 기준

> **모델명 SSOT**: 아래 표의 모델명은 `models.yaml`(단일 진실원)에서 온다. 버전업·모델명
> 변경 시 **models.yaml 만 고치고 `sync-models.sh`** — `check-models.sh` 가 이 파일과 SSOT
> 정합을 자동 검증(드리프트 시 FAIL). 스크립트는 `models.lib.sh` 를 source 해 변수로 읽는다.

| 에이전트 | 모델(기본) | 언제 쓰나 |
|----------|-----------|-----------|
| **Prometheus** | Kimi K2.7 / Claude Opus | 요구사항이 모호하거나 범위 확정·인터뷰가 먼저 필요한 경우. 계획을 먼저 수립하고 사용자 승인 후 Sisyphus에 위임. |
| **Sisyphus** | Kimi K2.7 / GLM-5.2 | 복잡한 다단계 구현, 병렬 서브태스크 오케스트레이션, 끝까지 완수 보장이 필요한 경우. **(기본 선택)** |
| **Hephaestus** | GPT-5.5 | 범위가 명확한 단일 심층 작업. 코드베이스를 직접 탐색·실행하는 자율 작업자. |

사용자가 에이전트를 명시하면 그대로 따른다. 명시 없으면 위 기준으로 Claude가 판단하고 사용자에게 한 줄로 이유를 설명한다.

---

## 0. 사전 점검

```bash
bash "$SKILL_DIR/scripts/check-omo.sh"
```

- exit 0 → 진행. exit 1 → 사용자에게 HINT 출력 후 중단.
- 임시 작업 폴더 생성(격리):
  ```bash
  slug=$(echo "<태스크 한 단어>" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | head -c20)
  RUN=$(umask 077; mktemp -d "${TMPDIR:-/tmp}/pto.${slug}.XXXXXX") || { echo "RUN 생성 실패"; exit 1; }
  [ -d "$RUN" ] || { echo "RUN 생성 실패"; exit 1; }
  ```

---

## 1. ANALYZE

현재 작업트리와 태스크를 분석한다:
- 변경 대상 파일·컴포넌트, 스택, 빌드·테스트·린트 명령
- 의존성·부작용, 인간 승인 필요 여부(스키마/보안/결제/배포)
- 태스크 복잡도 → 에이전트 선택 근거
- **UI 노출 판정(필수)**: 이 작업이 사용자에게 노출되는 변경인가(새 화면·컴포넌트·라우트·상호작용·표시 로직)를 yes/no로 판정하고 **1줄 근거**를 HANDOFF의 'UI 노출 판정' 필드에 기록한다.
  - yes → HANDOFF의 '디자인 스펙' 섹션 + UI Acceptance Criteria를 필수화(아래 §2 PLAN · §4 VERIFY 연동).
  - no → '디자인 스펙' 생략 가능하되, **근거 없는 no는 금지** — 판정 사유를 HANDOFF에 명시해 감사 가능성을 유지한다.

---

## 2. PLAN

`git -C "<프로젝트 루트>" rev-parse --is-inside-work-tree >/dev/null || { echo "프로젝트 루트가 git 저장소가 아닙니다"; exit 1; }`
`git -C "<프로젝트 루트>" status --short > "$RUN/baseline.status"` 로 baseline 스냅샷을 남긴다.

`templates/HANDOFF.md.tmpl`을 읽어 `{{...}}` 토큰을 채운 뒤 `"$RUN/handoff.md"`로 저장한다.

**자기완결성 체크**: Handoff는 omo 에이전트가 대화 컨텍스트 없이 읽어도 완전해야 한다.
- Mission 1줄, Context(스택/경로/명령), Baseline(dirty 파일 보존 지시), 변경 지시(파일별 구체 수치), Acceptance Criteria, BLOCKED 프로토콜이 모두 있는지 확인한다.
- 선택한 에이전트와 그 이유를 Handoff 상단에 명시한다.

계획을 사용자에게 보여주고 바로 진행한다(태스크가 인간 승인 영역이면 여기서 중단·확인).

---

## 3. DELEGATE

omo를 실행하고 manifest에 메타데이터를 기록한다. **실행 모드 선택(수동 대기 회피)**:
- **짧은 작업(예상 < 2분)**: 포그라운드 동기 실행. 끝날 때까지 같은 턴에서 기다린 뒤 바로 §4 VERIFY로.
- **긴 작업(다단계/Sisyphus 등)**: 백그라운드 실행. 단, 턴을 끝내고 수동으로 알림만 기다리지 **않는다** — 다음 응답에서 능동적으로 `cat "$RUN/round1.exit"`/로그 tail로 상태 확인. 완료 시 즉시 §4, 미완료 시 "실행 중" 1줄 보고.

```bash
# omo 바이너리 결정 (omo PATH 우선, 없으면 bunx oh-my-openagent)
OMO_BIN=$(command -v omo 2>/dev/null || echo "bunx oh-my-openagent")
AGENT="Sisyphus"   # 1단계 ANALYZE에서 선택한 에이전트로 치환(Prometheus/Sisyphus/Hephaestus)
# ⚠️ `bunx omo` / `npx omo`는 다른 패키지가 설치되므로 절대 사용 금지

$OMO_BIN run \
  --agent "$AGENT" \
  -d "<프로젝트 루트>" \
  --json \
  "$(cat "$RUN/handoff.md")" \
  > "$RUN/round1.log" 2>&1
echo "round1_exit=$?" >> "$RUN/manifest"
```

**Session ID 추출** (resume용):
```bash
SESSION_ID=$(grep -o '"sessionId":"[^"]*"' "$RUN/round1.log" | head -1 | sed 's/.*"sessionId":"\([^"]*\)".*/\1/')
# 실패 시 opencode session 목록에서 최신 세션 시도
if [ -z "$SESSION_ID" ]; then
  # opencode session list --format json 의 JSON 필드명은 버전에 따라 다를 수 있음.
  # 추출 실패 시 "$RUN/round1.log"에서 session 관련 JSON 키를 직접 확인할 것.
  SESSION_ID=$(opencode session list --format json 2>/dev/null | grep -o '"id":"[^"]*"' | head -1 | sed 's/.*"id":"\([^"]*\)".*/\1/')
fi
echo "session_id=$SESSION_ID" >> "$RUN/manifest"
```

- `round1_exit ≠ 0` 이면 `"$RUN/round1.log"` 확인 → 인증/경로/모델 오류면 Claude가 직접 수정 후 재시도(ORCHESTRATION_FAIL — 라운드 미산입).
- omo는 **모든 todo 완료 + 자식 세션 idle** 시 자동 종료된다 — 외부 폴링 불필요.

---

## 4. VERIFY

결과를 검증하고 미달이면 세션을 resume해 수정을 요청한다(최대 3라운드):

```bash
# 라운드 N resume
$OMO_BIN run \
  --session-id "$SESSION_ID" \
  -d "<프로젝트 루트>" \
  --json \
  "다음 Acceptance Criteria를 확인하고 미달 항목을 수정하라. 수정 후 재검증 결과를 보고하라.

$(awk '/^## Acceptance Criteria/{capture=1} capture && /^## / && !/^## Acceptance Criteria/{exit} capture {print}' "$RUN/handoff.md")

미달이면 BLOCKED 형식으로 보고하라." \
  > "$RUN/roundN.log" 2>&1
echo "roundN_exit=$?" >> "$RUN/manifest"
```

검증 항목:
1. **빌드·타입·테스트·린트** — Bash로 실제 실행, exit code·출력 확인
2. **Acceptance Criteria** — Handoff의 각 항목 대조
3. **UI 노출 판정=yes이면** — 디자인 스펙(타이포/컬러/간격/레이아웃) 반영 여부 + UI AC(예: before/after 스크린샷 대조) 충족. 스펙 미준수·UI 누락 시 FAIL → omo resume으로 수정 지시.
4. **Baseline 보존** — dirty 파일이 의도치 않게 revert·수정되지 않았는지
   - `git -C "<프로젝트 루트>" status --short | diff "$RUN/baseline.status" -` 로 현재 차이가 의도한 변경 파일뿐인지 확인
5. **범위 준수** — '변경 지시' 밖 파일이 수정되지 않았는지

- 검증 통과 → 5. REPORT 진행
- 미달 → `$RUN/roundN.log` 로 원인 파악 → resume으로 수정 요청 → 재검증
- **3라운드 후에도 미달이면 중단**하고 남은 항목을 사용자에게 보고.
- resume이 플래그 오류로 즉사하면 ORCHESTRATION_FAIL(라운드 미산입) — session ID 재확인 후 재시도.

---

## 5. REPORT

최종 메시지에 포함:
- 변경 파일 목록
- Acceptance Criteria 항목별 충족/미충족(증거 요약)
- **BLOCKED 여부·적용 기본 결정·남은 질문**
- 사용한 에이전트·모델, 라운드 수(+ORCHESTRATION_FAIL 횟수)
- `$RUN` 경로(handoff/manifest/round*.log)
- UI 작업이면 before/after 스크린샷 경로
