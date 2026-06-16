# img-maker-codex

로컬 **Codex CLI**의 `image_generation` 도구를 구동해, 사용자의 로그인된 **ChatGPT Plus/Pro 플랜**으로
이미지를 생성·편집하는 Claude Code 스킬. 별도 OpenAI API 키·과금 없이 동작한다.
기존 `gpt-image-2` 스킬의 개선 후속작 (Codex 0.139 실측 기반).

## 설치 (다른 makeskill 스킬과 동일: 심링크)

```bash
ln -s /Users/macpro/project/makeskill/skills/img-maker-codex \
      ~/.claude/skills/img-maker-codex
```

## 사용

```bash
# text-to-image
bash ~/.claude/skills/img-maker-codex/scripts/gen.sh \
  --prompt "a small blue ceramic coffee cup on a wooden table" --out ./cup.png

# image-to-image / 스타일 전이 (참조 이미지 반복 지정)
bash scripts/gen.sh --prompt "repaint as editorial watercolor" \
  --ref ./src.png --ref ./palette.webp --out ./out.png

# 한 번의 생성에서 여러 결과
bash scripts/gen.sh --prompt "three logo directions" --count 3 --out ./logo.png
```

트리거: "gpt image 2", "imagegen", "ChatGPT 구독으로 이미지 생성/편집" 등.

## 전제

- `codex` 설치 + `codex login` 완료, ChatGPT 계정에 이미지 생성 권한.
- `python3` (stdlib만 사용). macOS(bash 3.2 포함)·Linux.

## 동작 (Codex 0.139)

Codex가 생성 이미지를 `~/.codex/generated_images/<session-id>/<call_id>.png`에 저장하고 세션 rollout에
`image_generation_end`/`image_generation_call` 구조적 이벤트로 기록한다. `gen.sh`가 세션을 스냅샷-diff로
격리하고, `extract_image.py`가 구조적 이벤트를 파싱해 `saved_path`(루트 confine + magic 검사)를 우선 복사,
실패 시 `result` base64를 디코드한다. 동일 이미지의 end/call 쌍(한쪽 `call_id=null`)은 콘텐츠 신원
(`saved_path` → `result` 해시)으로 1장 병합한다. 출력마다 `<out>.json` 사이드카(raw/revised 프롬프트·모델·
참조·치수 등)를 남긴다.

자세한 rollout 스키마: `references/rollout_schema.md`. 전체 명세·exit 코드·보안: `SKILL.md`.

## 주의

- size/aspect/quality/format/transparent 플래그는 **프롬프트 힌트(best-effort)** — 모델 준수를 보장하지 않으며 transcoding 안 함.
- 출력 경로는 이미지 확장자만 허용, 시스템 디렉토리 거부. 기존 세션 파일은 읽기만(수정 안 함), 네트워크/시크릿 추가 없음.
