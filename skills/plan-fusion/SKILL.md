---
name: plan-fusion
description: >
  CLI Fusion 워크플로우 — 같은 작업을 서로 다른 AI 모델 패밀리에 각자의 CLI로 독립 실행시킨 뒤,
  Judge CLI가 후보를 비교·평가하고 Synthesizer CLI가 최종 답변을 합성하면 오케스트레이터가 검증한다.
  오케스트레이터는 자동 감지된다(ZCode/GLM, Codex CLI/GPT, AGY/Gemini, Claude/Opus) — 감지된 패밀리는
  참가자·Judge·Synth에서 제외된다(동족 회피). **단 GLM은 예외** — 오케스트레이터=GLM이면 opencode(GLM)를 동족이어도 **참가자에 필수 포함**(역할 분리: 오케스트레이터=검증 only / 참가자=독립 풀이, '최소 3종 백엔드' 보장, 동종할인 synthesis 명시). Judge·Synth는 여전히 동족 회피. 백엔드: codex(GPT)·agy(Gemini)·opencode/omo(GLM·Kimi·DeepSeek 등)·claude(Opus).
  다음일 때 사용: "gemini까지 넣어서 fusion으로", "GPT랑 Gemini, GLM, Kimi로 풀고 Judge·Synth로 합성해",
  "여러 CLI로 독립 실행하고 Opus가 판정·GPT가 종합", "agy로 gemini도 패널에 넣어", "judge synthesizer 구조로",
  "5개 모델 fusion"(모델 5 / 백엔드 4). 종합을 CLI에 위임하지 않고 오케스트레이터가 직접 종합하는 단순 교차검증이면 plan-codex-opencode를,
  단일 모델 위임이면 plan-then-codex / plan-then-opencode를 쓴다.
---

# plan-fusion — CLI Fusion (참가자 → Judge → Synthesizer → 검증)

**오케스트레이터 = 두뇌**(분석·계획·패널선택·**검증·사실확인**). **CLI들 = 손**: 같은 문제를 각 패밀리가 독립 실행. **합성 = Judge CLI + Synthesizer CLI에 위임**.

오케스트레이터는 §0.0에서 감지된다 — `glm`(ZCode)·`gpt`(Codex CLI)·`gemini`(AGY)·`claude`(Claude Code)·`unknown`. 감지된 패밀리는 동족(확증편향) 회피를 위해 **참가자·Judge·Synth 후보에서 자동 제외**된다(상세 §0.0·§0.2 동족 경고).

핵심 가치: codex(GPT)·agy(Gemini)·opencode(GLM/Kimi)는 **서로 다른 모델 패밀리** → 같은 문제에서 다른 실수 → 교차검증 독립성. plan-codex-opencode와의 차이는 **종합을 오케스트레이터가 직접 하지 않고 명시적 Judge→Synthesizer CLI로 위임**한다는 것(오케스트레이터는 검증만 불가양도). agy(Gemini)·claude(Opus)를 더해 **백엔드 패밀리 4 / 대표 모델 5종**(codex·agy·opencode·claude; GPT·Gemini·GLM·Kimi·Opus). "최대 5"는 패밀리 기준이며, 프리셋에 따라 같은 패밀리 다중 variant(예: fullPower의 Gemini Pro+Flash)면 참가자 슬롯은 6까지 늘 수 있다.
GLM·Kimi는 같은 opencode 백엔드(런타임·인증 공유)라 **모델 다양성**은 있으나 백엔드 독립성은 codex/agy와 동급이 아니다 — '모델 다양성'과 '백엔드 다양성'을 구분한다.

- `SKILL_DIR` = 이 SKILL.md가 있는 디렉토리. `$RUN` = 이번 위임의 격리 폴더(0단계 생성).
- `PANEL` = 참가자 목록(각 원소 `id|backend|model`, id는 `[a-z0-9-]` 슬러그). `JUDGE`·`SYNTH` = 각 1개 백엔드.
- 레퍼런스: 라우팅 `references/routing-fusion.md` · 5-CLI경로 `references/cli-fusion-map.md` · codex `references/codex-cli.md` · opencode/omo `references/opencode-cli.md` · 격리·Judge·Synth `references/fusion.md`.

> **진입 규칙(bail-out 금지)**: `/plan-fusion`으로 **명시 호출**되면 task 내용이 무엇이든 — "이 스킬을 검토/개선해" 같은 **메타 요청 포함** — 반드시 **§0부터 실행**한다. §0의 **2.5 패널 확정 게이트(모델 세트 선택/확인)는 §1 ANALYZE보다 먼저** 사용자에게 노출되어야 한다. task가 메타로 보인다는 이유로 워크플로우를 건너뛰고 곧장 단독 분석/리뷰로 진입하는 것은 **금지된 silent bail-out**이다(2.5의 silent-fallback 금지를 task-해석 단계로 확장). 스킬 자체 리뷰도 Fusion-Research의 정당한 task다 — 여러 패밀리가 독립 리뷰 → Judge·Synth 종합이 이 작업의 핵심 가치다.

---

## 0. 사전점검 + 요청 파싱 + 모드/패널 결정

0. **오케스트레이터 감지**(맨 처음, §1 ANALYZE보다 먼저): `check-fusion.sh`가 env `PLAN_FUSION_ORCHESTRATOR=glm|kimi|gpt|gemini|claude`(없으면 argv `${1}` 폴백, 둘 다 없으면 `unknown`)를 읽어 `ORCHESTRATOR_FAMILY`·`ORCHESTRATOR_BACKEND`·`EXCLUDED_FAMILIES`·`ORCH_FAMILY_EXCLUDED`·`JUDGE_DEFAULT`/`SYNTH_DEFAULT`(오케스트레이터 패밀리 회피)·`JUDGE_CONFLICT_RISK`/`SYNTH_CONFLICT_RISK`를 내보낸다. 감지된 패밀리는 동족(확증편향) 회피를 위해 **참가자·Judge·Synth 후보에서 자동 제외**된다(`EXCLUDED_FAMILIES`로 사유 표시). `unknown`이면 제외 룰 비활성(모든 패밀리 가용 후보).
   - 패밀리 매핑: `glm`→opencode(GLM/Kimi) · `gpt`→codex · `gemini`→agy · `claude`→claude(Opus).
   - 헤드리스(cron·자동화)에서도 결정론적 — env로 못 박거나, 대화형이면 §0.2.5 게이트에서 사용자에게 확정받는다.

