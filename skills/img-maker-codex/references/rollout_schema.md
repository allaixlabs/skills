# Codex 0.139 Image Rollout Schema

The extractor keys on structured JSONL events in
`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`. It does not scan for the largest
base64 blob.

## `image_generation_end`

Primary event shape:

```json
{
  "type": "event_msg",
  "payload": {
    "type": "image_generation_end",
    "call_id": "ig_...",
    "status": "generating",
    "revised_prompt": "Use case: ...",
    "result": "<base64 PNG>",
    "saved_path": "/Users/name/.codex/generated_images/<session>/<call_id>.png"
  }
}
```

Field notes:

- `call_id` is useful metadata but is not the sole deduplication key.
- `status` may still read `generating`; extraction must not gate on it.
- `revised_prompt` is copied into the sidecar.
- `saved_path` is preferred only after it resolves under
  `~/.codex/generated_images/` and passes an image magic check.
- `result` is the base64 fallback when `saved_path` is absent or unsafe.

## `image_generation_call`

Secondary event shape:

```json
{
  "type": "response_item",
  "payload": {
    "type": "image_generation_call",
    "call_id": null,
    "result": "<same base64 PNG>",
    "saved_path": "/Users/name/.codex/generated_images/<session>/<call_id>.png"
  }
}
```

Codex 0.139 can record the same image in both `_end` and `_call`, with the
`_call` line carrying `call_id: null`. The final extractor merges these by
`saved_path` or `result` hash so one generated image becomes one output. A
null-call-id line that has no matching `_end` line is still extractable.

## Non-Sources

Reference images passed through `-i` are not extracted because the parser only
accepts `image_generation_end` and `image_generation_call` payloads. Unrelated
concurrent Codex sessions are filtered out by the before/after rollout snapshot
and the run-specific correlation token.

## Output Metadata

Every image receives `<out>.json`, such as `apple.png.json`, with the raw prompt,
`revised_prompt`, model, refs, run id, `call_id`, rollout path, source path,
source kind, byte size, and PNG dimensions when available.
