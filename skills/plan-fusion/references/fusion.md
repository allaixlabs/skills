# Fusion 레퍼런스 — 격리 · 참가자 위임 · Judge→Synth 합성 (plan-fusion용)

Fusion = **동일 HANDOFF를 N개 패밀리 CLI에 병렬 위임 → Judge CLI가 후보 비교 → Synthesizer CLI가 최종 합성 → Claude가 검증**.
plan-codex-opencode의 Council과 다른 점은 **종합을 Claude가 직접 하지 않고 Judge·Synth CLI에 위임**한다는 것이다(Claude는 검증·사실확인만 불가양도).
worktree 격리 헬퍼는 `scripts/council-worktrees.sh`(부모와 동일, `cd` 기반이라 agy/claude에도 동작).

## 두 갈래

| | Fusion-Code (쓰기) | Fusion-Research (읽기) |
|---|---|---|
| 격리 | **git worktree** 참가자별 분리 | 불필요 — 동일 루트 read-only(민감 레포는 `cp -a` 사본) |
| 참가자 위임 | workspace-write (codex `--sandbox workspace-write` / agy·claude `--dangerously-skip-permissions` / omo·opencode 기본) | read-only (codex `-s read-only` 강제 / 그 외 지시+검증) |
| Synth 산출 | 합성 HANDOFF 또는 채택 지정 → 백엔드가 최종 구현 → 메인 적용 | 최종 텍스트 답변(`final.md`) |
| Claude 검증 | 빌드·테스트 직접 실행 | 위험·미검증 주장 grep 사실확인 |

---

## 0. 단계 개요

```
ANALYZE → HANDOFF → [참가자 병렬 위임] → [Judge CLI] → [Synth CLI] → [Claude 검증] → REPORT
```

---

## 1. 격리 (Fusion-Code)

```bash
source "$SKILL_DIR/scripts/council-worktrees.sh"
council_wt_setup "$ROOT" "$RUN" "$slug" codex gemini glm kimi   # 참가자 id 목록
```
정리는 REPORT 직전 `council_wt_cleanup "$ROOT" "$RUN"`로 명시 호출.
- 각 참가자는 `council/<slug>-<id>-<ts>` 독립 브랜치의 `$RUN/wt/<id>`에서 작업.
- 사용자 dirty는 `git stash create`(워킹트리 불변) → 각 worktree apply (동일 출발선).
- diff base는 `council_wt_diffbase "$RUN"`(stash 커밋 or HEAD).

### Fusion-Research 격리
- **codex 참가자**: `-s read-only`로 쓰기 강제 차단 → 동일 루트 안전.
- **opencode/omo 참가자**: 강제 샌드박스 없음 → ① 브리프 쓰기금지 지시 ② `--dangerously-skip-permissions` 미사용 ③ 위임 후 `git -C "$ROOT" status --short` 오염검사(예방 아닌 탐지). 민감 레포는 읽기전용 사본.
- **agy 참가자**: opencode와 같지만 **권한 프롬프트 교착 주의** — 도구 유발 프롬프트면 skip-permissions 없이 헤드리스에서 멈춘다(`--print-timeout`도 못 끊음). 그래서 Research에서도 **읽기전용 사본 + `--dangerously-skip-permissions`**로 돌려 교착을 막고 쓰기는 throwaway 사본에만 떨어지게 한다:
  ```bash
  RO="$RUN/ro/$id"; cp -a "$ROOT" "$RO"   # 대용량이면 rsync --exclude node_modules
  ( cd "$RO" && command agy --print-timeout 600s --dangerously-skip-permissions \
    --model "Gemini 3.1 Pro (High)" --print "$(cat "$RUN/handoff.md")" ) > "$RUN/$id/round1.log" 2>&1
  # 분석 종료 후: rm -rf "$RO"   # 사본이라 원본 무해
  ```

---

## 2. 참가자 병렬 위임

각 참가자를 **별도 Bash `run_in_background: true`** (한 셸에서 `&` 금지 — 개별 완료·exit 못 받음). 산출물은 `$RUN/<id>/`.

```bash
export PATH="/opt/homebrew/bin:$PATH"

# codex (GPT) — workspace-write, result.md 생성
codex exec -C "$RUN/wt/codex" -m gpt-5.5 -c model_reasoning_effort="xhigh" \
  --sandbox workspace-write -o "$RUN/codex/result.md" - < "$RUN/handoff.md" \
  > "$RUN/codex/round1.log" 2>&1
echo "round1_exit=$?" >> "$RUN/codex/manifest"

# agy (Gemini) — cd + skip-permissions(쓰기), stdout이 곧 result
( cd "$RUN/wt/gemini" && command agy --print-timeout 900s --dangerously-skip-permissions \
  --model "Gemini 3.1 Pro (High)" --print "$(cat "$RUN/handoff.md")" ) \
  > "$RUN/gemini/round1.log" 2>&1
echo "round1_exit=$?" >> "$RUN/gemini/manifest"

# glm (omo — 완수보장)
OMO_BIN=$(command -v omo 2>/dev/null || echo "bunx oh-my-openagent")
$OMO_BIN run --agent Sisyphus -m zai-coding-plan/glm-5.2 -d "$RUN/wt/glm" --json \
  "$(cat "$RUN/handoff.md")" > "$RUN/glm/round1.log" 2>&1
echo "round1_exit=$?" >> "$RUN/glm/manifest"

# kimi (opencode 직접)
opencode run -m opencode-go/kimi-k2.7-code --variant high --format json \
  --dir "$RUN/wt/kimi" "$(cat "$RUN/handoff.md")" > "$RUN/kimi/round1.log" 2>&1
echo "round1_exit=$?" >> "$RUN/kimi/manifest"
```

