---
name: loop-md
description: Definition-of-Done 관리 루프 프레임워크. 작업 완료 전 loop.md 감독관 문서를 기준으로 3단계 검증(Pass/Fail 게이트·정량·정성)을 강제하고, 프로젝트 스택을 자동 감지해 loop.md 기본 세팅을 깔아준다. Use when 사용자가 "loop.md 세팅", "완료 기준/DoD 루프 만들기", "작업 완료 전 검증", "감독관 루프", "CI 감시·자가치유 루프"를 요청하거나, 작업을 "완료"로 선언하기 직전 검증이 필요할 때. (반복 실행 스케줄러 /loop 와는 다름.)
---

# loop-md — 완료 기준 관리 루프

AI가 눈앞의 Task에만 매몰되어 전체 맥락·완료 기준을 잃는 것을 막는 감독관(`loop.md`) 프레임워크.
호출 시 **Setup 모드**(세팅 생성)와 **Verify 모드**(완료 검증)로 자동 분기한다.

`SKILL_DIR` = 이 SKILL.md가 있는 디렉토리. 아래 경로는 그 기준이다.

## 분기 판단

1. 프로젝트 루트(또는 대상 폴더)에 `loop.md`가 **없으면 → Setup 모드**.
2. `loop.md`가 **있으면 → Verify 모드** (사용자가 명시적으로 "재세팅" 요청하면 Setup).

---

## Setup 모드 — 기본 세팅 생성

1. **세팅 범위 선택** — `AskUserQuestion`(multiSelect)으로 묻는다:
   - **코어** (항상 포함): `loop.md` + `report.md` 포맷 + R&R 가드레일
   - **참조 문서 스텁**: `docs/PRD.md`, `docs/USER-FLOW.md`, `docs/UI-SPEC.md`, `docs/DB-SCHEMA.md`
   - **감시 루프 가이드**: CI 폴링·자가치유·리뷰반영 실행 스니펫 (`reference/WATCH-LOOP.md` 동봉)
   - **Codex 어댑터**: 프로젝트 루트에 `AGENTS.md` 생성 → Codex CLI 등 다른 에이전트도 같은 `loop.md`로 검증 강제

2. **스택 자동 감지**:
   ```bash
   bash "$SKILL_DIR/scripts/detect-stack.sh" .
   ```
   stdout의 `KEY=VALUE`를 파싱한다(STACK/PKG_MANAGER/IS_MONOREPO/BUILD_CMD/TYPECHECK_CMD/TEST_CMD/LINT_CMD/COVERAGE_CMD).
   **stderr 경고를 무시하지 말 것** — monorepo 경고나 미감지 키 요약이 나오면 그대로 사용자에게 보고하고,
   `IS_MONOREPO=yes`면 워크스페이스별 명령 보완이 필요함을 알린다.

3. **커버리지 하한 확인**: `COVERAGE_FLOOR` 기본 70. 사용자가 다르게 원하면 반영.

4. **loop.md 생성** (치환 주체·방식 명시): `Read`로 `templates/loop.md.tmpl` 전체를 읽고,
   2번에서 파싱한 값으로 `{{...}}` 토큰을 **문자열 치환한 결과를 `Write`로** 프로젝트 루트 `loop.md`에 쓴다.
   (sed 파이프라인 대신 Read→치환→Write 를 쓴다 — 명령어 값의 공백/특수문자 안전.)
   - 치환 토큰: `{{STACK}} {{BUILD_CMD}} {{TYPECHECK_CMD}} {{TEST_CMD}} {{LINT_CMD}} {{COVERAGE_CMD}} {{COVERAGE_FLOOR}}`
   - 감지 실패한 키(`<...>`)는 그대로 남기고, 어떤 키가 비었는지 사용자에게 명시적으로 알린다.

5. **선택 항목 생성**:
   - 참조 스텁 선택 시 → `templates/*.stub.md`를 `docs/`로 복사(이미 있으면 건너뜀).
   - 감시 루프 선택 시 → `reference/WATCH-LOOP.md`를 프로젝트에 안내하고, 폴링은 `Monitor`/`/loop`로 가동 가능함을 알린다.
   - **Codex 어댑터 선택 시** → `templates/AGENTS.md.tmpl`을 프로젝트 루트 `AGENTS.md`로 복사한다(이미 있으면 덮어쓰지 말고 검증 규칙 섹션을 append). Codex CLI가 자동 로드해 동일한 `loop.md` 검증을 따른다.

6. **CLAUDE.md 주입 제안**: 프로젝트 `CLAUDE.md`에 다음 가이드 추가를 제안한다(사용자 승인 후):
   > "작업을 '완료'로 선언하기 전 반드시 `loop.md`를 읽고 loop-md 스킬의 Verify 모드로 정량/정성 리포트를 마크다운으로 출력할 것."

7. 생성 결과 요약(생성 파일, 미감지 플레이스홀더, 다음 액션)을 보고한다.

---

## Verify 모드 — 완료 검증 루프

작업을 "완료"로 선언하기 직전 실행한다. 자세한 기준은 [reference/DOD.md](reference/DOD.md).

0. **체크포인트 생성** — 검증 전 `loop.md` 5번의 체크포인트 명령(git stash/wip commit)을 실행해 안전망을 만든다.
1. **`loop.md` 읽기** + 0번 상호 참조 체크리스트 역추적. **N/A 규칙**: 대상 문서가 **존재하면 N/A 금지**(반드시 열어 대조), **없을 때만** 1회 경고 후 N/A.
2. **① Pass/Fail 게이트 실행** — `loop.md`의 명령을 **반드시 Bash로 실제 실행**한다(빌드→타입체크→린트→테스트→마이그레이션→시크릿 스캔).
   각 명령의 **exit code와 출력 꼬리를 리포트에 그대로 인용**한다. **실행 증거(로그) 없는 ✅ 는 무효 = FAIL.** "통과한 듯"은 금지.
   **하나라도 실패/증거누락 시 즉시 FAIL** → 체크포인트 롤백(5번) → 원인 분류 → 수정 → 1번부터 재검증. ②③ 진입 금지.
3. **② 정량 측정** — 커버리지(하한 대비)·번들 크기·에러율 등 수치 수집.
4. **③ 정성 자기평가** — 항목별 1~5점. **감점 항목은 근거(Reason)+액션(Action) 필수** (확증 편향 방지).
5. **R&R 체크** ([reference/RNR.md](reference/RNR.md)) — 변경이 인간 승인 영역(스키마/보안/결제/PRD범위/아키텍처)에 해당하면 자동 진행 중단·사용자 호출.
6. **리포트 출력** — `templates/report.md.tmpl` 포맷으로 마크다운 리포트 생성.
   ①②③ 모두 통과 + 리포트 완료 시에만 "완료" 선언. 실패 항목은 다음 루프 입력으로.

---

## 감시 루프 (선택) — 사람 병목 제거

CI/CD 폴링·자가치유·리뷰반영 실행 가이드는 [reference/WATCH-LOOP.md](reference/WATCH-LOOP.md).
`Monitor` 도구 또는 `/loop <간격>`으로 가동하며, 자가치유 자동 수정은 **R&R 자동 영역 + 허용 브랜치**(`ai/*` 등)에서만 수행한다.

## 핵심 원칙
- Pass/Fail 게이트에 **타협 없음**. 하나라도 실패하면 완료 아님.
- 정성 평가는 점수만으로 끝내지 않는다 — 감점엔 반드시 근거+액션.
- 인간 승인 영역은 절대 자동 커밋하지 않는다.
