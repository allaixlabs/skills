# CLI Fusion Map — 5-백엔드 실행 매트릭스 (plan-fusion용)

각 모델 패밀리를 자기 CLI로 독립 실행하는 방법의 단일 참조. codex/opencode 상세는 `codex-cli.md`·`opencode-cli.md`에,
**신규 백엔드 agy(Gemini)·claude(Opus)** 상세는 이 문서에 둔다. 호명→정규화는 `routing-fusion.md`.

검증 환경(실측): codex 0.139.0 · opencode 1.16.2 · omo 4.10.0 · **agy 1.0.8** · **claude 2.1.x**.

## 통합 매트릭스

| | 패밀리 | 헤드리스 호출 | 작업디렉토리 | 모델 지정 | effort | 출력 캡처 | resume | 강제 read-only |
|-|-|-|-|-|-|-|-|-|
| **codex** | GPT | `codex exec - < FILE` | `-C <dir>` | `-m gpt-5.5` | `-c model_reasoning_effort="xhigh"` | `-o FILE` | `exec resume <id>` | `-s read-only` ✅ |
| **agy** | Gemini | `agy --print "<msg>"` | **`cd <dir>`** | `--model "Gemini 3.1 Pro (High)"` | 모델 문자열 내장 | **stdout 리다이렉트** | `--conversation <id>` | ❌(아래) |
| **claude** | Opus | `claude --print "<msg>"` | **`cd <dir>`** (+`--add-dir`) | `--model opus` | (alias) | **stdout**/`--output-format` | `--continue`/`-r <id>` | ⚠️(아래) |
| **omo** | GLM/Kimi/… | `omo run "<msg>"` | `-d <dir>` | `-m zai-coding-plan/glm-5.2` | (없음) | stdout | `--session-id <id>` | ❌(지시+검증) |
| **opencode** | GLM/Kimi/… | `opencode run "<msg>"` | `--dir <dir>` | `-m opencode-go/kimi-k2.7-code` | `--variant high` | stdout | `-s <id>` | ❌(지시+검증) |

**역할 기본값**: 참가자 = 가용한 서로 다른 패밀리. **Judge = claude(Opus)**. **Synthesizer = codex(GPT)**.

---

## 신규 백엔드 ① agy (Antigravity CLI — Gemini)

```bash
# 함수 래퍼(.zshrc) 회피 위해 'command agy' + PATH에 /opt/homebrew/bin
export PATH="/opt/homebrew/bin:$PATH"

# 참가자 — 코드(쓰기): worktree에서 cd 후 실행, 쓰기 권한 자동승인
( cd "$RUN/wt/gemini" && command agy \
    --print-timeout 900s \
    --dangerously-skip-permissions \
    --model "Gemini 3.1 Pro (High)" \
    --print "$(cat "$RUN/handoff.md")" ) > "$RUN/gemini/round1.log" 2>&1
echo "round1_exit=$?" >> "$RUN/gemini/manifest"

# 참가자 — 리서치(읽기): 읽기전용 사본 + skip-permissions (아래 ⚠️ 교착주의 참조)
RO="$RUN/ro/gemini"; mkdir -p "$RUN/ro"; cp -a "$ROOT" "$RO"   # 대용량이면 rsync --exclude node_modules
( cd "$RO" && command agy --print-timeout 600s --dangerously-skip-permissions \
    --model "Gemini 3.1 Pro (High)" \
    --print "$(cat "$RUN/handoff.md")" ) > "$RUN/gemini/round1.log" 2>&1
# 사본이라 쓰기가 떨어져도 원본 무해. 분석 종료 후: rm -rf "$RO"
```

### 주요 플래그 (실측 `agy --help`)

