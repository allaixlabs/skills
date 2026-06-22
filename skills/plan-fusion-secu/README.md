# plan-fusion-secu — 보안 통합 CLI Fusion

`plan-fusion`에 **시큐어 코딩 검증 3계층**(L1 정적분석 + L2 LLM 체크리스트 + L3 강제 보안 백엔드)을 통합한 변형.

## 핵심

- **진입 즉시 L1+L2 강제** — 별도 `-secu` 스킬로 들어온 시점이 보안 의도. codeSecurity 프리셋 또는 명시 시 L3 추가.
- **43개 체크리스트** — OWASP Top 10(2021/2025 병기) + OWASP LLM Top 10 + CWE/SANS Top 25 + 누락 3개(예외오처리·Prototype Pollution·Mass Assignment). SSOT: `references/secure-coding.md`.
- **3계층 평가**:
  - L1(정적 분석): semgrep·gitleaks·npm/pip/cargo audit → exit code로 객관 판정(loop.md "실행 증거 필수" 정렬)
  - L2(LLM 판단): Judge/Synth가 보안 루브릭으로 평가(기존 Fusion 라운드 안, 비용 0)
  - L3(강제 백엔드): codeSecurity 시 외부 조사(PoC·공급망 평판)

## 사용

```
/plan-fusion-secu <task>
```

예: "이 결제 API 보안 검증 포함해서 다중 모델로 풀어", "인증 모듈 취약점 점검하며 교차검증", "codeSecurity 프리셋으로 보안 코드리뷰".

## 다른 스킬과의 관계

| 스킬 | 용도 |
|---|---|
| **plan-fusion** | 보안 검증 없는 일반 다중 모델 작업 |
| **plan-fusion-secu** | 보안 검증 포함 다중 모델 작업(이 스킬) |
| **plan-fusion-dev-secu** | 계획(plan-fusion-secu) + 개발 체이닝(보안 게이트 포함) |

## 구조

```
plan-fusion-secu/
├── SKILL.md                           ← 보안 게이트 추가된 워크플로우
├── README.md                          ← 이 파일
├── references/
│   └── secure-coding.md               ← SSOT (체크리스트 + 분배 매트릭스 + 루브릭)
├── scripts/
│   ├── check-fusion-secu.sh           ← check-fusion.sh 래퍼 + SECURE_MODE + L1 도구 감지
│   └── run-secure-l1.sh               ← L1 정적 분석 러너
└── templates/
    ├── fusion-judge-secu.md.tmpl      ← 보안 루브릭(L2) 주입 Judge
    ├── fusion-synth-secu.md.tmpl      ← 보안 위험·AC 산출 Synth
    └── HANDOFF-secu.md.tmpl           ← SECURE_SCOPE + 체크리스트 주입 HANDOFF
```

**형제 스킬 자산 상대참조**(SSOT — 복제 아님): `../plan-fusion/`의 SKILL.md·fusion.md·routing-fusion.md·council-worktrees.sh 등.

## 사전 요구

- `plan-fusion/`이 같은 레포에 있어야 함(check-fusion-secu.sh가 래핑).
- L1 도구(권장): `semgrep`, `gitleaks`(또는 `trufflehog`), 스택별 의존성 스캐너(`npm audit`/`pip-audit`/`cargo audit`).
  - 도구가 없어도 L2(LLM 판단)로 폐인동은 가능하나, 객관 exit code가 없어 품질 저하.

## 검증 매트릭스 상태

본 체크리스트는 plan-fusion codeSecurity 프리셋(7호출 — codex·claude·agy·glm·kimi 교차검증) + 오케스트레이터 사실 판정을 거쳤다(2026-06-22):
- 12개 재분배 확정(T2-1/3/4/6/7/8/10, T3-9/20, T1-8, T2-5, T1-5)
- 3개 누락 추가(예외오처리·Prototype Pollution·Mass Assignment)
- 4개 코드 오기 수정(CWE-1427, CWE-1426, OWASP A06/A10 정확명)
