# 라우팅 레퍼런스 — 호명 → 백엔드 (plan-fusion 전용)

사용자가 자연어로 부르는 모델명을 `(backend, model, effort/variant, dir/session 플래그)`로 정규화하는 단일 진실 소스.
plan-codex-opencode/routing.md 를 확장해 **agy(Gemini) · claude(Opus)** 두 백엔드와 **CLI Fusion 프리셋**을 추가했다.
검증 환경(실측): codex-cli 0.139.0 · opencode 1.16.2 · omo 4.10.0 · **agy 1.0.8** · **claude 2.1.x** — 각 `--help` / `models` / 스모크로 확인.

## 대원칙

| 호명 모델 | 백엔드 | 이유 |
|---|---|---|
| **codex / gpt 계열** | `codex exec` | GPT 1급 시민(결정론 샌드박스, `exec review` 코드리뷰). 기본 **Synthesizer**. |
| **gemini 계열** | `agy --print` | Antigravity CLI가 Gemini 전용 실행기. **새 패밀리(Google)** — 교차검증 다양성↑. |
| **opus / claude 계열** | `claude --print` | Anthropic 직접. 기본 **Judge**. ⚠️ 오케스트레이터와 동족(아래 경고). |
| **그 외 모든 provider** (glm·kimi·deepseek·qwen·minimax·opus-via-dgrid 등) | **opencode 계열** (`omo run`/`opencode run`) | 멀티 프로바이더는 opencode 생태계 담당. |

핵심: codex(GPT)·agy(Gemini)·opencode(GLM/Kimi)는 **서로 다른 모델 패밀리** → 같은 문제에서 다른 실수 → 교차검증 독립성. 참가자는 가능한 한 **서로 다른 패밀리**로 구성한다.

## 호명 → 정규화 테이블

| 사용자 자연어 | backend | model | effort/variant | dir 플래그 | resume |
|---|---|---|---|---|---|
| codex / gpt5.5 / "gpt5.5 xhigh" | `codex exec` | `gpt-5.5` | `-c model_reasoning_effort="xhigh"` | `-C` | `exec resume <id>` |
| gpt5.5 fast / pro | `codex exec` | `gpt-5.5-fast` / `gpt-5.5-pro` | `-c model_reasoning_effort="<v>"` | `-C` | 〃 |
| **gemini / "gemini 3.1 pro" / "gemini pro"** | `agy --print` | `"Gemini 3.1 Pro (High)"` | **모델 문자열에 내장**(High/Low) | **`cd`** (`-C` 없음) | `--conversation <id>` |
| **gemini flash / "gemini 3.5 flash"** | `agy --print` | `"Gemini 3.5 Flash (Medium)"` | 〃 (Low/Medium/High) | **`cd`** | `--conversation <id>` |
| **opus / "opus 4.8" / claude** | `claude --print` | `opus` (alias) 또는 `claude-opus-4-8` | (모델 alias) | **`cd`** (`--add-dir` 보조) | `--continue`(최근) / `--resume <id>`(`-r`) |
| glm5.2 / "glm 5.2" | opencode | `zai-coding-plan/glm-5.2` | `--variant high` | `-d`(omo)/`--dir`(opencode) | `--session-id`/`-s` |
| glm5.1 / glm4.7 | opencode | `zai-coding-plan/glm-5.1` / `glm-4.7` | `--variant high` | `-d`/`--dir` | 〃 |
| kimi k2.7 / kimi | opencode | `opencode-go/kimi-k2.7-code` | `--variant high` | `-d`/`--dir` | 〃 |
| kimi k2.6 | opencode | `opencode-go/kimi-k2.6` | `--variant high` | `-d`/`--dir` | 〃 |
| deepseek / pro / flash | opencode | `opencode-go/deepseek-v4-pro` / `-flash` | `--variant high` | `-d`/`--dir` | 〃 |
| qwen / minimax / mimo … | opencode | `opencode-go/<model>` | `--variant high` | `-d`/`--dir` | 〃 |

> ⚠️ **Gemini 모델명은 실측 문자열 그대로** 쓴다(`agy models` 출력). 스펙에서 본 `gemini-3.5-pro`는 **존재하지 않음** — 실재는 **Gemini 3.1 Pro**(High/Low) + **Gemini 3.5 Flash**(Low/Medium/High). effort는 별도 플래그가 아니라 모델 문자열의 `(High/Medium/Low)`로 지정한다.
> ⚠️ **Opus 4.8은 `claude` 직접 호출**로만 얻는다. agy의 Claude 모델은 4.6, opencode의 `dgrid/claude-opus-4-8`도 경로가 다르다 → Opus 호명은 `claude --print --model opus`.

