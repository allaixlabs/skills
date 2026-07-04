# 라우팅 레퍼런스 — 호명 → 백엔드 (plan-fusion 전용)

사용자가 자연어로 부르는 모델명을 `(backend, model, effort/variant, dir/session 플래그)`로 정규화한다.
plan-codex-opencode/routing.md 를 확장해 **agy(Gemini) · claude(Opus)** 두 백엔드와 **CLI Fusion 프리셋**을 추가했다.
검증 환경(실측): codex-cli 0.139.0 · opencode 1.16.2 · omo 4.10.0 · **agy 1.0.10** · **claude 2.1.x** — 각 `--help` / `models` / 스모크로 확인.

> **오케스트레이터 자동감지**: 오케스트레이터는 `check-fusion.sh`가 env `PLAN_FUSION_ORCHESTRATOR=glm|gpt|gemini|claude`(argv 폴백)에서 읽어 `ORCHESTRATOR_FAMILY`로 내보낸다. **감지된 패밀리는 동족(확증편향) 회피를 위해 참가자·Judge·Synth 후보에서 자동 제외**된다. 따라서 아래 프리셋 표의 "기본"은 오케스트레이터=`unknown`일 때의 기준이며, 구체 오케스트레이터별로는 **오케스트레이터 패밀리 제거 변형**(아래 별표)을 적용한다.
>
> ⚠️ **GLM 예외(참가자 한정)**: 오케스트레이터=`glm`일 때만 opencode(GLM)를 동족이어도 **참가자에 필수 포함**한다(`GLM_MANDATORY_PARTICIPANT=yes`). 정당화 — 오케스트레이터는 검증-only(불가양도)·opencode 참가자는 독립 풀이 수행으로 역할 분리 → 동족 위험 완화 + '최소 3종 백엔드(codex·agy·glm)' 보장. 동종할인(`PARTICIPANT_CONFLICT_RISK=partial`)을 synthesis/REPORT에 명시. **Judge·Synth는 여전히 동족 회피**(참가자만 예외). gpt/gemini/claude 오케스트레이터는 종전대로 동족 회피.

> **모델명 SSOT(단일 진실원) = `models.yaml`**: 모델명·cli_model·패밀리·disabled 정책·패널 프리셋의
> 진실원은 **models.yaml**(레포 루트 + sync-models.sh 로 각 스킬 폴더에 복제)이다. 과거엔 이 문서가
> SSOT 를 자처했으나(마크다운 표의 값을 check-fusion.sh·council.md·SKILL.md·README.md·templates 가
> 복사), 이제 **models.yaml 이 진실원**이고 이 표는 사람이 읽는 뷰다. 버전업·모델명 변경 시:
> 1. **models.yaml 만 고친다**(단일 편집점).
> 2. `bash sync-models.sh` → models.lib.sh 재생성 + 각 스킬로 복제.
> 3. `bash check-models.sh` → 이 문서·스크립트·템플릿과 SSOT 정합 자동 검증(드리프트=FAIL).
> 스크립트(check-fusion.sh)는 models.lib.sh 를 source 해 `$M_GPT_CLI`·`is_disabled_model` 로 소비한다.
> agy 모델명(`"Gemini 3.1 Pro (High)"` 등)·CLI 버전 문자열의 실측 진실원도 models.yaml 이다.

## 대원칙

