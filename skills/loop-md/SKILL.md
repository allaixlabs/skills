---
name: loop-md
description: Definition-of-Done 관리 루프 프레임워크. 작업 완료 전 loop.md 감독관 문서를 기준으로 3단계 검증(Pass/Fail 게이트·정량·정성)을 강제하고, 프로젝트 스택을 자동 감지해 loop.md 기본 세팅을 깔아준다. Use when 사용자가 "loop.md 세팅", "완료 기준/DoD 루프 만들기", "작업 완료 전 검증", "감독관 루프", "CI 감시·자가치유 루프"를 요청하거나, 작업을 "완료"로 선언하기 직전 검증이 필요할 때. (반복 실행 스케줄러 /loop 와는 다름.)
---

# loop-md — 완료 기준 관리 루프

AI가 눈앞의 Task에만 매몰되어 전체 맥락·완료 기준을 잃는 것을 막는 감독관(`loop.md`) 프레임워크.
호출 시 **Setup 모드**(세팅 생성)와 **Verify 모드**(완료 검증)로 자동 분기한다.

`SKILL_DIR` = 이 SKILL.md가 있는 디렉토리. 아래 경로는 그 기준이다.

## ⚠️ 내장 `/loop` 스케줄러와의 관계 (이름이 같지만 충돌 주의)

loop-md가 만드는 루트 `loop.md`는 **완료 검증 기준문(DoD)**이다. 그런데 일부 에이전트 CLI(Claude Code, opencode/ZCode 포크 가능성)의 내장 `/loop`(반복 실행 스케줄러)은 **인자 없는 bare `/loop`** 실행 시 `<root>/.claude/loop.md` → `<root>/loop.md` 순으로 "loop-tasks 파일"을 찾아, 그 내용을 *"매 tick 실행할 task 목록"*으로 주입한다(feature-flag ON일 때 — 기본 OFF·게이트웨이 서버 제어·env override 불가라 현재는 잠재(latent)지만, 사용자 모르게 켜질 수 있다). 즉 같은 `loop.md` 파일을 두 기능이 **정반대 의미**(검증 기준문 vs 실행 task)로 본다 — "다름"이 아니라 "충돌 가능"이다.

- **구체 피해 경로(검증됨)**: bare `/loop`이 루트 `loop.md`를 task로 픽업하면, loop.md "5. 체크포인트 & 롤백 절차"의 `git stash push -u`·`git restore .`가 *매 tick 실행 지시*로 읽혀 **미저장 변경이 매 tick 폐기**될 수 있다(`--hard`만 자동실행 가드됨, stash/restore는 미가드).
- **올바른 사용법**: `/loop`로 검증을 반복하려면 **bare `/loop` 금지**, 항상 명시 프롬프트를 쓴다 — 예: `/loop 10m "loop.md 기준으로 Verify 모드 실행. ①②③ 통과면 루프 종료 선언."` (인자 있는 `/loop <프롬프트>`는 loop.md를 **읽지 않음** — CLI 동작 검증됨.)
- **표준 위치**: loop-md는 **루트 `loop.md`만** 생성한다. `<root>/.claude/loop.md`는 `/loop`이 *먼저* 탐색하는 **별개의 에이전트 설정 파일**(Self-Modification 권한 게이트 대상)이며, loop-md가 자동 생성하지 않는다. 사용자가 우연히 `.claude/loop.md`를 두면 루트 `loop.md`를 shadow하니 주의. (`/loop` 전용 task가 꼭 필요면 사용자가 거기에 따로 두는 보조 옵션은 가능 — 1차 해법은 위의 명시 프롬프트.)
- **에이전트별 `/loop` 존재 여부**: Claude Code는 `/loop` 내장(위 경로 동작 검증됨). **ZCode(opencode 포크)는 `/loop`가 있을 가능성이 있으나 확증 불가** — 사용자가 `/loop` 입력해보거나 `--help`로 확인. 확실하지 않으면 bare `/loop`를 쓰지 않는 보수적 정책 유지. `/loop`가 아예 없는 에이전트면 이 섹션 전체가 N/A.
- **하지 말 것**: 루트 `loop.md`를 `/loop` task 포맷으로 재설계하거나, loop-md Verify를 bare `/loop` 픽업에 의존시키지 않는다.

## 분기 판단