규칙:
- **모든 참가자 완료 알림 후에만** 결과 read (race 방지). manifest exit → codex `result.md`, 그 외 `round1.log`.
- **부분 실패 허용**: N≥2 중 1 생존 시 진행, 죽은 참가자 "무응답". CLI/인증/플래그 오류 = `ORCHESTRATION_FAIL`(라운드 미산입, 그 참가자만 재시도).
- agy/omo는 백그라운드 wall-clock 상한을 둔다(예: 30분). agy는 `--print-timeout`이 자체 차단하지만 Claude 쪽 상한도 병행.

세션 재개용 ID는 참가자 로그 직후 manifest에 남긴다. codex는 `round1.log`/세션 파일의 `session_id`, omo·opencode는 JSON `sessionId`/`id`를 추출(상세 명령은 `codex-cli.md`·`opencode-cli.md` 참조); agy·claude는 conversation 추출 실패 시 fresh 재위임한다.
- 동일 패밀리 중복 금지(gpt-5.5 + gpt-5.5-fast 같은 조합은 독립성 0).

---

## 3. FUSE — Judge → Synthesizer (plan-fusion의 핵심 신규 단계)

### 3-1. 후보 묶음 작성
모든 참가자 답변을 라벨링해 한 파일로:
```bash
{
  echo "# 원 작업/질문"; cat "$RUN/handoff.md"; echo
  for id in codex gemini glm kimi; do
    [ -f "$RUN/$id/manifest" ] || continue
    ex=$(sed -n 's/^round1_exit=//p' "$RUN/$id/manifest" | tail -1)
    [ "${ex:-1}" = "0" ] || continue          # 실패 참가자 제외
    echo "## [후보: $id]"
    if [ -f "$RUN/$id/result.md" ]; then cat "$RUN/$id/result.md"; else cat "$RUN/$id/round1.log"; fi
    echo
  done
} > "$RUN/judge-input.md"
```
> Fusion-Code면 답변 대신 **각 worktree diff**를 후보로 넣는다(`council_wt_diffbase` 기준, `git add -A` 후 `diff --cached`). 상세는 §5.

### 3-2. Judge CLI (기본 Opus/claude)
`templates/fusion-judge.md.tmpl`에 judge-input을 끼워 Judge CLI로:
```bash
# 템플릿 + 후보를 합쳐 Judge 프롬프트 구성 → claude로 판정
JUDGE_PROMPT="$(cat "$SKILL_DIR/templates/fusion-judge.md.tmpl")
$(cat "$RUN/judge-input.md")"
( cd "$ROOT" && claude --print --model opus "$JUDGE_PROMPT" ) > "$RUN/judge.md" 2>"$RUN/judge.err"
echo "judge_exit=$?" >> "$RUN/manifest"
```
> 주의: `judge-input`이 클 때(대형 diff 다수)는 argv 길이 한도(E2BIG) 위험 → Judge를 codex(`- < FILE` stdin)로 돌리거나 입력을 축약.

Judge 산출: 최강 후보 / 합의점 / 충돌점 / 위험·미검증 주장 / 최종 답변 포함사항.

### 3-3. Synthesizer CLI (기본 GPT/codex)
`templates/fusion-synth.md.tmpl` + 후보 + judge.md → Synth CLI로 최종 합성:
```bash
{ cat "$SKILL_DIR/templates/fusion-synth.md.tmpl"; echo
  echo "## 후보 답변"; cat "$RUN/judge-input.md"; echo
  echo "## Judge 평가"; cat "$RUN/judge.md"; } > "$RUN/synth-input.md"
if [ "${MODE:-Fusion-Research}" = "Fusion-Code" ]; then
  codex exec -C "$ROOT" -s read-only -o "$RUN/handoff.synth.md" - < "$RUN/synth-input.md" \
    > "$RUN/synth.log" 2>&1
else
  codex exec -C "$ROOT" -s read-only -o "$RUN/final.md" - < "$RUN/synth-input.md" \
    > "$RUN/synth.log" 2>&1
fi
echo "synth_exit=$?" >> "$RUN/manifest"
```
> Fusion-Code면 Synth는 `-s read-only`로 **합성 HANDOFF**(`$RUN/handoff.synth.md`) 또는 채택 지정을 산출하고, 실제 구현은 §5의 백엔드 위임으로 넘긴다(역할경계: Synth가 직접 메인 코드 작성 안 함).