1. **사전 점검**(read-only): `bash "$SKILL_DIR/scripts/check-fusion.sh"` → `CODEX/AGY/OPENCODE/CLAUDE_BACKEND_READY` · `ORCHESTRATOR_FAMILY`·`EXCLUDED_FAMILIES`·`ORCH_FAMILY_EXCLUDED` · `PARTICIPANT_FAMILIES` · `EFFECTIVE_BACKENDS` · `JUDGE_DEFAULT`/`SYNTH_DEFAULT`(+`JUDGE_CONFLICT_RISK`/`SYNTH_CONFLICT_RISK`) · `JUDGE_FALLBACK_CHAIN`·`JUDGE_DEEPSEEK_READY`(런타임 Judge 폴백 — claude死 시 차순위 자동 전환, §3-2) · provider 인증 매트릭스(`MODEL_READY_GLM`/`MODEL_READY_KIMI`/`MODEL_READY_DEEPSEEK`) · `FUSION_CAPABILITY`. 차단 게이트는 `EFFECTIVE_BACKENDS`(= 비-오케스트레이터 참가자 패밀리 + 비-오케스트레이터 claude-as-participant 후보) 기준이다 — **`EFFECTIVE_BACKENDS`<2면 exit 1**(Fusion 불성립, plan-then-* 또는 누락 백엔드 설정 안내·중단). 독립 백엔드가 2면 통과(exit 0). ⚠️ 단 그 경우 **비-오케스트레이터 패밀리를 '참가자'로 써야** 교차검증 2패밀리가 된다 — Judge-only default로만 쓰면 참가자 1패밀리뿐이라 런타임 quorum(§4)이 'Fusion 미성립'으로 격하한다(preflight는 이를 `FUSION_CAPABILITY=conditional`로 표기).
2. **호명 파싱**(`references/routing-fusion.md`): 부른 모델("gpt5.5, gemini, glm5.2, kimi")을 각각 `(backend, model, effort/variant, dir/session 플래그)`로 정규화. **호명 없으면 기본 패널 추천**(default: 오케스트레이터 패밀리를 제외한 비-동족 패밀리들 — Judge=오케스트레이터 패밀리 회피 `JUDGE_DEFAULT`, Synth=`SYNTH_DEFAULT`, 상세는 라우팅 문서 변형표) + **1줄 이유**. 프리셋(highEnd/codeSecurity/fullPower/budget)은 라우팅 문서 표 참조.
   - ⚠️ **`-m` 인자 형식 강제(빈번한 위임 실패 원인)**: opencode/omo 백엔드의 `-m`는 **항상 `provider/model` 전체 형식**이어야 한다 — 베어 모델명(`kimi-k2.7-code`)이나 끝 슬래시(`kimi-k2.7-code/`·`opencode-go/kimi-k2.7-code/`)는 opencode가 **`Model not found`로 즉시 exit=1**(위임 자체가 실패, 분석 1건도 안 돌음). 정규화 테이블(routing-fusion.md)의 `model`열 문자열을 **그대로 복사**해 `-m`에 넣되, 조립 후 **반드시 1회 사후 검증**(`grep -qE '^-m [a-z0-9._-]+/[a-z0-9._-]+$'` 로 `provider/model` 단일 슬래시·끝자리 슬래시 없음 확인 — 케이스는 §3 사후검증 블록). kimi=`opencode-go/kimi-k2.7-code` · glm=`zai-coding-plan/glm-5.2` · deepseek=`opencode-go/deepseek-v4-pro`. provider prefix를 빼먹지 말 것 — 자연어 "kimi" 호명이 `-m kimi-k2.7-code/`(끝 슬래시 오타)로 떨어진 사례가 실제로 발생했다.
   - **disabledModels**: `fable-5`·`mythos-5`는 참가자·Judge·Synth 어디에도 쓰지 않는다(사용자 정책).
   - **동족 경고(일반화)**: 오케스트레이터 패밀리(§0.0 감지값, 예: `glm`/`kimi`/`gpt`/`gemini`/`claude`)가 참가자·Judge·Synth 중 어디에 또 쓰이면 동족(확증편향)이다. `check-fusion.sh`가 그 패밀리를 `EXCLUDED_FAMILIES`로 이미 빼지만, 호명이나 프리셋이 명시적으로 그 패밀리를 다시 넣으려 하면 게이트가 노출하고 synthesis에 "비독립(동족) 할인"을 명시한다. `ORCH_FAMILY=unknown`이면 동족 룰 비활성. **⚠️ GLM/KIMI 예외(참가자 한정)**: `ORCH_FAMILY=glm|kimi`이면 opencode(해당 패밀리)는 동족이어도 **참가자에 필수 포함**(`GLM/KIMI_MANDATORY_PARTICIPANT=yes`) — 역할 분리(오케스트레이터=검증 only·불가양도 / opencode 참가자=독립 풀이)로 동족 위험 완화 + '최소 3종 백엔드(codex·agy·opencode)' 보장. 동종할인(`PARTICIPANT_CONFLICT_RISK=partial`)을 synthesis/REPORT에 명시(DeepSeek `judge_conflict=partial` 선례 재사용). **Judge·Synth는 여전히 동족 회피**(참가자만 예외).