0. **오케스트레이터·자산 경로 감지** — 이 스킬을 호출한 에이전트와, 스킬 자산(templates/scripts/reference)의 루트 경로를 식별한다. 아래 Setup 6(글로벌 가드)·reference 절대경로·AGENTS.md 어댑터의 자산 경로가 이 값에 의존한다.
   - **감지 우선순위**(env > argv > 파일시스템 탐침):
     1. `PLAN_LOOP_MD_ORCHESTRATOR=claude|codex|zcode|opencode` env (헤드리스/cron 안전)
     2. 스킬 호출 argv(있으면)
     3. 파일시스템 탐침(아래 표) — 어느 에이전트 환이 설치됐는지
   - **자산 경로 탐색 순서**(감지된 에이전트 우선 → fallback): `~/.claude/skills/loop-md/` → `~/.zcode/skills/loop-md/` → `~/.agents/skills/loop-md/` → `~/.config/opencode/skills/loop-md/`. 이하에서 `$SKILL_DIR` = 실제 존재하는 첫 경로(SKILL.md가 이 위치에 있다면 곧 이 파일의 디렉토리). 존재하지 않는 경로를 reference 절대경로에 쓰지 않는다.

   | 에이전트 | 감지 신호(탐침) | 글로벌 지침 파일 | 가드 주입 방식 |
   |---|---|---|---|
   | **claude** | `~/.claude/` 존재 | `~/.claude/CLAUDE.md` | `<!-- loop-md:dod-guard -->` 블록 삽입/교체 |
   | **codex** | `~/.codex/` 존재 | `~/.codex/AGENTS.md` | 〃 |
   | **zcode** | `~/.zcode/` 또는 `~/.config/opencode/opencode.json` 존재 | `~/.config/opencode/loop-md-guard.md` + `opencode.json` `instructions` 배열에 경로 멤버십 | 파일 통째(idempotent) + JSON 배열에 경로 추가(중복 방지) |
   | **opencode**(비-ZCode) | `~/.config/opencode/opencode.json` 존재하고 `~/.zcode/` 부재 | 〃 (zcode와 동일 메커니즘) | 〃 |

   - `unknown`이면(어느 신호도 없으면) Setup 6은 건너뛰고 REPORT에 "글로벌 가드 대상 에이전트 미감지" 표기. 단 프로젝트 단위(`loop.md` 자체)는 정상 동작한다.
   - **여러 에이전트 동시 설치** 시(예: claude+codex+zcode 전부) — Setup 6은 감지된 전부에 가드를 제안(각 에이전트의 글로벌 파일에 마커 블록/파일 추가). 단 주입은 항상 사용자 확인 후 — 글로벌 설정 파일은 인간 승인 영역.

1. 프로젝트 루트(또는 대상 폴더)에 `loop.md`가 **없으면 → Setup 모드**.
2. `loop.md`가 **있으면 → Verify 모드** (사용자가 명시적으로 "재세팅" 요청하면 Setup).

---

## Setup 모드 — 기본 세팅 생성

1. **세팅 범위 선택** — `AskUserQuestion`(multiSelect)으로 묻는다:
   - **코어** (항상 포함): `loop.md` + `report.md` 포맷 + R&R 가드레일
   - **참조 문서 스텁**: `docs/PRD.md`, `docs/USER-FLOW.md`, `docs/UI-SPEC.md`, `docs/DB-SCHEMA.md`
   - **감시 루프 가이드**: CI 폴링·자가치유·리뷰반영 실행 스니펫 (`reference/WATCH-LOOP.md` 동봉)
   - **다중 에이전트 어댑터** (구 "Codex 어댑터"): 프로젝트 루트에 `AGENTS.md` 생성 → Codex CLI·ZCode(opencode)·기타 `AGENTS.md` 자동 로드 에이전트도 같은 `loop.md`로 검증 강제. Claude Code는 글로벌 가드(Setup 6)로 커버되므로 이 어댑터의 주 대상은 Claude가 **아닌** 에이전트.

