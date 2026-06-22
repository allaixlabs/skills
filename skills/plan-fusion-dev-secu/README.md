# plan-fusion-dev-secu — 보안 체이닝 (계획 + 보안 + 개발 한 번에)

`plan-fusion-dev`에 **시큐어 코딩 검증**을 통합한 변형. 계획(plan-fusion-secu) → 변환 → 개발(plan-codex-opencode) 체인의 **양쪽 단계에 보안 게이트**가 적용된다.

## 핵심

- **계획 단계**: plan-fusion-secu Fusion-Research 호출 — L1+L2 강제, codeSecurity 시 L3.
- **변환 단계**: final.md의 보안 AC + SECURE_SCOPE를 handoff로 매핑 (누락 시 변환 중단).
- **개발 단계**: plan-codex-opencode 구현 후 **L1 재실행** — 신규 도입 취약점 잡기.
- **체크리스트**: `../plan-fusion-secu/references/secure-coding.md` SSOT 공유 (43개 항목).

## 사용

```
/plan-fusion-dev-secu <task>
```

예: "결제 API 보안 검증 포함 계획→개발 한 번에", "인증 모듈 시큐어 코딩 점검하며 체이닝", "codeSecurity로 잡은 설계를 보안 개발로 이어가".

## 다른 스킬과의 관계

| 스킬 | 용도 |
|---|---|
| plan-fusion-dev | 보안 없는 계획+개발 체이닝 |
| plan-fusion-secu | 보안 포함 계획만(개발 별도) |
| **plan-fusion-dev-secu** | 보안 포함 계획+개발 체이닝(이 스킬) |

## 구조

```
plan-fusion-dev-secu/
├── SKILL.md
├── README.md
└── templates/
    ├── fusion-synth-code-secu.md.tmpl   ← 체이닝+보안 Synth (final.md에 보안 AC+SCOPE 포함)
    └── HANDOFF-chain-secu.md.tmpl       ← 보안 AC 매핑 + L1 게이트 지시 HANDOFF
```

**형제 스킬 자산 상대참조**: `../plan-fusion-secu/`(SKILL.md·check-fusion-secu.sh·run-secure-l1.sh·secure-coding.md), `../plan-fusion-dev/`(체이닝 구조), `../plan-codex-opencode/`(개발 단계), `../plan-fusion/`(격리·worktree).

## 사전 요구

- 형제 스킬 3개가 같은 레포에 있어야 함: `plan-fusion-secu/`, `plan-fusion-dev/`, `plan-codex-opencode/`.
- L1 도구(권장): semgrep, gitleaks, 스택별 의존성 스캐너.

## 비용

- 계획(N+2 호출 + L1) + 개발(모드별 2~3 / 4~5) + (조건) L3 1회
- 단일 위임 대비: **Pipeline 약 8~11배, Council-Code 약 10~13배** (plan-fusion-dev보다 +1~2배 보안 오버헤드).
- 사소한 변경·되돌리기 쉬운 작업엔 과함 — plan-then-* 단일 위임 권장.