2.5. **패널 확정 게이트**(결정론 — 호명 파싱 결과 `intent` × 가용 매트릭스 `matrix` → `GATE_CASE`. **자동 silent-fallback 금지**): 부재 백엔드를 조용히 빼지 않는다 — 의도와 가용이 어긋나면(B/C/E) 알리고, 의도가 없으면(D) 선택받는다. "호명 파싱 이후 결정론"이라 호명 정규화(2번)까지 끝난 뒤 적용한다.
   - **가용 표시 규칙**: ① `CLAUDE_AUTH=assumed-ok`는 **설치만 확인(미확정)** — case A "전부 가용" 판정에서 실가용으로 세지 않고 `⚠️미확정(첫 --print서 확정)`으로 라벨(`check-fusion.sh`가 `CLAUDE_BACKEND_CONFIRMED=no`로 구분). ② 세트 제시는 **숫자(2/3/4/5) 세트 신설 금지** — 기존 named 프리셋(default/highEnd/codeSecurity/fullPower/budget)을 오케스트레이터 패밀리 제거 변형(`references/routing-fusion.md` 변형표)으로 필터해 `프리셋명 · 모델슬롯수 · 독립패밀리수 · 호출수(N+2) · 역할독립성`으로 표시. ③ **동족 노출(일반화)**: 오케스트레이터 패밀리가 참가자·Judge·Synth 중 어디에 또 쓰이면(= `JUDGE_CONFLICT_RISK=yes` / `SYNTH_CONFLICT_RISK=yes` / 호명이 오케스트레이터 패밀리) 세트 확정 시 노출 + synthesis 비독립 표기 예고.
   - **GATE_CASE 디스패치**:

   | case | 조건 | 동작 |
   |---|---|---|
   | hard-block | `EFFECTIVE_BACKENDS<2` | `check-fusion.sh` exit 1 — Fusion 불성립(0-1) |
   | policy-reject | disabledModels(`fable-5`/`mythos-5`) 호명 | 거부 + 대체 안내 |
   | **A** | 명시 호명 전부 **실가용**(assumed-ok 제외) · 독립패밀리≥2 · 역할 가용 | **묻지 않고** 요약 후 진행. 호명 외 추가 가용 **자동 추가 금지** |
   | **B** | 명시/부분 호명 중 일부 부재, **잔여 독립패밀리≥2** | 부재분(이유) 표시 → "①잔여로 진행 / ②설정 후 재시도". **silent-drop 금지**(②는 로그인 안내만·자동 로그인 금지 → BLOCKED) |
   | **C** | 부재 후 잔여 독립패밀리<2 또는 전원 부재 | **자동 대체 금지** → 대체 프리셋 선택 또는 BLOCKED |
   | **D** | 호명 없음/완전 모호 | 가용 매트릭스 + named 프리셋(라벨) 제시 → 선택 |
   | **E** | Judge/Synth 역할 백엔드 부재 | 명시 역할 부재=확인 게이트 / 기본 역할 부재=결정론 폴백(`JUDGE_DEFAULT`/`SYNTH_DEFAULT` 체인) + REPORT 표기 |
   | **F** | 동일 백엔드 다중 모델(GLM+Kimi 등) | 모델수·패밀리수 **분리 표시**, 독립성 카운트엔 **1패밀리** |
   | **I** | `participant<2 & effective≥2`(`FUSION_CAPABILITY=conditional`) | 비-오케스트레이터 패밀리를 **참가자**로 써야 성립함을 명시 — Judge-only default로 **조용히 진행 금지** |

   - **headless 폴백**(AskUserQuestion 불가 = cron·자동화 파이프라인): 명시 패널/프리셋이 있으면 그대로 시도하되 **미가용 자동대체 금지**(B/C는 BLOCKED). case D는 자동 진행하되 **min2(최소 2 독립패밀리) + env cap** — 확대는 env로만: `PLAN_FUSION_HEADLESS_PRESET` · `PLAN_FUSION_MAX_PARTICIPANTS` · `PLAN_FUSION_MAX_CALLS` · `PLAN_FUSION_ALLOW_DEGRADED`. REPORT에 "대화형 선택 생략, headless 기본 세트 적용" 표기.
3. **모드 선택**:
   - 파일 변경 없는 분석/리서치/설계 질문, "여러 모델로 풀어 정리" → **Fusion-Research**(read-only).
   - 코드 구현 + 신뢰도↑ → **Fusion-Code**(worktree 격리 병렬 → Judge → Synth → 적용 → 검증).