2. **스택 자동 감지 (힌트일 뿐, Claude 분석이 우선)**:
   ```bash
   bash "$SKILL_DIR/scripts/detect-stack.sh" .
   ```
   ⚠️ **이 출력은 단정이 아니라 힌트다.** 스크립트는 프레임워크 관습(Rails `bin/` 래퍼, 다중 서비스, CI 설정)을 놓칠 수 있으므로 **항상 프로젝트를 직접 분석해 보완**한다.
   stdout 파싱: `DETECTED_STACKS`(감지된 스택 목록)·`PRIMARY_STACK`·`IS_MULTISERVICE`·`COVERAGE_FLOOR`·단일 `BUILD_CMD/TYPECHECK_CMD/TEST_CMD/LINT_CMD/COVERAGE_CMD`(주 스택 기준)·`<STACK>_*_CMD`(스택별 상세, 예 `RUBY_TEST_CMD`).
   - **`IS_MULTISERVICE=yes`면 단일 키만 믿지 말 것** — `RUBY_*`/`NODE_*`/`PYTHON_*`/`GO_*` 명령을 loop.md 게이트에 **각 행으로 모두 종합**한다.
   - stderr 경고(다중서비스·미감지)를 그대로 사용자에게 보고한다. 못 잡은 명령은 Gemfile/manifest/`bin/`/CI를 직접 읽어 채운다.

3. **커버리지 하한 확인**: detect 출력의 `COVERAGE_FLOOR`(기본 70)를 쓰되, 사용자가 다르게 원하면 반영. 커버리지 도구 미설정이면 loop.md 2번에 "임시 대체 지표(신규 로직당 테스트 존재 여부)"로 명시한다.

4. **loop.md 생성** (치환 주체·방식 명시): `Read`로 `templates/loop.md.tmpl` 전체를 읽고,
   2번에서 파싱한 값으로 `{{...}}` 토큰을 **문자열 치환한 결과를 `Write`로** 프로젝트 루트 `loop.md`에 쓴다.
   (sed 파이프라인 대신 Read→치환→Write 를 쓴다 — 명령어 값의 공백/특수문자 안전.)
   - 치환 토큰: `{{STACK}} {{BUILD_CMD}} {{TYPECHECK_CMD}} {{TEST_CMD}} {{LINT_CMD}} {{COVERAGE_CMD}} {{COVERAGE_FLOOR}}` (모두 detect 출력에서 옴).
   - **다중서비스면 1번 게이트 표를 스택별 행으로 확장**하고 각 `<STACK>_*_CMD`를 채운다.
   - 감지 실패한 키(`<...>`)는 직접 분석해 채우거나, 어떤 키가 비었는지 사용자에게 알린다.
   - **생성 직후 필수 검증**: `grep -n '{{' loop.md` 로 **미치환 토큰이 0인지 확인**한다. 남아 있으면 즉시 치환한다. (특히 `{{COVERAGE_FLOOR}}` 를 설명문 안에 리터럴로 남기지 말 것.)
   - 프로젝트 `.gitignore`에 `.loop/` 를 추가한다(hard 가드 검증 마커 저장용, 커밋 대상 아님).
   - **loop.md ≤25,000바이트 유지**: 내장 `/loop`이 loop.md를 픽업하면 **25000바이트로 절단**한다(초과 시 게이트 하단이 잘려 검증 무력화). 다중서비스 게이트 표 확장·상세 설명·로그·lessons는 본문에 인라인하지 말고 5번의 reference 참조 정책대로 `reference/`·`docs/loop-md/`로 분리한다(이미 채택한 분리 패턴의 연장).

5. **선택 항목 생성**:
   - 참조 스텁 선택 시 → **기존 `docs/`에 동일·유사 문서가 있으면 스텁을 만들지 말고** 그 문서를 loop.md 상호참조에 연결한다(빈 스텁으로 `docs/` 오염 금지). 없을 때만 `templates/*.stub.md`를 복사.
   - **⚠️ 스텁 채움 가드 (가짜 프로젝트 정체 주입 금지)**: 복사한 스텁은 **빈 뼈대 그대로** 둔다. PRD/USER-FLOW/UI-SPEC/DB-SCHEMA의 내용을 에이전트가 **추측·예시로 지어내 채우지 않는다.** 채울 경우엔 실제 코드·README·매니페스트에 **근거가 있을 때만** 그 출처를 밝히며 사용자 확인 하에 채운다. 프로젝트와 무관한 **가공의 정체(임의의 앱·서버·도메인·표적 등)를 만들어 넣는 것은 금지**다. 대상이 GUI/DB가 없는 레포면 해당 스텁은 만들지 말고 loop.md 0번에 **N/A로 명시**한다.
   - 감시 루프 선택 시 → `reference/WATCH-LOOP.md`를 안내하고, 폴링은 `Monitor`/`/loop`로 가동 가능함을 알린다.
   - **다중 에이전트 어댑터 선택 시** → `templates/AGENTS.md.tmpl`을 프로젝트 루트 `AGENTS.md`로 복사(이미 있으면 검증 규칙 섹션만 append). Codex CLI·ZCode·opencode 등 `AGENTS.md`를 자동 로드하는 에이전트가 동일한 `loop.md` 검증을 따른다. (Claude Code는 글로벌 가드로 별도 커버.)
   - **reference 참조 정책 (일원화)**: loop.md가 가리키는 `DOD.md`/`RNR.md`/`WATCH-LOOP.md`는 **감지된 `$SKILL_DIR` 기준 절대경로**(`<SKILL_DIR>/reference/<NAME>.md`, 예: `~/.zcode/skills/loop-md/reference/DOD.md`)로 표기한다(끊긴 참조·임의 rename 방지). `~/.claude/`에만 있다는 가정 금지 — Setup 0에서 감지한 실제 자산 경로를 쓴다. 프로젝트에 두길 원하면 `docs/loop-md/`에 **이름 그대로** 복사하고 그 경로로 가리킨다. (롤백 절차는 loop.md 5번에 이미 있으므로 별도 `ROLLBACK.md`를 새로 만들지 않는다.)

