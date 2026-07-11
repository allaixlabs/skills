# codex exec 레퍼런스 (plan-fusion용)

검증 환경(실측): codex-cli 0.139.0 — resume 제약·sandbox 상속·`exec review` 서브커맨드를 이 버전에서 확인. 최소 요구는 0.139(`exec review` 신설).
의심스러우면 `codex exec --help` / `codex exec resume --help` / `codex exec review --help`로 대조.
이 스킬에서 codex는 패널의 한 백엔드(GPT 패밀리)이며, **교차리뷰의 1급 도구**다(`exec review`).

## 기본 호출 형태

```bash
codex exec [OPTIONS] [PROMPT]      # 프롬프트를 인자로
codex exec [OPTIONS] - < FILE      # 프롬프트를 stdin으로 (HANDOFF 전달은 항상 이 형태)
```

Fusion-Research/Fusion-Code에서 codex 패널은 자기 작업 디렉토리(`-C`)에서 실행한다 — Fusion-Code면 격리 worktree(`-C "$RUN/wt/codex"`), Fusion-Research/단일트리면 프로젝트 루트(`-C "$ROOT"`).

## 주요 플래그 (fresh `codex exec`)

| 플래그 | 용도 |
|---|---|
| `-C, --cd <DIR>` | 작업 루트. **항상 명시** (worktree 또는 프로젝트 루트) |
| `-m, --model <MODEL>` | 모델 (`gpt-5.6-sol`, `gpt-5.6-sol-fast`, `gpt-5.3-codex-spark` 등) |
| `-c model_reasoning_effort="<v>"` | effort: `minimal` `low` `medium` `high` `xhigh` |
| `-s, --sandbox <MODE>` | `read-only` / `workspace-write` / `danger-full-access` |
| `-c sandbox_workspace_write.network_access=true` | workspace-write의 네트워크 차단 해제 **시도**(아래 주의) |
| `-o <FILE>` | 에이전트 **최종 메시지**를 파일로 저장 (성공 판정 근거로는 불충분) |
| `-i <FILE>...` | 이미지 첨부(반복 가능). before 스크린샷 전달용 |
| `--add-dir <DIR>` | 루트 외 쓰기 허용 디렉터리 추가 |
| `--skip-git-repo-check` | git 레포 밖(비-git 사본) 실행 허용 |
| `-p, --profile <NAME>` | `$CODEX_HOME/<name>.config.toml` 레이어 |
| `--json` | 이벤트 JSONL stdout (디버깅용) |

`-c` 값은 TOML로 파싱된다(실패 시 문자열 리터럴). `model_reasoning_effort="xhigh"`처럼 쌍따옴표 포함이 안전하다.

## `codex exec review` — 교차리뷰의 핵심 (0.139.0 신설, 실측)

```bash
codex exec review [OPTIONS] [PROMPT | -]
```

현재 레포의 변경을 리뷰한다. 이 스킬에서 **다른 패밀리(GLM/Kimi)의 변경을 GPT가 독립 리뷰**하는 데 쓴다. 이 서브커맨드는 현재 cwd의 레포를 대상으로 하므로 대상 worktree에서 `( cd ... && codex exec review ... )`로 실행한다.

| 옵션 | 용도 |
|---|---|
| `--uncommitted` | 스테이징·언스테이징·추적되지 않은 변경 전부 리뷰 (Fusion-Code 구현 직후) |
| `--base <BRANCH>` | 주어진 base 브랜치 대비 변경 리뷰 (Fusion-Code: 패널 worktree를 baseline 대비) |
| `--commit <SHA>` | 특정 커밋이 도입한 변경 리뷰 |
| `-m <MODEL>` | 리뷰어 모델 |
| `--title <TITLE>` | 리뷰 요약에 표시할 커밋 제목 |
| `[PROMPT]` / `-` | 커스텀 리뷰 지시 (stdin은 `-`) |

예 — Fusion-Code에서 glm 패널 worktree의 변경을 GPT가 리뷰:
```bash
mkdir -p "$RUN/xreview"
( cd "$RUN/wt/glm" && codex exec review --base "$BASE" -m gpt-5.6-sol \
  "이 변경의 정확성/회귀/엣지케이스/범위일탈을 지적하라." ) \
  > "$RUN/xreview/codex-on-glm.md" 2>&1
```
> 자기 패밀리 자기리뷰(codex가 codex 변경 리뷰)는 확증편향 → **항상 다른 패밀리를 리뷰**시킨다.

## 비코드(read-only) 위임

분석/리서치 패널은 쓰기 금지. codex는 샌드박스로 강제:
```bash
codex exec -C "$ROOT" -s read-only -o "$RUN/codex/result.md" - < "$RUN/handoff.md"
```
`read-only`면 모델이 파일을 쓰려 해도 샌드박스가 차단 → Fusion-Research에서 안전.

## 산출물은 세트로 관리한다 (패널별 manifest)

`-o` 결과는 "마지막 메시지"일 뿐 — exit code도 실제 로그도 아니며, **codex가 성공처럼 써도 테스트는 실패했을 수 있다.** 패널마다 한 세트:

```
$RUN/<id>/manifest      # worktree= / branch= / round1_exit= / session=
$RUN/<id>/round1.log    # stdout+stderr 전체 (배너·세션 ID·실행 로그)
$RUN/<id>/result.md     # -o 최종 메시지
$RUN/handoff.md         # 전달한 지시서 (모든 패널 공유)
```

