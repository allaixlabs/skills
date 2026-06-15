---
name: plan-fusion
description: >
  CLI Fusion 워크플로우 — 같은 작업을 서로 다른 AI 모델 패밀리에 각자의 CLI로 독립 실행시킨 뒤,
  Judge CLI가 후보를 비교·평가하고 Synthesizer CLI가 최종 답변을 합성하면 Claude가 검증한다.
  백엔드: codex(GPT) · agy(Gemini) · opencode/omo(GLM·Kimi·DeepSeek 등) · claude(Opus, 기본 Judge).
  다음일 때 사용: "gemini까지 넣어서 fusion으로", "GPT랑 Gemini, GLM, Kimi로 풀고 Judge·Synth로 합성해",
  "여러 CLI로 독립 실행하고 Opus가 판정·GPT가 종합", "agy로 gemini도 패널에 넣어", "judge synthesizer 구조로",
  "5개 모델 fusion"(모델 5 / 백엔드 4). 종합을 CLI에 위임하지 않고 Claude가 직접 종합하는 단순 교차검증이면 plan-codex-opencode를,
  단일 모델 위임이면 plan-then-codex / plan-then-opencode를 쓴다.
---

# plan-fusion — CLI Fusion (참가자 → Judge → Synthesizer → 검증)

**Claude = 두뇌**(분석·계획·패널선택·**검증·사실확인**). **CLI들 = 손**: 같은 문제를 각 패밀리가 독립 실행. **합성 = Judge CLI + Synthesizer CLI에 위임**.

핵심 가치: codex(GPT)·agy(Gemini)·opencode(GLM/Kimi)는 **서로 다른 모델 패밀리** → 같은 문제에서 다른 실수 → 교차검증 독립성. plan-codex-opencode와의 차이는 **종합을 Claude가 직접 하지 않고 명시적 Judge→Synthesizer CLI로 위임**한다는 것(Claude는 검증만 불가양도). agy(Gemini)·claude(Opus)를 더해 **모델 최대 5 / 백엔드 패밀리 4**(codex·agy·opencode·claude).
GLM·Kimi는 같은 opencode 백엔드(런타임·인증 공유)라 **모델 다양성**은 있으나 백엔드 독립성은 codex/agy와 동급이 아니다 — '모델 다양성'과 '백엔드 다양성'을 구분한다.

- `SKILL_DIR` = 이 SKILL.md가 있는 디렉토리. `$RUN` = 이번 위임의 격리 폴더(0단계 생성).
- `PANEL` = 참가자 목록(각 원소 `id|backend|model`, id는 `[a-z0-9-]` 슬러그). `JUDGE`·`SYNTH` = 각 1개 백엔드.
- 레퍼런스: 라우팅 `references/routing-fusion.md` · 5-백엔드 `references/cli-fusion-map.md` · codex `references/codex-cli.md` · opencode/omo `references/opencode-cli.md` · 격리·Judge·Synth `references/fusion.md`.

---

## 0. 사전점검 + 요청 파싱 + 모드/패널 결정

1. **사전 점검**(read-only): `bash "$SKILL_DIR/scripts/check-fusion.sh"` → `CODEX/AGY/OPENCODE/CLAUDE_BACKEND_READY` · `PARTICIPANT_FAMILIES` · `JUDGE_DEFAULT`/`SYNTH_DEFAULT` · provider 인증 매트릭스 · `FUSION_CAPABILITY`. 참가자 백엔드 <2(exit 1)면 Fusion 불성립 — plan-then-* 또는 누락 백엔드 설정을 안내·중단.
2. **호명 파싱**(`references/routing-fusion.md`): 부른 모델("gpt5.5, gemini, glm5.2, kimi")을 각각 `(backend, model, effort/variant, dir/session 플래그)`로 정규화. **호명 없으면 기본 패널 추천**(default: GPT·Gemini·GLM·Kimi **4개 모델**(백엔드는 codex·agy·opencode **3개**), Judge=Opus, Synth=GPT) + **1줄 이유**. 프리셋(highEnd/codeSecurity/fullPower/budget)은 라우팅 문서 표 참조.
   - **disabledModels**: `fable-5`·`mythos-5`는 참가자·Judge·Synth 어디에도 쓰지 않는다(사용자 정책).
   - **동족 경고**: 오케스트레이터가 Opus다. Opus가 참가자이면서 Judge면 자기심사 확증편향 → 기본은 Opus=Judge 전용, 참가 프리셋이면 Judge를 Gemini로 바꾸거나 synthesis에 "Judge 비독립" 명시.
3. **모드 선택**:
   - 파일 변경 없는 분석/리서치/설계 질문, "여러 모델로 풀어 정리" → **Fusion-Research**(read-only).
   - 코드 구현 + 신뢰도↑ → **Fusion-Code**(worktree 격리 병렬 → Judge → Synth → 적용 → 검증).
