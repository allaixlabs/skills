# opencode 백엔드 레퍼런스 (omo run / opencode run 직접)

두 실행 경로 — **omo run**(Sisyphus 오케스트레이션·완수보장)과 **opencode run 직접**(경량 단발) — 의 실측 노트.
검증 환경(실측): omo(oh-my-openagent) 4.10.0 · opencode 1.16.2 — `omo run --help` / `opencode run --help`로 확인. 최소 요구 버전은 README 전제조건 참조(게이트는 ≥1.4). ⚠️ 단 이 문서의 플래그(`--variant`·`--format json`·`run` 등)는 **1.16.2에서만 실측**됐다 — 1.4~1.15에서 동일 동작 보장은 없으니, 게이트를 통과해도 플래그 오류가 나면 `opencode upgrade`로 최신을 권장.
모델은 동일(glm·kimi·deepseek 등), **실행기만 다르다**. 라우팅은 `references/routing-fusion.md` 참조.

---

## 경로 A — omo run (구현·다단계·완수보장)

```bash
OMO_BIN=$(command -v omo 2>/dev/null || echo "bunx oh-my-openagent")
$OMO_BIN run \
  --agent Sisyphus \
  -m zai-coding-plan/glm-5.2 \
  -d "$RUN/wt/glm" \
  --json \
  "$(cat "$RUN/handoff.md")" \
  > "$RUN/glm/round1.log" 2>&1
echo "round1_exit=$?" >> "$RUN/glm/manifest"
```

⚠️ **`bunx omo` / `npx omo` 금지** — 별개 패키지가 설치됨. `omo` 별칭 또는 `bunx oh-my-openagent`.

### 주요 플래그

| 플래그 | 설명 |
|--------|------|
| `-a, --agent <name>` | `Sisyphus` / `Hephaestus` / `Prometheus` / `Atlas` |
| `-m, --model <provider/model>` | 모델 오버라이드 (예: `zai-coding-plan/glm-5.2`) |
| `-d, --directory <path>` | **작업 디렉토리 (항상 명시)** — codex의 `-C`, opencode의 `--dir`에 해당 |
| `--session-id <id>` | 기존 세션 resume |
| `--json` | 구조화 JSON 이벤트 스트림 (session 추출·스크립팅용) |
| `--on-complete <cmd>` | 완료 후 셸 명령 |
| `-p, --port <port>` | 서버 포트 (사용 중이면 attach) |
| `--attach <url>` | 기존 opencode 서버에 연결 |

### 에이전트 가이드

| 에이전트 | 역할 | 언제 |
|----------|------|------|
| **Prometheus** | 전략 플래너. 인터뷰→범위 확정→계획 | 요구사항 모호, 설계 먼저 |
| **Sisyphus** | 오케스트레이터. 병렬 서브태스크 완수 | 다단계 복잡 구현 (기본) |
| **Hephaestus** | 자율 심층 작업자. 탐색→end-to-end | 범위 명확한 단일 작업 |
| **Atlas** | (4.10.0 코어 에이전트) | omo `run --help` 참조 |

에이전트 결정 우선순위: `--agent` → `OPENCODE_DEFAULT_AGENT` → 설정 `default_run_agent` → 기본 **Sisyphus**.

### 종료 조건 (omo의 핵심 가치)

omo run은 **두 조건 모두 충족 시에만** 자동 종료:
- 모든 todo가 completed / cancelled
- 모든 백그라운드 자식 세션이 idle

외부 폴링 불필요. 단 타임아웃 설정 없음 → 장시간 태스크는 백그라운드 + 완료 알림으로 관리.

백그라운드 패널에는 Claude 쪽 wall-clock 상한을 둔다(예: 30분 또는 handoff에서 정한 제한). 상한을 넘긴 패널은 `무응답`으로 표시하고 `ORCHESTRATION_FAIL`에 기록한 뒤, N≥2 중 생존 패널이 있으면 종합을 진행한다. 모든 패널이 미완료면 BLOCKED로 보고한다.

