# aside-repl 참조 — 브라우저 증거 수집 시 세션 유지 함정 (zcode·claude·codex 공통)

> 이 참조는 `plan-fusion` 등 브라우저 증거(스크린샷·DOM·PDF)를 소비하는 스킬에서 `aside`를 호출할 때
> **세션이 유지되지 않는 함정**과 **올바른 호출 경로**를 안내한다. 상세 API 사용법은 플랫폼 `aside-browser` 스킬이 담당한다 — 이 문서는 그 함정과 트리거만 담당한다(분업).

## 트리거 — 언제 이 참조를 보는가

- 브라우저 자동화·DOM 확인·스크린샷/PDF 증거 수집이 필요할 때
- `aside` / `aside repl` / `mcp__aside__repl` 키워드가 등장할 때
- 항상 활성화하지 않는다 — 완료 검증(DoD)과 무관한 조건부 도구다.

## 핵심: MCP 도구 경로 vs CLI 경로 — 세션 지속성이 다르다

| 경로 | 세션 수명 | 상태 유지 | 비고 |
|------|----------|-----------|------|
| **`mcp__aside__repl` MCP 도구** (stdio MCP 서버 경유) | MCP 서버 프로세스 수명 | ✅ `globalThis`·`const`/`let`·브라우저 탭/`page` 모두 호출 간 유지 | zcode 등 MCP 도구를 직접 호출하는 환경에서 우선 |
| **`aside repl "code"` CLI** (매번 별도 Bash 호출) | 프로세스 수명(1회성) | ❌ 매 호출 새 프로세스 → 세션 리셋 | `--session` 옵션 자체 없음 |
| **`aside repl` 단일 대화형 PTY 세션** | 세션 유지 중 | ✅ | CLI 경로에서 상태 보존이 필요하면 이쪽만 |
| **`aside exec --session <id>`** | 세션 ID 재사용 | ⚠️ 에이전트 세션 한정 | 비대화형에선 세션 ID가 노출 안 됨 → 재사용 사실상 불가 |

> **표준 권고**: "MCP 도구가 노출되면 `mcp__aside__repl` 우선, 아니면 단일 대화형 PTY `aside repl` 세션. 반복 `aside repl "code"`는 stateless다."
> 어느 쪽으로 표준화하지 말 것 — 환경(zcode·claude·codex)마다 MCP 노출 여부가 다르므로 조건문으로 표현.

## 다중 에이전트 호환성

| 에이전트 | `mcp__aside__repl` 가용성 | 비고 |
|----------|---------------------------|------|
| **zcode (GLM)** | ✅ 직접 호출 가능 | MCP 서버(`aside mcp`)가 stdio로 떠 있으면 노출 |
| **claude (Claude Code)** | ✅ MCP 설정(`.mcp.json`/플러그인)으로 가능 | 환경 설정에 따라 |
| **codex** | ✅ `codex mcp`/`mcp-server` 서브커맨드 존재 → MCP 지원 | "Codex는 MCP 못 쓴다"는 단정은 **틀림**(실측) |

> 환경별 MCP 노출 여부가 확정 전이면 "노출 시 MCP, 아니면 CLI 폴백" 조건문이 안전하다. 한쪽으로 고정하면 다른 에이전트가 함정에 빠진다.

## 핵심 함정 (Do / Don't)

### Do
- **값 반환은 `console.log()`로** — 표현식으로 끝내면 빈 결과가 돌아온다(aside-browser 스킬 명시).
- **상태 보존은 `globalThis.xxx`** 또는 **fresh 변수명**(`s1`, `s2`, …) — `mcp__aside__repl`은 top-level `const`/`let`이 호출 간 유지되지만, **같은 이름 재선언 시 `SyntaxError`**.
- **탭은 `closeTab()`로 정리** — `page.close()`/`page.context().newPage()`는 메모리 누수.
- **`process`/`require` 같은 Node 전역을 기대하지 마라** — REPL은 브라우저/워커 환경이라 Node 전역이 없다.
- **단일 대화형 PTY 세션**으로 CLI 상태 보존이 필요하면 `aside repl`(인자 없이)을 열어둔다.

### Don't
- **반복 `aside repl "code"` 호출을 stateful하게 전제하지 마라** — 매 호출이 새 프로세스, `--session` 옵션도 없다.
- **`aside exec --session`을 비대화형 재사용 수단으로 기대하지 마라** — 세션 ID가 노출 안 됨.
- **scratch JS 파일에 쿠키/시크릿을 남기지 마라** — 임시 파일에 민감 정보 누수 위험.
- **`aside` API 전체를 이 레포 문서에 복제하지 마라** — 플랫폼 `aside-browser` 스킬이 1차 소스. 이 문서는 함정·트리거만.

## 관찰 vs 상태 변경 경계 (R&R 연동)

`aside`로 로그인 세션을 이용한 **관찰**(스크린샷·DOM 읽기)은 자동 처리 가능하지만, **상태 변경 액션**(폼 제출·결제·설치 변경)은 `AGENTS.md` R&R의 "인증/인가/보안 로직" 인간 승인 영역에 걸린다. 관찰과 변경을 reference에서 명시적으로 구분할 것.

## 검증 근거 (실측)

이 가이드는 오케스트레이터 직접 진단 + plan-fusion Fusion-Research(5모델 교차검증)로 검증했다:
- `mcp__aside__repl` MCP 도구: `globalThis.__probe=42` → 다음 호출에서 `42` 유지(세션 리셋 아님).
- `aside repl "code"` CLI: `__x=99` 설정 → 다음 호출 `unset`(매 호출 새 프로세스).
- `const` 재선언: `SyntaxError: Identifier 'x' has already been declared`.
- codex MCP 지원: `codex --help`에 `mcp`·`mcp-server` 서브커맨드 존재.