| 호명 모델 | 백엔드 | 이유 |
|---|---|---|
| **codex / gpt 계열** | `codex exec` | GPT 1급 시민(결정론 샌드박스, `exec review` 코드리뷰). 기본 **Synthesizer**. ⚠️ 오케스트레이터가 gpt 패밀리면 동족. |
| **gemini 계열** | `agy -p` | Antigravity CLI가 Gemini 전용 실행기. **새 패밀리(Google)** — 교차검증 다양성↑. ⚠️ 오케스트레이터가 gemini 패밀리면 동족. **agy 1.0.10: 파일 검색 스코프 결함 → `--add-dir <작업dir>` + 프롬프트 파일 참조 절대경로** (아래 특이사항 참고). |
| **opus / claude 계열** | `claude --print` | Anthropic 직접. 기본 **Judge**(오케스트레이터가 claude 패밀리가 아닐 때). ⚠️ 오케스트레이터가 claude 패밀리면 동족. |
| **glm 계열** (zai-coding-plan) | **opencode 계열** (`omo run`/`opencode run`) | GLM 직접 provider. ⚠️ 오케스트레이터가 glm 패밀리면 동족(참가자 필수 포함 예외). |
| **kimi 계열** (opencode-go) | **opencode 계열** | Kimi 별도 provider → **별도 패밀리**(GLM과 동족 아님, 단 opencode 백엔드 공유로 상호 partial). ⚠️ 오케스트레이터가 kimi 패밀리면 동족(참가자 필수 포함 예외). |
| **그 외 provider** (deepseek·qwen·minimax·opus-via-dgrid 등) | **opencode 계열** | 멀티 프로바이더는 opencode 생태계 담당(glm family 잔류). ⚠️ 오케스트레이터가 glm 패밀리면 동족. |

핵심: codex(GPT)·agy(Gemini)·opencode-glm·opencode-kimi는 **서로 다른 모델 패밀리** → 같은 문제에서 다른 실수 → 교차검증 독립성. 참가자는 가능한 한 **서로 다른 패밀리**로 구성한다.

## 호명 → 정규화 테이블

| 사용자 자연어 | backend | model | effort/variant | dir 플래그 | resume |
|---|---|---|---|---|---|
| codex / gpt5.5 / "gpt5.5 xhigh" | `codex exec` | `gpt-5.5` | `-c model_reasoning_effort="xhigh"` | `-C` | `exec resume <id>` |
| gpt5.5 fast / pro | `codex exec` | `gpt-5.5-fast` / `gpt-5.5-pro` | `-c model_reasoning_effort="<v>"` | `-C` | 〃 |
| **gemini / "gemini 3.1 pro" / "gemini pro"** | `agy -p` | `"Gemini 3.1 Pro (High)"` | **모델 문자열에 내장**(High/Low) | **`cd`** (`-C` 없음) | `--conversation <id>` |
| **gemini flash / "gemini 3.5 flash"** | `agy -p` | `"Gemini 3.5 Flash (Medium)"` | 〃 (Low/Medium/High) | **`cd`** | `--conversation <id>` |
| **opus / "opus 4.8" / claude** | `claude --print` | `opus` (alias) 또는 `claude-opus-4-8` | (모델 alias) | **`cd`** (`--add-dir` 보조) | `--continue`(최근) / `--resume <id>`(`-r`) |
| glm5.2 / "glm 5.2" | opencode | `zai-coding-plan/glm-5.2` | `--variant high` | `-d`(omo)/`--dir`(opencode) | `--session-id`/`-s` |
| glm5.1 / glm4.7 | opencode | `zai-coding-plan/glm-5.1` / `glm-4.7` | `--variant high` | `-d`/`--dir` | 〃 |
| kimi k2.7 / kimi | opencode | `opencode-go/kimi-k2.7-code` | `--variant high` | `-d`/`--dir` | 〃 |
| kimi k2.6 | opencode | `opencode-go/kimi-k2.6` | `--variant high` | `-d`/`--dir` | 〃 |
| deepseek / pro / flash | opencode | `opencode-go/deepseek-v4-pro` / `-flash` | `--variant high` | `-d`/`--dir` | 〃 |
| qwen / minimax / mimo … | opencode | `opencode-go/<model>` | `--variant high` | `-d`/`--dir` | 〃 |

