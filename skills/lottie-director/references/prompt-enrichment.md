# Prompt Enrichment — 공식 Prompt guide 5원칙 적용표

> 출처: [diffusionstudio/lottie README — Prompt guide](https://github.com/diffusionstudio/lottie#prompt-guide).
> 이 문서는 그 5원칙을 브리프 항목으로 기계적으로 채우기 위한 실무 표다.

## 5원칙 원문 요약

1. **Ground the model** — SVG·실제 데이터·스크린샷 등 구체 자산을 제공할수록 결과가
   크게 좋아진다.
2. **Use motion design terminology** — ease-in, ease-out, ease-in-out 같은 모션 디자인
   언어로 타이밍과 움직임을 서술한다.
3. **Think like a camera operator** — 전문 모션 그래픽은 카메라 움직임에 의존하는 경우가
   많다. 카메라 push·pan·zoom·rig 스타일 모션을 프롬프트에 포함한다.
4. **Request the controls you need** — 기본 출력은 보통 배경색(bgColor) 컨트롤만 노출한다.
   다른 속성을 커스터마이즈하려면 명시적으로 컨트롤 생성을 요청해야 한다.
5. **Specify FPS and duration** — 특정 프레임레이트·길이가 필요하면 원하는 FPS와
   총 프레임 수를 프롬프트에 포함한다.

## 모호어 → 모션 용어 번역표 (원칙②)

| 사용자 표현 | 브리프 용어 |
|---|---|
| 부드럽게, 자연스럽게 | ease-in-out |
| 스르륵 나타나게 / 사라지게 | fade-in with ease-out entrance / fade-out with ease-in exit |
| 통통, 탱글, 쫀득, 튀는 느낌 | spring / bounce with overshoot, then settle |
| 착착, 순서대로, 하나씩 | staggered entrance (offset a few frames per element) |
| 임팩트 있게, 빵 터지게 | anticipation + scale punch (overshoot then settle) |
| 빨려 들어가듯 | ease-in acceleration + camera push-in |
| 슥 지나가듯, 흘러가듯 | constant-speed pan / continuous motion path |
| 깜빡이게, 숨쉬듯 | opacity pulse / low-amplitude scale loop |
| 물 흐르듯 이어지게 | match-cut transitions, continuous motion between beats |
| 살짝만 움직이게 | subtle secondary motion, low-amplitude idle loop |
| 고급스럽게, 미니멀하게 | restraint: fewer moves, ease-in-out, no overshoot |

## 타입별 기본값 (원칙③④⑤)

사용자가 지정하지 않은 칸만 이 값으로 채운다. fps 기본은 60(파일 크기가 문제면 30 제안).

| 타입 | frames(≈길이) | loop | 카메라(원칙③) | 컨트롤 제안(원칙④) | background |
|---|---|---|---|---|---|
| 로더/스피너/아이콘 | 60–120 (1–2s) | yes(seamless) | none — static | primaryColor | transparent |
| 로고 리빌 | 120–180 (2–3s) | no | subtle push-in(마무리, ~3% scale) | logoColor | transparent |
| 타이포/타이틀/인용 | 120–240 (2–4s) | no | 선택적 slow push | text 슬롯(문구 교체), textColor | 용도별 |
| UI 마이크로인터랙션·상태 피드백 | 30–90 (0.5–1.5s) | 상태별 | none — static | stateColor(success/error 등) | transparent |
| 로워서드/오버레이 | 150–300 (in–hold–out) | no | none | name/title text 슬롯, barColor | transparent |
| 데이터/차트/KPI | 180–300 (3–5s) | no | pan along flow, zoom to callout | seriesColor, 수치 text 슬롯 | full-frame + bgColor |
| 다이어그램/기술 라인 | 180–360 (3–6s) | 선택 | pan along flow trace | lineColor, calloutColor | full-frame + bgColor |
| 프로모/멀티 비트(챕터) | 300–600 (5–10s) | no | 비트 전환마다 push/pan/zoom 교차 | headline text 슬롯, brandColor | full-frame + bgColor |

> background 정책은 text-to-lottie 규칙과 동일하게 맞춘다: 로고·아이콘·로더·오버레이·
> 로워서드·SVG 자산은 transparent 기본, full-frame 독립 구성은 bgColor 슬롯을 가진
> 배경 레이어 포함.

## 카메라 연출 휴리스틱 (원칙③)

- **단일 로더/아이콘/마이크로인터랙션**: 카메라 없음. 요소 자체 모션에 집중 — 억지 카메라는 감점.
- **로고 리빌**: 마무리 구간에 subtle push-in(2–4% scale) 정도만.
- **스토리/프로모/챕터**: 비트 전환마다 camera push, lateral pan, zoom-out reveal을 교차.
- **데이터/다이어그램**: 흐름을 따라 pan, 강조 시점에 zoom to callout.
- 사용자가 정적을 원하면 `static composition (intentional)`을 명시한다.

## 컨트롤 제안 규칙 (원칙④)

- 기본 노출은 bgColor뿐이라고 가정한다. **bgColor는 브리프의 Controls에 다시 적지 않는다** —
  full-frame 구성의 bgColor 슬롯은 Format 필드의 `full-frame + bgColor`가 담당하고,
  transparent 구성에는 배경 레이어 자체가 없다.
- "나중에 바꿀 만한 것"이 보이면 컨트롤로 요청: 브랜드 컬러, 강조 컬러, 텍스트 문구, 수치 라벨.
- **3~5개 이하로 절제** — 모든 속성을 슬롯화하면 프로퍼티 패널이 무의미해진다.

## 완성 브리프 예시

### 예시 1 — 러프 요청: "우리 로고로 고급스러운 인트로 애니메이션 만들어줘" (`assets/logo.svg` 존재)

```
## Lottie Brief
- Deliverable: premium logo reveal intro for brand opening
- Grounding assets: assets/logo.svg (preserve original geometry and viewBox)
- Motion language: stroke reveal follows natural path direction with ease-in-out;
  fill fades in with ease-out after path completes; final settle without overshoot (premium = restraint)
- Camera direction: subtle push-in (~3% scale) across the last third; otherwise static
- Controls: logoColor
- Format: 60 fps, 150 frames (~2.5s), loop no, background transparent
```

### 예시 2 — 러프 요청: "결제 성공하면 나올 체크 애니메이션, 통통 튀는 느낌으로"

```
## Lottie Brief
- Deliverable: payment success feedback — animated checkmark
- Grounding assets: none — design from description
- Motion language: circle scales in with spring overshoot then settles;
  check stroke draws on with ease-out; single bounce, no secondary wiggle
- Camera direction: static composition (intentional)
- Controls: successColor
- Format: 60 fps, 72 frames (~1.2s), loop no, background transparent
```

### 예시 3 — 공식 README Quick Start 예시 (지향할 완성형)

> Create Lottie animation from SVG path in
> https://github.com/JaceThings/SF-Hello/blob/main/SVG/hello-en.svg.
> Reveal path animation follows natural path direction. Apply premium apple themed
> gradient path. Use ease-in-out timing, transparent background, preserve original
> SVG geometry.

자산(SVG URL)·모션 용어(ease-in-out)·배경 정책(transparent)·지오메트리 보존까지
한 문단에 들어간 형태 — 브리프 템플릿은 이것을 구조화한 것이다.
