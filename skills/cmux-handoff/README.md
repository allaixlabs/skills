# cmux-handoff

**멈춘 에이전트 패널을 읽고, 요약하고, 이어받는다** — cmux의 Unix 소켓 CLI로 다른 터미널 패널(Claude/Codex/opencode/셸)의 보이는 상태를 캡처하고, 후속 지시를 보내고, 작업을 넘겨받는 Claude Code 스킬.

> 경계 원칙: **모델의 숨은 컨텍스트·툴 상태는 복구할 수 없다.** 이 스킬이 다루는 것은 터미널에 보이는 텍스트뿐이며, 모든 요약·판단의 근거를 거기에 한정한다.
> 명령은 실제 `cmux --help`(+서브커맨드 help) 실측 대조로 검증했다 — `capture-pane`/`pipe-pane`은 최상위 목록에 없는 숨은 tmux 호환 별칭(실존), 미문서 `send --dry-run`은 의존 금지로 기각.

## 무엇을 하나

1. **패널 탐색** — `list-panels`로 후보 식별, `capture-pane --surface <ref>`로 실제 가시 내용 대조
2. **캡처** — `capture-pane --scrollback --lines 120`(120줄=시작 샘플). `pipe-pane 'wc -l'`로 전체 규모 파악, 캡처 범위·잘림 가능성 보고 의무
3. **핸드오프 모드 결정** — 이 세션이 직접 이어받기 / 원 패널 에이전트에 후속 프롬프트 전송 / `pipe-pane`으로 추출·요약 / 종료된 패널은 `surface resume get`(아래 경계 참조)
4. **전송** — pre-send 체크리스트: 타깃 일치 확인 → 다중 후보면 중단·사용자 확인 → 1~2초 2회 캡처로 busy 판정 → 제출 의도 없으면 `\n` 금지 → 보낼 내용 보고 후 전송
5. **경계 보고** — 읽은 것(스크롤백) / 추론한 것 / 보낸 것을 구분해 보고

핵심 경계 둘:

- `surface resume` 결과는 **opaque restart hint이지 작업 상태 복구가 아니다** — 자동 실행 금지, 승인 우회성 플래그 검토, cwd/kind 확인, 사용자 승인 후에만 실행.
- Feed·알림·hook 이벤트는 **라우팅 메타데이터일 뿐** — 요약·판단의 증거는 capture/repo/런타임 확인으로 한정.

## 전제조건

- **cmux** 설치 + 실행 중 (`cmux ping` → `PONG`)
- 텍스트 캡처/전송은 설정 불필요. Feed·알림·resume 메타데이터까지 쓰려면 대상 패널의 에이전트 통합 필요:
  - **Claude Code**: cmux 관리 pane에서 실행 시 자동(수동 설치 불필요)
  - **Codex 등 기타 에이전트**: `cmux hooks setup`(전체) 또는 `cmux hooks codex install`(개별) 1회

## 설치

```bash
npx skills add allaixlabs/skills --skill cmux-handoff   # 권장
```

수동 설치:

```bash
git clone https://github.com/allaixlabs/skills.git ~/project/skills   # 이미 있으면 생략
ln -s ~/project/skills/skills/cmux-handoff ~/.claude/skills/cmux-handoff
```

새 Claude Code 세션부터 자동 인식된다.

## 사용법

자연어 트리거로 동작한다:

```
옆 cmux 패널에서 멈춘 codex 작업 읽고 상태 요약해줘
surface:17 패널 작업을 이어받아서 계속 진행해
저 패널에 "테스트부터 고쳐" 라고 보내줘
```

## 구조

```
cmux-handoff/
├── SKILL.md                  # 핸드오프 워크플로우 (탐색→캡처→모드 결정→전송→경계 보고)
├── README.md                 # 이 문서
├── references/cmux-cli.md    # cmux CLI 실측 노트 — 명령·플래그·pre-send 체크리스트·resume 경계
└── agents/openai.yaml        # OpenAI 계열 에이전트 등록용 메타데이터(소비 주체 추정, 무해)
```