> ⚠️ **위 표의 `--variant high`는 opencode 직접 경로(`opencode run`) 전용이다.** omo run엔 `--variant`가 없으므로(아래 'effort / variant 매핑' 참조), 기본 구현 경로인 **omo run으로 위임할 때는 `--variant`를 빼라** — 미지원 플래그는 `ORCHESTRATION_FAIL`이 된다. dir 플래그도 omo는 `-d`, opencode는 `--dir`로 갈린다(한 행에 병기했을 뿐 동시 사용 아님).
> ⚠️ **`model`열 문자열은 `-m` 인자에 그대로 복사해 넣는다** — 항상 `provider/model` 전체(단일 슬래시, 끝 슬래시 없음). 베어 모델명이나 끝 슬래시(`kimi-k2.7-code/`)는 opencode가 `Model not found`로 exit=1(위임 실패, 무응답 처리 → quorum 피해). SKILL.md §0·`opencode-cli.md` 경로 B의 사후검증 참조.
> ⚠️ **Gemini 모델명은 실측 문자열 그대로** 쓴다(`agy models` 출력). 스펙에서 본 `gemini-3.5-pro`는 **존재하지 않음** — 실재는 **Gemini 3.1 Pro**(High/Low) + **Gemini 3.5 Flash**(Low/Medium/High). effort는 별도 플래그가 아니라 모델 문자열의 `(High/Medium/Low)`로 지정한다.
> ⚠️ **Opus 4.8은 `claude` 직접 호출**로만 얻는다. agy의 Claude 모델은 4.6, opencode의 `dgrid/claude-opus-4-8`도 경로가 다르다 → Opus 호명은 `claude --print --model opus`.

## effort / variant 매핑

- **codex**: `xhigh|high|medium|low|minimal` → `-c model_reasoning_effort="<v>"` (TOML — 쌍따옴표 필수).
- **agy**: effort가 **모델 문자열에 내장** — `"Gemini 3.1 Pro (High)"` vs `"(Low)"`. 별도 effort 플래그 없음.
- **claude**: 모델 alias(`opus`)로 선택. reasoning effort 별도 노출 없음(모델 기본).
- **opencode**: `--variant <high|max|minimal>`. **omo run엔 `--variant` 없음** → 고추론 필요 시 opencode 직접 경로.

## agy / claude 호출 특이사항 (Fusion 병렬에서 엉키지 않도록)

- **agy**: `-C`/`-o` 없음 → 작업디렉토리는 **`( cd "$RUN/wt/<id>" && command agy ... )`**, 출력은 **stdout 리다이렉트**(`> round1.log`). 함수 래퍼 회피 위해 **`command agy`**. **쓰기(코드)엔 `--dangerously-skip-permissions` 필수**(헤드리스 권한 프롬프트 차단 회피 — 실측 검증). 자체 `--print-timeout`(기본 5m)이 행을 차단.
- ⚠️ **agy 파일 검색 스코프 결함 (1.0.10 실측 — 핵심)**: `-p` 모드는 작업 디렉토리를 sandbox로 엄격히 제한하지 **않는다**. 프롬프트에 **상대 파일명만** 언급하면(`app/services/foo.rb` 처럼 경로만), agy가 현재 디렉토리에서 못 찾을 때 **홈 디렉토리 전역 파일 검색**으로 빠진다. 그 결과 다른 프로젝트(예: `~/gitlab-development-kit/`)의 같은 이름 파일을 발견해 그 컨텍스트로 분석을 진행하거나, 그 프로젝트의 `bin/ci`를 실행해 버린다(로그에 `Task task-N finished ... bin/ci` 로 나타남 — 프롬프트가 무시된 것처럼 보임). **실측(1.0.10)**:
    - 긴 프롬프트 + 상대 파일명만(`app/services/...`) + 빈 디렉토리 → ❌ 홈 전역 검색 → `~/gitlab-development-kit/...` 파일로 빠짐 → `bin/ci` 실행
    - 같은 프롬프트 + **절대경로 명시**(`"$RUN/ro/app/services/..."`) → ✅ 정상
    - 같은 프롬프트 + **`--add-dir "$RUN/ro"`** 스코프 제한 → ✅ 정상
  → **결론(1.0.10): Fusion 위임 시 반드시 둘 중 하나(권장: 둘 다)를 적용한다.**
    1. **프롬프트의 파일 참조는 모두 절대경로로** (`$RUN/ro/...` 또는 `$RUN/wt/<id>/...`). 상대 파일명 단독 언급 금지.
    2. **`--add-dir "<작업디렉토리 절대경로>"` 로 agy 검색 스코프를 명시적으로 제한**.
    - 권장 호출골격: `command agy --model "<문자열>" --add-dir "$WORKDIR" -p "<절대경로 포함 프롬프트>"`.
