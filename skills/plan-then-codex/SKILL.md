---
name: plan-then-codex
description: Split-brain 워크플로우 — Claude가 분석·계획·검증을 맡고 실제 코드 구현은 Codex CLI(codex exec)에 위임한다. Use when the user says "분석/계획은 claude로 하고 구현/수행/실행은 codex로(위임해서) 진행", "codex gpt5.5 xhigh로 구현", "codex에 위임", "implement with codex", or any request that splits planning (Claude) from implementation (Codex).
---

# Plan-then-Codex

Claude = 두뇌(분석·계획·검증), Codex = 손(구현). 핵심 전제: **Codex는 이 대화의
컨텍스트를 전혀 모른다.** 따라서 위임의 품질은 HANDOFF 문서의 자기완결성이 결정한다.

`SKILL_DIR` = 이 SKILL.md가 있는 디렉토리. 아래 경로는 그 기준이다.

## 역할 분담 (절대 규칙)

- **Claude**: 코드/페이지 분석, HANDOFF 작성, 결과 검증, 재지시. **프로덕션 코드를 직접 수정하지 않는다.**
- **Codex**: HANDOFF 스펙대로만 구현. 재계획·범위 확장 금지(HANDOFF에 명문화).
- 검증 중 발견된 문제도 직접 고치지 말고 `resume`으로 Codex에 되돌린다(4단계).

## 0. 사전 점검 + 요청 파싱

**사전 점검** (read-only — 설치/인증/기본값 확인):

```bash
bash "$SKILL_DIR/scripts/check-codex.sh"
```

- `CODEX_INSTALLED=no` → stderr의 설치 HINT를 사용자에게 안내하고 중단.
- `CODEX_AUTH=missing` → 사용자에게 `! codex login` 실행을 요청하고 중단.
- `DEFAULT_MODEL`/`DEFAULT_EFFORT` = 플래그 생략 시 적용될 값. 5단계 REPORT에 기록.

**요청 파싱** — 사용자 언급을 플래그로 변환. 언급이 없으면 플래그 생략(위 기본값 사용).

| 사용자 표현 | 플래그 |
|---|---|
| "gpt5.5", "gpt-5.5" | `-m gpt-5.5` |
| "spark" (빠른 작업) | `-m gpt-5.3-codex-spark` |
| "xhigh" / "high" / "medium" / "low" / "minimal" | `-c model_reasoning_effort="<값>"` |

## 1. ANALYZE — Claude가 직접

- 관련 소스 파일, 스택, 실행/빌드/테스트 명령을 파악한다.
- UI 작업이면 실행 중인 URL을 직접 확인하고(playwright-cli로 스크린샷 캡처 권장)
  **본 것을 텍스트 스펙으로 변환**한다 — Codex는 브라우저를 보지 못한다.
  스크린샷은 `/tmp/codex-handoff/<slug>-before-*.png`로 저장(3단계에서 `-i`로 첨부).

## 2. PLAN — HANDOFF 작성

[templates/HANDOFF.md.tmpl](templates/HANDOFF.md.tmpl) 기반으로
`/tmp/codex-handoff/<slug>.md` 작성. 자기완결성 체크:

- [ ] 파일 경로는 프로젝트 루트 기준 정확한 경로
- [ ] 변경 지시는 구체 수치/토큰/코드 수준 — "전문가 느낌으로" 같은 추상어 금지
      (예: "h1을 `clamp(2.5rem,5vw,4rem)`/`-0.02em`으로, 본문 행간 1.7로")
- [ ] Out of scope(금지 사항) 명시 — 무관 리팩토링·의존성 추가·포맷팅-only 변경 차단
- [ ] Acceptance Criteria마다 확인 명령 포함
- [ ] 완료 보고 형식 지정(변경 파일 목록 + 기준별 증거)

작성 후 사용자에게 계획 요약(변경 파일·핵심 지시·검증 기준)을 보여주고 바로 3단계 진행.

## 3. DELEGATE — codex exec (항상 백그라운드)

```bash
mkdir -p /tmp/codex-handoff
codex exec -C "<프로젝트 루트>" \
  --sandbox workspace-write -c sandbox_workspace_write.network_access=true \
  [-m gpt-5.5] [-c model_reasoning_effort="xhigh"] \
  [-i /tmp/codex-handoff/<slug>-before-1.png] \
  -o /tmp/codex-handoff/<slug>.result.md \
  - < /tmp/codex-handoff/<slug>.md
```

- **반드시 Bash `run_in_background: true`로 실행** — xhigh 구현은 수 분~수십 분 걸린다.
  완료 알림이 오면 `.result.md`(Codex 최종 보고)부터 읽는다.
- 플래그 상세·트러블슈팅: [references/codex-cli.md](references/codex-cli.md)

## 4. VERIFY — Claude가 직접

1. `git diff --stat`으로 변경 범위가 HANDOFF Scope 안인지 확인(밖이면 즉시 FAIL 항목으로).
2. 핵심 변경 파일을 읽고 Acceptance Criteria를 **하나씩 실행 증거로** 확인
   — 빌드/테스트 실행, UI면 같은 URL 재스크린샷 후 before와 비교.
3. 프로젝트 루트에 `loop.md`가 있으면 loop-md 스킬 Verify 모드를 수행한다.
4. 미달 항목이 있으면 같은 세션에서 재작업(컨텍스트 유지):

   ```bash
   codex exec resume --last -C "<프로젝트 루트>" --sandbox workspace-write \
     -o /tmp/codex-handoff/<slug>.result-r2.md \
     "VERIFY 결과 미달 항목만 수정하라: <기준별 실패 증거와 교정 지시>"
   ```

   최대 3라운드. 그래도 미달이면 중단하고 남은 항목을 사용자에게 보고.

## 5. REPORT

최종 메시지에 포함: 변경 파일 목록, 기준별 충족/미충족(증거 요약), 사용 모델·effort·라운드 수,
HANDOFF/result 파일 경로. UI 작업이면 before/after 스크린샷 경로.