6. **완료 검증 가드 (글로벌 1회 — 감지된 모든 에이전트 대칭, 프로젝트 주입 금지)**: 프로젝트마다 주입하지 않는다(복붙·중복·누락 유발). 대신 Setup 0에서 감지된 각 에이전트의 글로벌 지침 파일에 가드가 있는지 확인하고, 없는 쪽만 1회 추가 제안한다(글로벌 파일은 인간 승인 영역 → 사용자 확인 후 주입):
   ```bash
   # 감지(Setup 0) — env 우선, 없으면 파일시스템 탐침. 어느 축이든 가드 있으면 "✓".
   grep -q "loop-md:dod-guard" ~/.claude/CLAUDE.md            2>/dev/null && echo "claude ✓"  || echo "claude 미감지 또는 가드 없음"
   grep -q "loop-md:dod-guard" ~/.codex/AGENTS.md             2>/dev/null && echo "codex ✓"   || echo "codex 미감지 또는 가드 없음"
   # ZCode/opencode(opencode 포크) — 마커는 별도 파일 + opencode.json instructions 배열로 로드
   [ -f ~/.config/opencode/loop-md-guard.md ]                  2>/dev/null && echo "opencode ✓" || echo "opencode(zcode 포함) 미감지 또는 가드 없음"
   ```
   - **감지 기준**(Setup 0 표와 동일): claude=`~/.claude/` 존재 · codex=`~/.codex/` 존재 · zcode/opencode=`~/.zcode/` 또는 `~/.config/opencode/opencode.json` 존재.
   - **에이전트별 주입 방식**:
     - **claude** → `~/.claude/CLAUDE.md`, **codex** → `~/.codex/AGENTS.md`: `<!-- loop-md:dod-guard -->` … `<!-- /loop-md:dod-guard -->` 마커 블록 삽입. 재실행 시 마커 블록을 통째로 교체(idempotent).
     - **zcode/opencode** → `~/.config/opencode/loop-md-guard.md` 파일을 통째로 만들고(안에 같은 조건부 규칙 + 마커), `~/.config/opencode/opencode.json`의 `instructions` 배열에 `"loop-md-guard.md"` 가 없으면 추가(jq 또는 수동 — 멤버십 체크로 중복 방지). ZCode/opencode는 `opencode.json`의 `instructions` 배열만 글로벌 지침으로 로드하므로 이 방식이 정확한 타겟(실측: ZCode `config.json`이 `opencode.ai/config.json` 스키마 사용).
   - 둘 다 같은 조건부 규칙: *"loop.md 있으면 완료 선언 전 반드시 ①②③ 리포트(실행 증거 포함) 출력, 없으면 N/A."*
   - **마커 컨벤션(표준)**: 주입은 항상 `<!-- loop-md:dod-guard -->` … `<!-- /loop-md:dod-guard -->` 블록으로 감싼다(zcode/opencode 별도 파일도 마커로 감싼다 — 향후 claude/codex와 통합 병합 시 식별 가능).
   - 조건부라 `loop.md` 없는 프로젝트엔 무해 → **1회 설정으로 감지된 전 에이전트의 전 프로젝트가 커버**된다.
   - hard 강제를 원하면 **옵트인** 세 가지를 안내: ① 에이전트 PreToolUse hook(Claude `~/.claude/settings.json`; ZCode/opencode는 hook 메커니즘이 다를 수 있어 해당 에이전트 문서 확인) — `git commit`시 `--no-verify`도 잡고 `[skip-loop]`·`LOOP_SKIP=1` 모두 지원. ② **에이전트 불문 강제**: `.git/hooks/pre-commit`에서 `precommit-guard.sh --git-hook` 호출 — Codex/ZCode/Claude/사람 누구든 셸 `git commit` 시 발동·차단. 커밋 메시지를 못 읽어 `[skip-loop]`는 불가하므로 `LOOP_SKIP=1`을 쓴다. ③ 셸 `git commit`에서도 `[skip-loop]`를 쓰려면 `.git/hooks/commit-msg`에서 `precommit-guard.sh --commit-msg "$1"` 호출. 단 `--no-verify`는 git hook을 건너뛰므로 ①과 병행 권장. (Stop hook은 매 턴 발동해 노이즈가 크므로 비권장.)
   - ⚠️ **옵트인 명시성(결함 방지)**: 위 세 가지 hard 가드는 **"안내"로 끝내고, 사용자가 명시적으로 "설치하라"고 승인하기 전에는 절대 설치하지 않는다.** Setup 흐름에서 가드를 조용히 설치하면(=안내만 하고 설치까지) 이후 매 커밋이 차단→`LOOP_SKIP=1` 우회 사이클에 빠진다(실제 makeskill에서 발생 — bypass.log 29회). 특히 **자기참조 모순** 주의: Setup이 `loop.md`+가드를 설치한 직후 셋업 산출물(loop.md/AGENTS.md/scripts)을 커밋하려면 마커가 필요한데, 마커는 Verify 통과 후에만 생기므로 셋업 커밋이 무조건 차단된다. 따라서:
     - Setup §6은 가드 **후보만 식별**(위 grep)하고 설치는 **사용자 승인 후 별도 단계**로. `AskUserQuestion`으로 "hard 가드(①/②/③) 설치할까?" 명시 확인 없이는 `.git/hooks/`·`settings.json` 수정 금지.
     - **셋업 산출물 커밋 면제**: 셋업 직후 첫 커밋(loop.md·AGENTS.md·scripts/·docs/loop-md/)은 가드가 면제한다 — `precommit-guard.sh`가 스테이징된 파일이 전부 `loop.md`·`AGENTS.md`·`skills/loop-md/`·`docs/loop-md/` 범위면(=순수 셋업 산출) 마커 없어도 통과. (상세: `scripts/precommit-guard.sh` line 271+ 면제 분기.)
   - 비대화형(headless) 환경에서는 사용자 승인을 받을 수 없으므로 **가드 설치를 건너뛰고** REPORT에 "hard 가드 미설치(비대화형 — 수동 설치 안내)"로 표기한다. 자동 설치 금지.

