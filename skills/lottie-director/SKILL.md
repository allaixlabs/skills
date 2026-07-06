---
name: lottie-director
displayName: "Lottie Director"
description: >-
  러프한 Lottie 애니메이션 요청을 diffusionstudio/lottie 공식 Prompt guide 5원칙
  (① 자산 그라운딩 ② 모션 디자인 용어 ③ 카메라 연출 ④ 컨트롤 명시 ⑤ FPS·길이 명시)을
  채운 감독급 브리프로 보강한 뒤, 실제 제작은 text-to-lottie 스킬에 위임한다.
  Use when 사용자가 "로티/애니메이션 만들어줘", "로딩 스피너/로고 애니메이션"처럼 러프하게
  Lottie 생성·수정을 요청하거나 "lottie-director", "가이드대로 로티"를 언급할 때.
  사용자가 이미 5원칙을 갖춘 상세 브리프를 줬거나 text-to-lottie 직접 사용을 지목하면
  이 래퍼 없이 text-to-lottie를 바로 쓴다. Requires: text-to-lottie 스킬
  (npx skills add diffusionstudio/lottie).
license: MIT
---

# Lottie Director

이 스킬은 **브리프 컴파일러**다. 사용자의 러프한 요청을 공식 Prompt guide 5원칙을
채운 브리프로 보강하고, Lottie JSON 작성·씬 배치·플레이어 검증은 **전부
`text-to-lottie` 스킬에 위임**한다. 이 스킬 안에서 Lottie JSON을 직접 만들지 않는다.

## 전제 확인

1. `text-to-lottie` 스킬이 설치되어 있는지 확인한다(사용 가능 스킬 목록, 또는
   `~/.claude/skills/text-to-lottie/SKILL.md` 존재).
2. 없으면 진행하지 말고 설치를 안내한다: `npx skills add diffusionstudio/lottie`

## 워크플로우

### 1. 자산 그라운딩 — 원칙① Ground the model

- 대화·첨부·프로젝트에서 구체 자산을 수집한다: SVG, 로고 파일, 실제 데이터(수치·라벨),
  스크린샷, 브랜드 컬러/폰트.
- 로고·브랜드·데이터 작업인데 원본 자산이 없고 그것이 결과를 실질적으로 바꾸면
  **한 번만** 질문한다. 그 외에는 묻지 않고 진행한다.
- 자산이 전혀 없으면 브리프에 `none — design from description`을 명시해
  위임받는 쪽이 상황을 알게 한다.

### 2. 브리프 보강 — 원칙②~⑤

[references/prompt-enrichment.md](references/prompt-enrichment.md)의 번역표와
타입별 기본값으로 아래 템플릿의 빈 칸을 채운다.
**사용자가 명시한 값은 절대 덮어쓰지 않는다** — 보강은 빈 칸만 채운다.

```
## Lottie Brief
- Deliverable: <애니메이션 한 줄 정의 + 용도(로더/로고/프로모…)>
- Grounding assets: <파일 경로/URL/데이터 — 없으면 "none — design from description">   ← 원칙①
- Motion language: <요소별 easing(ease-in/out/in-out, spring, overshoot), stagger, anticipation> ← 원칙②
- Camera direction: <push/pan/zoom/parallax + 타이밍 — 정적이면 "static composition (intentional)"> ← 원칙③
- Controls: <bgColor 외에 노출할 슬롯 — 브랜드 컬러, 텍스트 문구 등 3~5개 이하>      ← 원칙④
- Format: <fps> fps, <N> frames (~<초>s), loop <yes/no>, background <transparent|color> ← 원칙⑤
```

### 3. 위임

- `text-to-lottie` 스킬을 호출해 완성된 브리프를 그대로 전달한다.
- 위임 후에는 text-to-lottie의 레퍼런스 라우팅·씬 규칙·검증 절차에 개입하지 않는다.

### 4. 보고

위임 완료 후 사용자에게 정리해 준다:

- 씬 경로(`public/projects/<project>/<scene-N>/lottie.json`)와 플레이어 확인 방법
- 노출된 컨트롤 목록, 최종 fps/총 프레임
- **이 스킬이 보강한 항목** — 사용자가 말하지 않아 기본값·번역표로 채운 값들을
  투명하게 공개해 수정 여지를 준다.

## 규칙

- 질문 최소화: 자산 확보(최대 1회) 외에는 기본값으로 진행한다.
- 브리프의 모션 서술은 영어 모션 디자인 용어를 유지한다(ease-in-out, overshoot 등) —
  text-to-lottie 레퍼런스 문서와 어휘가 일치해야 라우팅이 정확하다.
- 카메라 연출은 "항상 넣기"가 아니다 — 로더/아이콘/마이크로인터랙션은 보통 정적이 맞다.
  타입별 휴리스틱은 references 참조.
- 사용자가 "정적으로/카메라 없이"라고 하면 브리프에 `static composition (intentional)`을
  명시해 위임받는 쪽이 임의로 카메라를 넣지 않게 한다.

## Reference

- 5원칙 원문 요약 · 모호어→모션 용어 번역표 · 타입별 기본값 · 완성 브리프 예시:
  [references/prompt-enrichment.md](references/prompt-enrichment.md)
