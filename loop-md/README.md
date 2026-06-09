# loop-md

작업을 "완료"로 선언하기 전, **3단계 완료 기준(Definition of Done)** 을 강제하는 에이전트 프레임워크.
AI가 눈앞의 Task에만 매몰되어 전체 맥락·완료 기준을 잃는 것을 막는 **감독관(`loop.md`)** 패턴을 패키징했다.

> **듀얼 포맷** — Claude Code(스킬)와 Codex/기타 에이전트(`AGENTS.md`)에서 **같은 `loop.md`** 로 동작한다.

## 무엇을 하나

- **Setup 모드**: 프로젝트 스택을 자동 감지(Node·TS·Rust·Python·Go·Make)해 빌드/타입/테스트/린트 명령이 채워진 `loop.md`를 생성. 참조 문서 스텁·감시 루프 가이드·Codex 어댑터는 선택.
- **Verify 모드**: "완료" 선언 직전 3단계 검증을 강제.
  - **① Pass/Fail 게이트** — 실제 실행 + **exit code·로그·시각 증거 필수**(증거 없는 ✅ = FAIL)
  - **② 정량 측정** — 커버리지·번들 크기·에러율
  - **③ 정성 자기평가** — 1~5점, 감점 시 **근거+액션 필수**(확증 편향 방지)
- **R&R 가드레일**: AI 자동 처리 vs 인간 승인 경계. 자가치유 푸시는 코드로 집행(브랜치 화이트리스트 + 민감경로 diff 검사).

## 설치

### Claude Code (스킬)
```bash
git clone https://github.com/allaixlabs/loop-md.git ~/project/loop-md
ln -s ~/project/loop-md ~/.claude/skills/loop-md   # 심볼릭 링크 권장 (원본만 관리)
```
새 세션에서 `/loop-md` 호출. (description 트리거로 "DoD 루프 세팅", "완료 전 검증" 등으로도 작동.)

### Codex CLI / 기타 에이전트
스킬 자동 인식은 Claude Code 전용이다. Codex에서는 **`AGENTS.md`** 로 같은 규칙을 쓴다:
```bash
cp templates/AGENTS.md.tmpl <프로젝트>/AGENTS.md   # Setup 모드의 'Codex 어댑터'가 자동 수행
```
Codex가 `AGENTS.md`를 자동 로드해 "완료 전 `loop.md` 검증"을 따른다. `scripts/detect-stack.sh`는 그대로 `bash`로 호출.

## 구조

```
loop-md/
├── SKILL.md                # Claude Code 오케스트레이션 (Setup/Verify 분기)
├── reference/
│   ├── DOD.md              # 3단계 검증 상세 + 리포트 예시
│   ├── RNR.md              # AI 자동 vs 인간 승인 경계표 + 가드레일
│   └── WATCH-LOOP.md       # CI 폴링·자가치유(가드 포함)·리뷰반영
├── templates/
│   ├── loop.md.tmpl        # 감독관 DoD 문서 (체크포인트/롤백 포함)
│   ├── report.md.tmpl      # 실행 증거 강제 리포트 포맷
│   ├── AGENTS.md.tmpl      # Codex/에이전트 공통 지침 어댑터
│   └── *.stub.md           # PRD·유저플로우·UI·DB 참조 스텁
└── scripts/detect-stack.sh # 스택 자동 감지 (read-only, monorepo 경고)
```

## 핵심 원칙

- Pass/Fail 게이트에 **타협 없음** — 하나라도 실패하면 완료 아님, 롤백.
- 정성 평가는 점수만으로 끝내지 않는다 — 감점엔 반드시 근거+액션.
- 인간 승인 영역(스키마·인증·결제·마이그레이션)은 **절대 자동 커밋하지 않는다**.