| 플래그 | 용도 |
|---|---|
| `--print` / `-p` / `--prompt` | **비인터랙티브** 단일 프롬프트 실행·응답 출력 (= codex `exec`, claude `--print`) |
| `--model <문자열>` | 모델. `agy models` 출력 문자열 그대로 (`"Gemini 3.1 Pro (High)"`, `"Gemini 3.5 Flash (Low)"`) |
| `--print-timeout <dur>` | print 모드 대기 타임아웃 (기본 `5m0s`). **omo와 달리 자체 타임아웃 존재** → 장시간 작업도 자가 차단 |
| `--dangerously-skip-permissions` | 도구 권한 자동승인. **헤드리스 쓰기 작업에 필수**(미지정 시 권한 프롬프트로 멈춤) |
| `--sandbox` | "터미널 제약" 샌드박스 — **파일시스템 read-only를 보장하지 않음**(아래 주의) |
| `--add-dir <dir>` | 워크스페이스에 디렉토리 추가(반복 가능). 주 작업디렉토리는 cwd |
| `--continue` / `-c` | 최근 대화 이어가기 — **병렬 패널에선 금지**(다른 패널 대화 오선택) |
| `--conversation <id>` | 특정 대화 ID resume |
| `--log-file <path>` | CLI 로그 파일 경로 |
| `models` (서브커맨드) | 사용 가능 모델 목록 |

### 실측 확인 사항 (이 세션 스모크)
- `--print` 채팅 응답 OK (exit 0).
- `--print --dangerously-skip-permissions`로 **cwd에 파일 생성 성공** → **Fusion-Code 참가자로 사용 가능**(Research 한정 아님).
- `cd <dir>` 후 실행 시 그 디렉토리에 쓴다 → worktree 격리와 결합.

### 주의
- **`-C`/`-o` 없음** → 항상 `( cd <dir> && ... ) > round1.log 2>&1`. codex처럼 `-o result.md` 못 만드니 round1.log가 곧 result.
- **⚠️ 권한 프롬프트 교착**: agy는 에이전트 CLI라 프롬프트가 도구 사용(파일읽기·명령)을 유발하면 헤드리스에서 **권한 프롬프트로 멈출 수 있고 `--print-timeout`이 이를 못 끊는다**(실측: 도구 무유발 프롬프트나 `--dangerously-skip-permissions`면 정상 종료). 그래서 **쓰기(Code)든 읽기(Research)든 `--dangerously-skip-permissions`를 붙이되, Research는 읽기전용 `cp -a` 사본에서 실행**해 쓰기가 떨어져도 원본을 보호한다(위 예시).
- **⚠️ 최상위 백그라운드로 호출**: agy는 **각 참가자를 자기 `run_in_background` Bash 호출로 직접** 띄운다(실측: 백그라운드 래퍼 스크립트 안에 `( cd && agy )`를 다시 중첩하면 종료가 안 잡혀 무한대기). 부모 스크립트 중첩 금지. wall-clock 상한 초과 시 `무응답`/`ORCHESTRATION_FAIL`.
- **`--sandbox`는 파일 RO 보장 X** — codex의 `-s read-only` 같은 강제 차단이 아니다(터미널 제약일 뿐). RO가 필요하면 위 `cp -a` 사본 격리.
- **resume id 추출 미확정**: round1.log에서 conversation id를 못 찾으면 `--conversation` 대신 **fresh 재위임**.
- **세션 저장소 경합**: `--continue`(최근) 금지. resume은 명시 `--conversation <id>`만.

---

## 신규 백엔드 ② claude (Claude Code — Opus, 기본 Judge)

```bash
# claude로 판정(읽기). 프롬프트 = 템플릿 + judge-input.
JUDGE_PROMPT="$(cat "$SKILL_DIR/templates/fusion-judge.md.tmpl")
$(cat "$RUN/judge-input.md")"
( cd "$ROOT" && claude --print --model opus "$JUDGE_PROMPT" ) > "$RUN/judge.md" 2>"$RUN/judge.err"
echo "judge_exit=$?" >> "$RUN/manifest"
# 주의: judge-input이 클 때(대형 diff 다수)는 argv 길이 한도(E2BIG) 위험 → Judge를 codex(`- < FILE` stdin)로 돌리거나 입력을 축약.

# 참가자 — 코드(쓰기, highEnd/codeSecurity 프리셋에서만): worktree에서
( cd "$RUN/wt/opus" && claude --print --model opus \
    --dangerously-skip-permissions \
    "$(cat "$RUN/handoff.md")" ) > "$RUN/opus/round1.log" 2>&1
echo "round1_exit=$?" >> "$RUN/opus/manifest"
```

