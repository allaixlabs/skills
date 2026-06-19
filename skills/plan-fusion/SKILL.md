---
name: plan-fusion
description: >
  CLI Fusion 워크플로우 — 같은 작업을 서로 다른 AI 모델 패밀리에 각자의 CLI로 독립 실행시킨 뒤,
  Judge CLI가 후보를 비교·평가하고 Synthesizer CLI가 최종 답변을 합성하면 오케스트레이터가 검증한다.
  오케스트레이터는 자동 감지된다(ZCode/GLM, Codex CLI/GPT, AGY/Gemini, Claude/Opus) — 감지된 패밀리는
  참가자·Judge·Synth에서 제외된다(동족 회피). 백엔드: codex(GPT)·agy(Gemini)·opencode/omo(GLM·Kimi·DeepSeek 등)·claude(Opus).
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

0. **오케스트레이터 감지**(맨 처음, §1 ANALYZE보다 먼저): `check-fusion.sh`가 env `PLAN_FUSION_ORCHESTRATOR=glm|gpt|gemini|claude`(없으면 argv `${1}` 폴백, 둘 다 없으면 `unknown`)를 읽어 `ORCHESTRATOR_FAMILY`·`ORCHESTRATOR_BACKEND`·`EXCLUDED_FAMILIES`·`ORCH_FAMILY_EXCLUDED`·`JUDGE_DEFAULT`/`SYNTH_DEFAULT`(오케스트레이터 패밀리 회피)·`JUDGE_CONFLICT_RISK`/`SYNTH_CONFLICT_RISK`를 내보낸다. 감지된 패밀리는 동족(확증편향) 회피를 위해 **참가자·Judge·Synth 후보에서 자동 제외**된다(`EXCLUDED_FAMILIES`로 사유 표시). `unknown`이면 제외 룰 비활성(모든 패밀리 가용 후보).
   - 패밀리 매핑: `glm`→opencode(GLM/Kimi) · `gpt`→codex · `gemini`→agy · `claude`→claude(Opus).
   - 헤드리스(cron·자동화)에서도 결정론적 — env로 못 박거나, 대화형이면 §0.2.5 게이트에서 사용자에게 확정받는다.