- ℹ️ **agy 1.0.10 플래그 순서 (1.0.9 대비 변경)**: 1.0.9의 "--model 은 -p 앞이어야 한다" 결함은 **1.0.10에서 해결**됐다. `--model X -p "p"`, `-p "p" --model X`, `--model X --print "p"` 전부 정상. 단 **위치인자 패턴 `--print --model X "위치인자"`는 여전히 결함**(프롬프트 무시)이므로 위치인자 대신 항상 `-p "..."` 인용 형식을 쓴다.
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

> 위 "기본" 열은 **오케스트레이터=`unknown`(또는 claude 패밀리)** 일 때의 기준이다. 감지된 오케스트레이터 패밀리는 동족 회피를 위해 참가자·Judge·Synth에서 빠진다 — 아래 변형표 참조.

### ⚙️ 오케스트레이터 패밀리 제거 변형 (default 프리셋 예시)

`check-fusion.sh`의 `EXCLUDED_FAMILIES`/`JUDGE_CONFLICT_RISK`/`SYNTH_CONFLICT_RISK`/`GLM_MANDATORY_PARTICIPANT`/`PARTICIPANT_CONFLICT_RISK`와 정합. 원칙은 오케스트레이터 패밀리를 뺀 뒤 남은 가용 패밀리로 재구성하되, **GLM 예외**(`glm` 행)만 오케스트레이터와 같은 패밀리를 참가자에 필수 포함한다.

| `ORCHESTRATOR_FAMILY` | default 변형(참가자) | Judge | Synth | 비고 |
|---|---|---|---|---|
| `claude` | codex·agy·opencode-glm·opencode-kimi | 차순위(claude 제거 → codex/agy/opencode 중 가용) | codex(GPT) | 오케스트레이터가 claude라 Judge=claude는 동족 → check-fusion.sh가 codex 등 차순위로 산출 |
| `glm` | **codex·agy·opencode-glm** | claude(Opus) → 폴백 체인: codex→agy→opencode-deepseek(동종할인)→self | codex(GPT) | **GLM 예외**: opencode(GLM)는 오케스트레이터와 동족이나 **참가자에 필수 포함**(`GLM_MANDATORY_PARTICIPANT=yes`) — 역할 분리(오케스트레이터=검증 only·불가양도 / opencode 참가자=독립 풀이)로 동족 위험 완화 + '최소 3종 백엔드' 보장. 동종할인(`PARTICIPANT_CONFLICT_RISK=partial`)을 synthesis/REPORT에 명시. Judge·Synth는 여전히 동족 회피(참가자만 예외). Judge 폴백 체인의 DeepSeek 라우트(`opencode-go/deepseek-v4-pro`)는 종전대로 동종할인 후보로 잔존. |
| `gpt` | agy·opencode-glm·opencode-kimi | claude(Opus) | 차순위(codex 제거 → claude/agy/opencode 중 가용) | codex 제거. Synth가 claude/agy/opencode로 가면 GPT-동족 아님 |
| `gemini` | codex·opencode-glm·opencode-kimi | claude(Opus) | codex(GPT) | agy 제거 — 백엔드 2(+claude) |
| `unknown` | codex·agy·opencode-glm·opencode-kimi | claude(Opus) | codex(GPT) | 동족 룰 비활성 — 기본 그대로 |

> 변형 후 **독립 패밀리 수 < 2**(`EFFECTIVE_BACKENDS<2`)면 `check-fusion.sh`가 exit 1(Fusion 불성립) → `plan-then-*` 단일 위임 또는 백엔드 추가 안내. `ORCH_FAMILY=gpt`이고 Synth 차순위가 모두 동족이면 `SYNTH_CONFLICT_RISK=yes`로 표기되어 synthesis에 "비독립 할인" 명시. **GLM 예외**: `ORCH_FAMILY=glm`은 변형(제거)이 아니라 default(참가자 3종) 그대로 적용 — opencode(GLM)가 동족이어도 참가자에 필수 포함(`GLM_MANDATORY_PARTICIPANT=yes`, 동종할인 `PARTICIPANT_CONFLICT_RISK=partial` 명시).

**게이트 표시 라벨**(SKILL.md 0-2.5 case D — 가용분으로 필터해 이 형식으로 제시. **숫자(2/3/4/5) 세트 신설 금지** — named 프리셋 재사용):
`프리셋 · 모델슬롯 N · 독립패밀리 M · 호출 N+2 · 역할독립성`