7. 생성 결과 요약(생성 파일, 미감지 플레이스홀더, 다음 액션)을 보고한다.

---

## Verify 모드 — 완료 검증 루프

plan-fusion 등 worktree 격리 워크플로우 안에서 작업하면, 패널 worktree에서 한 Verify는 메인 작업트리의 `.loop/last-verified`를 갱신하지 못한다. adopt 후 **메인 작업트리에서 Verify를 다시 실행**해야 마커가 현재 HEAD로 갱신된다.

작업을 "완료"로 선언하기 직전 실행한다. 자세한 기준은 [reference/DOD.md](reference/DOD.md).

0. **체크포인트 생성** — 검증 전 `loop.md` 5번의 체크포인트 명령(git stash/wip commit)을 실행해 안전망을 만든다.
1. **`loop.md` + lessons 읽기(consult)** — `docs/loop-md/lessons.md`가 있으면 먼저 읽고 과거 규칙을 적용한다(재유도 금지).
   (git 추적 경로인 이유: 워크트리 간 공유 + 히스토리. 구버전 `.loop/lessons.md`가 있으면 내용을 옮기고 삭제한다.)
   이어서 0번 상호 참조 체크리스트 역추적. **N/A 규칙**: 대상 문서가 **존재하면 N/A 금지**(반드시 열어 대조), **없을 때만** 1회 경고 후 N/A.
