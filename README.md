# loop-md

작업을 "완료"로 선언하기 전 **3단계 완료 기준(Definition of Done)** 을 강제하는 에이전트 프레임워크.
AI가 눈앞의 Task에만 매몰되어 전체 맥락·완료 기준을 잃는 것을 막는 **감독관(`loop.md`)** 패턴.

> **듀얼 포맷** — Claude Code(스킬)와 Codex/기타 에이전트(`AGENTS.md`)에서 **같은 `loop.md`** 로 동작.
> 스킬 상세 문서는 [`loop-md/README.md`](loop-md/README.md).

- **Setup 모드**: 프로젝트 스택을 자동 감지해 빌드/타입/테스트/린트 명령이 채워진 `loop.md`를 생성. 참조 스텁·감시 루프·Codex 어댑터는 선택.
- **Verify 모드**: "완료" 선언 전 3단계 검증 강제 — ① Pass/Fail 게이트(실행 증거 필수) ② 정량 측정 ③ 정성 자기평가(감점 시 근거+액션 필수).
- **R&R 가드레일**: AI 자동 처리 vs 인간 승인 경계. 자가치유 푸시는 브랜치·민감경로 가드로 코드 집행.

## 설치

### Claude Code (스킬)
```bash
git clone https://github.com/allaixlabs/loop-md.git ~/project/loop-md
ln -s ~/project/loop-md ~/.claude/skills/loop-md   # 심볼릭 링크 권장 (원본만 관리)
```
새 세션에서 `/loop-md` 호출.

### Codex CLI / 기타 에이전트
Setup 모드의 **Codex 어댑터**가 프로젝트 루트에 `AGENTS.md`를 깔아준다(수동: `cp loop-md/templates/AGENTS.md.tmpl <프로젝트>/AGENTS.md`).
Codex가 이를 자동 로드해 동일한 `loop.md` 검증을 따른다.

## 구조
```
loop-md/
├── SKILL.md                # Claude Code 오케스트레이션 (Setup/Verify)
├── README.md               # 스킬 상세 문서
├── reference/              # DOD · RNR · WATCH-LOOP 상세
├── templates/              # loop.md / report / AGENTS.md / 참조 스텁
└── scripts/detect-stack.sh # 스택 자동 감지 (read-only, monorepo 경고)
```