### 3-4. 폴백 (Judge/Synth에서 절대 막히지 않음)
- **Judge CLI 실패/공백** → Claude 오케스트레이터가 직접 판정(부모 council 종합 로직) + `synthesis.md`에 "Judge=self(폴백)" 표기.
- **Synth CLI 실패** → 차순위 참가자 CLI로 재시도, 그래도 실패면 Claude가 합성 + 표기.
- **동족 경고**: Judge가 Opus이고 Opus가 참가자이기도 하면 `synthesis.md`에 "Judge 비독립(동족) — 판정 할인" 명시.

---

## 4. Claude 검증 (불가양도)

### Fusion-Research
- Synth의 `final.md`를 그대로 신뢰하지 않는다. Judge가 표시한 **위험·미검증 주장**을 Claude가 **코드·문서 직접 grep으로 사실 판정**(다수결 금지). 충돌점은 근거 기반 결론.
- 확정된 답변 + 근거(어느 후보/코드경로) + 사실확인 결과를 `synthesis.md`로.

### Fusion-Code
- 합성/채택 결과를 메인에 반영 후 **직접 실행 증거로 검증**: 빌드·타입·테스트·린트 Bash 실행, exit·출력 인용. Acceptance Criteria 항목별 대조. baseline 보존·범위 준수 확인.
- result/final 주장은 근거가 아니다.

---

## 5. 합성 후 적용 (Fusion-Code) — 메인에 안전 반영

역할경계: **Claude는 프로덕션 코드를 직접 수정하지 않는다.** 최종 코드 작성 주체는 항상 백엔드.

후보가 diff인 경우 §3-1 대신:
```bash
BASE=$(council_wt_diffbase "$RUN")
for id in codex gemini glm kimi; do
  git -C "$RUN/wt/$id" add -A >/dev/null 2>&1
  git -C "$RUN/wt/$id" --no-pager diff --cached "$BASE" -- > "$RUN/$id/diff.patch"
done
```
교차리뷰(독립성 활용 — 리뷰어도 다양하게):
```bash
mkdir -p "$RUN/xreview"
# GPT가 GLM diff 리뷰 (codex exec review 특화)
( cd "$RUN/wt/glm" && codex exec review --base "$BASE" -m gpt-5.5 \
  "정확성/회귀/엣지/범위일탈 지적" ) > "$RUN/xreview/codex-on-glm.md" 2>&1
# Gemini가 codex diff 리뷰 (agy 일반 위임 — review 서브커맨드 없음)
{ echo "아래 diff를 리뷰하라(정확성/회귀/엣지/범위일탈, 코드수정 금지·지적만):"; cat "$RUN/codex/diff.patch"; } \
  > "$RUN/xreview/brief-gemini-on-codex.md"
( cd "$ROOT" && command agy --print-timeout 600s --dangerously-skip-permissions --model "Gemini 3.1 Pro (High)" \
  --print "$(cat "$RUN/xreview/brief-gemini-on-codex.md")" ) > "$RUN/xreview/gemini-on-codex.md" 2>&1
```

판정→적용:
- **단일 채택**: Judge 압승 후보 → `council_wt_adopt "$ROOT" "$RUN" "<id>"` (드리프트 체크 + `apply --3way`).
- **장점 합성**: Synth가 만든 `handoff.synth.md`를 **한 백엔드에 최종 위임**(`$RUN/wt/final`) → 검증 후 `council_wt_adopt`.

**정리**: REPORT 직전 `council_wt_cleanup "$ROOT" "$RUN"` 1회. `git worktree list` / `git branch --list 'council/*'` 잔존 0 확인.

---

## 위험요소 ↔ 방어책

| 위험 | 방어책 |
|---|---|
| Judge/Synth CLI 실패로 마비 | Claude 폴백(직접 판정/합성) + 표기 — 절대 막히지 않음 |
| Judge 동족 비독립(Opus가 참가자+Judge) | Judge를 Gemini로 교체 또는 synthesis에 "비독립 할인" 명시 |
| agy 쓰기 권한 프롬프트로 행 | `--dangerously-skip-permissions` + `--print-timeout`로 자가 차단 |
| agy/claude resume id 미추출 | fresh 재위임(부모 패턴) |
| research 쓰기 오염(agy/opencode) | 지시+사후 `git status`+민감레포 `cp -a` 사본 (codex만 강제 RO) |
| worktree/브랜치 누수 | `council_wt_cleanup` + REPORT서 `worktree list`/`branch --list 'council/*'` 0 확인 |
| race(완료 전 read) | 모든 참가자 완료 알림 후 read |
| 부분 실패 | N≥2 중 1 생존 진행, ORCHESTRATION_FAIL 미산입 |
| 역할경계 침범 | 최종 코드는 항상 백엔드. Synth/Judge·adopt patch는 새 변경 생성 아님 |
| disabledModels 누수 | fable-5/mythos-5는 참가자·Judge·Synth 어디에도 라우팅 금지 |
