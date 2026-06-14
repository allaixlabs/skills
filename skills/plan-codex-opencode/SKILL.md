---
name: plan-codex-opencode
description: >
  멀티모델 패널 워크플로우 — Claude가 분석·계획·패널선택·종합·검증을 맡고, 실제 실행은 서로 다른 AI
  모델 패밀리(codex/GPT · opencode·omo의 GLM·Kimi·DeepSeek 등)에 위임해 Council(병렬 교차검증) 또는
  Pipeline(구현→타모델 리뷰→종합)으로 돌린 뒤 합의·충돌·고유통찰을 종합한다. 다음일 때 사용:
  "codex랑 glm5.2, kimi k2.7로 교차검증", "여러 AI와 대화해서 정리", "여러 모델로 구현하고 서로 리뷰시켜",
  "panel/council로 진행", "구현은 omo, 리뷰는 codex로", "gpt5.5랑 glm 둘 다 해보고 비교", 또는 분석/리서치를
  여러 모델에 맡겨 종합할 때. 단일 모델 위임이면 plan-then-codex / plan-then-opencode를 쓴다.
---

# plan-codex-opencode — Claude 계획 × 멀티모델 패널

**Claude = 두뇌**(분석·계획·패널선택·종합·교차리뷰·검증·최종 적용 지시). **패널 = 손**: `codex exec`(GPT 패밀리) + `omo/opencode run`(GLM·Kimi·DeepSeek 등 멀티 프로바이더).

핵심 가치: codex(GPT)와 opencode(GLM/Kimi)는 **서로 다른 모델 패밀리** → 같은 문제에서 다른 실수 → 교차검증 독립성이 구조적으로 보장된다. 단일 모델 위임(plan-then-codex/opencode)과 달리, 이 스킬만이 **교차 모델 다양성**을 산출물로 만든다.

- `SKILL_DIR` = 이 SKILL.md가 있는 디렉토리. `$RUN` = 이번 위임의 격리 작업 폴더(0단계 생성).
- `PANEL` = 참여 백엔드 목록. 각 원소 `id|backend|model` (id는 `[a-z0-9-]` 슬러그 — worktree/브랜치/manifest 폴더명).
- 레퍼런스: 라우팅 `references/routing.md` · codex `references/codex-cli.md` · opencode/omo `references/opencode-cli.md` · 격리·종합 `references/council.md`.

---

## 0. 사전점검 + 요청 파싱 + 모드/패널 결정

1. **사전 점검**(read-only): `bash "$SKILL_DIR/scripts/check-panels.sh"` → `CODEX_BACKEND_READY` / `OPENCODE_BACKEND_READY` / provider 인증 매트릭스 / `PANEL_CAPABILITY`. 전부 불가(exit 1)면 중단·보고. 부분 가용이면 가용 백엔드 내 다중 모델로 축소 진행 제안.
2. **호명 파싱**(`references/routing.md`): 사용자가 부른 모델("codex, glm5.2, kimi k2.7")을 각각 `(backend, model, effort/variant, dir 플래그)`로 정규화. **호명 없으면 기본 패널 추천**(서로 다른 패밀리 2~3개, 예: codex `gpt-5.5` + `zai-coding-plan/glm-5.2`) + **1줄 이유** 제시.
3. **모드 선택**:
   - 답이 갈릴 수 있는 설계/구현 + 신뢰도↑ 목적 → **Council**
   - 범위 명확 + 구현 품질 검증 깊이 목적 → **Pipeline**
   - 파일 변경 없는 분석/리서치/설계 질문 → **Council-Research**(read-only)
   - 토폴로지 미지정("여러 AI와 대화해서 정리")이면: 비코드 분석 → Council-Research, 코드 구현 → 답 갈림이면 Council / 검증깊이면 Pipeline.
4. **격리 폴더**:
   ```bash
   slug=$(printf '%s' "<task 한단어>" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | cut -c1-20)
   RUN=$(umask 077; mktemp -d "${TMPDIR:-/tmp}/pco.${slug}.XXXXXX")
   printf 'mode=%s\npanel=%s\n' "<모드>" "<패널 id들>" >> "$RUN/manifest"
   ```
