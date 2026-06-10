# codex exec 레퍼런스 (plan-then-codex용)

검증 기준 버전: codex-cli 0.138.0. 의심스러우면 `codex exec --help`로 대조.

## 기본 호출 형태

```bash
codex exec [OPTIONS] [PROMPT]      # 프롬프트를 인자로
codex exec [OPTIONS] - < FILE      # 프롬프트를 stdin으로 (HANDOFF 전달은 항상 이 형태)
```

stdin 형태를 쓰는 이유: 셸 인용 문제가 없고, HANDOFF 파일이 그대로 감사 기록으로 남는다.

## 주요 플래그

| 플래그 | 용도 |
|---|---|
| `-C, --cd <DIR>` | 작업 루트 지정. **항상 프로젝트 루트를 명시**한다 |
| `-m, --model <MODEL>` | 모델 오버라이드 (`gpt-5.5`, `gpt-5.3-codex-spark` 등) |
| `-c model_reasoning_effort="<v>"` | effort 오버라이드. 값: `minimal` `low` `medium` `high` `xhigh` |
| `-s, --sandbox <MODE>` | `read-only` / `workspace-write` / `danger-full-access` |
| `-c sandbox_workspace_write.network_access=true` | workspace-write에서 네트워크 허용(localhost dev 서버 확인용) |
| `-o <FILE>` | 에이전트 **최종 메시지**를 파일로 저장. 검증 시 이 파일부터 읽는다 |
| `-i <FILE>...` | 이미지 첨부(반복 가능). before 스크린샷 전달용 |
| `--add-dir <DIR>` | 프로젝트 루트 외 쓰기 허용 디렉터리 추가 |
| `--skip-git-repo-check` | git 레포 밖에서 실행 허용 |
| `--json` | 이벤트를 JSONL로 stdout 출력(평소 불필요, 디버깅용) |

`-c`의 값은 TOML로 파싱된다(실패 시 문자열 리터럴). `model_reasoning_effort="xhigh"`처럼
쌍따옴표를 포함해 넘기는 게 안전하다.

## 모델/effort 기본값

`~/.codex/config.toml`의 `model` / `model_reasoning_effort`가 기본값이다.
사용자가 명시하지 않았으면 플래그를 생략해 기본값을 따른다.
사용자가 "gpt5.5 xhigh"처럼 명시했으면 기본값과 같더라도 플래그를 명시한다(의도 고정).

## 샌드박스 선택

- 기본 권장: `--sandbox workspace-write` — 쓰기를 `-C` 루트(+`--add-dir`)로 한정.
  사용자 config가 더 관대해도(예: `danger-full-access`) 플래그가 우선하므로 위임 범위가 좁아진다.
- workspace-write는 기본적으로 **네트워크 차단**. Codex가 dev 서버를 직접 확인해야 하면
  `-c sandbox_workspace_write.network_access=true`를 함께 준다.
- `codex exec`는 비대화형이라 승인 프롬프트가 없다. 샌드박스가 곧 안전장치다.

## 백그라운드 실행 패턴 (Claude Code 쪽)

xhigh 구현은 수 분~수십 분. 포그라운드로 돌리면 타임아웃(기본 2분)에 걸린다.

1. Bash 도구로 `run_in_background: true` + 위 명령 실행.
2. 완료 알림이 오면: ① `-o` 결과 파일 읽기 → ② 백그라운드 출력 파일에서 에러 유무 확인.
3. 중간 확인이 필요하면 백그라운드 출력 파일을 Read (stdout에 진행 로그가 흐른다).

## 세션 이어가기 (VERIFY 라운드)

```bash
codex exec resume --last [OPTIONS] "<교정 지시>"
```

- `--last`: 가장 최근 세션 재개. 세션 목록은 **cwd로 필터링**되므로 `-C`를 처음 실행과
  동일하게 지정해야 같은 세션이 잡힌다(`--all`은 필터 해제).
- resume 시에도 `--sandbox`, `-o` 등을 다시 명시한다(플래그는 세션에 저장되지 않는 것 전제).
- 새 HANDOFF로 갈아엎어야 할 만큼 방향이 틀렸으면 resume 대신 fresh `codex exec`.

## 트러블슈팅

| 증상 | 조치 |
|---|---|
| 인증 오류 | 사용자에게 `! codex login` 실행 요청 |
| "not inside a trusted directory" / git 체크 실패 | `--skip-git-repo-check` 추가, 또는 사용자 config의 `projects.<path>.trust_level` 확인 |
| 변경이 일부 디렉터리에 안 써짐 | 쓰기 경로가 `-C` 루트 밖 → `--add-dir` 추가 |
| Codex가 localhost 접근 실패 | `-c sandbox_workspace_write.network_access=true` 누락 여부 확인 |
| 결과 파일이 비어 있음 | 백그라운드 출력 파일에서 스택트레이스/에러 확인 후 fresh 재실행 |
| 프록시(headroom 등) 경유 오류 | `codex exec` 단독으로 재현 확인 → 사용자에게 프록시 상태 보고 |
