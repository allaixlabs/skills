# Council 레퍼런스 — 격리 · 교차리뷰 · 종합 (plan-codex-opencode용)

Council = **동일 HANDOFF를 N개 패널에 병렬 위임 → Claude가 비교·교차리뷰·종합**.
서로 다른 모델 패밀리의 독립적 실수를 교차검증으로 잡아내는 것이 목적이다.
worktree 셋업/정리/적용 셸 함수는 `scripts/council-worktrees.sh`에 캡슐화되어 있다.

## 두 갈래

| | Council-Code (쓰기) | Council-Research (읽기) |
|---|---|---|
| 격리 | **git worktree** 패널별 분리 (충돌 방지) | **참가자별 읽기전용 사본**(`$RUN/ro/<id>`, `.git` 제외·심링크 차단) |
| 위임 | workspace-write | read-only (codex `-s read-only` / opencode·omo는 사본에서 `--dangerously-skip-permissions`) |
| 산출 | 패널별 diff → 채택/합성 → 메인 적용 | 패널별 답변 → 종합 문서 |
| 검증 | 빌드·테스트 직접 실행 | 사실확인(인용 grep 대조) + 변경 0 확인 |

---

## 1. 격리 (Council-Code)

```bash
source "$SKILL_DIR/scripts/council-worktrees.sh"
council_wt_setup "$ROOT" "$RUN" "$slug" codex glm kimi   # 패널 id 목록
```
정리는 REPORT 직전 `council_wt_cleanup "$ROOT" "$RUN"`로 명시 호출한다. setup·위임·정리를 한 Bash 호출에 묶을 때만 `trap ... EXIT`가 유효하다.
- 각 패널은 `council/<slug>-<id>-<ts>` 독립 브랜치의 `$RUN/wt/<id>` worktree에서 작업.
- 사용자 uncommitted 변경은 `git stash create`(워킹트리 불변) → 각 worktree에 apply (동일 출발선).
- `baseline.head`는 setup이 기록한다(diff/적용 기준).

### 비-git 폴백
```bash
WT="$RUN/wt/$id"; cp -a "$ROOT" "$WT"     # 대용량이면 rsync --exclude node_modules / 비용 경고
# codex: codex exec ... --skip-git-repo-check -C "$WT"
```
diff는 `diff -ru "$ROOT" "$WT" > "$RUN/$id/diff.patch"`로 대체.

### Council-Research (참가자별 읽기전용 사본 기본)
- **codex 패널**: `-s read-only`로 샌드박스가 쓰기를 강제 차단한다.
- **opencode/omo 패널**: 기본은 원본 루트가 아니라 참가자별 읽기전용 사본(`$RUN/ro/<id>`)에서 `--dangerously-skip-permissions`로 실행한다. 헤드리스 권한 프롬프트 교착을 피하되, 쓰기 오염은 원본과 분리된 사본에 가둔다.
  ```bash
  RO="$RUN/ro/$id"
  mkdir -p "$RUN/ro"
  if ! rsync -a --safe-links --exclude '.git' --exclude node_modules "$ROOT/" "$RO/" 2>/dev/null; then
    rm_rc=0; rm -rf "$RO" || rm_rc=$?
    cp_rc=0; cp -a "$ROOT" "$RO" || cp_rc=$?
    find "$RO" -name .git -prune -exec rm -rf {} + 2>/dev/null || true
    find "$RO" -type l -delete 2>/dev/null || true
    if [ "$rm_rc" -ne 0 ] || [ "$cp_rc" -ne 0 ] || find "$RO" \( -name .git -o -type l \) -print -quit | grep -q .; then
      echo "ABORT: '$id' 읽기전용 사본 격리 실패(rsync·rm/cp/cleanup 모두 실패 — .git/심링크 잔존 가능) → 이 참가자 위임 중단(무응답 처리). 불완전·비격리 사본에서 참가자를 돌리지 않는다." >&2
      exit 2
    fi
  fi

  mkdir -p "$RUN/$id"
  opencode run -m <prov/model> --variant high --format json \
    --dangerously-skip-permissions --dir "$RO" "$(cat "$RUN/handoff.md")" \
    > "$RUN/$id/round1.log" 2>&1
  # omo: $OMO_BIN run --agent Sisyphus -m <prov/model> -d "$RO" --json --dangerously-skip-permissions ...
  ```
