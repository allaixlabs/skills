---
name: plan-then-codex
description: Split-brain 워크플로우 — Claude가 분석·계획·검증을 맡고 실제 코드 구현은 Codex CLI(codex exec)에 위임한다. Use when the user says "분석/계획은 claude로 하고 구현/수행/실행은 codex로(위임해서) 진행", "codex gpt5.5 xhigh로 구현", "codex에 위임", "implement with codex", or any request that splits planning (Claude) from implementation (Codex).
---

# Plan-then-Codex

Claude = 두뇌(분석·계획·검증), Codex = 손(구현). 핵심 전제: **Codex는 이 대화의
컨텍스트를 전혀 모른다.** 따라서 위임의 품질은 HANDOFF 문서의 자기완결성이 결정한다.

`SKILL_DIR` = 이 SKILL.md가 있는 디렉토리. `$RUN` = 이번 위임의 격리 작업 폴더(0단계 생성).

## 역할 분담 (절대 규칙)

- **Claude**: 분석, HANDOFF 작성, 결과 검증, 재지시. **프로덕션 코드를 직접 수정하지 않는다.**
  단, 오케스트레이션 산출물(`$RUN`의 HANDOFF/manifest/로그) 수정과 fresh 재위임은 Claude 권한.
- **Codex**: HANDOFF 스펙대로만 구현. 재계획·범위 확장 금지. 모호성은 BLOCKED 프로토콜로 처리.
- 검증 중 발견된 코드 문제도 직접 고치지 말고 resume으로 Codex에 되돌린다(4단계).

## 0. 사전 점검 + 요청 파싱

```bash
bash "$SKILL_DIR/scripts/check-codex.sh"                          # read-only 점검
slug=$(echo "<태스크 한 단어>" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | head -c20)
RUN=$(umask 077; mktemp -d "${TMPDIR:-/tmp}/ptc.${slug}.XXXXXX") || { echo "RUN 생성 실패"; exit 1; }
[ -d "$RUN" ] || { echo "RUN 생성 실패"; exit 1; }
echo "$RUN"
```

- `CODEX_INSTALLED=no` → stderr의 설치 HINT 안내 후 중단. `CODEX_AUTH=missing` → `! codex login` 요청 후 중단.
- `CONFIG_MODEL_ESTIMATE`/`CONFIG_EFFORT_ESTIMATE`는 top-level config 해석일 뿐이다. 실험값은 실행 배너로 확정한다.

**요청 파싱** — 사용자 언급을 플래그로 변환. 언급 없으면 플래그 생략(config 기본값).

| 사용자 표현 | 플래그 |
|---|---|
| "gpt5.5", "gpt-5.6-sol" | `-m gpt-5.6-sol` — 사용자의 Codex 환경에서 지원/alias 확인 시 |
| "xhigh" / "high" / "medium" / "low" / "minimal" | `-c model_reasoning_effort="<값>"` |

모델명이 unsupported로 실패하면 구현 라운드가 아니라 `ORCHESTRATION_FAIL`로 분류하고, 사용자 config alias 또는 사용 가능한 모델명을 확인한 뒤 재시도한다.

## 1. ANALYZE — Claude가 직접

- 관련 소스 파일, 스택, 실행/빌드/테스트 명령을 파악한다.
- UI 작업이면 실행 중인 URL을 직접 확인하고(playwright-cli 스크린샷 → `$RUN/before-*.png`)
  **본 것을 텍스트 스펙으로 변환**한다 — Codex는 브라우저를 보지 못한다.
- **UI 노출 판정(필수)**: 이 작업이 사용자에게 노출되는 변경인가(새 화면·컴포넌트·라우트·상호작용·표시 로직)를 yes/no로 판정하고 **1줄 근거**를 HANDOFF의 'UI 노출 판정' 필드에 기록한다.
  - yes → HANDOFF의 '디자인 스펙' 섹션 + UI Acceptance Criteria를 필수화(아래 §2 PLAN · §4 VERIFY 연동).
  - no → '디자인 스펙' 생략 가능하되, **근거 없는 no는 금지** — 판정 사유를 HANDOFF에 명시해 감사 가능성을 유지한다.