4. **격리 폴더**:
   ```bash
   slug=$(printf '%s' "<task 한단어>" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | cut -c1-20)
   RUN=$(umask 077; mktemp -d "${TMPDIR:-/tmp}/pf.${slug}.XXXXXX") || { echo "RUN 생성 실패" >&2; exit 1; }
   [ -d "$RUN" ] || { echo "RUN 생성 실패" >&2; exit 1; }
   # 데이터 펜스 토큰(런별 난수) — Judge/Synth로 보낼 후보를 감싸는 경계. 후보가 추측·삽입 불가하게 난수.
   # ⚠️ 파이프 종료코드는 마지막 tr(빈입력에도 exit0)이라 'od ... || echo' 폴백은 죽은 코드다 — od 실패 시
   #    fence가 정적 'CANDIDATE_DATA_'로 굳어 인젝션 방어가 무력화된다. 변수로 받아 ${:-}로 폴백한다(폴백도 숫자뿐 → sed 구분자 안전).
   rand=$(od -An -N6 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
   fence="CANDIDATE_DATA_${rand:-$(date +%s 2>/dev/null)$$$RANDOM}"
   # mode 값은 §4(fusion.md §3-3)에서 MODE로 읽혀 Synth 분기를 가른다 → 반드시 리터럴 'Fusion-Code' 또는 'Fusion-Research'.
   # selected_family_count = 2.5 게이트가 확정한 '독립 패밀리 수'(INDEPENDENT_FAMILIES_CONFIRMED 기준). §4 quorum이 축소 알림(선택 N→생존 M)에 쓴다.
   # orchestrator_family = §0.0 감지값(glm/gpt/gemini/claude/unknown) — Judge/Synth 동족 판정·REPORT 표기용. check-fusion.sh 출력에서 읽어 치환.
   # judge_fallback_chain = check-fusion.sh의 JUDGE_FALLBACK_CHAIN(런타임 Judge 폴백 — claude死 시 차순위 자동 전환, references/fusion.md §3-2).
   #    형식: "backend:model:conflict -> backend:model:conflict -> ... -> orchestrator-self:glm:yes". 빈값·'<…>' 잔존 금지(미치환 시 §3-2 루프 ABORT).
   printf 'mode=%s\npanel=%s\njudge=%s\nsynth=%s\nfence=%s\nselected_family_count=%s\norchestrator_family=%s\njudge_fallback_chain=%s\n' "<Fusion-Code|Fusion-Research>" "<참가자 id들>" "<judge>" "<synth>" "$fence" "<2.5 확정 독립패밀리 수>" "<glm|kimi|gpt|gemini|claude|unknown>" "<check-fusion.sh JUDGE_FALLBACK_CHAIN 산출값>" >> "$RUN/manifest"
   # ⚠️ #3 회피: Synth 백엔드를 codex 에 하드코딩하지 않도록, check-fusion.sh 의 SYNTH_DEFAULT(·model)를
   #    manifest 에 기록해 §3-3 run_synth() 가 분기하게 한다. 오케스트레이터가 어떤 패밀리든 동족 강제를 피함.
   printf 'synth_backend=%s\nsynth_model=%s\n' "<check-fusion.sh SYNTH_DEFAULT backend(codex/claude/agy/opencode)>" "<해당 model>" >> "$RUN/manifest"
# timeout 예산(초) — 폴백 체인·참가자 per-call 모두 이 값을 읽어 timeout(1) 인자로 쓴다.
# env 오버라이드: PLAN_FUSION_JUDGE_TIMEOUT / PLAN_FUSION_SYNTH_TIMEOUT / PLAN_FUSION_CHAIN_CAP / PLAN_FUSION_MAX_PARALLEL / PLAN_FUSION_PARTICIPANT_TIMEOUT
printf 'judge_timeout=%s\nsynth_timeout=%s\nchain_wall_clock=%s\nmax_parallel=%s\nparticipant_timeout=%s\n' "${PLAN_FUSION_JUDGE_TIMEOUT:-180}" "${PLAN_FUSION_SYNTH_TIMEOUT:-600}" "${PLAN_FUSION_CHAIN_CAP:-900}" "${PLAN_FUSION_MAX_PARALLEL:-3}" "${PLAN_FUSION_PARTICIPANT_TIMEOUT:-600}" >> "$RUN/manifest"
   # ⚠️ placeholder 치환 검증(작성 직후 1회): mode·selected_family_count·orchestrator_family가 실제 리터럴/숫자로 치환됐는지 확인한다 —
   #    미치환 시 §4 Synth(mode case ABORT)·quorum 축소비교(selected_family_count 비숫자 → '[: integer expression expected')·
   #    동족 판정(orchestrator_family 미치환 → Judge/Synth 비독립 표기 누락)이 깨진다.
   grep -qE '^mode=(Fusion-Code|Fusion-Research)$' "$RUN/manifest" || { echo "ABORT: manifest mode 미치환/오타 — §0.4 placeholder 확인." >&2; exit 1; }
   grep -qE '^selected_family_count=[0-9]+$' "$RUN/manifest" || { echo "ABORT: manifest selected_family_count 비숫자/미치환 — §0.4 placeholder 확인." >&2; exit 1; }
   grep -qE '^orchestrator_family=(glm|kimi|gpt|gemini|claude|unknown)$' "$RUN/manifest" || { echo "ABORT: manifest orchestrator_family 미치환/오타 — §0.4 placeholder 확인." >&2; exit 1; }
   # panel/judge/synth도 빈값·'<…>' placeholder 잔존이면 ABORT(검증 일관성 — 미치환이 §3-1 동적수집·§3-3 Synth로 샘)
   for k in panel judge synth; do v=$(sed -n "s/^$k=//p" "$RUN/manifest" | head -1)
     case "$v" in ''|*'<'*'>'*) echo "ABORT: manifest $k 미치환/빈값('$v') — §0.4 placeholder 확인." >&2; exit 1;; esac; done
   # judge_fallback_chain 검증: 빈값·'<…>' placeholder 잔존 금지(미치환 시 §3-2 루프 ABORT). 최소 1개 후보(self 포함) 있어야 한다.
   _jfc=$(sed -n 's/^judge_fallback_chain=//p' "$RUN/manifest" | head -1)
   case "$_jfc" in ''|*'<'*'>'*) echo "ABORT: manifest judge_fallback_chain 미치환/빈값('$_jfc') — §0.4에서 check-fusion.sh JUDGE_FALLBACK_CHAIN 치환 확인." >&2; exit 1;; esac
   # timeout 예산 검증: 숫자만 허용(비숫자면 timeout(1) 인자가 깨져 폴백 체인이 무한정 대기).
   for k in judge_timeout synth_timeout chain_wall_clock max_parallel participant_timeout; do v=$(sed -n "s/^$k=//p" "$RUN/manifest" | head -1)
     grep -qE "^$k=[0-9]+$" "$RUN/manifest" || { echo "ABORT: manifest $k 비숫자/미치환('$v') — §0.4 timeout 예산 확인." >&2; exit 1; }; done
   ```
5. **패널·모드·Judge·Synth·각 백엔드 플래그 + 예상 비용/시간을 1회 요약** → **2.5 `GATE_CASE`별 확인/선택 후 진행**(**자동 진행은 case A·headless 명시 정책만**; 그 외 silent-fallback 금지) — N참가자 + Judge 1 + Synth 1은 단일 위임의 N+2배 이상 호출이다(agy `--print-timeout`은 일반 장기실행은 차단하나 **권한프롬프트 교착은 못 끊는다**(→ `--dangerously-skip-permissions` 병행, references 참조), omo는 자체 타임아웃 없음 → 백그라운드+완료알림). **동시성 상한**(기본 `PLAN_FUSION_MAX_PARALLEL=3`)·**참가자/Judge/Synth per-call timeout**·**폴백 체인 wall-clock cap**(기본 900s)·**과반 타임아웃 시 순차 회귀** 폴백이 §3·§4에 정의돼 있으니 이를 비용 요약에 포함할 것(4패밀리 동시는 비권장 — 경합으로 전원 타임아웃된 실증 패턴). **대상 repo 크기**(Fusion-Research의 cp 사본)도 `du -sh`로 추정해 포함 — 수 GB(직전 6.7GB 관측)면 shallow/sparse/NO_RO_COPY 옵션을 미리 제시. 인간 승인 영역(스키마/보안/키·시크릿/결제/배포/PRD범위/아키텍처)이면 여기서 BLOCKED.

## 1. ANALYZE

오케스트레이터가 코드·실행 페이지를 직접 분석. 변경 대상·스택·빌드/테스트/린트 명령·인간 승인 영역 식별. UI면 스크린샷 → 텍스트 스펙. 브라우저 증거 수집(`aside`/`mcp__aside__repl`) 시 [`references/aside-repl.md`](references/aside-repl.md) 참조 — 세션 유지 함정(MCP 도구 vs CLI 경로).
**Fusion-Research**면 질문을 **검증가능한 하위 질문(Q1..Qn)**으로 분해 — Judge 평가·오케스트레이터 사실확인의 축이 된다.
- **UI 노출 판정(필수)**: 이 작업이 사용자에게 노출되는 변경인가(새 화면·컴포넌트·라우트·상호작용·표시 로직)를 yes/no로 판정하고 **1줄 근거**를 HANDOFF의 'UI 노출 판정' 필드에 기록한다.
  - yes → HANDOFF의 '디자인 스펙' 섹션 + UI Acceptance Criteria를 필수화(아래 §2 PLAN · §5 VERIFY · `templates/fusion-judge.md.tmpl`·`fusion-synth.md.tmpl` 연동).
  - no → '디자인 스펙' 생략 가능하되, **근거 없는 no는 금지** — 판정 사유를 HANDOFF에 명시해 감사 가능성을 유지한다.