---

## 경로 B — opencode run 직접 (리뷰·분석·2nd opinion·단발)

```bash
opencode run \
  -m opencode-go/kimi-k2.7-code \
  --variant high \
  --format json \
  --dir "$RUN/wt/kimi" \
  "$(cat "$RUN/handoff.md")" \
  > "$RUN/kimi/round1.log" 2>&1
echo "round1_exit=$?" >> "$RUN/kimi/manifest"
```

오케스트레이션·완수보장 없음 → **가볍고 빠르다**. 읽기전용 의견 수집·리뷰·N개 병렬에 적합.

### 주요 플래그 (실측)

| 플래그 | 설명 |
|--------|------|
| `-m, --model <provider/model>` | 모델 |
| `--variant <v>` | provider-specific reasoning effort (`high`/`max`/`minimal`) — **omo엔 없는 옵션** |
| `--format <default\|json>` | `json`이면 raw JSON 이벤트 (session 추출용) |
| `--dir <path>` | **작업 디렉토리** — omo의 `-d`, codex의 `-C`에 해당 (이름 다름 주의) |
| `-s, --session <id>` | 세션 resume |
| `-c, --continue` | 마지막 세션 이어가기 — **병렬 패널에선 금지**(다른 패널 세션 오선택) |
| `--agent <name>` | 에이전트 |
| `-f, --file <path>` | 메시지에 파일 첨부 |
| `--dangerously-skip-permissions` | 권한 자동승인. Fusion-Research에선 **읽기전용 `cp -a` 사본 안에서** 이 플래그와 함께 실행한다(헤드리스 권한 교착 회피 + 쓰기는 throwaway 사본에만) |

---

## 경로 선택 기준

| 단계 | 권장 경로 | 이유 |
|---|---|---|
| 구현(쓰기)·다단계 | **omo run** (Sisyphus) | 완수보장·병렬 서브태스크 |
| 리뷰 / 분석 / 2nd opinion | **opencode run 직접** | 단발·경량·N개 병렬 용이 |
| 고추론(variant) 필요 | **opencode run 직접** | `--variant high` (omo엔 없음) |

---

## Session ID 추출 (resume용)

### omo (`--json`)
```bash
SESSION_ID=$(grep -o '"sessionId":"[^"]*"' "$RUN/<id>/round1.log" | head -1 \
  | sed 's/.*"sessionId":"\([^"]*\)".*/\1/')
# 폴백: opencode session 목록 최신 — ⚠️ 병렬 패널 동시 실행 중엔 다른 패널의 세션을
#       잡을 수 있다(opencode `--continue` 금지와 같은 race). round1.log 직접 추출이 항상 우선이며,
#       이 폴백은 "그 시점 그 패널만 단독 실행 중"이 확실할 때만 신뢰하라.
if [ -z "$SESSION_ID" ]; then
  SESSION_ID=$(opencode session list --format json 2>/dev/null \
    | grep -o '"id":"[^"]*"' | head -1 | sed 's/.*"id":"\([^"]*\)".*/\1/')
fi
echo "session=${SESSION_ID:-<not-found>}" >> "$RUN/<id>/manifest"
```

### opencode (`--format json`)
JSON 이벤트에서 session 키 추출. 필드명은 버전차가 있으니 **실패 시 `round1.log`의 `session` 관련 키를 직접 확인**.

⚠️ omo 4.10.0 `--json` 세션 필드명은 `sessionId`다. opencode fallback의 `id`는 별도 명령 출력이다. 추출 실패가 곧 실패는 아니며, resume이 필요할 때만 확정하면 된다.

## Resume (VERIFY 라운드)

```bash
# omo
$OMO_BIN run --session-id "$SESSION_ID" -d "<원 디렉토리>" --json "검증 지시…" > "$RUN/<id>/roundN.log" 2>&1
# opencode
opencode run -m <prov/model> -s "$SESSION_ID" --dir "<원 디렉토리>" --format json "검증 지시…" > "$RUN/<id>/roundN.log" 2>&1
```
방향이 크게 틀렸으면 resume 대신 새 HANDOFF로 fresh 재위임.