- **격리 실패 시 ABORT**: `.git` 또는 심링크가 남을 수 있는 불완전 사본에서는 실행하지 않는다. 비격리 동일 루트로 폴백하지 않는다.
- **한계**: 읽기전용 사본은 네트워크 egress, 시크릿 유출, out-of-tree 심링크를 통한 사본 밖 파일시스템 접근(`--safe-links`/심링크 차단으로 좁힘), `git push` 같은 원격 부작용을 막지 못한다. 민감 레포는 OS sandbox/네트워크 차단을 별도로 걸어야 한다.
- 사후 `git -C "$ROOT" status --short` 검사는 원본 오염을 확인하는 **보조 탐지**로만 둔다. 기본 안전모델은 사본 격리다.
---

## 2. 병렬 위임

각 패널을 **별도 Bash `run_in_background: true`** 로 실행 (한 셸에서 `&`로 묶지 말 것 — 개별 완료·exit 못 받음). 산출물은 `$RUN/<id>/`로 분리.

```bash
# codex 패널 (코드: workspace-write / 리서치: read-only)
mkdir -p "$RUN/codex"
codex exec -C "$RUN/wt/codex" -m gpt-5.5 -c model_reasoning_effort="xhigh" \
  --sandbox workspace-write -o "$RUN/codex/result.md" - < "$RUN/handoff.md" \
  > "$RUN/codex/round1.log" 2>&1
echo "round1_exit=$?" >> "$RUN/codex/manifest"

# glm 패널 (omo — 구현 완수보장)
OMO_BIN=$(command -v omo 2>/dev/null || echo "bunx oh-my-openagent")
mkdir -p "$RUN/glm"
$OMO_BIN run --agent Sisyphus \
  -m zai-coding-plan/glm-5.2 -d "$RUN/wt/glm" --json \
  "$(cat "$RUN/handoff.md")" \
  > "$RUN/glm/round1.log" 2>&1
echo "round1_exit=$?" >> "$RUN/glm/manifest"

# kimi 패널 (opencode 직접 — 가벼움)
mkdir -p "$RUN/kimi"
opencode run -m opencode-go/kimi-k2.7-code --variant high --format json \
  --dir "$RUN/wt/kimi" "$(cat "$RUN/handoff.md")" \
  > "$RUN/kimi/round1.log" 2>&1
echo "round1_exit=$?" >> "$RUN/kimi/manifest"
```

규칙:
- **모든 패널 완료 알림 후에만** 결과 read (race 방지). 읽는 순서: manifest exit → codex 패널은 `result.md`, omo/opencode 패널은 `round1.log`.
- **부분 실패 허용 / quorum**: 생존 모델 패밀리 ≥2일 때만 Council 성립. 1패밀리만 생존하면 교차검증 미성립이므로 단일위임 결과 + `Council 미성립` 표기로 격하한다. CLI/인증/플래그 오류 = `ORCHESTRATION_FAIL`(라운드 미산입, 그 패널만 재시도).
- codex 패널은 council당 1개 권장(세션 저장소 경합 회피, GPT 1표).

---

## 3. 종합 (SYNTHESIS) — Council의 핵심 산출

### Council-Code
1. **결과 수집**: 각 패널 exit·result(DONE/BLOCKED). BLOCKED 질문 모아 차단 판단.
2. **diff 추출** (주장이 아니라 실제 변경 — ⚠️ 신규 파일 포함 + 사용자 dirty 제외):
   - **stash apply 실패 패널은 제외**: 각 패널 manifest에 `stash apply 실패` 마커가 있으면 그 패널은 diff 추출/교차리뷰에서 제외한다. setup이 사용자 dirty를 worktree에 적용하지 못했으므로, diffbase(stash)와 어긋나 사용자 dirty 역헝크가 섞일 수 있다(adopt 가드와 대칭).