| 프리셋 | 모델슬롯 | 독립패밀리 | 호출(N+2) | 역할 독립성 |
|---|---|---|---|---|
| default | 4 | 3 (codex·agy·opencode) | 6 | Judge 독립 · **Synth 동족(GPT 참가+GPT Synth)** |
| highEnd | 4 | 4 (+claude) | 6 | **Judge 비독립(Opus 참가)** · Synth 동족(GPT) |
| codeSecurity | 5 | 4 | 7 | **Judge 비독립** · Synth 동족 |
| fullPower | 6 | 4 (agy ×2=1패밀리) | 8 | **Judge 비독립** · Synth 동족 |
| budget | 3 | 2 (agy·opencode) | 5 | **Judge=Synth 동족(Opus)** |

- **모델 다양성 ≠ 백엔드 다양성**: GLM+Kimi는 같은 opencode라 모델슬롯만 +1, 독립패밀리는 그대로(`check-fusion.sh`의 `MODEL_READY_GLM/KIMI`로 모델 단위, `INDEPENDENT_FAMILIES_CONFIRMED`로 패밀리 단위 구분 — 게이트 case F). default가 4모델이어도 백엔드 독립성은 3인 이유다.
- **Synth 동족 주의**: default·highEnd·codeSecurity·fullPower는 Synth=GPT인데 참가자에도 GPT가 있다 → Synth가 자기 후보를 과대대표할 여지(예: 한 후보의 미검증 주장을 합성이 되살림). 게이트는 이를 세트 확정 시 노출하고, 회피하려면 Synth를 비참가 패밀리로 두거나 `fusion-synth.md.tmpl`의 "Judge가 제거 판정한 주장 재도입 금지" 제약에 의존한다.
- **headless**(비대화형 = cron·자동화): case D 자동 진행은 **min2(최소 2 독립패밀리)** + env cap(`PLAN_FUSION_HEADLESS_PRESET`·`PLAN_FUSION_MAX_PARTICIPANTS`·`PLAN_FUSION_MAX_CALLS`·`PLAN_FUSION_ALLOW_DEGRADED`). 명시 프리셋 미가용 시 **자동 축소·대체 금지**(BLOCKED). 상세는 SKILL.md 0-2.5.
- `⚠️비독립` 표기는 위 동족 편향 경고의 명시 예외다. highEnd/codeSecurity/**fullPower**는 Opus(claude) 참가자와 Judge가 같은 계열이므로 Judge 독립성이 할인된다(synthesis.md에 명시). 단 이는 **오케스트레이터=`unknown`/`claude`가 아닐 때의 기준** — 오케스트레이터가 다른 패밀리면 변형표가 우선.
- budget은 비용 절감을 위해 Judge=Synth=Opus를 허용한다. 이 경우 `synthesis.md`에 "비독립 할인" 명시 필수.
- 추천 시 한 줄 이유 제시: 예) "GPT·Gemini·GLM·Kimi 4개 모델(백엔드 3)로 교차검증 독립성을 확보하고, Opus가 판정·GPT가 합성합니다."(오케스트레이터가 어느 패밀리든 기본은 동일하되, 동족 패밀리는 변형표에서 제외됨)
- 참가자 백엔드 수는 `check-fusion.sh`의 `PARTICIPANT_FAMILIES`로 확인. 가용 백엔드에 맞춰 프리셋을 축소한다(예: agy 미설치 → Gemini 빼고 백엔드 2(codex·opencode)).

## disabledModels 가드 (사용자 정책)

- **`fable-5` · `mythos-5` 는 참가자·Judge·Synth 어디에도 라우팅 금지.** 사용자가 명시적으로 배제한 "No Fable" 정책. 호명되거나 폴백 후보로 떠올라도 선택하지 않는다.

## ⚠️ 동족 편향 경고 (오케스트레이터 패밀리의 이중 역할 — 일반화)

오케스트레이터의 패밀리는 `check-fusion.sh`가 `ORCHESTRATOR_FAMILY`로 감지한다(`glm`/`gpt`/`gemini`/`claude`/`unknown`). 감지된 패밀리를 참가자·Judge·Synth에 또 쓰면 **참가자·Judge·오케스트레이터가 같은 패밀리**가 되어 교차검증 독립성이 떨어지고, Judge가 자기(동족) 후보를 심사하는 **확증편향**이 생긴다.

`check-fusion.sh`는 감지된 오케스트레이터 패밀리를 **자동으로 참가자 카운트·JUDGE/SYNTH_DEFAULT에서 제외**한다(`EXCLUDED_FAMILIES`·`JUDGE_CONFLICT_RISK`·`SYNTH_CONFLICT_RISK`). 게이트(§0.2.5)는 이를 노출하고, 회피 경로를 제시한다.

패밀리별 동족 시나리오:
- **오케스트레이터=`claude`(Opus)**: claude를 참가자로도 쓰면 동족. 기본은 claude=Judge 전용(default 프리셋). highEnd/codeSecurity처럼 claude가 참가자인 프리셋에선 Judge를 다른 패밀리(Gemini/codex)로 바꾸거나 synthesis에 "Judge 비독립" 명시.
- **오케스트레이터=`gpt`(codex)**: codex를 참가자나 Synth에 쓰면 동족. default의 Synth=codex(GPT)는 Synth 동족 → 차순위(claude/agy/opencode 중 비-동족 가용)로 바꾸거나 약한 비독립 표기.
- **오케스트레이터=`gemini`(agy)**: agy를 참가자로 쓰면 동족. default에서 agy 제거 → 백엔드 2(codex·opencode)+claude Judge.
- **오케스트레이터=`glm`(ZCode/opencode)**: **GLM 예외(참가자 한정)** — opencode(GLM/Kimi)는 동족이나 default에서 제거하지 않고 **참가자에 필수 포함**(`GLM_MANDATORY_PARTICIPANT=yes`). 정당화: 오케스트레이터는 검증-only(불가양도)·opencode 참가자는 독립 풀이 수행으로 역할 분리 → 동족 위험 완화 + '최소 3종 백엔드(codex·agy·glm)' 보장. 동종할인 경고(`PARTICIPANT_CONFLICT_RISK=partial`)를 synthesis/REPORT에 명시(DeepSeek `judge_conflict=partial` 선례 재사용). → 백엔드 3(codex·agy·opencode-glm)+claude Judge. **Judge·Synth는 여전히 동족 회피** — Judge 폴백 체인의 DeepSeek 라우트(`opencode-go/deepseek-v4-pro`)는 동종할인 후보로 잔존(claude 런타임 사망 시 `judge_conflict=partial`로 허용).
- **오케스트레이터=`unknown`**: 동족 룰 비활성 — 모든 패밀리 가용 후보(기본 프리셋 그대로). 단 검증자가 같은 패밀리라는 보장이 없으므로, 추정 가능하면 env로 명시 권장.

**Synth 동족 주의(약)**: 참가자에 오케스트레이터 패밀리가 있고 Synth도 같은 패밀리면 → Synth가 자기(동족) 후보를 과대대표할 여지(Judge 자기심사와 동형, 단 약함). Synth 템플릿이 "Judge 판정·근거 강도로만 선별"하도록 제약해 실효 위험은 제한적이지만, 동족이면 `synthesis.md`에 약하게 표기하거나 Synth를 비-동족 패밀리로 두는 편이 깔끔하다.

## 백엔드 선택: omo vs opencode 직접 (모델 동일, 실행기만 다름)

| 경로 | 명령 골격 | 권장 용도 |
|---|---|---|
| **omo run** | `omo run --agent Sisyphus -m <prov/model> -d <dir> --json [--session-id <id>] "<msg>"` | 구현(쓰기)·다단계·완수보장 |
| **opencode run** | `opencode run -m <prov/model> --variant high --format json --dir <dir> [-s <id>] "<msg>"` | 리뷰·분석·2nd opinion·N개 병렬 |

codex는 항상 `codex exec`, gemini는 항상 `agy -p`(1.0.10: `--add-dir <작업dir>` 스코프 제한 + 프롬프트 파일 참조 절대경로), opus는 항상 `claude --print`.

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