- **외부정보 선fetch 의무**: 참가자 사본의 네트워크 상태는 백엔드마다 다르다 — **codex `-s read-only`만 진짜 샌드박스**이고, agy·opencode·omo·claude는 cp 사본이라 **네트워크가 열려 있다**(§3가 명시하듯 cp -a는 egress·git push·시크릿·심링크 탈출을 못 막는다). 따라서 "참가자는 네트워크가 막혀 있다"는 전제는 **거짓**이며, 선fetch 의무는 다음 둘 중 하나로 정당화된다: (a) **격리 강제 루트** — `unshare -n`/firejail/sandbox-exec로 네트워크를 실제로 차단한 환경에서만 선fetch를 의무화(단일 오케스트레이터 fetch가 패널 전체의 단일실패점); (b) **독립 fetch 허용 루트(권장)** — 참가자가 외부 웹을 쓸 수 있음을 인정하고 선fetch를 "최소 공통 근거"로 축소하되, 각 참가자가 **독립적으로** 외부 문서를 조사하도록 권장(단일 실패점 제거 + 교차검증 독립성 강화). 어느 쪽이든 **§1(네트워크 막힘 단정)과 §3(egress 못 막음)의 모순을 해소**해야 한다. 최신 문서·API·외부 근거가 필요하면 오케스트레이터가 §1에서 직접 fetch해 HANDOFF에 발췌+출처로 첨부한다(참가자는 제공 자료+로컬 사본만으로 분석). 단 발췌는 **요약·핵심만**(전문 무제한 인라인은 참가자 argv `E2BIG` 위험 → `references/fusion.md` §2). ⚠️ 선fetch를 누락하면 **상관 맹점**(전 패널이 같은 정보 공백 공유 → 교차검증 독립성 무력화)이 생기므로, 외부근거가 답을 가르는 task면 fetch 품질이 패널 전체의 단일 실패점임을 인지한다.

## 2. PLAN — HANDOFF 작성 (모든 참가자가 공유하는 단일 스펙)

- 코드: `templates/HANDOFF.md.tmpl` / 비코드: `templates/HANDOFF-research.md.tmpl` → `"$RUN/handoff.md"`.
- **단일 HANDOFF 원칙**: 같은 스펙을 모든 참가자에 동일하게 — 교차검증 공정성. 백엔드별 차이(에이전트·sandbox·dir·skip-permissions)는 본문이 아니라 **호출 플래그**로만.
- 자기완결성: 참가자는 대화 컨텍스트를 모른다. Baseline·Out-of-scope·BLOCKED 프로토콜·실행가능 Acceptance Criteria를 문서에 다 담는다.
- baseline 스냅샷(코드): `git -C "<root>" status --short > "$RUN/baseline.status"` · `git -C "<root>" rev-parse HEAD > "$RUN/baseline.head"`.

## 3. DELEGATE — 참가자 병렬 (백그라운드 + 참가자별 manifest, 능동 폴링)

> 각 참가자는 **별도 Bash `run_in_background: true`**(한 셸 `&` 금지). 산출물 `$RUN/<id>/`. 다중 패널은 병렬이 기본이되, **동시성 상한·타임아웃·과반 실패 시 직렬 회귀**를 함께 적용한다(무제한 병렬은 CLI 프로세스 경합으로 전원 타임아웃되는 실증된 실패 패턴 — 동시성 cap 없는 "병렬이 본질" 가정은 위험). 다음 응답마다 **능동적으로** 각 참가자의 exit 파일(`$RUN/<id>/exit.txt` 또는 manifest)을 폴링해 완료 수를 센다(예: "3/3 완료" / "2/3 완료, 나머지 agy 실행 중"). 전원 완료 확인 시 즉시 §4 FUSE로 넘어간다 — "기다리겠다"며 멈추거나 진행 없이 안내문만 내놓지 않는다(부분 완료 진행 보고는 허용).
> **race 가드**: 참가자 결과 파일(`result.md`/`round1.log`)은 해당 참가자 완료 *후에만* 읽는다(완료 전 read는 빈/직전 결과). 단, exit/manifest로 진행 상태 카운트하는 것은 완료 전에 허용. 셸 상세·5-CLI경로 호출은 `references/fusion.md` §2 · `references/cli-fusion-map.md`.

> **동시성·타임아웃 예산 (직접 관측된 실패에서 도출)**:
> - **동시성 상한**: `PLAN_FUSION_MAX_PARALLEL`(기본 **3**, 미설정 시). 4패밀리를 동시에 띄우면 CLI 프로세스 경합으로 전원 600초 타임아웃되는 패턴이 실증됨. 4 이상은 `PLAN_FUSION_MAX_PARALLEL`로 명시 설정한 경우만 허용하고, 기본값은 3으로 순차 배치를 섞는다(예: 4패밀리 → 3 동시 + 1 대기 → 1 완료 시 잔여 1 실행).
> - **참가자 per-call timeout**: 각 참가자 호출은 반드시 `timeout <T>`로 감싼다(권장 T=600s). CLI 자체 timeout(agy `--print-timeout`)만 믿으면 안 된다 — 권한 프롬프트 교착·파일 디스크립터 누수는 CLI 내부 timeout으로 끊기지 않는다.
> - **과반 타임아웃 → 직렬 회귀**: 동시에 띄운 참가자 중 과반(>50%)이 timeout/실패하면 잔여를 **순차 재실행**한다(한 번에 1개씩). 동시성 경합이 원인이면 순차로 회복되는 패턴이 실증됨. quorum(생존 ≥2)만 보면 되므로 2개만 살아도 Fusion은 성립.
> - **기대 시간 요약**(§0.5 비용 요약에 포함): N=참가자수, 평균 T=참가자당 호출시간. 병렬일 때 `≈ T + Judge + Synth`, 순차 회귀 시 `≈ N×T + Judge + Synth`. 참가자 수·대상 규모가 크면 순차 폴백이 수십 분까지 갈 수 있음을 사용자에게 미리 고지.

