# plan-then-codex

**Claude = 두뇌(분석·계획·검증), Codex = 손(구현)** — "분석은 claude로 하고 실제 구현은 codex에 위임해" 류 요청을 표준 워크플로우로 패키징한 Claude Code 스킬.

> 핵심 전제: Codex는 Claude의 대화 컨텍스트를 전혀 모른다. 위임 품질은 **자기완결적 HANDOFF 문서**가 결정하며, 이 스킬은 그 작성·전달·검증 루프를 강제한다.

## 무엇을 하나

1. **요청 파싱** — "gpt5.5", "xhigh" 같은 모델/effort 언급을 `codex exec` 플래그로 변환 (없으면 `~/.codex/config.toml` 기본값)
2. **ANALYZE** — Claude가 코드·실행 중인 페이지를 직접 분석 (UI면 스크린샷 캡처 → 텍스트 스펙 변환)
3. **PLAN** — 자기완결 구현 지시서(HANDOFF) 작성: 파일별 구체 지시·Out of scope·실행 가능한 Acceptance Criteria
4. **DELEGATE** — `codex exec`를 백그라운드로 실행 (workspace-write 샌드박스, before 스크린샷 `-i` 첨부)
5. **VERIFY** — diff 범위 검사 + 기준별 실행 증거 확인. 미달분은 `codex exec resume --last`로 같은 세션에 재지시 (최대 3라운드)

역할 경계는 절대 규칙: Claude는 검증 중 발견한 문제도 직접 고치지 않고 Codex에 되돌린다. Codex는 재계획·범위 확장 금지.

## 전제조건

- **Codex CLI** ≥ 0.138 — `npm install -g @openai/codex`
- **인증** — `codex login` 1회
- (권장) `~/.codex/config.toml`에 `model` / `model_reasoning_effort` 기본값 설정

사전 점검은 동봉 스크립트로(읽기 전용):

```bash
bash scripts/check-codex.sh
# CODEX_INSTALLED / CODEX_VERSION / CODEX_AUTH / DEFAULT_MODEL / DEFAULT_EFFORT 출력
```

## 설치

```bash
npx skills add allaixlabs/skills --skill plan-then-codex
```

수동 설치:
```bash
git clone https://github.com/allaixlabs/skills.git ~/project/skills   # 이미 있으면 생략
ln -s ~/project/skills/skills/plan-then-codex ~/.claude/skills/plan-then-codex  # 심볼릭 링크 권장
```

새 Claude Code 세션부터 자동 인식된다. **Codex 쪽 설치는 불필요** — HANDOFF가 stdin으로 전달되는 Claude Code 단독 오케스트레이션이다 (loop-md의 `AGENTS.md` 어댑터 같은 Codex측 세팅 없음).

## 사용법

별도 명령 없이 자연어 트리거로 동작한다:

```
http://localhost:3999/ 랜딩페이지를 상세하게 분석하고 디자인을 전문가 느낌이 나도록 개선해.
단, 계획 및 분석은 claude로 진행하고 실제 구현은 codex gpt5.5 xhigh를 사용해.
```

명시 호출: `/plan-then-codex <작업 내용>`

## loop-md 연동

프로젝트 루트에 `loop.md`가 있으면 VERIFY 단계에서 loop-md 스킬 Verify 모드(①Pass/Fail 게이트·②정량·③정성)를 함께 수행한다. 없으면 N/A.

## 구조

```
plan-then-codex/
├── SKILL.md                  # 5단계 워크플로우 (Claude Code 오케스트레이션)
├── README.md                 # 이 문서
├── references/codex-cli.md   # codex exec 플래그·백그라운드·resume·트러블슈팅
├── templates/HANDOFF.md.tmpl # Codex 구현 지시서 템플릿
└── scripts/check-codex.sh    # 사전 점검 (read-only)
```
