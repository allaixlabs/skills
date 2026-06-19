# img-maker-codex

로컬 **Codex CLI**의 `image_generation` 도구를 구동해, 사용자의 로그인된 **ChatGPT Plus/Pro 플랜**으로
이미지를 생성·편집하는 Claude Code 스킬. 별도 OpenAI API 키나 API 사용량 과금 없이, 사용자의 ChatGPT 구독 한도 내에서 동작한다.
기존 `gpt-image-2` 스킬의 개선 후속작 (Codex 0.139 실측 기반).

## 설치

### npx skills (권장)
```bash
npx skills add allaixlabs/skills --skill img-maker-codex --agent claude-code   # --agent 생략 시 감지된 모든 에이전트에 설치됨
```

### 수동 설치 (Claude Code)
```bash
git clone https://github.com/allaixlabs/skills.git ~/project/skills   # 이미 있으면 생략
ln -s ~/project/skills/skills/img-maker-codex ~/.claude/skills/img-maker-codex   # 심볼릭 링크 권장 (원본만 관리)
```

`~/project/skills`는 예시 경로 — 실제 클론 위치에 맞춰 두 명령의 경로를 함께 수정한다.

새 Claude Code 세션부터 자동 인식된다.

## 사용

```bash
# text-to-image
bash ~/.claude/skills/img-maker-codex/scripts/gen.sh \
  --prompt "a small blue ceramic coffee cup on a wooden table" --out ./cup.png

# image-to-image / 스타일 전이 (참조 이미지 반복 지정)
bash ~/.claude/skills/img-maker-codex/scripts/gen.sh --prompt "repaint as editorial watercolor" \
  --ref ./src.png --ref ./palette.webp --out ./out.png

# 한 번의 생성에서 여러 결과
bash ~/.claude/skills/img-maker-codex/scripts/gen.sh --prompt "three logo directions" --count 3 --out ./logo.png
```

스킬 루트에서 로컬 개발 중일 때만 `bash scripts/gen.sh ...` 상대경로 호출도 유효하다.

트리거: "gpt image 2", "imagegen", "ChatGPT 구독으로 이미지 생성/편집" 등.

## 전제

- `codex` 설치 + `codex login` 완료, ChatGPT 계정에 이미지 생성 권한. 스크립트가 `codex --version`과 `codex login status`를 사전점검한다.
- `python3` (stdlib만 사용). macOS(bash 3.2 포함)·Linux. `timeout`/`gtimeout`이 없으면 `--timeout-sec` 미적용 경고 후 실행한다.

## 동작 (Codex 0.139)

Codex가 생성 이미지를 `~/.codex/generated_images/<session-id>/<call_id>.png`에 저장하고 세션 rollout에
`image_generation_end`/`image_generation_call` 구조적 이벤트로 기록한다. `gen.sh`가 세션을 스냅샷-diff로
격리하고, `extract_image.py`가 구조적 이벤트를 파싱해 `saved_path`(루트 confine + magic 검사)를 우선 복사,
실패 시 `result` base64를 디코드한다. 동일 이미지의 end/call 쌍(한쪽 `call_id=null`)은 다중 신원
(`saved_path` + `result` 해시 + `call_id`)으로 1장 병합한다. 기본 출력은 이미지 파일과 `<out>.json`
사이드카 2개이며, 예를 들어 `cup.png`와 `cup.png.json`이 생긴다. `--no-sidecar`를 주면 이미지 파일만 남긴다.

자세한 rollout 스키마: `references/rollout_schema.md`. 전체 명세·exit 코드·보안: `SKILL.md`.

## 주의

- size/aspect/quality/format/transparent 플래그는 **프롬프트 힌트(best-effort)** — 모델 준수를 보장하지 않으며 transcoding 안 함.
- 출력 경로는 이미지 확장자만 허용, 시스템 디렉토리 거부. 기존 세션 파일은 읽기만(수정 안 함), 네트워크/시크릿 추가 없음.
- Codex 원본은 `~/.codex/generated_images/`에 남는다. 민감 이미지라면 사용 후 별도 정리하고, prompt/path 메타데이터 저장을 피하려면 `--no-sidecar`를 사용한다.

## 구조

```
img-maker-codex/
├── SKILL.md                       # 오케스트레이션 — 트리거·컨트롤·exit 코드·보안·동작 원리
├── README.md                      # 이 문서
├── references/rollout_schema.md   # Codex 0.139 세션 rollout JSONL 스키마 실측 노트
└── scripts/
    ├── gen.sh                     # 진입점 — 사전점검·세션 스냅샷-diff·codex exec 호출·이미지 복사
    └── extract_image.py           # rollout 파서 — 구조적 이미지 이벤트 추출·중복 병합·saved_path/base64 폴백
```