세션 ID는 실행 배너에 stdout으로 찍힌다:
```bash
grep -m1 'session id:' "$RUN/<id>/round1.log" | awk '{print $NF}'
```

## 샌드박스 선택

- 코드 작업 기본: `--sandbox workspace-write` — 쓰기를 `-C` 루트(+`--add-dir`)로 한정. Fusion-Code worktree와 결합하면 패널 격리가 이중으로 보장된다.
- workspace-write는 기본 네트워크 차단. `-c sandbox_workspace_write.network_access=true`는 **정책 차단을 풀 뿐 접근 성공을 보장하지 않는다**. 최종 검증(localhost 등)은 오케스트레이터가 직접.
- 비코드: `--sandbox read-only`.
- `codex exec`는 비대화형 — 승인 프롬프트 없음. 샌드박스가 곧 안전장치다.

## 백그라운드 실행 (오케스트레이터 쪽)

xhigh 구현은 수 분~수십 분. 포그라운드는 타임아웃(기본 2분).
1. Bash `run_in_background: true` + `> "$RUN/<id>/round1.log" 2>&1`.
2. **완료 알림을 수동으로 기다리지 말 것** — 하네스가 "You will be notified when it completes"를 반환해도, 그것을 **유일한 트리거로 삼아 턴을 종료하면 안 된다**(실제로 알림이 수 시간 누락된 사례가 있었다 — 그 동안 에이전트가 멈춰 사용자가 재촉해야 했다). 대신 **같은 응답 내에서 즉시 능동 폴링 루프**를 이어간다: 짧은 `sleep`(예: 15~60초) 후 `exit.txt`/manifest exit 필드/`round1.log` 크기 변화를 점검하는 것을 반복. 종료 신호(0/1 exit 확보)가 잡히면 즉시 다음 절차로 넘어간다 — "알림을 기다리겠다"며 멈추거나 진행 없이 안내문만 내놓지 않는다(부분 완료 진행 보고는 허용).
3. **완료 전 `-o`/`result.md` 읽기는 race**(완료 후에만 의미 있는 결과). 능동 폴링은 **진행 상태 카운트**(exit/manifest/로그 꼬리)만 확인하고, 결과 파일 read는 exit=0/1 확보 **후**에.
4. 읽는 순서: manifest exit → codex `result.md` → 이상하면 `round1.log` 에러.
5. **이 규칙은 글로벌 가드(`async-polling-guard`)가 강제한다** — loop-md Setup §6이 모든 에이전트(zcode/claude/codex) 글로벌 지침에 배포하며, 스킬 문서뿐 아니라 글로벌 가드가 최후의 방어선이다.

## 세션 이어가기 (VERIFY 라운드) — 0.139.0 실측

```bash
cd "<원 세션 루트>"   # manifest의 project_root/worktree와 일치 확인 후
codex exec resume "<session_id>" [-o FILE] [-c key=val] [-m MODEL] "<교정 지시>"
```
- **resume에는 `-C`/`--sandbox`/`--add-dir`가 없다.** 넘기면 에러 → `ORCHESTRATION_FAIL`(라운드 미산입). 반드시 원 세션 루트로 `cd` 후 실행.
- sandbox는 **원 세션 설정 상속**(read-only→read-only). 바꿔야 하면 fresh `codex exec` 재위임.
- **`--last` 금지** — 동시 다중 패널/세션에서 다른 작업 세션을 잡을 수 있다. 항상 manifest의 명시 session id.

## 실패 분류: 구현 실패 vs ORCHESTRATION_FAIL

라운드 카운트(최대 3)는 **정상 실행된 구현 시도**에만. 다음은 `ORCHESTRATION_FAIL`(라운드 미산입, 오케스트레이터가 호출 쪽 교정 후 재시도):
- unsupported 플래그·인증 만료·config/프록시 문제
- 샌드박스 차단(쓰기 경로·네트워크), 테스트 인프라 고장
- 세션 유실(session_id 미기록/삭제) → fresh 재위임

## 트러블슈팅

| 증상 | 조치 |
|---|---|
| 인증 오류 | 사용자에게 `! codex login` 요청 |
| "not inside a trusted directory" | `--skip-git-repo-check` 추가 (비-git worktree 사본) 또는 config `projects.<path>.trust_level` |
| resume이 플래그 에러로 즉사 | `-C`/`--sandbox`를 넘겼는지 확인 — resume 미지원(ORCHESTRATION_FAIL) |
| result는 성공인데 검증 실패 | 정상 — result는 주장일 뿐. 직접 실행 증거가 판정 기준 |
| review가 빈 결과 | 변경이 실제로 작업트리/base에 있는지(`git status`/`git diff --stat`) 확인 |
| 구현이 끝났는데 파일 변경 0건 | codex가 응답 완료 전 세션 종료(provider 연결 끊김·headroom 프록시 타임아웃). round1.log 끝이 "Load applicable coding instructions" 등 도중 문구로 끝나면 이 케이스. **재시도**(fresh `codex exec`) 또는 provider 직접 연결로 전환. |
| `git` 명령 결과가 비정상(council_wt_adopt가 "bad revision"/"No valid patches"로 ABORT) | PATH의 `git`이 wrapper(`rtk git` 등)여서 `stash create`/`diff` 출력을 가로챈 것. `type git` 확인 → wrapper면 `/usr/bin/git`를 쓰도록 환경 조정. **스크립트는 stash create 출력을 40hex SHA로 검증**해 노이즈를 빈 값으로 정규화한다. |
