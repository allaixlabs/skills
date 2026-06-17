#!/usr/bin/env python3
from __future__ import annotations

import argparse, base64, binascii, datetime as dt, hashlib, json, pathlib, shutil, struct, sys
from typing import NamedTuple, Union

E_ARGS, E_REF, E_NOSESSION, E_NOIMG, E_REFUSAL = 2, 4, 6, 7, 8; EXTS = frozenset({".png", ".jpg", ".jpeg", ".webp"})
BAD_ROOTS = tuple(pathlib.Path(p) for p in "/bin /boot /dev /etc /lib /lib64 /proc /root /run /sbin /sys /usr /System /Library /private/etc /var/root /var/log /var/db /private/var/root /private/var/log /private/var/db".split())
GEN_ROOT = pathlib.Path.home() / ".codex" / "generated_images"
REFUSALS = tuple("quota|entitlement|not entitled|usage limit|rate limit|upgrade your plan|forbidden|unauthorized|image generation is not|image generation unavailable|image_generation disabled|temporarily unavailable|capacity".split("|"))
Json = Union[None, bool, int, float, str, list["Json"], dict[str, "Json"]]
JMap = dict[str, Json]


class CliError(Exception):
    def __init__(self, code: int, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


class Doc(NamedTuple):
    path: pathlib.Path
    text: str


class Event(NamedTuple):
    call_id: str | None
    revised_prompt: str | None
    result_b64: str | None
    saved_path: str | None
    session: pathlib.Path
    order: int


def strip_private(raw: str) -> str: return raw[len("/private"):] if raw.startswith("/private/") else raw


def under(path: pathlib.Path, root: pathlib.Path) -> bool:
    p, r = path.resolve(strict=False), root.resolve(strict=False)
    return p == r or r in p.parents


def validate_out(raw: str) -> pathlib.Path:
    if raw.strip() == "":
        raise CliError(E_ARGS, "invalid-output: empty --out path")
    out = pathlib.Path(raw).expanduser().resolve(strict=False)
    if out.suffix.lower() not in EXTS:
        raise CliError(E_ARGS, "invalid-output: extension must be .png, .jpg, .jpeg, or .webp")
    if out.parent == pathlib.Path("/"):
        raise CliError(E_ARGS, "invalid-output: refuses to write at filesystem root")
    norm = pathlib.Path(strip_private(str(out)))
    for root in BAD_ROOTS:
        if under(out, root) or under(norm, pathlib.Path(strip_private(str(root)))):
            raise CliError(E_ARGS, f"invalid-output: refuses to write under {root}")
    if out.parent.exists() and not out.parent.is_dir():
        raise CliError(E_ARGS, "invalid-output: parent path is not a directory")
    return out


def out_for(base: pathlib.Path, index: int, count: int) -> pathlib.Path: return base if count == 1 else base.with_name(f"{base.stem}-{index}{base.suffix}")


def image_format(data: bytes) -> str | None:
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "png"
    if data.startswith(b"\xff\xd8\xff"):
        return "jpg"
    if len(data) >= 12 and data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "webp"
    return None


def validate_ref(raw: str) -> pathlib.Path:
    ref = pathlib.Path(raw).expanduser().resolve(strict=False)
    if not ref.is_file():
        raise CliError(E_REF, f"ref-not-found: {raw}")
    try:
        head = ref.read_bytes()[:16]
    except OSError as err:
        raise CliError(E_REF, f"ref-not-readable: {raw}: {err.strerror}") from err
    if image_format(head) is None:
        raise CliError(E_REF, f"ref-not-image: {raw} is not PNG, JPEG, or WebP")
    return ref


def field(mapping: JMap, key: str) -> str | None:
    value = mapping.get(key); return value if isinstance(value, str) and value else None


def payload(line: str) -> JMap | None:
    try:
        parsed: Json = json.loads(line)
    except json.JSONDecodeError:
        return None
    if not isinstance(parsed, dict):
        return None
    nested = parsed.get("payload")
    if isinstance(nested, dict):
        outer = parsed.get("type")
        inner = nested.get("type")
        if (outer, inner) in (("event_msg", "image_generation_end"), ("response_item", "image_generation_call")):
            return nested
    return parsed if parsed.get("type") in ("image_generation_end", "image_generation_call") else None


def session_paths(list_file: pathlib.Path) -> list[pathlib.Path]:
    try:
        lines = list_file.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError as err:
        raise CliError(E_NOSESSION, f"no-session: cannot read session list: {err.strerror}") from err
    paths = [pathlib.Path(line).expanduser() for line in lines if line.strip()]
    if not paths:
        raise CliError(E_NOSESSION, "no-session: session list is empty")
    return paths


def read_docs(paths: list[pathlib.Path], run_id: str | None) -> list[Doc]:
    docs: list[Doc] = []
    for path in paths:
        try:
            docs.append(Doc(path, path.read_text(encoding="utf-8", errors="replace")))
        except OSError:
            continue
    return [doc for doc in docs if run_id in doc.text] if run_id else docs


def refusal_seen(docs: list[Doc]) -> bool:
    return any(any(hint in doc.text.lower() for hint in REFUSALS) for doc in docs)


def events_from(docs: list[Doc]) -> list[Event]:
    events: list[Event] = []
    for doc in docs:
        for line in doc.text.splitlines():
            item = payload(line)
            if item is None:
                continue
            result = field(item, "result")
            saved = field(item, "saved_path")
            if result is None and saved is None:
                continue
            events.append(Event(field(item, "call_id"), field(item, "revised_prompt"), result, saved, doc.path, len(events)))
    return events


def identities(event: Event) -> list[str]:
    keys: list[str] = []
    if event.saved_path:
        saved = pathlib.Path(event.saved_path).expanduser().resolve(strict=False)
        keys.append("saved:" + strip_private(str(saved)))
    if event.result_b64:
        digest = hashlib.sha256(event.result_b64.encode("ascii", errors="ignore")).hexdigest()
        keys.append(f"result:{len(event.result_b64)}:{digest}")
    if event.call_id:
        keys.append(f"call:{event.call_id}")
    return keys or [f"event:{event.session}:{event.order}"]


def merge(left: Event, right: Event) -> Event:
    source = left if left.order <= right.order else right
    return Event(
        left.call_id or right.call_id,
        left.revised_prompt or right.revised_prompt,
        left.result_b64 or right.result_b64,
        left.saved_path or right.saved_path,
        source.session,
        min(left.order, right.order),
    )


def dedupe(events: list[Event]) -> list[Event]:
    keyed: dict[str, Event] = {}
    order: list[str] = []
    for event in events:
        event_keys = identities(event)
        existing = next((keyed[key] for key in event_keys if key in keyed), None)
        merged = merge(existing, event) if existing is not None else event
        if existing is None:
            order.append(event_keys[0])
        for key in event_keys:
            keyed[key] = merged
        for key, value in list(keyed.items()):
            if value is existing:
                keyed[key] = merged
    seen: set[int] = set()
    unique: list[Event] = []
    for key in order:
        event = keyed[key]
        marker = id(event)
        if marker not in seen:
            seen.add(marker)
            unique.append(event)
    return unique


def safe_saved(raw: str | None) -> pathlib.Path | None:
    if not raw:
        return None
    saved = pathlib.Path(raw).expanduser().resolve(strict=False)
    root = GEN_ROOT.resolve(strict=False)
    saved_norm = strip_private(str(saved))
    root_norm = strip_private(str(root))
    if not (under(saved, root) or saved_norm == root_norm or saved_norm.startswith(root_norm + "/")):
        return None
    try:
        return saved if saved.is_file() and saved.stat().st_size > 0 else None
    except OSError:
        return None


def dimensions(data: bytes, fmt: str | None) -> tuple[int, int] | None:
    return struct.unpack(">II", data[16:24]) if fmt == "png" and len(data) >= 24 and data[12:16] == b"IHDR" else None


def materialize(event: Event) -> tuple[bytes, pathlib.Path | None, str]:
    saved = safe_saved(event.saved_path)
    if saved is not None:
        try:
            data = saved.read_bytes()
        except OSError:
            data = b""
        if image_format(data) is not None:
            return data, saved, "saved_path"
    if event.result_b64 is not None:
        try:
            data = base64.b64decode(event.result_b64, validate=True)
        except binascii.Error as err:
            raise CliError(E_NOIMG, "no-image-payload: invalid base64 image result") from err
        if image_format(data) is not None:
            return data, None, "result"
    raise CliError(E_NOIMG, "no-image-payload: no readable image bytes")


def write_meta(out: pathlib.Path, event: Event, data: bytes, source_path: pathlib.Path | None, source: str, args: argparse.Namespace) -> None:
    fmt = image_format(data)
    dims = dimensions(data, fmt)
    meta = {
        "raw_prompt": args.prompt, "revised_prompt": event.revised_prompt,
        "model": args.model, "reference_images": args.refs, "run_id": args.run_id,
        "timestamp": dt.datetime.now(dt.timezone.utc).isoformat(), "call_id": event.call_id,
        "session_rollout": str(event.session), "saved_path": event.saved_path,
        "source": source, "source_path": str(source_path) if source_path else None,
        "output_path": str(out),
        "output": {"byte_size": len(data), "format": fmt, "width": dims[0] if dims else None, "height": dims[1] if dims else None},
    }
    out.with_name(out.name + ".json").write_text(json.dumps(meta, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def extract(args: argparse.Namespace) -> int:
    base = validate_out(args.out)
    paths = session_paths(pathlib.Path(args.sessions_list))
    all_docs = read_docs(paths, None)
    docs = read_docs(paths, args.run_id)
    if not docs:
        raise CliError(E_REFUSAL, "quota-or-entitlement-refused?: Codex appears to have declined image generation") if refusal_seen(all_docs) else CliError(E_NOIMG, "no-image-payload: no rollout matched the run id")
    events = dedupe(events_from(docs))
    if not events:
        raise CliError(E_REFUSAL, "quota-or-entitlement-refused?: Codex appears to have declined image generation") if refusal_seen(docs) else CliError(E_NOIMG, "no-image-payload: no structured image_generation events found")
    ready: list[tuple[Event, bytes, pathlib.Path | None, str]] = []
    last_error: CliError | None = None
    for event in events:
        if len(ready) >= args.count:
            break
        try:
            data, source_path, source = materialize(event)
        except CliError as err:
            last_error = err
            continue
        ready.append((event, data, source_path, source))
    if not ready:
        raise last_error or CliError(E_NOIMG, "no-image-payload: no usable image bytes found")
    written: list[pathlib.Path] = []
    actual_count = len(ready)
    for index, item in enumerate(ready, start=1):
        event, data, source_path, source = item
        out = out_for(base, index, actual_count)
        out.parent.mkdir(parents=True, exist_ok=True)
        tmp = out.with_name(out.name + ".tmp")
        tmp.write_bytes(data)
        shutil.move(str(tmp), str(out))
        if not args.no_sidecar:
            write_meta(out, event, data, source_path, source, args)
        written.append(out)
    if actual_count < args.count:
        print(f"warning: requested {args.count} image(s), extracted {actual_count}", file=sys.stderr)
    print("\n".join(str(path) for path in written))
    return 0


def parse(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Extract structured Codex image_generation output.")
    for flag in ("--out", "--sessions-list", "--run-id", "--validate-out"):
        parser.add_argument(flag)
    parser.add_argument("--prompt", default=""); parser.add_argument("--model", default="codex default")
    parser.add_argument("--ref", dest="refs", action="append", default=[])
    parser.add_argument("--count", type=int, default=1)
    parser.add_argument("--no-sidecar", action="store_true")
    parser.add_argument("--validate-ref", action="append", default=[])
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse(argv)
    try:
        if args.count < 1:
            raise CliError(E_ARGS, "bad-args: --count must be positive")
        if args.validate_out is not None:
            validate_out(args.validate_out)
            return 0
        for ref in args.validate_ref:
            validate_ref(ref)
        if args.validate_ref: return 0
        if args.out is None or args.sessions_list is None:
            raise CliError(E_ARGS, "bad-args: --out and --sessions-list are required")
        return extract(args)
    except CliError as err:
        print(err.message, file=sys.stderr)
        return err.code


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