## effort / variant 매핑

- **codex**: `xhigh|high|medium|low|minimal` → `-c model_reasoning_effort="<v>"` (TOML — 쌍따옴표 필수).
- **agy**: effort가 **모델 문자열에 내장** — `"Gemini 3.1 Pro (High)"` vs `"(Low)"`. 별도 effort 플래그 없음.
- **claude**: 모델 alias(`opus`)로 선택. reasoning effort 별도 노출 없음(모델 기본).
- **opencode**: `--variant <high|max|minimal>`. **omo run엔 `--variant` 없음** → 고추론 필요 시 opencode 직접 경로.

## agy / claude 호출 특이사항 (Fusion 병렬에서 엉키지 않도록)

- **agy**: `-C`/`-o` 없음 → 작업디렉토리는 **`( cd "$RUN/wt/<id>" && command agy ... )`**, 출력은 **stdout 리다이렉트**(`> round1.log`). 함수 래퍼 회피 위해 **`command agy`**. **쓰기(코드)엔 `--dangerously-skip-permissions` 필수**(헤드리스 권한 프롬프트 차단 회피 — 실측 검증). 자체 `--print-timeout`(기본 5m)이 행을 차단.
- **claude**: `-C` 없음 → **`( cd "$RUN/wt/<id>" && claude --print ... )`** + `--add-dir` 보조. 쓰기 작업이면 `--dangerously-skip-permissions`. 기본은 **Judge(읽기·판정)** 라 쓰기 불필요.
- 둘 다 resume id 추출 경로가 codex/opencode만큼 확정적이지 않다 → **추출 실패 시 fresh 재위임**(부모 패턴).

## 모호 호명 처리 (순서대로)

1. provider 토큰 명시("zai", "openai", "google/gemini", "anthropic/opus") → 그대로.
2. 패밀리만("glm", "kimi", "gemini", "opus") → 최신 안정 기본(glm→glm-5.2, kimi→kimi-k2.7-code, gemini→Gemini 3.1 Pro (High), opus→claude opus).
3. 백엔드만("opencode"/"agy") → 백엔드 확정, 모델은 기본 패널 로직 + **1줄 확인**.
4. 완전 모호("아무 모델로 fusion") → 기본 패널 추천.

## 패널 프리셋 (스펙→실측 교정)

> 형식: 참가자 목록 | **Judge** | **Synth**. 모델명은 실측.

| 프리셋 | 참가자(패밀리) | Judge | Synth | 용도 |
|---|---|---|---|---|
| **default**(호명 없을 때) | codex `gpt-5.5` · agy `"Gemini 3.1 Pro (High)"` · opencode `glm-5.2` · opencode `kimi-k2.7-code` | claude(Opus) | codex(GPT) | 일반 — 4개 모델(백엔드 3: codex·agy·opencode)로 다양성 확보 |
| **highEnd** | gpt-5.5 · **Opus 4.8(claude)** · Gemini 3.1 Pro · glm-5.2 | Opus ⚠️비독립 | GPT | 고성능(Opus 참가) |
| **codeSecurity**(스펙 추천) | highEnd + `kimi-k2.7-code` | Opus ⚠️비독립 | GPT | 취약점·보안·코드리뷰·PoC |
| **fullPower** | codeSecurity + agy `"Gemini 3.5 Flash (High)"` | Opus ⚠️비독립 | GPT | 최종보고서·중대판단(느림) |
| **budget** | agy `"Gemini 3.5 Flash (Low)"` · glm-5.2 · kimi-k2.7-code | Opus | Opus ⚠️(동족 — 비용절감 예외, synthesis.md에 비독립 표기) | 비용절감 |

