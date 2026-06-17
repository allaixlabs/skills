---
name: img-maker-codex
displayName: "Img Maker Codex"
description: >-
  Generate and edit images by driving the local Codex CLI image_generation tool
  with the user's logged-in ChatGPT Plus or Pro plan. Use when the user asks to
  create, edit, restyle, vary, or compose images via codex, imagegen, GPT Image
  2, ChatGPT Images, or their ChatGPT subscription.
license: MIT
---

# Img Maker Codex

## When To Trigger

Use this skill for text-to-image generation, image editing, style transfer,
multi-reference composition, and image variations when the user wants the local
`codex` CLI route rather than a direct OpenAI API key.

Do not use it unless `codex login` is already working and the ChatGPT account has
image-generation entitlement. This skill does not grant image access.

## How To Invoke

Text-to-image:

```bash
bash ~/.claude/skills/img-maker-codex/scripts/gen.sh --prompt "a precise raw user prompt" --out ./image.png
```

Image edit or style transfer with one or more references:

```bash
bash ~/.claude/skills/img-maker-codex/scripts/gen.sh \
  --prompt "repaint this as a clean editorial watercolor" \
  --ref ./source.png \
  --ref ./palette.webp \
  --out ./watercolor.png
```

Multiple results from one Codex run, if Codex emits multiple distinct image
calls:

```bash
bash ~/.claude/skills/img-maker-codex/scripts/gen.sh --prompt "three distinct logo directions" --count 3 --out ./logo.png
```

This writes `./logo-1.png`, `./logo-2.png`, and `./logo-3.png` when three
distinct structured image results are present, plus matching sidecars such as
`./logo-1.png.json` unless `--no-sidecar` is set. The default is one image
written exactly to `--out`, plus `<out>.json`.

## Default Behavior

The user's prompt is passed through raw. The wrapper adds only operational
instructions needed to call image generation, attach references, and correlate
the session rollout. It does not translate, polish, or add style modifiers unless
the user explicitly passes `--enhance`.

Codex CLI 0.139 was measured saving PNG output to disk and recording structured
rollout events. `gen.sh` checks for `codex`, `codex --version`, `codex login
status`, `python3`, and timeout tooling before execution. The default observed image was a 1254x1254, 8-bit RGB,
non-interlaced PNG with no alpha. Treat dimensions and format as observed
behavior, not a hard contract.

## Controls

Supported flags:

- `--prompt TEXT`: required raw user prompt.
- `--out PATH`: required image output path. Prefer `.png`.
- `--ref PATH`: repeatable reference image input. PNG, JPEG, and WebP are checked.
- `--count N` or `-n N`: extract up to N distinct structured image results.
- `--model MODEL` or `-m MODEL`: pass a Codex model override.
- `--aspect-ratio RATIO`, `--size SIZE`, `--quality LEVEL`, `--format FORMAT`,
  `--transparent`: best-effort prompt hints. Codex 0.139 was verified to save
  PNG output; this script does not transcode.
- `--enhance`: opt in to prompt refinement by the image model.
- `--display`: after success, open written image files with `open` or `xdg-open`
  when available.
- `--no-sidecar`: skip `<out>.json` metadata sidecar files that otherwise store
  prompt, reference, rollout, and source-path metadata.
- `--timeout-sec N`: uses `timeout(1)` or `gtimeout` when present; warns and runs
  without an enforced timeout if neither tool is installed.

## Prerequisites

- `codex` is installed, `codex --version` runs, and `codex login status` passes.
- Codex CLI 0.139 is recommended; other versions may work but can change rollout schema.
- The logged-in ChatGPT Plus or Pro account can use image generation within the user's ChatGPT subscription limits.
- `python3` is available.
- Do not use `--ephemeral`; persistent sessions are required for rollout parsing
  and Codex's generated image files.

## Exit Codes

| code | meaning |
| ---: | --- |
| 0 | success; output image path or paths printed on stdout |
| 2 | bad arguments or invalid output path |
| 3 | missing local CLI dependency or failed preflight (`codex`, `codex --version`, `codex login status`, or `python3`) |
| 4 | reference image missing or not recognized as PNG/JPEG/WebP |
| 5 | `codex exec` failed outside entitlement/quota classification |
| 6 | no new session rollout was created for the invocation |
| 7 | no structured image payload was found in the created rollout |
| 8 | quota, entitlement, plan, or auth refusal suspected |

Failures name the failing layer in one line and avoid dumping raw Codex stderr.

## How It Works

Codex CLI 0.139 saves generated images to disk at:

```text
~/.codex/generated_images/<session-id>/<call_id>.png
```

The same rollout JSONL contains structured image events:

- `event_msg` with payload type `image_generation_end`
- `response_item` with payload type `image_generation_call`

In measured 0.139 sessions, both lines can carry the same `result` and
`saved_path`, while the `image_generation_call` line may have `call_id: null`.
The extractor therefore deduplicates by resolved `saved_path` first, then by a
stable hash of the base64 `result`, and `call_id`. A single event can contribute
multiple identity keys, so later partial-key events merge into the same output. If
a null-call-id event is the only event for an image, it is still extracted.

`~/.claude/skills/img-maker-codex/scripts/gen.sh` snapshots `~/.codex/sessions/`, runs:

```bash
codex exec --enable image_generation --sandbox read-only
```

with stdin prompt text and repeatable `-i/--image` references, then diffs the
session snapshot. `scripts/extract_image.py` parses only the new rollout
candidates, filters them by a per-run correlation token, reads structured image
events, prefers copying a safe `saved_path`, and falls back to decoding the
event `result` base64 field. From the skill root during local development,
`bash scripts/gen.sh` is also valid.

For each output image it writes a sidecar JSON at `<out>.json`, for example
`apple.png.json`, containing the raw prompt, revised prompt, model, reference
images, run id, timestamp, structured call id, source rollout, saved path, output
byte size, and detected PNG dimensions when available. Pass `--no-sidecar` to
write only the image file(s).

## Data Handling And Security

- Output paths must have an image extension and cannot target system directories
  such as `/bin`, `/etc`, `/usr`, `/System`, `/Library`, `/var/log`, `/var/db`,
  `/var/root`, or their `/private` macOS equivalents.
- Existing session files are never modified. The extractor is scoped to rollout
  files discovered by the before/after session diff for this invocation.
- A run-specific token prevents images from unrelated concurrent Codex sessions
  from being selected.
- `saved_path` is trusted only after it resolves under
  `~/.codex/generated_images/` and its bytes pass PNG/JPEG/WebP magic checks.
- Reference images are checked for existence and image magic headers before
  Codex is invoked.
- Codex keeps its original generated files under `~/.codex/generated_images/`;
  the wrapper copies from there and does not delete those originals. For sensitive
  images, prompts, or references, clean that directory separately after use.
- Sidecar JSON files include raw prompt and local paths unless `--no-sidecar` is
  used. Use `--no-sidecar` for sensitive prompts or reference filenames.
- The wrapper does not read environment secrets, install dependencies, add
  telemetry, or make network calls beyond the user's own `codex exec`.

## What This Skill Is Not

This is not a direct OpenAI API client, not a GUI, not a server, not a package
installer, and not a capability bypass. It depends on the local Codex CLI,
persistent Codex sessions, and the user's ChatGPT image entitlement.