## 2. PLAN — HANDOFF 작성 + baseline 스냅샷

[templates/HANDOFF.md.tmpl](templates/HANDOFF.md.tmpl) 기반으로 `$RUN/handoff.md` 작성.

```bash
git -C "<프로젝트 루트>" rev-parse --is-inside-work-tree >/dev/null || { echo "프로젝트 루트가 git 저장소가 아닙니다"; exit 1; }
git -C "<프로젝트 루트>" rev-parse HEAD > "$RUN/baseline.head"
git -C "<프로젝트 루트>" status --porcelain=v1 -z > "$RUN/baseline.status.z"
git -C "<프로젝트 루트>" status --short > "$RUN/baseline.status"
git -C "<프로젝트 루트>" diff --binary > "$RUN/baseline.unstaged.patch"
git -C "<프로젝트 루트>" diff --cached --binary > "$RUN/baseline.staged.patch"
git -C "<프로젝트 루트>" ls-files -o --exclude-standard -z > "$RUN/baseline.untracked.z"
```

자기완결성 체크:

- [ ] 파일 경로 정확, 변경 지시는 구체 수치/토큰/코드 수준 — "전문가 느낌" 같은 추상어 금지
- [ ] Baseline 섹션: 위임 전 dirty 파일 목록 + **기존 변경 revert/포함 금지** 명시
- [ ] 위임 전 dirty 파일이 변경 지시 파일과 겹치면 사용자에게 "기존 변경 위에 추가 수정" 승인 확인. 승인 없으면 BLOCKED.
- [ ] Out of scope + 모호성 처리(BLOCKED 프로토콜, 템플릿 기본 포함) 유지
- [ ] Acceptance Criteria마다 확인 명령 포함, 완료 보고 형식 지정

계획 요약(변경 파일·핵심 지시·검증 기준·모델/effort·네트워크 필요 여부)을 사용자에게 보여준다.
다음 중 하나라도 해당하면 진행 전 명시 확인을 받는다: 네트워크 허용, 의존성 설치, 스키마/보안/시크릿/결제/배포/PRD범위/아키텍처 영향, xhigh 장시간 실행, baseline dirty 파일과 변경 대상 겹침.
그 외 저위험 단순 위임은 사용자 요청이 이미 명시적이면 3단계로 진행한다.

## 3. DELEGATE — codex exec (포그라운드 또는 백그라운드+능동 폴링)

```bash
NETWORK_FLAGS=()
# 기본: 네트워크 차단. 패키지 설치/API 호출/localhost 접근이 꼭 필요할 때만 사용자 승인 후 NETWORK_FLAGS를 채운다.
# 승인된 경우에만:
# NETWORK_FLAGS=(-c sandbox_workspace_write.network_access=true)

# Bash 도구는 이 전체 블록을 run_in_background: true로 실행한다.
ROUND=1
printf 'project_root=%s\nround%s_started_at=%s\nround%s_result=%s\nround%s_log=%s\n' \
  "<프로젝트 루트>" "$ROUND" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "$ROUND" "$RUN/result-r1.md" "$ROUND" "$RUN/round1.log" >> "$RUN/manifest"

codex exec -C "<프로젝트 루트>" \
  --sandbox workspace-write "${NETWORK_FLAGS[@]}" \
  [-m gpt-5.6-sol] [-c model_reasoning_effort="xhigh"] [-i "$RUN/before-1.png"] \
  -o "$RUN/result-r1.md" - < "$RUN/handoff.md" > "$RUN/round1.log" 2>&1
round1_rc=$?

session_id=$(grep -m1 'session id:' "$RUN/round1.log" | awk '{print $NF}')
{
  printf 'round1_exit=%s\n' "$round1_rc"
  printf 'round1_finished_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  [ -n "$session_id" ] && printf 'session_id=%s\nround1_session_id=%s\n' "$session_id" "$session_id"
  grep -m1 '^model:' "$RUN/round1.log"
  grep -m1 '^reasoning effort:' "$RUN/round1.log"
} >> "$RUN/manifest"

exit "$round1_rc"
```

