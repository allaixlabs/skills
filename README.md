# makeskill

Claude Code용 에이전트 스킬 모음.

## loop-md — 완료 기준 관리 루프 (Definition of Done)

AI가 눈앞의 Task에만 매몰되어 전체 맥락·완료 기준을 잃는 것을 막는 **감독관(`loop.md`) 프레임워크**.

- **Setup 모드**: 프로젝트 스택을 자동 감지해 빌드/타입/테스트/린트 명령이 채워진 `loop.md`를 생성. 참조 문서 스텁·감시 루프 가이드는 선택.
- **Verify 모드**: "완료" 선언 전 3단계 검증 강제 — ① Pass/Fail 게이트(타협 없음) ② 정량 측정 ③ 정성 자기평가(감점 시 근거+액션 필수).
- **R&R 가드레일**: AI 자동 처리 vs 인간 승인 경계.
- **감시 루프**: CI/CD 폴링·자가치유·리뷰 반영 실행 가이드.

### 설치
```bash
cp -r loop-md ~/.claude/skills/loop-md
```
이후 `/loop-md` 로 호출.

### 구조
```
loop-md/
├── SKILL.md                # Setup/Verify 오케스트레이션
├── reference/              # DOD · RNR · WATCH-LOOP 상세
├── templates/              # loop.md / report / 참조 스텁
└── scripts/detect-stack.sh # 스택 자동 감지 (read-only)
```
