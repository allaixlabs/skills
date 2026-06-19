# plan-then-opencode

**Claude가 분석·계획·에이전트 선택·검증**을 맡고, **oh-my-openagent(omo)가 실제 구현**을 맡는 split-brain 워크플로우.

> 핵심 원칙: omo 에이전트(Sisyphus/Hephaestus/Prometheus)는 대화 컨텍스트를 모른다.
> Handoff 문서가 유일한 진실이며, Claude가 이를 자기완결적으로 작성한다.

## 무엇을 하나

1. **에이전트 선택** — 태스크 특성에 맞는 에이전트를 Claude가 선택 (Prometheus·Sisyphus·Hephaestus)
2. **계획** — HANDOFF.md 자기완결 문서 생성 (Mission·Context·Baseline·변경 지시·Acceptance Criteria)
3. **위임** — `omo run` 비대화형 실행(짧은 작업은 포그라운드 동기, 긴 작업은 백그라운드+능동 폴링; **수동 대기 금지**), session ID 추출
4. **검증** — 빌드·테스트·린트 실제 실행 + Acceptance Criteria 대조, 미달 시 resume으로 수정 요청 (최대 3라운드)
5. **리포트** — 변경 파일·기준별 충족 증거·에이전트·라운드 수 보고

## 에이전트 가이드

| 에이전트 | 역할 | 언제 |
|----------|------|------|
| **Prometheus** | 전략 플래너. 인터뷰→범위 확정→계획 | 요구사항 모호, 설계 먼저 |
| **Sisyphus** | 오케스트레이터. 병렬 서브태스크 완수 | 다단계 복잡 구현 (기본) |
| **Hephaestus** | 자율 심층 작업자. 탐색→end-to-end 실행 | 범위 명확한 단일 작업 |

## 전제조건

- **opencode** >= 1.4.0 설치 + 프로바이더 인증
- **oh-my-openagent** 플러그인 등록:
  ```bash
  bunx oh-my-openagent install
  ```
- `omo` 별칭(권장) 또는 `bunx` 설치:
  ```bash
  npm install -g oh-my-openagent   # omo 별칭 등록
  ```
  ⚠️ `bunx omo` / `npx omo` 사용 금지 — 별개 패키지가 설치됨

사전 점검:
```bash
bunx oh-my-openagent doctor
```

## 설치

```bash
npx skills add allaixlabs/skills --skill plan-then-opencode   # 권장
```

수동 설치:

```bash
git clone https://github.com/allaixlabs/skills.git ~/project/skills   # 이미 있으면 생략
ln -s ~/project/skills/skills/plan-then-opencode ~/.claude/skills/plan-then-opencode
```

새 Claude Code 세션부터 자동 인식된다.

## 사용법

자연어 트리거로 동작한다:

```
분석은 claude로 하고 구현은 omo sisyphus로 진행해
이 기능 구현을 hephaestus에 위임해서 진행해
plan-then-opencode로 인증 플로우 개선해
```

또는 슬래시 명령:

```
/plan-then-opencode <작업 설명>
```

## codex vs opencode 선택 기준

| | plan-then-codex | plan-then-opencode |
|-|----------------|-------------------|
| 에이전트 | 단일(Codex) | Prometheus/Sisyphus/Hephaestus 중 선택 |
| 멀티 프로바이더 | OpenAI 전용 | anthropic/openai/google/kimi 등 자유 |
| 샌드박스 | workspace-write 격리 | 풀 파일시스템 접근 (주의) |
| 병렬 서브태스크 | 수동 다중 실행 | Sisyphus Team Mode 자동 오케스트레이션 |
| 설치 의존성 | codex CLI | opencode + oh-my-openagent |

## 구조

```
plan-then-opencode/
├── SKILL.md                    # Claude 오케스트레이션 (5단계 워크플로우)
├── README.md                   # 이 문서
├── references/omo-cli.md       # omo run 실측 레퍼런스 — 플래그·에이전트·resume·트러블슈팅
├── templates/HANDOFF.md.tmpl   # 자기완결 구현 지시서 템플릿
└── scripts/check-omo.sh        # 사전 점검 (omo/opencode/플러그인 설치 확인)
```