5. **패널·모드·각 백엔드 플래그 + 예상 비용/시간을 사용자에게 1회 요약**하고 진행 — N개 패밀리를 고추론(xhigh/high)으로 병렬 위임하면 토큰·시간이 단일 위임의 N배 이상이고 omo run은 자체 타임아웃이 없다(백그라운드 + 완료 알림으로 관리). 인간 승인 영역(스키마/보안/키·시크릿/결제/배포/PRD범위/아키텍처)이면 여기서 중단.

## 1. ANALYZE

Claude가 코드·실행 페이지를 직접 분석. 변경 대상 파일·스택·빌드/테스트/린트 명령·인간 승인 영역 식별. UI면 스크린샷 → 텍스트 스펙.
**Council-Research**면 질문을 **검증가능한 하위 질문 목록**(Q1..Qn)으로 분해 — 이게 종합 시 합의/충돌 축이 된다.

## 2. PLAN — HANDOFF 작성 (모든 패널이 공유하는 단일 스펙)

- 코드: `templates/HANDOFF.md.tmpl` / 비코드: `templates/HANDOFF-research.md.tmpl` → `"$RUN/handoff.md"`.
- **단일 HANDOFF 원칙**: 같은 스펙을 모든 패널에 동일하게 줘야 교차검증이 공정. 백엔드별 차이(에이전트·sandbox·dir)는 본문이 아니라 **호출 플래그**로만.
- 자기완결성: 패널은 대화 컨텍스트를 모른다. Baseline·Out-of-scope·BLOCKED 프로토콜·실행 가능한 Acceptance Criteria를 문서에 다 담는다.
- baseline 스냅샷(코드):
  ```bash
  git -C "<root>" status --short > "$RUN/baseline.status"
  git -C "<root>" rev-parse HEAD  > "$RUN/baseline.head"
  ```

## 3. DELEGATE (모드별 위임 — 전부 백그라운드 + 패널별 manifest)

> 공통: 각 패널은 **별도 Bash `run_in_background: true`**(한 셸에서 `&` 금지). 산출물 `$RUN/<id>/`. **모든 패널 완료 알림 후에만** 결과 read(race 방지).

### Council-Code — 격리 worktree 병렬
```bash
source "$SKILL_DIR/scripts/council-worktrees.sh"
council_wt_setup "<root>" "$RUN" "$slug" <패널 id들>
trap 'council_wt_cleanup "<root>" "$RUN"' EXIT
```
각 패널을 자기 worktree에서 병렬 실행 — codex `-C "$RUN/wt/<id>"`, omo `-d "$RUN/wt/<id>"`, opencode `--dir "$RUN/wt/<id>"`. 셸 상세: `references/council.md` §2.

### Council-Research — read-only 병렬
codex `-s read-only -C "<root>"`(샌드박스 강제). opencode/omo는 강제 샌드박스가 없어 기본은 쓰기금지 지시 + 사후 `git status` 오염검사이며 **이는 예방이 아닌 탐지**다 — 민감 레포는 비-codex 패널을 **읽기전용 사본**(`cp -a`)에서 실행해 격리한다(`references/council.md` §1).

### Pipeline — 구현 → 리뷰 → 수정 → 종합
> 격리: 구현도 baseline 보존을 위해 worktree에서 한다 — `council_wt_setup "<root>" "$RUN" "$slug" impl` 후 `$RUN/wt/impl`에서 작업하고, 종합 후 `council_wt_adopt "<root>" "$RUN" impl`로 메인 반영(단일 패널이라 worktree 1개). 단일트리 직접 구현이면 `baseline.status`로 사후 범위 검증.
1. **구현**: 모델 A를 `omo run --agent Sisyphus -d "$RUN/wt/impl"`(완수보장), SESSION_A 추출.
2. **리뷰** (리뷰어 패밀리 ≠ 구현자 패밀리): 구현자가 omo(glm/kimi)면 `codex exec review --uncommitted -C "$RUN/wt/impl"`. **구현자가 codex면** opencode엔 `exec review`가 없으니 diff를 브리프에 담아 glm/kimi에 일반 위임한다(`references/council.md` §3-(b) 패턴).
3. **수정**: 리뷰 지적을 모델 A에 resume으로 되돌림(omo `--session-id` / opencode `-s` / codex `exec resume`). Claude가 직접 안 고침.
4. → 4단계 종합으로.

