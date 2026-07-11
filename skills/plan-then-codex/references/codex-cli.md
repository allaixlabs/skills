# codex exec 레퍼런스 (plan-then-codex용)

검증 기준 버전: codex-cli 0.139.0 — 아래 resume 제약과 sandbox 상속은 **실측**으로 확인했다.
의심스러우면 `codex exec --help` / `codex exec resume --help`로 대조.

## 기본 호출 형태

```bash
codex exec [OPTIONS] [PROMPT]      # 프롬프트를 인자로
codex exec [OPTIONS] - < FILE      # 프롬프트를 stdin으로 (HANDOFF 전달은 항상 이 형태)
```

stdin 형태를 쓰는 이유: 셸 인용 문제가 없고, HANDOFF 파일이 그대로 감사 기록으로 남는다.

## 주요 플래그 (fresh `codex exec`)

| 플래그 | 용도 |
|---|---|
| `-C, --cd <DIR>` | 작업 루트 지정. **항상 프로젝트 루트를 명시**한다 |
| `-m, --model <MODEL>` | 모델 오버라이드 (`gpt-5.6-sol`) |
| `-c model_reasoning_effort="<v>"` | effort 오버라이드. 값: `minimal` `low` `medium` `high` `xhigh` |
| `-s, --sandbox <MODE>` | `read-only` / `workspace-write` / `danger-full-access` |
| `-c sandbox_workspace_write.network_access=true` | 사용자 승인 후에만 workspace-write 네트워크 차단 해제 시도 |
| `-o <FILE>` | 에이전트 **최종 메시지**를 파일로 저장 (성공 판정 근거로는 불충분 — 아래) |
| `-i <FILE>...` | 이미지 첨부(반복 가능). before 스크린샷 전달용 |
| `--add-dir <DIR>` | 프로젝트 루트 외 쓰기 허용 디렉터리 추가 |
| `--skip-git-repo-check` | git 레포 밖에서 실행 허용 |
| `--json` | 이벤트를 JSONL로 stdout 출력(평소 불필요, 디버깅용) |

`-c`의 값은 TOML로 파싱된다(실패 시 문자열 리터럴). `model_reasoning_effort="xhigh"`처럼
쌍따옴표 포함 전달이 안전하다.

실행 배너 형식: stdout에 `model: <id>`와 `reasoning effort: <effort>` 행이 출력된다.

## 산출물은 세트로 관리한다 (manifest)

`-o` 결과 파일은 "마지막 메시지"일 뿐이다 — exit code도, 실제 명령 로그도 아니며,
**Codex가 성공처럼 써도 실제 테스트는 실패했을 수 있다.** 라운드마다 네 가지를 한 세트로 남긴다:

```
$RUN/manifest        # project_root= / session_id= / roundN_exit= / roundN_prompt= / roundN_result= / roundN_log= / roundN_started_at= / roundN_finished_at=
$RUN/roundN.log      # stdout+stderr 전체 (배너·세션 ID·실행 로그)
$RUN/result-rN.md    # -o 최종 메시지
$RUN/roundN-prompt.md # resume 교정 지시
$RUN/handoff.md      # 전달한 지시서
```

`$RUN`은 고정 경로가 아니라 매 위임마다 격리 생성한다(slug 충돌·덮어쓰기·/tmp 청소 방지):

```bash
RUN=$(umask 077; mktemp -d "${TMPDIR:-/tmp}/ptc.<slug>.XXXXXX") || { echo "RUN 생성 실패"; exit 1; }
[ -d "$RUN" ] || { echo "RUN 생성 실패"; exit 1; }
```

세션 ID는 실행 배너에 stdout으로 찍힌다 — 캡처:

```bash
grep -m1 'session id:' "$RUN/round1.log" | awk '{print $NF}'
```

## 샌드박스 선택

- 기본 권장: `--sandbox workspace-write` — 쓰기를 `-C` 루트(+`--add-dir`)로 한정.
  사용자 config가 더 관대해도(예: `danger-full-access`) 플래그가 우선하므로 위임 범위가 좁아진다.
- 기본은 `--sandbox workspace-write` 단독 실행, 즉 네트워크 차단이다.
- 네트워크가 필요한 작업(패키지 설치, 외부 API, localhost 접근)은 PLAN 단계에서 이유와 대상(host/port/명령)을 사용자에게 보여주고 승인받은 뒤에만 `sandbox_workspace_write.network_access=true`를 추가한다.
- `-c sandbox_workspace_write.network_access=true`는 **샌드박스 정책의 차단을 푸는 것일 뿐, 접근 성공을 보장하지 않는다** (런타임/호스트 바인딩/인증 문제는 별개). Codex의 localhost 확인은 보조 신호로만 쓰고, **최종 검증은 Claude가 브라우저로** 한다.
- `codex exec`는 비대화형이라 승인 프롬프트가 없다. 샌드박스가 곧 안전장치다.