```bash
BASE=$(council_wt_diffbase "$RUN")   # 패널 worktree 출발점(stash 있으면 그 커밋, 없으면 HEAD).
# baseline.head(HEAD)를 직접 쓰면 ① 사용자 dirty가 패널 기여분으로 오인되고 ② adopt 패치와 base가
# 어긋난다. 반드시 adopt와 같은 council_wt_diffbase 를 쓴다(헬퍼는 §1에서 source됨).
# 그리고 그냥 git diff <base>는 패널이 새로 만든 untracked 파일(새 모듈·테스트)을 빠뜨리므로
# add -A 후 인덱스 기준 diff로 신규까지 포함한다(worktree 인덱스만 staged — ROOT엔 영향 없음).
git -C "$RUN/wt/$id" add -A >/dev/null 2>&1
git -C "$RUN/wt/$id" --no-pager diff --cached "$BASE" -- > "$RUN/$id/diff.patch"
git -C "$RUN/wt/$id" --no-pager diff --cached --stat "$BASE" > "$RUN/$id/diff.stat"
```
3. **접근 차이 분석**: 파일·알고리즘·구조 차이, 테스트 추가 여부, Out-of-scope 침범 패널 식별.
4. **교차리뷰** (독립성 활용 — council의 진짜 가치): 한 패널 변경을 **다른 패밀리**가 리뷰. ⚠️ **리뷰어도 다양해야 한다** — `codex exec review`만 쓰면 구현자는 다양해도 리뷰어가 GPT 단일이라, GPT 계열 공통 약점은 종합에서도 안 잡힌다.
```bash
mkdir -p "$RUN/xreview"
# (a) GPT가 GLM 변경 리뷰 — codex exec review 특화 도구
( cd "$RUN/wt/glm" && codex exec review --base "$BASE" -m gpt-5.5 \
  "정확성/회귀/엣지케이스/범위일탈 지적" ) > "$RUN/xreview/codex-on-glm.md" 2>&1

# (b) 비-GPT 상호리뷰 — GLM/Kimi가 codex(또는 서로의) diff를 리뷰.
#     opencode엔 exec review가 없으니 diff를 브리프에 담아 일반 위임한다.
{ echo "아래 diff를 리뷰하라(정확성/회귀/엣지/범위일탈 지적). 코드 변경 금지, 지적만 반환:";
  cat "$RUN/codex/diff.patch"; } > "$RUN/xreview/brief-kimi-on-codex.md"
opencode run -m opencode-go/kimi-k2.7-code --format json --dir "$ROOT" \
  "$(cat "$RUN/xreview/brief-kimi-on-codex.md")" > "$RUN/xreview/kimi-on-codex.md" 2>&1
```
교차 행렬: 각 패널 변경을 최소 1개 **다른 패밀리**가 리뷰하고, 리뷰어 집합도 한 패밀리에 쏠리지 않게 한다(예: 2-패널이면 GPT→GLM·GLM→GPT를 모두). 자기 패밀리 자기리뷰 금지(확증편향).
5. **판정**: (a) diff 객관 비교 + (b) 교차리뷰 지적 →
   - **단일 채택**: 한 패널 압승 → 그 worktree 채택.
   - **장점 합성**: "codex 알고리즘 + glm 테스트 + kimi 에러처리"를 파일별 구체 지시로 새 HANDOFF(`$RUN/handoff.synth.md`).