> **능동 폴링 — per-id manifest 정확 읽기(섞임 방지)**: 각 참가자는 **자기 `$RUN/<id>/manifest`**에만 `round1_exit=`·`family=`를 기록한다(글로벌 `$RUN/manifest`가 아님). 폴링은 **참가자별로** `$RUN/<id>/manifest`를 열어 `round1_exit=` 유무로 완료를 판정하고, `$RUN/<id>/round1.log`의 바이트 크기로 진행 여부를 본다. **절대 여러 참가자 로그를 하나로 합쳐 파싱하지 말 것** — agy의 manifest와 kimi의 로그를 섞어 읽으면 exit=1·logbytes=17748 처럼 다른 참가자의 상태가 뒤섞인 오판이 난다(실제 발생). 폴링 골격:
> ```bash
> # PANEL_IDS=("codex" "gemini" "glm" "kimi")   # §0.2.5에서 확정한 참가자 id 목록
> done_n=0; total=${#PANEL_IDS[@]}
> for id in "${PANEL_IDS[@]}"; do
>   m="$RUN/$id/manifest"
>   if [ -f "$m" ] && grep -q '^round1_exit=' "$m"; then
>     ex=$(sed -n 's/^round1_exit=//p' "$m" | tail -1)
>     done_n=$((done_n + 1))
>     echo "$id: DONE(exit=$ex)"
>   else
>     sz=$([ -f "$RUN/$id/round1.log" ] && wc -c < "$RUN/$id/round1.log" || echo 0)
>     echo "$id: RUNNING(logbytes=$sz)"
>   fi
> done
> echo "완료 $done_n/$total"
> ```
> 위를 매 응답마다 반복하되 `sleep 15~60` 사이에 끼워 넣는다. `$done_n = $total`이면 즉시 §4 FUSE로.

### Fusion-Code — 격리 worktree 병렬
```bash
source "$SKILL_DIR/scripts/council-worktrees.sh"
council_wt_setup "<root>" "$RUN" "$slug" <참가자 id들>
# 반환값 소비(council-worktrees.sh 계약): 0=전부 성공 / 3=부분(일부 worktree 실패) / 1=전부 실패.
rc=$?; case "$rc" in
  0) ;;
  3) echo "WARN: setup 부분성공 — WT_FAIL 난 id는 위임에서 제외(quorum은 생존 family≥2로 §4 판정)." >&2 ;;
  1) echo "BLOCKED: worktree setup 전부 실패 — Fusion 불성립, 중단." >&2 ;;
esac
```
정리는 REPORT 직접 `council_wt_cleanup "<root>" "$RUN"`로 명시 호출(setup·위임·정리를 한 Bash에 안 묶으면 `trap EXIT` 금지). 각 참가자를 자기 worktree에서 — codex `-C`, **agy `( cd && command agy ... -p "..." )`**(agy 1.0.10 파일 검색 스코프 결함 → **`--add-dir "<작업dir 절대경로>"` + 프롬프트 파일 참조는 절대경로만**, routing-fusion.md 특이사항 참조), omo `-d`, opencode `--dir`, **claude `( cd && claude --dangerously-skip-permissions )`**.

### Fusion-Research — read-only 병렬
codex `-s read-only`(강제, live 루트 안전). **codex 외 전 백엔드(agy·opencode·omo·claude)는 강제 샌드박스가 없으므로 읽기전용 사본(`.git` 제외·심링크 차단)에서 `--dangerously-skip-permissions`로 실행**한다 — 로컬 원본 쓰기는 무해(예방), 사후 `git status`는 보조 탐지. ⚠️ `cp -a` 단독은 로컬 in-tree 쓰기만 막고 **네트워크 egress·git push·시크릿·심링크 탈출은 못 막으니** 사본 생성 시 `.git` 제거·`--safe-links`로 좁힌다(`references/fusion.md` §1). 백엔드별 들쭉날쭉을 없앤 통일 규칙. 과거 "권한 프롬프트가 차단(skip 미사용)" 가정은 헤드리스 미검증이라 폐기.
**대형 코드베이스 비용 게이트**: cp 사본은 대상 repo가 크면 수 GB(직전 관측: 6.7GB)가 될 수 있다. 사본 생성 전 반드시 `du -sh`로 크기를 추정하고, 임계값(권장 1GB)을 넘으면 (a) 사용자에게 디스크 비용 경고, (b) 얕은 복제(`git clone --depth 1` 또는 sparse-checkout) 또는 allowlist 복사(`.git`/`node_modules`/`tmp`/빌드 산출물 제외)로 전환, (c) `PLAN_FUSION_NO_RO_COPY=1`로 사본 자체를 생략하고 참가자가 원본을 직접 read-only로 읽게 하는 옵션을 제시한다. ABORT/크래시 시 cleanup이 누락되는 것을 막기 위해, 사본 생성 시점에 `$RUN/ro/CLEANUP_NEEDED` 마커를 두고 **다음 실행 시작 단계**가 stale `$RUN/ro`를 self-heal 정리하도록 한다(trap EXIT가 금지된 대체 안전망).

위임 산출물 세트(참가자별): `$RUN/<id>/manifest`, `$RUN/<id>/round1.log`; **codex 참가자만** `-o`로 `result.md` 생성. **agy/claude/omo/opencode는 `round1.log`가 result**(judge-input엔 `extract_answer`로 최종 텍스트만 추출 — JSON 이벤트·배너 금지, `references/fusion.md` §3-1).
**omo 폴백**: `check-fusion.sh`가 `OMO_RUN_READY=no`(또는 `OMO_PLUGIN_REGISTERED=no`)면 GLM도 **opencode 직접 경로**로 위임한다 — `opencode run -m zai-coding-plan/glm-5.2 --variant high --format json --dir <wt> "$(cat handoff)"`(필수 인자 `-m`/`--dir`/`--format json` 포함, 전체 골격은 `references/fusion.md` §2·`references/opencode-cli.md`). 기본 패널 예시는 omo를 가정하나 omo 미준비 시 자동 폴백.
**부분 실패 + quorum**: 죽은 참가자는 "무응답". **생존 패밀리 ≥2**라야 종합 진행 — 1패밀리만 생존하면 교차검증이 아니므로 단일위임+"Fusion 미성립" 표기로 격하. CLI/인증/플래그 오류 = `ORCHESTRATION_FAIL`(라운드 미산입, 그 참가자만 재시도).

## 4. FUSE — Judge → Synthesizer (plan-fusion의 핵심)

