# WATCH-LOOP.md — CI/CD 감시 · 자가치유 루프 (실행 가능)

코드 작성뿐 아니라 CI/CD 결과 모니터링·피드백 반영에서 발생하는
**인간의 대기 시간(새로고침, 로그 분석)을 제로화**하는 자동화 루프.

> 전제: `gh` CLI 인증 완료 + CI 파이프라인 존재. R&R(`RNR.md`) 경계에 걸리면 자동 수정 중단.

---

## 1. 주기적 감시 (Polling)

`Monitor` 도구(Claude Code·ZCode 등 지원 에이전트)로 PR 체크 상태를 폴링한다. 터미널 상태가 바뀌면 알림이 온다. `Monitor`가 없는 환경(Codex 등)은 `/loop <간격> "<command>"` 또는 셸 `while` 루프로 대체한다.

```bash
# PR <NUM> 의 체크가 모두 끝날 때까지 폴링, 상태 변화 시 emit (Monitor 도구 command 에 사용)
prev=""
while true; do
  s=$(gh pr checks <NUM> --json name,bucket 2>/dev/null || echo '[]')
  cur=$(echo "$s" | jq -r '.[] | select(.bucket!="pending") | "\(.name): \(.bucket)"' | sort)
  comm -13 <(echo "$prev") <(echo "$cur")
  prev="$cur"
  echo "$s" | jq -e 'length>0 and all(.[]; .bucket!="pending")' >/dev/null && break
  sleep 30   # 원격 API 폴링은 30초+ 간격 (레이트리밋)
done
```

> 실제로는 사용자가 `/loop 5m <command>` 또는 Monitor 도구로 가동한다. 위 스니펫이 그 command 본문이다.
> ⚠️ **`/loop`은 항상 명시 프롬프트/명령과 함께** 쓴다(`/loop <간격> "<명시>"`). **인자 없는 bare `/loop`은 쓰지 말 것** — 루트 `loop.md`(loop-md DoD 기준문)를 "매 tick 실행 task"로 오인 픽업해 5번 롤백 명령(`git stash`/`git restore`)이 매 tick 실행될 수 있다(상세: `SKILL.md`의 "`/loop` 스케줄러와의 관계"). `/loop`의 dynamic pacing(ScheduleWakeup, 기본 1200s)·3-tick 무작업 자동중단은 feature-flag/환경 의존이라 **선택적 참고**로만 둔다(기본 OFF).

---

## 2. 자가치유 (Self-Healing) — 빌드 실패 자동 수정

CI 빌드가 실패하면 사람 개입 없이 AI가 로그를 파싱·분류 후 수정 커밋/푸시한다.

```bash
# 실패한 최근 런의 로그 추출 → AI가 분석
RUN_ID=$(gh run list --branch "$(git branch --show-current)" \
          --status failure --limit 1 --json databaseId -q '.[0].databaseId')
gh run view "$RUN_ID" --log-failed > /tmp/ci-failure.log
```

자가치유 절차:
1. `/tmp/ci-failure.log` 파싱 → 원인 분류 (lint / type / test / build / 의존성)
2. **R&R 체크**: 원인이 자동 처리 영역인가? (`RNR.md`)
   - ✅ 자동 영역 → 수정 코드 작성 → **가드 통과 시** 커밋·푸시 → 1번 폴링으로 복귀
   - ⛔ 인간 영역(스키마/보안/결제 등) → 자동 중단 + Slack 알림
3. K회(예: 3회) 연속 실패하거나 동일 원인 반복 시 자동 중단, 사용자 호출.

> **⚠️ 가드레일은 문서가 아니라 코드로 집행한다 (P0).** RNR.md의 "하라"는 원칙을
> 아래 `guard()` 가 실제로 검사한다. 이 게이트를 통과하지 못하면 **push 하지 않는다.**

```bash
# --- 자가치유 푸시 선행 가드 (R&R 코드 집행) ---
guard() {
  # 1) 허용 브랜치 화이트리스트 (자동 푸시는 ai/* bot/* 에서만)
  local br; br="$(git branch --show-current)"
  case "$br" in
    ai/*|bot/*) : ;;
    *) echo "⛔ 보호 브랜치 '$br' — 자동 푸시 금지"; return 1 ;;
  esac
  # 2) 민감 경로(diff) 검사 — 스키마/인증/결제/마이그레이션은 인간 승인
  if git diff --cached --name-only | grep -qiE 'migration|schema|auth|payment|secret|\.env'; then
    echo "⛔ 민감 경로 변경 감지 — Human-in-the-Loop 필요"; return 1
  fi
  return 0
}

git add -A
if guard; then
  git commit -m "fix(ci): <원인 요약> 자동 수정" && git push
else
  # 가드 실패 → 푸시 중단 + 알림 (SLACK_WEBHOOK_URL 은 사용자 설정)
  git reset    # 스테이징 해제, 변경은 보존
  [ -n "${SLACK_WEBHOOK_URL:-}" ] && curl -sX POST "$SLACK_WEBHOOK_URL" \
    -H 'Content-Type: application/json' \
    -d '{"text":"⛔ 자가치유 가드 차단: 보호 브랜치 또는 민감 경로. 자동 진행 중단."}'
  echo "자동 수정을 중단했습니다. 사용자 확인이 필요합니다."
fi
```

---

## 3. 리뷰 반영 루프

인간 리뷰어의 단순 피드백(네이밍 등)을 인지해 자동 반영한다.

```bash
# 새 리뷰 코멘트 폴링
last=$(date -u +%Y-%m-%dT%H:%M:%SZ)
while true; do
  gh api "repos/<OWNER>/<REPO>/pulls/<NUM>/comments?since=$last" \
    --jq '.[] | "\(.user.login) @ \(.path):\(.line): \(.body)"' || true
  last=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  sleep 60
done
```

반영 절차: 코멘트 분류 → 자동 영역(네이밍/포맷/주석)만 수정·푸시 →
설계·범위 변경 요청은 사용자 확인.

---

## 안전 수칙
- 모든 자동 푸시는 R&R 자동 영역 + 허용 브랜치(`ai/*` 등)에서만.
- 무한 루프 방지: 최대 재시도 횟수와 동일 원인 반복 감지를 둔다. (loop-md의 "동일 게이트 3회 실패 중단"과 `/loop`의 "3-tick 무작업 중단"은 충돌이 아니라 서로 다른 축의 탈출 조건 — 둘 다 두면 상호보완.)
- 폴링 간격은 원격 API 30초+, 로컬 0.5~1초.