- **실행 모드 선택(수동 대기 회피)**:
  - **짧은 작업(예상 < 2분)**: 포그라운드 동기 실행(`run_in_background: false`). 백엔드가 끝날 때까지 같은 턴에서 기다린 뒤 바로 §4 VERIFY로 넘어간다 — 다른 동기 스킬처럼 "대기 없는 진행".
  - **긴 작업(수분~수십분, xhigh 등)**: `run_in_background: true`로 실행. 단, 턴을 끝내고 수동으로 알림만 기다리지 **않는다** — 완료 가능성이 있으면 다음 응답에서 **능동적으로** `cat "$RUN/round1.exit" 2>/dev/null`(또는 로그 tail)로 상태를 확인하고, 완료 시 즉시 §4 VERIFY로, 미완료 시 "아직 실행 중(예상 N분)" 1줄만 보고한다.
- 완료 전에는 `$RUN/result-rN.md`, `$RUN/roundN.log`, `$RUN/manifest`의 **최종 결과**를 읽지 않는다(race 방지 — 빈 파일·직전 라운드 결과). 단 exit/로그 tail로 진행 상태 확인은 허용한다.
- **완료(exit 파일 존재 또는 `Background task completed`/`task-notification` 알림) 확인 시 즉시** 결과 read → §4 VERIFY로 넘어간다. "기다리겠다"며 멈추거나 진행 없이 안내문만 내놓지 않는다(진행 상황 보고는 허용) — "전(read) 금지"는 알림 **후** 진행을 막는 게 아니라 **전** race만 막는다.
- `session_id`가 비어 있으면 구현 실패가 아니라 `ORCHESTRATION_FAIL`로 분류하고 fresh 재위임한다.
- 플래그 상세·트러블슈팅: [references/codex-cli.md](references/codex-cli.md)

## 4. VERIFY — Claude가 직접

1. `git status --short`를 `$RUN/baseline.status`와 대조 — **Codex 변경분만** 평가한다.
   Scope 밖 수정·기존 dirty 파일 훼손은 즉시 FAIL 항목.
2. `result-r1.md`의 성공 주장을 믿지 말고 Acceptance Criteria를 **직접 실행 증거로** 확인
   — 빌드/테스트 실행, UI면 재스크린샷(`$RUN/after-*.png`) 후 before와 비교.
   Codex의 localhost 확인은 "시도"일 뿐, 최종 진실은 Claude의 브라우저 검증이다.
   **UI 노출 판정=yes**이면 디자인 스펙(타이포/컬러/간격/레이아웃) 반영 여부도 대조한다 — 스펙을 안 따르면 FAIL → Codex resume으로 수정 지시.
