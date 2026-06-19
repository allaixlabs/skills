---
name: delegate
description: >-
  plan-* 위임 스킬 단일 진입점; 사용자 요청을 분류해 같은 세션에서 선택된 sibling 스킬 절차를 실행한다.
  Use when the user asks for router selection, such as "delegate로 골라줘",
  "어느 위임 스킬 쓰지?", or "적절한 위임 스킬로".
---

# delegate

## 개요

`delegate`는 `plan-*` 계열 스킬의 추천표가 아니라 분류와 실행을 맡는 dispatcher다. 사용자 요청을 라우팅한 뒤 선택된 sibling 스킬의 `SKILL.md`를 런타임에 읽고, 그 파일의 절차를 같은 세션에서 따른다.

대상 sibling:

- `plan-then-codex`
- `plan-then-opencode`
- `plan-codex-opencode`
- `plan-fusion`
- `plan-fusion-dev`

## 라우팅 우선순위

아래 순서대로 처음 일치하는 분기를 선택한다.

1. **사용자가 이미 특정 `plan-*` 스킬명을 명시한 경우**
   - `delegate`가 가로채지 않는다.
   - 사용자가 명시한 스킬을 직접 우선한다.
2. **명시적 체이닝 신호가 있는 경우**
   - 예: "계획 후 개발까지 한 번에", "fusion으로 잡고 개발까지"
   - `plan-fusion-dev`를 선택한다.
3. **모델 수나 다양성 요구가 있는 경우**
   - 예: "여러 모델로 검증", "교차검증"
   - Judge/Synth 위임까지 요구하면 `plan-fusion`을 선택한다.
   - 직접 종합하거나 Council/Pipeline 패널만 요구하면 `plan-codex-opencode`를 선택한다.
4. **명시 백엔드가 있는 경우**
   - "codex로", "gpt로"는 `plan-then-codex`를 선택한다.
   - "omo로", "opencode 에이전트로", "sisyphus로"는 `plan-then-opencode`를 선택한다.
5. **기본값: 모호한 위임 요청**
   - 예: "이거 구현해줘", "적절한 위임 스킬로 처리해줘"
   - 비용 효율 기본값으로 경량 단일 위임인 `plan-then-codex`를 선택한다.
   - 단, 작업이 명백히 복잡하거나 고위험이면 1회 확인 질문 후 분기한다.

## 실행 방식

1. 선택된 sibling 디렉토리와 `SKILL.md` 존재 여부를 확인한다.
2. 선택된 sibling의 check 스크립트를 **`scripts/check-delegate.sh <선택 스킬>`로 실행**한다(`bash` 소싱 — 형제 check 스크립트 중 일부는 실행권한이 없으므로 `check-delegate.sh`가 `bash`로 균일 처리). 직접 `scripts/check-*.sh`를 호출하지 않는다.
3. 통과하면 선택된 sibling의 `SKILL.md`를 `Read`로 읽는다.
4. 읽은 sibling `SKILL.md`의 §0~§5 절차를 같은 세션에서 따른다.

선택된 sibling의 절차를 `delegate` 본문에 인라인 복제하지 않는다. 절차의 단일 진실원은 항상 sibling `SKILL.md`다.

## 사전점검

기본은 route-first다. 선택된 sibling의 check 스크립트 1개만 실행한다.

| 선택 스킬 | 실행할 check 스크립트 |
| --- | --- |
| `plan-then-codex` | `skills/plan-then-codex/scripts/check-codex.sh` |
| `plan-then-opencode` | `skills/plan-then-opencode/scripts/check-omo.sh` |
| `plan-codex-opencode` | `skills/plan-codex-opencode/scripts/check-panels.sh` |
| `plan-fusion` | `skills/plan-fusion/scripts/check-fusion.sh` |
| `plan-fusion-dev` | `skills/plan-fusion-dev/scripts/check-fusion-dev.sh` |

사용자가 "가능한 스킬 다 보여줘"처럼 매트릭스를 요청한 경우에만 `scripts/check-delegate.sh --matrix`를 실행한다. 이 모드는 5개 check 스크립트를 전부 순차 실행하지 않고, `SKILL.md` 존재 여부와 `command -v codex/opencode/agy/claude` 공통 백엔드 프로브 1회로 가용성 매트릭스를 출력한다.

## 미설치 처리

선택된 sibling 스킬이나 해당 check 스크립트가 없으면 실행하지 않는다. 설치가 필요한 스킬명을 알려주고, `npx skills add allaixlabs/skills --skill <skill-name> --agent claude-code` 형식으로 설치하거나 해당 스킬을 직접 호출하라고 안내한다.

## 역할경계

`delegate`는 분류와 실행 진입만 담당한다. 실제 분석, 구현, 검증은 선택된 sibling 스킬과 그 백엔드가 수행한다.

인간 승인 영역인 스키마, 보안, 키와 시크릿, 결제, 배포, PRD 범위, 아키텍처 결정은 선택된 sibling 스킬의 `BLOCKED` 규칙을 따른다.

## 이 스킬을 쓰지 말아야 할 때

- 사용자가 이미 특정 `plan-*` 스킬을 명시했다면 `delegate`를 쓰지 말고 그 스킬을 직접 호출한다.
- 루트 `README.md`의 인간용 선택 트리만으로 충분히 고를 수 있다면 그 선택을 따른다.