- `⚠️비독립` 표기는 아래 동족 편향 경고의 명시 예외다. highEnd/codeSecurity/**fullPower**는 Opus 참가자와 Judge가 같은 계열이므로 Judge 독립성이 할인된다(synthesis.md에 명시).
- budget은 비용 절감을 위해 Judge=Synth=Opus를 허용한다. 이 경우 `synthesis.md`에 "비독립 할인" 명시 필수.
- 추천 시 한 줄 이유 제시: 예) "GPT·Gemini·GLM·Kimi 4개 모델(백엔드 3)로 교차검증 독립성을 확보하고, Opus가 판정·GPT가 합성합니다."
- 참가자 백엔드 수는 `check-fusion.sh`의 `PARTICIPANT_FAMILIES`로 확인. 가용 백엔드에 맞춰 프리셋을 축소한다(예: agy 미설치 → Gemini 빼고 백엔드 2(codex·opencode)).

## disabledModels 가드 (사용자 정책)

- **`fable-5` · `mythos-5` 는 참가자·Judge·Synth 어디에도 라우팅 금지.** 사용자가 명시적으로 배제한 "No Fable" 정책. 호명되거나 폴백 후보로 떠올라도 선택하지 않는다.

## ⚠️ 동족 편향 경고 (Opus의 이중 역할)

오케스트레이터(이 Claude)가 **Opus**다. 그래서:
- **Opus를 참가자로도 쓰면** → 참가자·Judge·오케스트레이터가 모두 같은 패밀리 → 교차검증 독립성이 떨어지고, Judge가 자기(동족) 후보를 심사하는 **확증편향**이 생긴다.
- 기본 권장: **Opus는 Judge 전용**(default 프리셋). highEnd/codeSecurity처럼 Opus가 참가자인 프리셋에서는 ① Judge를 다른 패밀리(예: Gemini)로 바꾸거나 ② 그대로 둘 거면 `synthesis.md`에 "**Judge 비독립(동족) — 판정 신뢰도 할인**"을 명시한다.
- Synthesizer는 기본 GPT(codex)로 두어 Judge(Opus)와 다른 패밀리가 합성을 맡게 한다.
- **Synth 동족 주의(약):** default 패널은 참가자에 GPT가 있고 Synth도 GPT다 → Synth가 자기(동족) 후보를 과대대표할 여지가 있다(Judge 자기심사와 동형, 단 약함). Synth 템플릿이 "Judge 판정·근거 강도로만 선별"하도록 제약해 실효 위험은 제한적이지만, Synth가 참가자와 동족이면 `synthesis.md`에 약하게 표기하거나 Synth를 비참가 패밀리로 두는 편이 깔끔하다.

## 백엔드 선택: omo vs opencode 직접 (모델 동일, 실행기만 다름)

| 경로 | 명령 골격 | 권장 용도 |
|---|---|---|
| **omo run** | `omo run --agent Sisyphus -m <prov/model> -d <dir> --json [--session-id <id>] "<msg>"` | 구현(쓰기)·다단계·완수보장 |
| **opencode run** | `opencode run -m <prov/model> --variant high --format json --dir <dir> [-s <id>] "<msg>"` | 리뷰·분석·2nd opinion·N개 병렬 |

codex는 항상 `codex exec`, gemini는 항상 `agy --print`, opus는 항상 `claude --print`.

## ⚠️ 백엔드별 플래그 차이 (5-CLI 실행경로 — Fusion 병렬에서 디렉토리/세션 섞임 방지)

| | 작업 디렉토리 | 모델 | effort | resume | 출력 | 쓰기 허용 |
|---|---|---|---|---|---|---|
| codex | `-C <dir>` | `-m gpt-5.5` | `-c model_reasoning_effort="<v>"` | `exec resume <id>` | `-o FILE` | `--sandbox workspace-write` |
| agy | **`cd <dir>`** | `--model "<문자열>"` | (모델 문자열 내장) | `--conversation <id>` | **stdout** | `--dangerously-skip-permissions` |
| claude | **`cd <dir>`**+`--add-dir` | `--model opus` | (alias) | `--continue`/`--resume <id>`(`-r`) | **stdout**/`--output-format` | `--dangerously-skip-permissions` |
| omo | `-d <dir>` | `-m <prov/model>` | (없음) | `--session-id <id>` | stdout | (기본 허용) |
| opencode | `--dir <dir>` | `-m <prov/model>` | `--variant <v>` | `-s <id>` | stdout | (기본 허용) |

> ⚠️ "쓰기 허용=기본 허용"(omo/opencode)은 **강제 read-only 샌드박스가 없다**는 뜻이다. 따라서 **Fusion-Research에선 live 루트에서 돌리지 말고 `cp -a` 사본에서 실행**해 쓰기를 throwaway로 떨어뜨린다(`fusion.md` §1). 과거 "권한 프롬프트가 쓰기를 차단" 가정은 헤드리스 미검증이라 폐기.

상세 매트릭스·예시는 `references/cli-fusion-map.md`. codex/opencode 상세는 `references/codex-cli.md` · `references/opencode-cli.md`.