3. **loop-md Verify는 이 단계(§4)에서 실행하지 않는다** — 완료 보고를 지연시키는 연동 결함 방지. loop.md 연동은 아래 §4.5에서 REPORT **전**에 별도 실행한다(다른 동기 스킬처럼 "완료 결과 먼저 사용자에게, 무거운 DoD 검증은 그 후").
4. 미달 시 재작업 — **manifest의 session id로 resume** (`--last` 금지: 동시 세션 오선택 위험):

   ```bash
   cd "<프로젝트 루트>"   # manifest의 project_root와 `pwd -P` 일치 확인 후

   # Claude가 $RUN/round2-prompt.md를 파일로 작성한다.
   # 실패 로그/따옴표/backtick/$(...)를 셸 명령 문자열에 직접 붙이지 않는다.
   ROUND=2
   SESSION_ID="<session_id>"
   ROUND_PROMPT_FILE="$RUN/round2-prompt.md"
   [ -s "$ROUND_PROMPT_FILE" ] || { echo "round2 prompt missing"; exit 2; }

   printf 'round%s_started_at=%s\nround%s_prompt=%s\nround%s_result=%s\nround%s_log=%s\n' \
     "$ROUND" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     "$ROUND" "$ROUND_PROMPT_FILE" "$ROUND" "$RUN/result-r2.md" "$ROUND" "$RUN/round2.log" >> "$RUN/manifest"

   ROUND_PROMPT=$(cat "$ROUND_PROMPT_FILE")
   codex exec resume "$SESSION_ID" -o "$RUN/result-r2.md" \
     "$ROUND_PROMPT" > "$RUN/round2.log" 2>&1
   round2_rc=$?
   printf 'round2_exit=%s\nround2_finished_at=%s\n' \
     "$round2_rc" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$RUN/manifest"
   exit "$round2_rc"
   ```

   - 동적 실패 증거는 반드시 `$RUN/roundN-prompt.md`에 먼저 저장한다. 셸 명령의 quoted argument 안에 로그 원문을 직접 보간하지 않는다.
   - resume은 `-C`/`--sandbox`/`--add-dir` **미지원**(0.139.0 실측). sandbox는 원 세션에서 상속된다.
     cwd/sandbox/쓰기 범위를 바꿔야 하면 resume 불가 → 새 HANDOFF로 fresh 재위임.
   - **라운드 산입 규칙**: Codex가 정상 실행된 구현 시도만 센다(최대 3라운드).
     CLI 플래그·설정·환경 실패는 `ORCHESTRATION_FAIL` — 라운드 미산입, Claude가 고치고 재시도.
   - 3라운드 후에도 미달이면 중단하고 남은 항목을 사용자에게 보고.

## 4.5 loop-md 연동 (완료 보고 후 별도 실행 — 지연 방지)

프로젝트 루트에 `loop.md`가 있으면, **§4 VERIFY 통과 직후·사용자에게 완료 결과를 보고한 뒤** loop-md 스킬 Verify 모드(①Pass/Fail 게이트·②정량·③정성)를 실행한다. 순서가 중요:
1. **먼저** 백엔드 결과(`result-rN.md` 요약·변경 파일·AC 충족)를 사용자에게 보고 — 다른 동기 스킬처럼 "완료 즉시 알림".
2. **그 다음** loop-md Verify(긴 절차: 게이트 실행·stash 체크포인트·필요 시 롤백)를 실행 — 이게 끼어들어 1의 완료 보고를 지연시키지 않게.
3. loop-md Verify 통과 시 `.loop/last-verified` 마커를 현재 HEAD로 갱신한 뒤 커밋(가드 통과 조건).
루트 `loop.md` 없으면 이 절차 N/A.

## 5. REPORT

REPORT 전 BLOCKED 검증:

- `result-rN.md`가 `BLOCKED`를 보고하면 즉시 현재 상태를 저장한다.
  `git -C "<프로젝트 루트>" status --short > "$RUN/blocked.status"`
- `diff -u "$RUN/baseline.status" "$RUN/blocked.status"`가 0이 아니면 `BLOCKED_WITH_DIFF_FAIL`로 분류한다.
- BLOCKED 상태에서 변경이 섞였으면 Codex의 BLOCKED 보고를 신뢰하지 말고, 변경 파일 목록과 함께 사용자에게 중단 보고한다.

`$RUN` 보존 정책:

- `DONE` + 검증 통과: 최종 보고에 핵심 증거를 요약한 뒤 기본 삭제(`rm -rf -- "$RUN"`). 사용자가 디버깅/감사를 위해 보존 요청하면 경로를 보고하고 보존.
- `FAIL` / `BLOCKED` / `ORCHESTRATION_FAIL`: 삭제하지 않고 `$RUN` 경로를 보고.
- `$RUN`은 `umask 077`로 생성된 민감 로그 영역이므로, 경로를 공유할 때 외부 업로드 금지.

최종 메시지에 포함: 변경 파일 목록, 기준별 충족/미충족(증거 요약), **BLOCKED 여부·적용된 기본
결정·남은 질문**, 사용 모델·effort(배너 실효값 기준), 라운드 수(+`ORCHESTRATION_FAIL` 횟수).
UI 작업이면 before/after 스크린샷 경로. `$RUN` 경로는 보존 정책상 보고 대상일 때만 포함한다.