2. **① Pass/Fail 게이트 실행** — `loop.md`의 명령을 **반드시 Bash로 실제 실행**한다(빌드→타입체크→린트→테스트→마이그레이션→시크릿 스캔).
   각 명령의 **exit code와 출력 꼬리를 리포트에 그대로 인용**한다. **실행 증거(로그) 없는 ✅ 는 무효 = FAIL.** "통과한 듯"은 금지.
   **하나라도 실패/증거누락 시 즉시 FAIL** → 체크포인트 롤백(5번) → 원인 분류 → 수정 → 1번부터 재검증. ②③ 진입 금지.
   - **FAIL마다 증류 기록(distill)**: 원인을 검증한 뒤 `docs/loop-md/lessons.md`에 `[날짜] [게이트] 증상 → 검증된 원인 → 일반 규칙` 1줄을 남긴다. 추측("아마 X?")은 기록 금지 — 검증된 사실만.
     기록 즉시 **전용 커밋으로 분리**한다(작업 커밋에 섞지 않기): `git add docs/loop-md/lessons.md && git commit -m "chore(loop): lesson — <규칙 요약>"` — 가드는 `docs/loop-md/` 전용 커밋을 게이트 면제한다.
   - **동일 게이트 연속 3회 실패 시 루프 중단** — 남은 항목과 검증된 진단을 사용자에게 보고한다(무한 루프 탈출 조건).
3. **② 정량 측정** — 커버리지(하한 대비)·번들 크기·에러율 등 수치 수집.
4. **③ 정성 평가 — 독립 검증자 권장** — 자기 출력 자기비판은 확증 편향에 약하므로, 가능하면 **fresh-context 서브에이전트**에
   `loop.md + git diff + ①② 실행 로그`**만** 주고(작업 맥락·중간 대화 제공 금지) 항목별 1~5점 채점을 위임한다. 절차: [reference/DOD.md](reference/DOD.md).
   서브에이전트를 띄울 수 없는 환경에서만 자기평가로 대체하되, **감점 항목은 근거(Reason)+액션(Action) 필수**.
5. **R&R 체크** ([reference/RNR.md](reference/RNR.md)) — 변경이 인간 승인 영역(스키마/보안/결제/PRD범위/아키텍처)에 해당하면 자동 진행 중단·사용자 호출.
6. **리포트 출력 + 검증 마커** — `templates/report.md.tmpl` 포맷으로 리포트 생성.
   report 생성 시 `{{TASK_NAME}}`=작업명, `{{TIMESTAMP}}`=현재 시각, command/coverage 토큰=`loop.md`의 값으로 치환하고,
   생성 후 미치환 `{{...}}`가 없는지 확인한다.
   ①②③ 모두 통과 시에만 "완료" 선언하고, **hard 가드용 마커를 기록**한다(첫 줄 = 검증 시점 HEAD):
   ```bash
   mkdir -p .loop && { git rev-parse HEAD > .loop/last-verified 2>/dev/null || : > .loop/last-verified; }
   ```
   (옵트인 커밋 가드 `scripts/precommit-guard.sh`가 ①마커 존재 ②마커 HEAD=현재 HEAD ③부분 스테이징 없음 ④마커 이후 소스 무변경을 검사 — 즉 검증된 상태 그대로일 때만 커밋 허용. 우회는 `.loop/bypass.log`에 기록된다.)
   리포트에 **검증 주체(독립 서브에이전트/자기평가)와 라운드 수**를 기록한다. 실패 항목은 다음 루프 입력으로.

---

## 감시 루프 (선택) — 사람 병목 제거

CI/CD 폴링·자가치유·리뷰반영 실행 가이드는 [reference/WATCH-LOOP.md](reference/WATCH-LOOP.md).
`Monitor` 도구 또는 `/loop <간격>`으로 가동하며, 자가치유 자동 수정은 **R&R 자동 영역 + 허용 브랜치**(`ai/*` 등)에서만 수행한다.

## 핵심 원칙
- Pass/Fail 게이트에 **타협 없음**. 하나라도 실패하면 완료 아님.
- 정성 평가는 점수만으로 끝내지 않는다 — 감점엔 반드시 근거+액션. 가능하면 **독립 컨텍스트가 채점**한다.
- 실패는 소비하지 말고 증류한다 — `docs/loop-md/lessons.md`에 규칙으로 남기고, 다음 루프는 그것을 먼저 읽는다.
- 인간 승인 영역은 절대 자동 커밋하지 않는다.