1. **후보 묶음**: 생존 참가자 답변(또는 diff)을 라벨링해 `$RUN/judge-input.md`. ⚠️ **`references/fusion.md` §3-1의 `extract_answer()` 함수를 반드시 그대로 소싱(`source`/복사)해서 쓸 것** — 백엔드별 산출물 포맷(codex `result.md`/opencode JSON `type:text`의 `part.text`/agy·claude ANSI strip)을 이미 다룬 검증된 파서다. **직접 awk·python·jq 파서를 새로 짜지 마라** — 이 스텝에서 자체 파서를 굴리면 포맷 역공학 오류로 빈 본문이 judge-input에 들어가 Judge가 "후보 1개뿐"으로 오판한다(실제 발생한 사고). 조립 스크립트 전문은 §3-1 블록을 그대로 실행한다.
2. **Judge CLI**(`check-fusion.sh`의 `JUDGE_DEFAULT` — 오케스트레이터 패밀리 회피: `ORCH_FAMILY≠claude`면 `claude --print`, 아니면 차순위 비-동족 백엔드): `templates/fusion-judge.md.tmpl` + judge-input → `$RUN/judge.md`(최강후보·합의·충돌·위험주장·**공통맹점/고유통찰**(§4.5)·최종 포함사항). **런타임 폴백 체인**: claude(기본 Judge)가 런타임에 죽어도(주간 한도·인증 만료 등) 즉시 self로 직행하지 않는다. `check-fusion.sh`가 `JUDGE_FALLBACK_CHAIN`(claude→codex→agy→opencode-deepseek→opencode-glm→opencode-kimi→self, 총 7후보)을 산출하고 §3-2가 차순위로 자동 전환한다(`references/fusion.md` §3-2 루프). **DeepSeek 예외**: `ORCH_FAMILY=glm`이면 opencode는 **GLM 예외로 참가자에 필수 포함**되며, DeepSeek 라우트와 glm/kimi 라우트가 Judge 폴백 체인의 별도 후보로도 살아남는다(동종할인 `judge_conflict=partial`/`PARTICIPANT_CONFLICT_RISK=partial` — synthesis 명시). 이것이 "claude가 죽어 Judge를 잃는다"를 막는 핵심 경로.
3. **Synthesizer CLI**(`SYNTH_DEFAULT` — 오케스트레이터 패밀리 회피: `ORCH_FAMILY≠gpt`면 `codex exec`, 아니면 차순위): `templates/fusion-synth.md.tmpl` + 후보 + judge.md → `$RUN/final.md`(Research 최종답변) / `handoff.synth.md`(Code 합성지시).
4. **폴백(절대 막히지 않되, 시간한 명시)**: §4.4의 "폴백"은 "체인이 순회한다"는 뜻이지 무한정 기다린다는 뜻이 아니다. 각 후보는 반드시 `timeout <T>`로 감싼다(Judge=180s, Synth=600s 권장). 체인 전체 wall-clock cap(권장 900s = 15분)을 두고, 초과 시 즉시 오케스트레이터 직접 판정·합성으로 전환(스킬 본문에 "정상 경로 붕괴"로 표기). per-call timeout 발생 시 해당 후보를 dead 처리하고 차순위로 넘기는 명시 규칙(`references/fusion.md` §3-2 루프에 `--time` 인자로 주입). Judge CLI 실패 → §3-2 체인이 차순위 후보로 순회(전 후보 실패 시에만 오케스트레이터 직접 판정 + 표기). Synth CLI 실패 → 차순위 CLI 또는 오케스트레이터 합성 + 표기. **Judge 백엔드 동족 라벨** — `JUDGE_CONFLICT_RISK=yes`(=self, 완전 비독립) 또는 `judge_conflict=partial`(=opencode-deepseek, 동종할인)이면 synthesis에 해당 할인 문구 명시.

## 5. VERIFY / SYNTHESIZE / REPORT (오케스트레이터 불가양도)

### 검증
- **Fusion-Research**: `final.md`를 그대로 신뢰하지 않는다. Judge가 표시한 **위험·미검증 주장을 오케스트레이터가 코드 grep으로 사실 판정**(다수결 금지). 충돌점은 근거 기반 결론.
  - **Judge 맹점 보강**: Judge→Synth 직렬 구조라 Judge가 놓친 위험은 Synth로 고착된다. 그래서 오케스트레이터는 Judge가 표시한 항목**만** 검증하지 말고, 핵심 주장 1~2개는 **독립적으로 추가 spot-check**한다(Judge 커버리지에 종속되지 않기 위해). ⚠️ Judge가 `fusion-judge.md.tmpl` §4.5에서 **blind_spots=없음**으로 보고해도 이 독립 spot-check 의무는 **불변**이다 — Judge 자기보고가 오케스트레이터 검증을 약화하지 못하게 한다(맹점은 정의상 Judge도 못 본 것).
  - **상관 맹점(correlated blindness) 방어 — 합의에 대한 적대적 falsification**: 직전 실행에서 패널 4/4가 동일한 오독("보안 갭")을 공유해 Judge→Synth→최종 보고서로 고착된 사례가 있었다. Judge는 후보 *간* 차이를 비교하는 구조라 **모든 후보가 같은 오류를 공유하면 정답측이 없어 잡을 수 없다**. 따라서:
    1. **만장일치/과반 합의 주장 중 최소 1개**는 오케스트레이터가 **부정 시도(red-team)**를 수행한다 — "이 합의가 틀렸다면 어떤 증거가 있어야 하는가?"를 정하고 그 증거를 직접 코드/문서에서 찾는다(단순 확인이 아닌 반박 시도).
    2. spot-check 과녁은 "Judge가 지적한 위험"이 아니라 **"합의된 전제"**에서 선정한다. 합의의 결론이 아니라 그 결론이 세워진 전제(예: "X 기능이 없다"·"Y 게이트가 없다"·"Z 파일이 그 역할을 안 한다")를 직접 코드에서 확인.
    3. 외부 근거가 답을 가르는 task(§1 선fetch 의무 참조)에서는 합의 주장을 외부 출처와 대조하는 것까지 확장.
    4. **uncontested consensus 라벨**: Judge가 모든 후보 동일 주장을 `uncontested_consensus: true`로 보고하면(`fusion-judge.md.tmpl` §4.5 필드), 오케스트레이터 red-team 의무가 자동으로 강제 트리거된다 — 이 라벨이 있으면 spot-check 1~2개로 끝내지 않고 합의 전제 전부를 과녁으로 삼는다.
