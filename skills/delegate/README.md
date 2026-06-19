# delegate

`delegate`는 `plan-*` 위임 스킬이 헷갈릴 때 쓰는 단일 진입점이다.

## 무엇을 하나

- 사용자 요청에서 위임 의도를 분류한다.
- 선택된 sibling 스킬 하나의 사전점검만 실행한다.
- 선택된 sibling의 `SKILL.md`를 런타임에 읽고 그 절차를 같은 세션에서 따른다.

`delegate`는 실제 구현 절차를 복제하지 않는다. 분석, 구현, 검증은 선택된 sibling 스킬이 맡는다.

## 라우팅 결정 트리

```text
특정 plan-* 스킬명이 이미 있는가?
├─ 예 → delegate가 가로채지 않고 그 스킬 직접 사용
└─ 아니오
   ├─ 계획 후 개발까지 한 번에 / fusion 개발 체이닝 → plan-fusion-dev
   ├─ 여러 모델 검증 / 교차검증
   │  ├─ Judge/Synth까지 위임 → plan-fusion
   │  └─ 직접 종합 / Council·Pipeline → plan-codex-opencode
   ├─ codex / gpt 명시 → plan-then-codex
   ├─ omo / opencode / sisyphus 명시 → plan-then-opencode
   └─ 모호한 "이거 구현해줘" → plan-then-codex
```

작업이 명백히 복잡하거나 고위험인데 사용자의 요청이 모호하면 한 번 확인한 뒤 분기한다. 기본값은 무거운 fusion이 아니라 경량 단일 위임이다.

## 다른 스킬과의 차이

세부 비교의 단일 출처는 루트 `README.md`의 "스킬 한눈에" 표다. `delegate`는 그 표를 대체하지 않고, 진입점 선택이 애매할 때 아래 스킬 중 하나로 연결한다.

| 스킬 | delegate 관점의 선택 기준 |
| --- | --- |
| `plan-then-codex` | GPT/Codex 단일 위임 또는 모호 요청 기본값 |
| `plan-then-opencode` | omo/opencode/Sisyphus 계열 단일 위임 |
| `plan-codex-opencode` | Codex와 opencode 패널을 직접 종합 |
| `plan-fusion` | 여러 패밀리와 Judge/Synth 합성까지 위임 |
| `plan-fusion-dev` | fusion 계획 뒤 개발까지 체이닝 |

## 전제조건

- 선택될 sibling 스킬이 설치되어 있어야 한다.
- 선택될 sibling의 `scripts/check-*.sh`가 실행 가능해야 한다.
- Bash와 sibling 스킬이 요구하는 CLI가 필요하다.

## 설치

```bash
npx skills add allaixlabs/skills --skill delegate --agent claude-code
```

필요하면 대상 sibling도 함께 설치한다.

```bash
npx skills add allaixlabs/skills --skill plan-then-codex --agent claude-code
npx skills add allaixlabs/skills --skill plan-then-opencode --agent claude-code
npx skills add allaixlabs/skills --skill plan-codex-opencode --agent claude-code
npx skills add allaixlabs/skills --skill plan-fusion --agent claude-code
npx skills add allaixlabs/skills --skill plan-fusion-dev --agent claude-code
```

## 사용법

모호한 위임 요청:

```text
delegate로 골라줘. 이 기능 구현해줘.
```

특정 백엔드 요청:

```text
codex로 구현 위임해줘.
opencode 에이전트로 처리해줘.
```

가용성 매트릭스:

```bash
bash skills/delegate/scripts/check-delegate.sh --matrix
```

선택된 route만 점검:

```bash
bash skills/delegate/scripts/check-delegate.sh plan-then-codex
```

## 구조

```text
delegate/
├── SKILL.md
├── README.md
└── scripts/
    └── check-delegate.sh
```