4. **격리 폴더**:
   ```bash
   slug=$(printf '%s' "<task 한단어>" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | cut -c1-20)
   RUN=$(umask 077; mktemp -d "${TMPDIR:-/tmp}/pf.${slug}.XXXXXX") || { echo "RUN 생성 실패" >&2; exit 1; }
   [ -d "$RUN" ] || { echo "RUN 생성 실패" >&2; exit 1; }
   printf 'mode=%s\npanel=%s\njudge=%s\nsynth=%s\n' "<모드>" "<참가자 id들>" "<judge>" "<synth>" >> "$RUN/manifest"
   ```
5. **패널·모드·Judge·Synth·각 백엔드 플래그 + 예상 비용/시간을 1회 요약**하고 진행 — N참가자 + Judge 1 + Synth 1은 단일 위임의 N+2배 이상 호출이다(agy `--print-timeout`은 일반 장기실행은 차단하나 **권한프롬프트 교착은 못 끊는다**(→ `--dangerously-skip-permissions` 병행, references 참조), omo는 자체 타임아웃 없음 → 백그라운드+완료알림). 인간 승인 영역(스키마/보안/키·시크릿/결제/배포/PRD범위/아키텍처)이면 여기서 BLOCKED.

## 1. ANALYZE

Claude가 코드·실행 페이지를 직접 분석. 변경 대상·스택·빌드/테스트/린트 명령·인간 승인 영역 식별. UI면 스크린샷 → 텍스트 스펙.
**Fusion-Research**면 질문을 **검증가능한 하위 질문(Q1..Qn)**으로 분해 — Judge 평가·Claude 사실확인의 축이 된다.

## 2. PLAN — HANDOFF 작성 (모든 참가자가 공유하는 단일 스펙)

- 코드: `templates/HANDOFF.md.tmpl` / 비코드: `templates/HANDOFF-research.md.tmpl` → `"$RUN/handoff.md"`.
- **단일 HANDOFF 원칙**: 같은 스펙을 모든 참가자에 동일하게 — 교차검증 공정성. 백엔드별 차이(에이전트·sandbox·dir·skip-permissions)는 본문이 아니라 **호출 플래그**로만.
- 자기완결성: 참가자는 대화 컨텍스트를 모른다. Baseline·Out-of-scope·BLOCKED 프로토콜·실행가능 Acceptance Criteria를 문서에 다 담는다.
- baseline 스냅샷(코드): `git -C "<root>" status --short > "$RUN/baseline.status"` · `git -C "<root>" rev-parse HEAD > "$RUN/baseline.head"`.

## 3. DELEGATE — 참가자 병렬 (전부 백그라운드 + 참가자별 manifest)

> 각 참가자는 **별도 Bash `run_in_background: true`**(한 셸 `&` 금지). 산출물 `$RUN/<id>/`. **모든 참가자 완료 알림 후에만** read(race 방지). 셸 상세·5-백엔드 호출은 `references/fusion.md` §2 · `references/cli-fusion-map.md`.

### Fusion-Code — 격리 worktree 병렬
```bash
source "$SKILL_DIR/scripts/council-worktrees.sh"
council_wt_setup "<root>" "$RUN" "$slug" <참가자 id들>
```
정리는 REPORT 직전 `council_wt_cleanup "<root>" "$RUN"`로 명시 호출(setup·위임·정리를 한 Bash에 안 묶으면 `trap EXIT` 금지). 각 참가자를 자기 worktree에서 — codex `-C`, **agy `( cd && command agy --dangerously-skip-permissions )`**, omo `-d`, opencode `--dir`, **claude `( cd && claude --dangerously-skip-permissions )`**.

### Fusion-Research — read-only 병렬
codex `-s read-only`(강제). **agy/opencode/omo/claude는 강제 샌드박스 없음** → 쓰기금지 지시 + skip-permissions 미사용(**단 agy는 권한 교착 회피 위해 읽기전용 `cp -a` 사본에서 `--dangerously-skip-permissions` 사용 — 예외**) + 사후 `git status` 오염검사(예방 아닌 탐지). 민감 레포는 읽기전용 사본(`cp -a`)에서 실행(`references/fusion.md` §1).

위임 산출물 세트(참가자별): `$RUN/<id>/manifest`, `$RUN/<id>/round1.log`; **codex 참가자만** `-o`로 `result.md` 생성. **agy/claude/omo/opencode는 `round1.log`가 result**.
**부분 실패 허용**: N≥2 중 1 생존 시 진행, 죽은 참가자 "무응답". CLI/인증/플래그 오류 = `ORCHESTRATION_FAIL`(라운드 미산입, 그 참가자만 재시도).

## 4. FUSE — Judge → Synthesizer (plan-fusion의 핵심)