### 주요 플래그 (실측 `claude --help`)

| 플래그 | 용도 |
|---|---|
| `--print` / `-p` | **비인터랙티브** 출력 |
| `--model <model>` | `opus`(alias) 또는 `claude-opus-4-8`(풀네임) |
| `--add-dir <dirs...>` | 도구 접근 허용 디렉토리 추가 (주 작업디렉토리는 cwd) |
| `--output-format <fmt>` | `--print` 전용 출력 형식(text/json/stream-json) |
| `--json-schema <schema>` | 구조화 출력(`--print` 전용) — Judge 판정을 구조화하고 싶을 때 |
| `--dangerously-skip-permissions` | 모든 권한 우회 (쓰기 참가자에 필요) |
| `--continue` / `-r <id>` | 세션 이어가기 / 특정 세션 resume(`--print`) |
| `--fallback-model <model>` | 기본 모델 실패 시 폴백 |

### ⚠️ 동족 주의 (가장 중요)
오케스트레이터(이 Claude)가 **Opus**다. claude 백엔드를 쓰면 외부 Opus 프로세스를 부르는 것이지만 **모델 패밀리는 동일**하다.
- **기본**: claude = **Judge 전용**(읽기 판정). 참가자로는 기본 제외(독립성 보존).
- **Opus가 참가자인 프리셋**(highEnd/codeSecurity): Judge가 Opus면 자기 후보 자기심사 → 확증편향. **Judge를 Gemini로 바꾸거나** `synthesis.md`에 "Judge 비독립" 명시.
- Synthesizer는 GPT(codex)로 두어 Judge와 다른 패밀리가 합성.

### Judge/Synth 폴백 (불가양도 안전망)
- **Judge CLI 실패** → Claude 오케스트레이터가 직접 판정(부모 plan-codex-opencode 방식) + REPORT에 "Judge=self" 표기.
- **Synth CLI 실패** → 차순위 참가자 CLI 또는 Claude가 합성 + 표기.
- 코드의 **최종 구현은 항상 백엔드**(역할경계). Synth가 코드일 땐 "합성 HANDOFF"를 만들고 실제 작성은 백엔드가.

---

## codex / opencode (재사용 — 요약)

- **codex(GPT)**: `codex exec -C <dir> -m gpt-5.5 -c model_reasoning_effort="xhigh" -o result.md - < handoff.md`. 비코드는 `-s read-only`. **교차리뷰 1급 도구 `codex exec review --base <BASE>`**. 상세 `codex-cli.md`.
- **opencode(GLM/Kimi)**: 구현 `omo run --agent Sisyphus -m <prov/model> -d <dir> --json`, 리뷰/단발 `opencode run -m <prov/model> --variant high --format json --dir <dir>`. 상세 `opencode-cli.md`.

## 산출물 세트 (참가자별 manifest — 모든 백엔드 공통)

```
$RUN/<id>/manifest      # worktree= / branch= / round1_exit= / session(or conversation)=
$RUN/<id>/round1.log    # stdout+stderr 전체 (agy/claude/omo/opencode는 이게 result)
$RUN/<id>/result.md     # codex 패널만 (-o)
$RUN/handoff.md         # 모든 참가자 공유 단일 스펙
$RUN/judge-input.md     # handoff + 참가자별 라벨 답변 (Judge 입력)
$RUN/judge.md           # Judge CLI 판정
$RUN/final.md           # Synthesizer CLI 최종(Research) / 합성 HANDOFF(Code)
```

읽는 순서: 모든 참가자 완료 알림 → manifest exit → codex는 `result.md`, 그 외는 `round1.log`.