위임 산출물 세트(패널별): `$RUN/<id>/{manifest,round1.log,result.md}`. session_id 추출은 백엔드별(`references/`).
**부분 실패 허용**: N≥2 중 1 생존 시 진행, 죽은 패널 "무응답". CLI/인증/플래그 오류 = `ORCHESTRATION_FAIL`(라운드 미산입, 그 패널만 재시도).

## 4. VERIFY / SYNTHESIZE

### 종합 (Council / Pipeline 공통 핵심)
1. 패널별 결과·exit 수집(DONE/BLOCKED).
2. **코드**: worktree별 diff 추출(`baseline.head` 대비) → 접근 차이 분석 → **교차리뷰**(다른 패밀리가 리뷰, `codex exec review --base`) → 판정(단일 채택 / 장점 합성).
3. **비코드**: N개 답변을 Q축으로 정렬 → 합의/충돌/고유통찰 3분할, 충돌은 **코드 직접 확인해 사실 판정**(다수결 금지).
4. `templates/synthesis.md.tmpl`로 `$RUN/synthesis.md` 작성(합의·충돌·강약점·교차리뷰·**판정과 근거**). 상세: `references/council.md` §3.

### 적용·검증 (Council-Code / Pipeline)
- 채택/합성 결과를 메인에 반영: `council_wt_adopt "<root>" "$RUN" "<id>"`(드리프트 체크 + `apply --3way`). 장점 합성은 `handoff.synth.md`를 한 백엔드에 최종 위임 후 적용. **역할경계: Claude는 코드 직접수정 안 함.**
- **직접 실행 증거로 검증**(result 주장은 근거 아님): 빌드·타입·테스트·린트 Bash 실행, exit·출력 인용. Acceptance Criteria 항목별 대조. baseline 보존·범위 준수 확인.
- 미달 시 최종 적용 백엔드 **세션 resume**(최대 3라운드, `ORCHESTRATION_FAIL`은 미산입). 방향이 틀렸으면 fresh 재위임.

### loop-md 연동
프로젝트 루트에 `loop.md` 있으면 loop-md 스킬 Verify 모드(①Pass/Fail 게이트·②정량·③정성). **③정성의 독립 검증자를 council 교차리뷰로 자연 충족** — synthesis.md의 교차리뷰를 ③ 근거로 연결. 없으면 N/A.

## 5. REPORT

최종 메시지에 포함:
- **모드**(Council-Code/Research/Pipeline) · **패널 구성·모델·effort**(배너 실효값 기준)
- 패널별 상태(DONE/BLOCKED/ORCHESTRATION_FAIL/무응답)
- **종합 결과**: 합의/충돌/판정 + **근거**(diff·교차리뷰·테스트)
- 채택 vs 합성 경로 · 최종 변경 파일 목록 + 기준별 충족 증거
- **BLOCKED 여부·적용한 기본 결정·남은 질문**(분리해서)
- 라운드 수(+`ORCHESTRATION_FAIL` 횟수) · `$RUN` 경로(handoff/synth/diff/xreview/synthesis/manifest/final.patch)
- UI면 before/after 스크린샷 경로
- **누수 점검**: `git -C "<root>" worktree list`에 council worktree 잔존 0 + `git -C "<root>" branch --list 'council/*'`에 비채택 브랜치 잔존 0(채택/보존분만 남김) 확인(1줄)

---

## 역할 경계 (절대 규칙)

- Claude는 **분석·계획·종합·검증**만. 검증 중 발견한 문제도 **직접 고치지 않고** 패널에 되돌린다(resume 또는 합성 HANDOFF).
- 최종 코드 작성 주체는 **항상 백엔드**. `council_wt_adopt`의 patch apply는 채택한 패널 산출물을 가져오는 것이지 새 변경 생성이 아니다.
- 패널은 재계획·범위 확장·무관 리팩토링 금지(HANDOFF에 명시).
- 인간 승인 영역(스키마/보안/키·시크릿/결제/배포/PRD범위/아키텍처)은 자동 진행 금지 — BLOCKED로.

## 단일 모델이면 이 스킬을 쓰지 마라

교차검증·다양성이 목적이 아니라 단순 위임이면 **plan-then-codex**(codex 단독) 또는 **plan-then-opencode**(omo 단독)가 더 가볍고 적합하다. 이 스킬은 **2개 이상 모델 패밀리**를 함께 돌릴 때의 오케스트레이션이다.