6. `templates/synthesis.md.tmpl`로 `$RUN/synthesis.md` 작성: 합의/충돌/각 패널 강약점/교차리뷰 요지/**판정과 근거**.

### Council-Research
N개 답변을 ANALYZE의 하위 질문 축으로 정렬 → **합의 / 충돌(+각 근거) / 고유통찰** 3분할.
충돌점은 Claude가 **코드·문서 직접 확인해 사실 판정**(다수결 금지, 근거 기반). 코드 변경 없으니 적용 단계 없이 종합 문서로 종료.

> 종합 모호성 방어: 무리한 단일채택 대신 합성 스펙으로. **근거 없는 채택 금지** — diff·테스트·교차리뷰 증거를 반드시 synthesis.md에 남긴다.

---

## 4. 합성 후 적용 (Council-Code) — 메인에 안전 반영

역할경계: **Claude는 프로덕션 코드를 직접 수정하지 않는다.** 최종 코드 작성 주체는 항상 백엔드.

**경로 A — 단일 채택**: 채택 worktree 변경만 patch로.
```bash
council_wt_adopt "$ROOT" "$RUN" "<채택 id>"   # rev-parse 드리프트 체크 + git apply --3way
```
(머지 대신 patch apply — 임시커밋 히스토리 오염 방지, baseline dirty 충돌은 `--3way`로 표면화)

**경로 B — 장점 합성**: `handoff.synth.md`를 **한 백엔드에 최종 위임**해 1개 결과로 구현(결정론적 codex 또는 최우수 패널). 새 worktree `$RUN/wt/final`에 구현 → 검증 후 `council_wt_adopt`로 적용. 합성도 새 HANDOFF→백엔드 위임이므로 역할경계 유지.

**적용 후 정리**: REPORT 직전 `council_wt_cleanup "$ROOT" "$RUN"` 최종 1회. 기본 동작은 manifest에 기록된 council worktree와 `council/*` 브랜치를 모두 제거한다. 채택 브랜치를 보존해야 하면 세 번째 인자로 채택 id를 넘긴다. REPORT에서 `git worktree list`와 `git branch --list 'council/*'` 잔존 0을 확인한다.

---

## 위험요소 ↔ 방어책

| 위험 | 방어책 |
|---|---|
| worktree/브랜치 누수 | `$RUN/wt/<id>` 격리 + REPORT 직전 `council_wt_cleanup` + `worktree remove --force`+`prune`+manifest `council/*` 브랜치 삭제. REPORT서 `worktree list`/`branch --list 'council/*'` 확인 |
| 브랜치명 충돌 | `council/<slug>-<id>-<ts>` 유니크 명명 |
| 동시 파일 충돌 | 패널마다 독립 worktree(비-git은 `cp -a`) |
| baseline 오염 / 사용자 dirty 중복충돌 | `stash create`(워킹트리 불변)→worktree apply로 동일 출발선. diff·adopt의 base는 `council_wt_diffbase`(=stash 출발점)라 **패널 순수 기여분만** 추출. 메인 적용은 `apply --3way` 단일 시도이며, 실패 시 `APPLY_CONFLICT`로 표면화(수동 머지) — plain 재시도는 충돌을 가중시키므로 하지 않는다 |
| race(완료 전 read) | 모든 패널 완료 알림 후 read, manifest exit→codex result.md 또는 omo/opencode round1.log |
| 부분 실패로 council 마비 | 생존 모델 패밀리 ≥2면 Council 진행. 1패밀리만 생존하면 단일위임 결과 + `Council 미성립`으로 격하. ORCHESTRATION_FAIL 라운드 미산입 |
| 합성 모호성 | 임의 채택 금지 — diff·교차리뷰·테스트 증거로 판정, 근거 synthesis.md 명시 |
| 역할경계 침범 | 최종 코드는 항상 백엔드. patch apply는 변경 생성 아님 |
| research 모드 쓰기 오염 | codex `-s read-only` + opencode/omo 읽기전용 사본 격리(`.git` 제외·심링크 차단) + 브리프 쓰기금지 + 사후 `git status` 보조 탐지 |
| 메인 드리프트(council 중 사용자 커밋) | 적용 직전 `rev-parse HEAD == baseline.head`(council_wt_adopt가 검사) |
