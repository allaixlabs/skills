# lottie-director — 공식 Prompt guide로 로티를 지시한다

> 러프한 "로티 만들어줘"를 [diffusionstudio/lottie](https://github.com/diffusionstudio/lottie)
> 공식 **Prompt guide 5원칙**을 채운 감독급 브리프로 보강한 뒤,
> 실제 제작은 설치된 `text-to-lottie` 스킬에 위임하는 래퍼 스킬.

## 왜 필요한가

`text-to-lottie`는 강력하지만, 결과 품질은 **프롬프트 품질에 비례**한다.
upstream README의 Prompt guide는 좋은 프롬프트의 조건 5가지를 명시한다:

1. **Ground the model** — SVG·실데이터·스크린샷 등 구체 자산 제공
2. **Use motion design terminology** — ease-in/out/in-out 같은 모션 언어로 서술
3. **Think like a camera operator** — 카메라 push·pan·zoom·rig 모션 포함
4. **Request the controls you need** — 기본 노출은 bgColor뿐, 필요한 컨트롤은 명시 요청
5. **Specify FPS and duration** — 원하는 FPS와 총 프레임 수 명시

사용자가 매번 이 5가지를 기억해 쓰는 대신, 이 스킬이 러프한 요청에서 빈 칸을
자동으로 채워(번역표·타입별 기본값) 브리프를 완성하고 위임한다.

## 동작 흐름

```
러프 요청 ("결제 성공 체크 애니메이션, 통통 튀게")
   │
   ▼
[1] 그라운딩 — 대화·프로젝트에서 SVG/데이터/스크린샷 수집 (없고 결정적이면 1회만 질문)
   │
   ▼
[2] 브리프 보강 — 5원칙 템플릿의 빈 칸을 번역표·타입별 기본값으로 채움
   │     "통통 튀게" → spring overshoot then settle
   │     타입=상태 피드백 → 60fps · 72 frames · transparent · successColor 컨트롤
   ▼
[3] 위임 — text-to-lottie 스킬 호출, 브리프 전달 (JSON 작성·씬 배치·검증은 전부 저쪽 소관)
   │
   ▼
[4] 보고 — 씬 경로·컨트롤·fps/frames + "이 스킬이 보강한 항목" 투명 공개
```

## 경계 (하지 않는 것)

- **Lottie JSON을 직접 만들지 않는다** — 제작·씬 규칙·플레이어 검증은 `text-to-lottie` 소관.
- **사용자가 명시한 값을 덮어쓰지 않는다** — 보강은 빈 칸만 채운다.
- **이미 5원칙을 갖춘 상세 브리프**가 오면 이 래퍼를 거치지 않고 text-to-lottie 직행.
- 컨트롤은 3~5개 이하, 카메라는 타입별 휴리스틱(로더/아이콘은 정적)으로 절제한다.

## 전제조건

| 항목 | 설치 |
|---|---|
| `text-to-lottie` 스킬 | `npx skills add diffusionstudio/lottie` |

미설치면 스킬이 진행을 멈추고 위 명령을 안내한다.

## 트리거 예시

- "로딩 스피너 로티 만들어줘"
- "우리 로고로 인트로 애니메이션 하나"
- "lottie-director로 결제 성공 체크 애니메이션"
- "가이드대로 로티 뽑아줘"

## 파일 구성

```
lottie-director/
├── SKILL.md                          # 오케스트레이션 (전제 확인 → 그라운딩 → 보강 → 위임 → 보고)
├── README.md                         # 이 문서
└── references/
    └── prompt-enrichment.md          # 5원칙 원문 요약 · 모호어→모션 용어 번역표 · 타입별 기본값 · 브리프 예시
```