1. **사전 점검**(read-only): `bash "$SKILL_DIR/scripts/check-fusion.sh"` → `CODEX/AGY/OPENCODE/CLAUDE_BACKEND_READY` · `ORCHESTRATOR_FAMILY`·`EXCLUDED_FAMILIES`·`ORCH_FAMILY_EXCLUDED` · `PARTICIPANT_FAMILIES` · `EFFECTIVE_BACKENDS` · `JUDGE_DEFAULT`/`SYNTH_DEFAULT`(+`JUDGE_CONFLICT_RISK`/`SYNTH_CONFLICT_RISK`) · `JUDGE_FALLBACK_CHAIN`·`JUDGE_DEEPSEEK_READY`(런타임 Judge 폴백 — claude死 시 차순위 자동 전환, §3-2) · provider 인증 매트릭스(`MODEL_READY_GLM`/`MODEL_READY_KIMI`/`MODEL_READY_DEEPSEEK`) · `FUSION_CAPABILITY`. 차단 게이트는 `EFFECTIVE_BACKENDS`(= 비-오케스트레이터 참가자 패밀리 + 비-오케스트레이터 claude-as-participant 후보) 기준이다 — **`EFFECTIVE_BACKENDS`<2면 exit 1**(Fusion 불성립, plan-then-* 또는 누락 백엔드 설정 안내·중단). 독립 백엔드가 2면 통과(exit 0). ⚠️ 단 그 경우 **비-오케스트레이터 패밀리를 '참가자'로 써야** 교차검증 2패밀리가 된다 — Judge-only default로만 쓰면 참가자 1패밀리뿐이라 런타임 quorum(§4)이 'Fusion 미성립'으로 격하한다(preflight는 이를 `FUSION_CAPABILITY=conditional`로 표기).
2. **호명 파싱**(`references/routing-fusion.md`): 부른 모델("gpt5.5, gemini, glm5.2, kimi")을 각각 `(backend, model, effort/variant, dir/session 플래그)`로 정규화. **호명 없으면 기본 패널 추천**(default: 오케스트레이터 패밀리를 제외한 비-동족 패밀리들 — Judge=오케스트레이터 패밀리 회피 `JUDGE_DEFAULT`, Synth=`SYNTH_DEFAULT`, 상세는 라우팅 문서 변형표) + **1줄 이유**. 프리셋(highEnd/codeSecurity/fullPower/budget)은 라우팅 문서 표 참조.
   - **disabledModels**: `fable-5`·`mythos-5`는 참가자·Judge·Synth 어디에도 쓰지 않는다(사용자 정책).
   - **동족 경고(일반화)**: 오케스트레이터 패밀리(§0.0 감지값, 예: `glm`/`gpt`/`gemini`/`claude`)가 참가자·Judge·Synth 중 어디에 또 쓰이면 동족(확증편향)이다. `check-fusion.sh`가 그 패밀리를 `EXCLUDED_FAMILIES`로 이미 빼지만, 호명이나 프리셋이 명시적으로 그 패밀리를 다시 넣으려 하면 게이트가 노출하고 synthesis에 "비독립(동족) 할인"을 명시한다. `ORCH_FAMILY=unknown`이면 동족 룰 비활성.
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
   printf 'mode=%s\npanel=%s\njudge=%s\nsynth=%s\nfence=%s\nselected_family_count=%s\norchestrator_family=%s\njudge_fallback_chain=%s\n' "<Fusion-Code|Fusion-Research>" "<참가자 id들>" "<judge>" "<synth>" "$fence" "<2.5 확정 독립패밀리 수>" "<glm|gpt|gemini|claude|unknown>" "<check-fusion.sh JUDGE_FALLBACK_CHAIN 산출값>" >> "$RUN/manifest"
   # ⚠️ placeholder 치환 검증(작성 직후 1회): mode·selected_family_count·orchestrator_family가 실제 리터럴/숫자로 치환됐는지 확인한다 —
   #    미치환 시 §4 Synth(mode case ABORT)·quorum 축소비교(selected_family_count 비숫자 → '[: integer expression expected')·
   #    동족 판정(orchestrator_family 미치환 → Judge/Synth 비독립 표기 누락)이 깨진다.
   grep -qE '^mode=(Fusion-Code|Fusion-Research)$' "$RUN/manifest" || { echo "ABORT: manifest mode 미치환/오타 — §0.4 placeholder 확인." >&2; exit 1; }
   grep -qE '^selected_family_count=[0-9]+$' "$RUN/manifest" || { echo "ABORT: manifest selected_family_count 비숫자/미치환 — §0.4 placeholder 확인." >&2; exit 1; }
   grep -qE '^orchestrator_family=(glm|gpt|gemini|claude|unknown)$' "$RUN/manifest" || { echo "ABORT: manifest orchestrator_family 미치환/오타 — §0.4 placeholder 확인." >&2; exit 1; }
   # panel/judge/synth도 빈값·'<…>' placeholder 잔존이면 ABORT(검증 일관성 — 미치환이 §3-1 동적수집·§3-3 Synth로 샘)
   for k in panel judge synth; do v=$(sed -n "s/^$k=//p" "$RUN/manifest" | head -1)
     case "$v" in ''|*'<'*'>'*) echo "ABORT: manifest $k 미치환/빈값('$v') — §0.4 placeholder 확인." >&2; exit 1;; esac; done
   # judge_fallback_chain 검증: 빈값·'<…>' placeholder 잔존 금지(미치환 시 §3-2 루프 ABORT). 최소 1개 후보(self 포함) 있어야 한다.
   _jfc=$(sed -n 's/^judge_fallback_chain=//p' "$RUN/manifest" | head -1)
   case "$_jfc" in ''|*'<'*'>'*) echo "ABORT: manifest judge_fallback_chain 미치환/빈값('$_jfc') — §0.4에서 check-fusion.sh JUDGE_FALLBACK_CHAIN 치환 확인." >&2; exit 1;; esac
   ```
5. **패널·모드·Judge·Synth·각 백엔드 플래그 + 예상 비용/시간을 1회 요약** → **2.5 `GATE_CASE`별 확인/선택 후 진행**(**자동 진행은 case A·headless 명시 정책만**; 그 외 silent-fallback 금지) — N참가자 + Judge 1 + Synth 1은 단일 위임의 N+2배 이상 호출이다(agy `--print-timeout`은 일반 장기실행은 차단하나 **권한프롬프트 교착은 못 끊는다**(→ `--dangerously-skip-permissions` 병행, references 참조), omo는 자체 타임아웃 없음 → 백그라운드+완료알림). 인간 승인 영역(스키마/보안/키·시크릿/결제/배포/PRD범위/아키텍처)이면 여기서 BLOCKED.

## 1. ANALYZE

오케스트레이터가 코드·실행 페이지를 직접 분석. 변경 대상·스택·빌드/테스트/린트 명령·인간 승인 영역 식별. UI면 스크린샷 → 텍스트 스펙.
**Fusion-Research**면 질문을 **검증가능한 하위 질문(Q1..Qn)**으로 분해 — Judge 평가·오케스트레이터 사실확인의 축이 된다.
- **UI 노출 판정(필수)**: 이 작업이 사용자에게 노출되는 변경인가(새 화면·컴포넌트·라우트·상호작용·표시 로직)를 yes/no로 판정하고 **1줄 근거**를 HANDOFF의 'UI 노출 판정' 필드에 기록한다.
  - yes → HANDOFF의 '디자인 스펙' 섹션 + UI Acceptance Criteria를 필수화(아래 §2 PLAN · §5 VERIFY · `templates/fusion-judge.md.tmpl`·`fusion-synth.md.tmpl` 연동).
  - no → '디자인 스펙' 생략 가능하되, **근거 없는 no는 금지** — 판정 사유를 HANDOFF에 명시해 감사 가능성을 유지한다.
- **외부정보 선fetch 의무**: 참가자는 read-only 사본에서 돌아 네트워크가 막혀 있다(OpenRouter panel처럼 자체 web 없음). 최신 문서·API·외부 근거가 필요하면 **오케스트레이터가 §1에서 직접 fetch해 HANDOFF에 발췌+출처로 첨부**한다(참가자는 제공 자료+로컬 사본만으로 분석). 단 발췌는 **요약·핵심만**(전문 무제한 인라인은 참가자 argv `E2BIG` 위험 → `references/fusion.md` §2). ⚠️ 선fetch를 누락하면 **상관 맹점**(전 패널이 같은 정보 공백 공유 → 교차검증 독립성 무력화)이 생기므로, 외부근거가 답을 가르는 task면 fetch 품질이 패널 전체의 단일 실패점임을 인지한다.

## 2. PLAN — HANDOFF 작성 (모든 참가자가 공유하는 단일 스펙)

- 코드: `templates/HANDOFF.md.tmpl` / 비코드: `templates/HANDOFF-research.md.tmpl` → `"$RUN/handoff.md"`.
- **단일 HANDOFF 원칙**: 같은 스펙을 모든 참가자에 동일하게 — 교차검증 공정성. 백엔드별 차이(에이전트·sandbox·dir·skip-permissions)는 본문이 아니라 **호출 플래그**로만.
- 자기완결성: 참가자는 대화 컨텍스트를 모른다. Baseline·Out-of-scope·BLOCKED 프로토콜·실행가능 Acceptance Criteria를 문서에 다 담는다.
- baseline 스냅샷(코드): `git -C "<root>" status --short > "$RUN/baseline.status"` · `git -C "<root>" rev-parse HEAD > "$RUN/baseline.head"`.

## 3. DELEGATE — 참가자 병렬 (전부 백그라운드 + 참가자별 manifest)

> 각 참가자는 **별도 Bash `run_in_background: true`**(한 셸 `&` 금지). 산출물 `$RUN/<id>/`. **모든 참가자 완료 알림 후에만** read(race 방지). **완료 알림(`Background task completed` / `task-notification`)이 도착하면 즉시** 결과 read → §4 FUSE로 넘어간다 — "기다리겠다"며 멈추거나 안내문만 출력하지 않는다("전 read 금지"는 알림 **후** 진행이 아니라 **전** race만 막는다). 셸 상세·5-CLI경로 호출은 `references/fusion.md` §2 · `references/cli-fusion-map.md`.

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

위임 산출물 세트(참가자별): `$RUN/<id>/manifest`, `$RUN/<id>/round1.log`; **codex 참가자만** `-o`로 `result.md` 생성. **agy/claude/omo/opencode는 `round1.log`가 result**(judge-input엔 `extract_answer`로 최종 텍스트만 추출 — JSON 이벤트·배너 금지, `references/fusion.md` §3-1).
**omo 폴백**: `check-fusion.sh`가 `OMO_RUN_READY=no`(또는 `OMO_PLUGIN_REGISTERED=no`)면 GLM도 **opencode 직접 경로**로 위임한다 — `opencode run -m zai-coding-plan/glm-5.2 --variant high --format json --dir <wt> "$(cat handoff)"`(필수 인자 `-m`/`--dir`/`--format json` 포함, 전체 골격은 `references/fusion.md` §2·`references/opencode-cli.md`). 기본 패널 예시는 omo를 가정하나 omo 미준비 시 자동 폴백.
**부분 실패 + quorum**: 죽은 참가자는 "무응답". **생존 패밀리 ≥2**라야 종합 진행 — 1패밀리만 생존하면 교차검증이 아니므로 단일위임+"Fusion 미성립" 표기로 격하. CLI/인증/플래그 오류 = `ORCHESTRATION_FAIL`(라운드 미산입, 그 참가자만 재시도).

## 4. FUSE — Judge → Synthesizer (plan-fusion의 핵심)

1. **후보 묶음**: 생존 참가자 답변(또는 diff)을 라벨링해 `$RUN/judge-input.md` (`references/fusion.md` §3-1).
2. **Judge CLI**(`check-fusion.sh`의 `JUDGE_DEFAULT` — 오케스트레이터 패밀리 회피: `ORCH_FAMILY≠claude`면 `claude --print`, 아니면 차순위 비-동족 백엔드): `templates/fusion-judge.md.tmpl` + judge-input → `$RUN/judge.md`(최강후보·합의·충돌·위험주장·**공통맹점/고유통찰**(§4.5)·최종 포함사항). **런타임 폴백 체인**: claude(기본 Judge)가 런타임에 죽어도(주간 한도·인증 만료 등) 즉시 self로 직행하지 않는다. `check-fusion.sh`가 `JUDGE_FALLBACK_CHAIN`(claude→codex→agy→opencode-deepseek→self)을 산출하고 §3-2가 차순위로 자동 전환한다(`references/fusion.md` §3-2 루프). **DeepSeek 예외**: `ORCH_FAMILY=glm`이면 opencode는 *참가자* 집계에서 제외되지만, DeepSeek 라우트는 Judge 후보로 살아남는다(동종할인 `judge_conflict=partial` — synthesis 명시). 이것이 "claude가 죽어 Judge를 잃는다"를 막는 핵심 경로.
3. **Synthesizer CLI**(`SYNTH_DEFAULT` — 오케스트레이터 패밀리 회피: `ORCH_FAMILY≠gpt`면 `codex exec`, 아니면 차순위): `templates/fusion-synth.md.tmpl` + 후보 + judge.md → `$RUN/final.md`(Research 최종답변) / `handoff.synth.md`(Code 합성지시).
4. **폴백(절대 막히지 않음)**: Judge CLI 실패 → §3-2 체인이 차순위 후보로 순회(전 후보 실패 시에만 오케스트레이터 직접 판정 + 표기). Synth CLI 실패 → 차순위 CLI 또는 오케스트레이터 합성 + 표기. **Judge 백엔드 동족 라벨** — `JUDGE_CONFLICT_RISK=yes`(=self, 완전 비독립) 또는 `judge_conflict=partial`(=opencode-deepseek, 동종할인)이면 synthesis에 해당 할인 문구 명시.

## 5. VERIFY / SYNTHESIZE / REPORT (오케스트레이터 불가양도)

### 검증
- **Fusion-Research**: `final.md`를 그대로 신뢰하지 않는다. Judge가 표시한 **위험·미검증 주장을 오케스트레이터가 코드 grep으로 사실 판정**(다수결 금지). 충돌점은 근거 기반 결론.
  - **Judge 맹점 보강**: Judge→Synth 직렬 구조라 Judge가 놓친 위험은 Synth로 고착된다. 그래서 오케스트레이터는 Judge가 표시한 항목**만** 검증하지 말고, 핵심 주장 1~2개는 **독립적으로 추가 spot-check**한다(Judge 커버리지에 종속되지 않기 위해). ⚠️ Judge가 `fusion-judge.md.tmpl` §4.5에서 **blind_spots=없음**으로 보고해도 이 독립 spot-check 의무는 **불변**이다 — Judge 자기보고가 오케스트레이터 검증을 약화하지 못하게 한다(맹점은 정의상 Judge도 못 본 것).
- **Fusion-Code**: 합성/채택을 메인 반영 후 **직접 실행 증거로 검증** — 빌드·타입·테스트·린트 Bash 실행, exit·출력 인용, Acceptance Criteria 항목별 대조, baseline·범위 확인. result/final 주장은 근거 아님.
- **UI 노출 작업이면(HANDOFF 'UI 노출 판정=yes')**: 디자인 스펙(타이포/컬러/간격/레이아웃)이 구현에 반영되었는지 대조 + UI Acceptance Criteria(예: 주요 화면 before/after 스크린샷 대조) 충족 확인. 구현이 스펙을 따르지 않거나 UI 부분이 빠졌으면 **FAIL → 백엔드 재위임**(오케스트레이터 자가치유 금지 — 역할 경계).
- `templates/synthesis.md.tmpl`로 `$RUN/synthesis.md`(Judge판정·Synth최종·**오케스트레이터 검증증거**·교차리뷰·판정근거).

### 적용 (Fusion-Code)
- 단일 채택: `council_wt_adopt "<root>" "$RUN" "<id>"`(드리프트 체크 + `apply --3way`). 장점 합성: **먼저 `council_wt_setup "<root>" "$RUN" "$slug" final`로 합성 worktree를 만든 뒤**(이 단계 없이는 `$RUN/wt/final` 부재로 adopt가 ABORT) `handoff.synth.md`를 한 백엔드에 `$RUN/wt/final`로 최종 위임 → 검증 후 `council_wt_adopt "<root>" "$RUN" final`.
- 미달 시 최종 백엔드 세션 resume(최대 3라운드, `ORCHESTRATION_FAIL` 미산입). 방향 틀렸으면 fresh 재위임.

### loop-md 연동
루트에 `loop.md` 있으면 loop-md 연동은 다음 순서로 고정한다: `council_wt_adopt` → **메인 ROOT에서** loop-md Verify 전체 ①Pass/Fail·②정량·③정성 실행 → `.loop/last-verified`가 현재 HEAD인지 확인 → 그 다음 커밋. 패널 worktree 검증은 사전검증일 뿐 hard-guard 충족이 아니다. 루트에 `loop.md` 없으면 이 절차(마커 갱신)와 Judge ③루브릭 주입 모두 N/A.

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