1. **후보 묶음**: 생존 참가자 답변(또는 diff)을 라벨링해 `$RUN/judge-input.md` (`references/fusion.md` §3-1).
2. **Judge CLI**(기본 Opus/`claude --print`): `templates/fusion-judge.md.tmpl` + judge-input → `$RUN/judge.md`(최강후보·합의·충돌·위험주장·최종 포함사항).
3. **Synthesizer CLI**(기본 GPT/`codex exec`): `templates/fusion-synth.md.tmpl` + 후보 + judge.md → `$RUN/final.md`(Research 최종답변) / `handoff.synth.md`(Code 합성지시).
4. **폴백(절대 막히지 않음)**: Judge CLI 실패 → Claude 직접 판정 + 표기. Synth CLI 실패 → 차순위 CLI 또는 Claude 합성 + 표기. **Judge가 Opus·Opus가 참가자면** synthesis에 "Judge 비독립(동족) 할인" 명시.

## 5. VERIFY / SYNTHESIZE / REPORT (Claude 불가양도)

### 검증
- **Fusion-Research**: `final.md`를 그대로 신뢰하지 않는다. Judge가 표시한 **위험·미검증 주장을 Claude가 코드 grep으로 사실 판정**(다수결 금지). 충돌점은 근거 기반 결론.
- **Fusion-Code**: 합성/채택을 메인 반영 후 **직접 실행 증거로 검증** — 빌드·타입·테스트·린트 Bash 실행, exit·출력 인용, Acceptance Criteria 항목별 대조, baseline·범위 확인. result/final 주장은 근거 아님.
- `templates/synthesis.md.tmpl`로 `$RUN/synthesis.md`(Judge판정·Synth최종·**Claude 검증증거**·교차리뷰·판정근거).

### 적용 (Fusion-Code)
- 단일 채택: `council_wt_adopt "<root>" "$RUN" "<id>"`(드리프트 체크 + `apply --3way`). 장점 합성: `handoff.synth.md`를 한 백엔드에 최종 위임 → `$RUN/wt/final` 구현 → 검증 후 adopt. **역할경계: Claude는 코드 직접수정 안 함.**
- 미달 시 최종 백엔드 세션 resume(최대 3라운드, `ORCHESTRATION_FAIL` 미산입). 방향 틀렸으면 fresh 재위임.

### loop-md 연동
루트에 `loop.md` 있으면 loop-md Verify 모드(①Pass/Fail·②정량·③정성). **③정성의 독립 검증자를 Judge·교차리뷰로 자연 충족**. 없으면 N/A.

### REPORT
- **모드**(Fusion-Code/Research) · **참가자·모델·effort**(배너 실효값) · **Judge/Synth 백엔드**(+비독립 여부)
- 참가자별 상태(DONE/BLOCKED/ORCHESTRATION_FAIL/무응답)
- **Judge 판정요지 + Synth 최종 + Claude 검증증거**(grep·diff·테스트)
- 채택 vs 합성 경로 · 최종 변경 파일 + 기준별 충족 증거
- **BLOCKED·적용한 기본 결정·남은 질문**(분리) · 라운드 수(+`ORCHESTRATION_FAIL` 횟수)
- `$RUN` 경로(handoff/judge/final/synthesis/diff/xreview/manifest/final.patch) · UI면 before/after 경로
- REPORT 직전 `council_wt_cleanup "<root>" "$RUN"` 1회 + **누수 점검**: `git -C "<root>" worktree list` council 잔존 0 + `git -C "<root>" branch --list 'council/*'` 잔존 0(1줄)

---

## 역할 경계 (절대 규칙)

- Claude는 **분석·계획·검증·사실확인**만. 종합은 Judge·Synth CLI에 위임하되, **그 결과를 직접 코드로 고치지 않고** 검증 후 문제는 백엔드에 되돌린다(resume 또는 합성 HANDOFF).
- 최종 코드 작성 주체는 **항상 백엔드**. `council_wt_adopt`의 patch apply·Synth의 합성지시는 새 변경 생성이 아니다.
- 참가자는 재계획·범위 확장·무관 리팩토링 금지(HANDOFF에 명시).
- 인간 승인 영역(스키마/보안/키·시크릿/결제/배포/PRD범위/아키텍처)은 자동 진행 금지 — BLOCKED로.

## 이 스킬을 쓰지 말아야 할 때

- **단순 교차검증**(종합을 CLI에 위임할 필요 없이 Claude가 직접 비교·종합) → **plan-codex-opencode**가 더 가볍다.
- **단일 모델 위임** → **plan-then-codex**(codex 단독) 또는 **plan-then-opencode**(omo 단독).
- plan-fusion은 **명시적 Judge→Synthesizer CLI 합성**이 필요하고 **Gemini(agy)·Opus(claude)까지 패밀리를 넓힐 때**의 오케스트레이션이다.