## 백그라운드 실행 패턴 (Claude Code 쪽)

xhigh 구현은 수 분~수십 분. 포그라운드로 돌리면 타임아웃(기본 2분)에 걸린다.

1. Bash 도구로 `run_in_background: true` + `> "$RUN/roundN.log" 2>&1` 실행.
2. **완료 알림이 온 뒤에만** 결과를 읽는다(완료 전 `-o` 파일 읽기는 race — 비어 있거나 직전 라운드 것). **완료 알림(`Background task completed` / `task-notification`)이 도착하면 즉시** read → 다음 절차(검증)로 넘어간다 — "기다리겠다"며 멈추거나 진행 없이 안내문만 내놓지 않는다(진행 상황 보고는 허용)("전 read 금지"는 알림 **후** 진행이 아니라 **전** race만 막는다).
3. 읽는 순서: manifest의 exit code → `result-rN.md` → 이상하면 `roundN.log`의 에러.

## 세션 이어가기 (VERIFY 라운드) — 0.139.0 실측 기준

```bash
cd "<프로젝트 루트>"            # manifest의 project_root와 `pwd -P` 일치 확인 후
codex exec resume "<session_id>" [-o FILE] [-c key=val] [-m MODEL] [-i IMG] "<교정 지시>"
```

- **`exec resume`에는 `-C`/`--sandbox`/`--add-dir`가 없다.** 넘기면 그대로 에러난다.
  - cwd: `-C`가 없으므로 **반드시 프로젝트 루트로 `cd`한 뒤** 실행한다(workdir 복원 여부는
    버전에 따라 불확실 — 호출 루트를 원 세션 루트와 일치시키면 어느 구현이든 안전).
  - sandbox: **원 세션의 설정이 상속된다**(실측: read-only 세션을 resume하면 read-only 유지).
    재명시 불필요. 바꿔야 하면 resume이 아니라 fresh `codex exec` 재위임.
- **`--last`를 쓰지 마라.** 동시에 여러 Claude/Codex 작업이 돌면 "마지막 세션"이 다른 repo나
  다른 작업의 세션일 수 있다. 항상 manifest의 명시 session id로 resume한다.
- 새 HANDOFF로 갈아엎어야 할 만큼 방향이 틀렸으면 resume 대신 fresh `codex exec`.

## 실패 분류: 구현 실패 vs ORCHESTRATION_FAIL

라운드 카운트(최대 3)는 **Codex가 정상 실행된 구현 시도**에만 적용한다.
다음은 `ORCHESTRATION_FAIL` — 라운드에 산입하지 않고 Claude가 호출 쪽을 고쳐 재시도한다:

- unsupported 플래그 등 CLI 사용 오류, 인증 만료, config/프록시 문제
- 샌드박스 차단(쓰기 경로·네트워크), 테스트 인프라 자체의 고장
- 세션 유실(`session_id` 미기록, 세션 파일 삭제) → fresh 재위임

## 트러블슈팅

| 증상 | 조치 |
|---|---|
| 인증 오류 | 사용자에게 `! codex login` 실행 요청 |
| "not inside a trusted directory" / git 체크 실패 | `--skip-git-repo-check` 추가, 또는 config의 `projects.<path>.trust_level` 확인 |
| 변경이 일부 디렉터리에 안 써짐 | 쓰기 경로가 `-C` 루트 밖 → fresh 재위임에 `--add-dir` 추가 |
| resume이 플래그 에러로 즉사 | `-C`/`--sandbox`를 넘겼는지 확인 — resume 미지원(ORCHESTRATION_FAIL, 라운드 미산입) |
| Codex가 localhost 접근 실패 | network_access 플래그 확인 → 그래도 실패면 HANDOFF에서 "서버 확인은 Claude가 수행"으로 조정 |
| 결과 파일이 비어 있음 | 완료 알림 전에 읽었는지(race) 확인 → `roundN.log`의 에러 확인 → fresh 재실행 |
| 구현이 끝났는데 파일 변경 0건 | codex가 응답 완료 전 세션 종료(provider 연결 끊김·headroom 프록시 타임아웃). round1.log 끝이 "Load applicable coding instructions" 등 도중 문구로 끝나면 이 케이스. **재시도**(fresh `codex exec`) 또는 provider 직접 연결로 전환. |
| result는 성공인데 검증 실패 | 정상 상황 — result는 주장일 뿐. VERIFY의 직접 실행 증거가 판정 기준 |
| 프록시(headroom 등) 경유 오류 | `codex exec` 단독 재현 확인 → 사용자에게 프록시 상태 보고 |
| `git` 명령 결과가 비정상(stash create가 "ok stash create" 반환, diff 본문 누락) | PATH의 `git`이 wrapper(`rtk git` 등). `type git` 확인 → wrapper면 `/usr/bin/git`를 쓰도록 환경 조정(스크립트는 stash create 출력을 40hex SHA로 검증해 노이즈를 정규화). |
