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
- `CONFIG_MODEL`/`CONFIG_EFFORT`는 top-level config 해석(추정값) — 실효값은 3단계 실행 배너로 확정.

**요청 파싱** — 사용자 언급을 플래그로 변환. 언급 없으면 플래그 생략(config 기본값).

| 사용자 표현 | 플래그 |
|---|---|
| "gpt5.5", "gpt-5.5" | `-m gpt-5.5` |
| "spark" (빠른 작업) | `-m gpt-5.3-codex-spark` |
| "xhigh" / "high" / "medium" / "low" / "minimal" | `-c model_reasoning_effort="<값>"` |

## 1. ANALYZE — Claude가 직접

- 관련 소스 파일, 스택, 실행/빌드/테스트 명령을 파악한다.
- UI 작업이면 실행 중인 URL을 직접 확인하고(playwright-cli 스크린샷 → `$RUN/before-*.png`)
  **본 것을 텍스트 스펙으로 변환**한다 — Codex는 브라우저를 보지 못한다.

## 2. PLAN — HANDOFF 작성 + baseline 스냅샷

[templates/HANDOFF.md.tmpl](templates/HANDOFF.md.tmpl) 기반으로 `$RUN/handoff.md` 작성.

```bash
git -C "<프로젝트 루트>" rev-parse --is-inside-work-tree >/dev/null || { echo "프로젝트 루트가 git 저장소가 아닙니다"; exit 1; }
git -C "<프로젝트 루트>" status --short > "$RUN/baseline.status"   # 위임 전 dirty 상태 고정
```

자기완결성 체크:

- [ ] 파일 경로 정확, 변경 지시는 구체 수치/토큰/코드 수준 — "전문가 느낌" 같은 추상어 금지
- [ ] Baseline 섹션: 위임 전 dirty 파일 목록 + **기존 변경 revert/포함 금지** 명시
- [ ] Out of scope + 모호성 처리(BLOCKED 프로토콜, 템플릿 기본 포함) 유지
- [ ] Acceptance Criteria마다 확인 명령 포함, 완료 보고 형식 지정

계획 요약(변경 파일·핵심 지시·검증 기준)을 사용자에게 보여주고 바로 3단계 진행.

## 3. DELEGATE — codex exec (항상 백그라운드)

```bash
codex exec -C "<프로젝트 루트>" \
  --sandbox workspace-write -c sandbox_workspace_write.network_access=true \
  [-m gpt-5.5] [-c model_reasoning_effort="xhigh"] [-i "$RUN/before-1.png"] \
  -o "$RUN/result-r1.md" - < "$RUN/handoff.md" > "$RUN/round1.log" 2>&1
echo "round1_exit=$?" >> "$RUN/manifest"
```

- **반드시 Bash `run_in_background: true`로 실행** — xhigh 구현은 수 분~수십 분.
- 완료 후 manifest를 채운다(이후 라운드와 REPORT의 생명줄):

```bash
{ echo "project_root=<프로젝트 루트>"
  grep -m1 'session id:' "$RUN/round1.log" | awk '{print "session_id="$NF}'
  grep -m1 '^model:' "$RUN/round1.log"
  grep -m1 '^reasoning effort:' "$RUN/round1.log"
} >> "$RUN/manifest"
```

- 플래그 상세·트러블슈팅: [references/codex-cli.md](references/codex-cli.md)

## 4. VERIFY — Claude가 직접

1. `git status --short`를 `$RUN/baseline.status`와 대조 — **Codex 변경분만** 평가한다.
   Scope 밖 수정·기존 dirty 파일 훼손은 즉시 FAIL 항목.
2. `result-r1.md`의 성공 주장을 믿지 말고 Acceptance Criteria를 **직접 실행 증거로** 확인
   — 빌드/테스트 실행, UI면 재스크린샷(`$RUN/after-*.png`) 후 before와 비교.
   Codex의 localhost 확인은 "시도"일 뿐, 최종 진실은 Claude의 브라우저 검증이다.
3. 프로젝트 루트에 `loop.md`가 있으면 loop-md 스킬 Verify 모드를 수행한다.
4. 미달 시 재작업 — **manifest의 session id로 resume** (`--last` 금지: 동시 세션 오선택 위험):

   ```bash
   cd "<프로젝트 루트>"   # manifest의 project_root와 `pwd -P` 일치 확인 후
   codex exec resume "<session_id>" -o "$RUN/result-r2.md" \
     "VERIFY 미달 항목만 수정하라: <기준별 실패 증거와 교정 지시>" > "$RUN/round2.log" 2>&1
   ```

   - resume은 `-C`/`--sandbox`/`--add-dir` **미지원**(0.139.0 실측). sandbox는 원 세션에서 상속된다.
     cwd/sandbox/쓰기 범위를 바꿔야 하면 resume 불가 → 새 HANDOFF로 fresh 재위임.
   - **라운드 산입 규칙**: Codex가 정상 실행된 구현 시도만 센다(최대 3라운드).
     CLI 플래그·설정·환경 실패는 `ORCHESTRATION_FAIL` — 라운드 미산입, Claude가 고치고 재시도.
   - 3라운드 후에도 미달이면 중단하고 남은 항목을 사용자에게 보고.

## 5. REPORT

최종 메시지에 포함: 변경 파일 목록, 기준별 충족/미충족(증거 요약), **BLOCKED 여부·적용된 기본
결정·남은 질문**, 사용 모델·effort(배너 실효값 기준), 라운드 수(+`ORCHESTRATION_FAIL` 횟수),
`$RUN` 경로(handoff/manifest/result/log/스크린샷). UI 작업이면 before/after 스크린샷 경로.