## 비코드(read-only) 위임 — 강제 샌드박스 없음 → `cp -a` 사본으로 예방

opencode/omo는 codex의 `-s read-only` 같은 강제 샌드박스가 없다. "권한 프롬프트가 쓰기를 차단"한다는 가정은 헤드리스에서 미검증이라 의존하지 않는다. 대신 **구조적 예방**:
1. **읽기전용 사본에서 실행**한다 — `RO="$RUN/ro/$id"`. ⚠️ `cp -a`는 `.git`(원본 리모트·자격증명)·out-of-tree 심링크를 보존하므로 사본 단독으론 `git push`·시크릿 유출·심링크 탈출을 못 막는다 → `rsync -a --safe-links --exclude '.git' --exclude node_modules "$ROOT/" "$RO/"`(없으면 `rm -rf "$RO"; cp -a "$ROOT" "$RO" && rm -rf "$RO/.git" && find "$RO" -type l -delete` — `rm` 선행으로 rsync 부분실패 시 cp 중첩 방지) 후 `--dir "$RO"`. 그러면 로컬 원본 쓰기가 떨어져도 무해.
2. 사본에선 `--dangerously-skip-permissions`를 **써도 된다**(헤드리스 권한 교착 회피). 단 이는 OS 샌드박스가 아니라 네트워크 차단이 없으므로, 진짜 차단이 필요하면 codex `-s read-only` 백엔드를 쓴다.
3. HANDOFF 상단에 **"파일 쓰기·git 변경 금지, 분석/답변만"** 명시(이중 방어).
4. 보조 탐지: 위임 후 `git -C "$ROOT" status --short`로 원본 불변 재확인. 종료 후 `rm -rf "$RUN/ro"`.
5. 비코드는 omo의 완수보장 가치가 낮으니 **opencode run 직접 경로 권장**(가볍게 N개 병렬).

## codex exec 대비 차이 요약

| | codex exec | omo run | opencode run |
|-|-----------|---------|--------------|
| 작업 디렉토리 | `-C` | `-d` | `--dir` |
| 모델 | `-m gpt-5.5` | `-m prov/model` | `-m prov/model` |
| effort | `-c model_reasoning_effort="xhigh"` | (없음) | `--variant high` |
| stdin | `- < FILE` | `"$(cat FILE)"` | `"$(cat FILE)"` |
| 샌드박스 | `--sandbox` | 없음(지시+검증) | 없음(지시+검증) |
| resume | `exec resume <id>` | `--session-id <id>` | `-s <id>` |
| 종료 감지 | 프로세스 종료 | todo완료+idle 자동 | 프로세스 종료 |
| 코드리뷰 | `exec review` 특화 | 일반 위임 | 일반 위임 |

## 트러블슈팅

| 증상 | 조치 |
|------|------|
| `omo: command not found` | `bunx oh-my-openagent run …` |
| `bunx: command not found` | `curl -fsSL https://bun.sh/install \| bash` |
| 플러그인 미등록 (omo run 경로) | `! bunx oh-my-openagent install` (opencode 직접 경로는 불필요) |
| 모델 인증 오류 | `opencode providers list`로 해당 provider `●` 확인 (check-fusion.sh의 매트릭스) |
| sessionId 추출 실패 | round1.log에서 `session` 키 직접 확인 — resume 필요할 때만 |
| resume 즉사 | sessionId 오입력/만료 → 새 세션 재위임 |
| 변경이 지정 디렉토리 밖에 생성 | `-d`/`--dir` 경로 재확인, HANDOFF 루트 점검 |
| 비코드인데 파일이 수정됨 | read-only 지시 누락 → 그 패널 제외, HANDOFF 보강 후 재위임 |
