# omo CLI 레퍼런스

oh-my-openagent(omo) 비대화형 실행 실측 노트 — `omo run` 기반 위임 워크플로우 전용.
소스: `bunx oh-my-openagent --help`, `omo run --help`, 공식 CLI 레퍼런스(docs/reference/cli.md).

---

## 핵심 커맨드

```bash
# 형식
omo run "<message>" [옵션]
bunx oh-my-openagent run "<message>" [옵션]   # omo 별칭 없을 때
```

⚠️ **`bunx omo` / `npx omo` 절대 사용 금지** — 별개 패키지가 설치됨.

### 주요 플래그

| 플래그 | 설명 |
|--------|------|
| `-a, --agent <name>` | 에이전트 지정 (`Sisyphus` / `Hephaestus` / `Prometheus` 등) |
| `-m, --model <provider/model>` | 모델 오버라이드 (예: `anthropic/claude-sonnet-4-6`) |
| `-d, --directory <path>` | 작업 디렉토리 (프로젝트 루트 — 항상 명시) |
| `--session-id <id>` | 기존 세션 resume |
| `--json` | 구조화 JSON 이벤트 스트림 출력 (스크립팅용) |
| `--verbose` | 전체 이벤트 스트림 출력 |
| `--no-timestamp` | 출력 타임스탬프 비활성화 |
| `--on-complete <cmd>` | 완료 후 실행할 셸 명령 |
| `--attach <url>` | 기존 opencode 서버에 연결 |
| `-p, --port <port>` | 서버 포트 (사용 중이면 attach) |

### 에이전트 결정 우선순위

1. `--agent` 플래그
2. 환경변수 `OPENCODE_DEFAULT_AGENT`
3. 플러그인 설정 `default_run_agent`
4. 기본값: **Sisyphus**

---

## 에이전트 가이드

| 에이전트 | 기본 모델 | 역할 | 언제 |
|----------|-----------|------|------|
| **Prometheus** | Kimi K2.6 / Claude Opus | 전략 플래너. 인터뷰 모드로 범위 확정 후 계획 수립 | 요구사항 모호, 범위 확정 먼저 필요 |
| **Sisyphus** | Kimi K2.6 / GLM-5.1 | 오케스트레이터. 계획·병렬 위임·끝까지 완수 | 다단계 구현, 병렬 서브태스크 (기본) |
| **Hephaestus** | GPT-5.5 | 자율 심층 작업자. 탐색 후 end-to-end 실행 | 범위 명확한 단일 심층 작업 |

**Sisyphus 서브에이전트 카테고리** (위임 시 힌트로 쓸 수 있음):
- `visual-engineering` — 프론트엔드·UI
- `deep` — 자율 리서치 + 실행
- `quick` — 소규모 단일 파일 작업
- `ultrabrain` — 복잡한 로직·아키텍처 (GPT-5.5 xhigh 라우팅)

---

## 위임 패턴

### 기본 실행

```bash
OMO_BIN=$(command -v omo 2>/dev/null || echo "bunx oh-my-openagent")

$OMO_BIN run "$(cat "$RUN/handoff.md")" \
  --agent Sisyphus \
  -d "<프로젝트 루트>" \
  --json \
  > "$RUN/round1.log" 2>&1
echo "round1_exit=$?" >> "$RUN/manifest"
```

### Session ID 추출 (resume용)

`--json` 출력에서 session_id 추출:

```bash
SESSION_ID=$(grep -o '"session_id":"[^"]*"' "$RUN/round1.log" | head -1 \
  | sed 's/.*"session_id":"\([^"]*\)".*/\1/')

# 실패 시 opencode session 목록에서 최신 세션
if [ -z "$SESSION_ID" ]; then
  SESSION_ID=$(opencode session list --format json 2>/dev/null \
    | grep -o '"id":"[^"]*"' | head -1 \
    | sed 's/.*"id":"\([^"]*\)".*/\1/')
fi
echo "session_id=${SESSION_ID:-<not-found>}" >> "$RUN/manifest"
```

⚠️ JSON 이벤트 스트림의 정확한 필드명은 omo 버전에 따라 다를 수 있다 —
추출 실패 시 `"$RUN/round1.log"` 에서 `session` 관련 JSON 키를 직접 확인할 것.

### Resume (검증 라운드)

```bash
$OMO_BIN run "검증 지시..." \
  --session-id "$SESSION_ID" \
  -d "<프로젝트 루트>" \
  --json \
  > "$RUN/roundN.log" 2>&1
```

### 모델 오버라이드

```bash
$OMO_BIN run "..." --agent Hephaestus \
  --model openai/gpt-5.5 \
  -d "<프로젝트 루트>" --json > "$RUN/round1.log" 2>&1
```

---

## 종료 조건

omo run은 아래 **두 조건이 모두 충족될 때만** 자동 종료:
- 모든 todo가 completed / cancelled 상태
- 모든 백그라운드 자식 세션이 idle 상태

외부 폴링 불필요 — 단 타임아웃은 별도 설정 없음이므로 장시간 태스크는 주의.

---

## codex exec 대비 주요 차이

| | codex exec | omo run |
|-|-----------|---------|
| stdin 입력 | `- < FILE` | `"$(cat FILE)"` 또는 메시지 인자 |
| 작업 디렉토리 | `-C <dir>` | `-d <dir>` |
| 모델 | `-m gpt-5.5` | `-m provider/model` |
| effort | `-c model_reasoning_effort="xhigh"` | `--variant high` (opencode run) |
| 샌드박스 | `--sandbox workspace-write` | 없음 (풀 파일시스템 접근) |
| 세션 resume | `codex exec resume <id>` | `omo run --session-id <id>` |
| 종료 감지 | 프로세스 종료 | todo완료+idle 자동 감지 |
| 에이전트 선택 | 없음(단일) | `--agent` 로 명시 |

---

## 트러블슈팅

| 증상 | 조치 |
|------|------|
| `omo: command not found` | `bunx oh-my-openagent run ...` 로 대체 |
| `bunx: command not found` | `curl -fsSL https://bun.sh/install | bash` |
| oh-my-openagent 플러그인 미등록 | `bunx oh-my-openagent install` 실행 |
| opencode 버전 부족 | `opencode upgrade` |
| session_id 추출 실패 | round1.log에서 `session` 키 직접 확인 |
| resume 즉사 | session_id 오입력 또는 세션 만료 — 새 세션으로 재위임 |
| 변경이 지정 디렉토리 밖에 생성됨 | `-d` 경로 재확인, HANDOFF의 프로젝트 루트 점검 |
| 인증 오류 | `opencode providers` 로 프로바이더별 인증 상태 확인 |
