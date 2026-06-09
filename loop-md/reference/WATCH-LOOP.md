# WATCH-LOOP.md — CI/CD 감시 · 자가치유 루프 (실행 가능)

코드 작성뿐 아니라 CI/CD 결과 모니터링·피드백 반영에서 발생하는
**인간의 대기 시간(새로고침, 로그 분석)을 제로화**하는 자동화 루프.

> 전제: `gh` CLI 인증 완료 + CI 파이프라인 존재. R&R(`RNR.md`) 경계에 걸리면 자동 수정 중단.

---

## 1. 주기적 감시 (Polling)

Claude Code의 `Monitor` 도구로 PR 체크 상태를 폴링한다. 터미널 상태가 바뀌면 알림이 온다.

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

> 실제로는 사용자가 `/loop 5m` 또는 Monitor 도구로 가동한다. 위 스니펫이 그 command 본문이다.

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
   - ✅ 자동 영역 → 수정 코드 작성 → 커밋 → 푸시 → 1번 폴링으로 복귀
   - ⛔ 인간 영역(스키마/보안/결제 등) → 자동 중단 + Slack 알림
3. K회(예: 3회) 연속 실패하거나 동일 원인 반복 시 자동 중단, 사용자 호출.

```bash
# 자동 수정 커밋 (자동 영역에 한함)
git add -A && git commit -m "fix(ci): <원인 요약> 자동 수정" && git push
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
- 무한 루프 방지: 최대 재시도 횟수와 동일 원인 반복 감지를 둔다.
- 폴링 간격은 원격 API 30초+, 로컬 0.5~1초.