- **Fusion-Code**: 합성/채택을 메인 반영 후 **직접 실행 증거로 검증** — 빌드·타입·테스트·린트 Bash 실행, exit·출력 인용, Acceptance Criteria 항목별 대조, baseline·범위 확인. result/final 주장은 근거 아님.
- **UI 노출 작업이면(HANDOFF 'UI 노출 판정=yes')**: 디자인 스펙(타이포/컬러/간격/레이아웃)이 구현에 반영되었는지 대조 + UI Acceptance Criteria(예: 주요 화면 before/after 스크린샷 대조) 충족 확인. 구현이 스펙을 따르지 않거나 UI 부분이 빠졌으면 **FAIL → 백엔드 재위임**(오케스트레이터 자가치유 금지 — 역할 경계).
- `templates/synthesis.md.tmpl`로 `$RUN/synthesis.md`(Judge판정·Synth최종·**오케스트레이터 검증증거**·교차리뷰·판정근거).

### 적용 (Fusion-Code)
- 단일 채택: `council_wt_adopt "<root>" "$RUN" "<id>"`(드리프트 체크 + `apply --3way`). 장점 합성: **먼저 `council_wt_setup "<root>" "$RUN" "$slug" final`로 합성 worktree를 만든 뒤**(이 단계 없이는 `$RUN/wt/final` 부재로 adopt가 ABORT) `handoff.synth.md`를 한 백엔드에 `$RUN/wt/final`로 최종 위임 → 검증 후 `council_wt_adopt "<root>" "$RUN" final`.
- 미달 시 최종 백엔드 세션 resume(최대 3라운드, `ORCHESTRATION_FAIL` 미산입). 방향 틀렸으면 fresh 재위임.

### loop-md 연동
루트에 `loop.md` 있으면 loop-md 연동은 다음 순서로 고정한다(**완료 보고 먼저, 무거운 DoD 검증은 그 후** — 지연 방지):
1. `council_wt_adopt`로 메인 반영.
2. **사용자에게 합성/채택 결과·변경 파일·AC 충족을 먼저 보고** (다른 동기 스킬처럼 완료 즉시 알림).
3. **그 다음** **메인 ROOT에서** loop-md Verify 전체 ①Pass/Fail·②정량·③정성 실행 → `.loop/last-verified`가 현재 HEAD인지 확인 → 커밋.
패널 worktree 검증은 사전검증일 뿐 hard-guard 충족이 아니다. 루트에 `loop.md` 없으면 이 절차(마커 갱신)와 Judge ③루브릭 주입 모두 N/A.

Judge는 후보 비교용으로 loop-md ③정성(fresh-context 채점)과 입력·목적이 다르다. `loop.md` 감지 시 Judge 입력에 loop.md ③루브릭 + ①② 실행로그를 조건부 주입해 ③을 실제 충족하고, ②정량(커버리지 등)은 메인 검증 단계에서 loop.md 명령으로 직접 실행한다.

### REPORT
- **모드**(Fusion-Code/Research) · **참가자·모델·effort**(배너 실효값) · **Judge/Synth 백엔드**(+비독립 여부)
- 참가자별 상태(DONE/BLOCKED/ORCHESTRATION_FAIL/무응답) + (선택) `ORCHESTRATION_FAIL`엔 **failure_reason 라벨**(`credits`/`rate_limit`/`auth`/`flag_error`/`timeout`/`unknown`) 부착 — 관찰가능성용 표기일 뿐 **자동 재시도 분기는 하지 않는다**(CLI별 stderr 포맷 불안정 → 오탐 위험. 재시도 정책은 문서 가이드로만: credits=포기, rate_limit=후재시도, auth/flag_error=설정·스킬 수정, `references/fusion.md` §2).
- **Judge 판정요지 + Synth 최종 + 오케스트레이터 검증증거**(grep·diff·테스트)
- 채택 vs 합성 경로 · 최종 변경 파일 + 기준별 충족 증거
- **BLOCKED·적용한 기본 결정·남은 질문**(분리) · 라운드 수(+`ORCHESTRATION_FAIL` 횟수)
- `$RUN` 경로(handoff/judge/final/synthesis/diff/xreview/manifest/final.patch) · UI면 before/after 경로
- REPORT 직전 `council_wt_cleanup "<root>" "$RUN"` 1회 + **`rm -rf "$RUN/ro"`(모드 무관 — Research 참가자 사본·Code 모드 xreview 사본 둘 다 `ro/` 사용)**(council_wt_cleanup은 `wt/`·`council/*`만 다루고 `ro/`는 안 지운다 → 디스크·민감코드 사본 누수) + **누수 점검**: `git -C "<root>" worktree list` council 잔존 0 + `git -C "<root>" branch --list 'council/*'` 잔존 0 + `[ ! -d "$RUN/ro" ]`(1줄)

---

## 역할 경계 (절대 규칙)

- 오케스트레이터는 **분석·계획·검증·사실확인**만. 종합은 Judge·Synth CLI에 위임하되, **그 결과를 직접 코드로 고치지 않고** 검증 후 문제는 백엔드에 되돌린다(resume 또는 합성 HANDOFF).
- 최종 코드 작성 주체는 **항상 백엔드**. `council_wt_adopt`의 patch apply·Synth의 합성지시는 새 변경 생성이 아니다.
- 참가자는 재계획·범위 확장·무관 리팩토링 금지(HANDOFF에 명시).
- loop-md ① 게이트 FAIL 시 — 기계적 린트/포맷 위반은 오케스트레이터 자가치유 허용(예외), 설계·로직 변경은 백엔드 재위임.
- 인간 승인 영역(스키마/보안/키·시크릿/결제/배포/PRD범위/아키텍처)은 자동 진행 금지 — BLOCKED로.

## 이 스킬을 쓰지 말아야 할 때

- **단순 교차검증**(종합을 CLI에 위임할 필요 없이 오케스트레이터가 직접 비교·종합) → **plan-codex-opencode**가 더 가볍다.
- **단일 모델 위임** → **plan-then-codex**(codex 단독) 또는 **plan-then-opencode**(omo 단독).
- **비용/시간이 가치를 못 넘을 때**: N참가자 + Judge + Synth = 단일 위임의 **N+2배 이상** 호출(고추론 5패밀리는 수십 분). 사소·저위험·되돌리기 쉬운 작업이거나, **답이 갈릴 여지가 작은** 작업이면 비용 대비 이득이 없다 → plan-then-* 단일 위임이나 오케스트레이터 단독으로. Fusion은 **답이 갈릴 수 있고 틀리면 비용이 큰** 구현·판단에 한정한다.
- plan-fusion은 **명시적 Judge→Synthesizer CLI 합성**이 필요하고 **Gemini(agy)·Opus(claude)까지 패밀리를 넓힐 때**의 오케스트레이션이다.
