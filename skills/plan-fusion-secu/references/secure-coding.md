# secure-coding.md — 시큐어 코딩 검증 SSOT

> 이 파일은 `plan-fusion-secu`·`plan-fusion-dev-secu` 두 스킬의 **단일 진실원(SSOT)**이다.
> 체크리스트·분배 매트릭스·평가 계층 정의가 바뀌면 이 파일만 고치면 양쪽에 반영된다.
>
> **검증 상태**: 본 매트릭스는 plan-fusion codeSecurity 프리셋(7호출, codex·claude·agy·glm·kimi)
> 교차검증 + 오케스트레이터 사실 판정을 거쳤다(2026-06-22). 12개 재분배·3개 누락 추가·4개 코드 오기 수정 반영.

---

## 0. 평가 철학

> "도구가 잡을 수 있는 건 도구가, 판단이 필요한 건 LLM이"

- **L1(정적 분석)**이 담당하는 항목은 exit code로 객관 판정 — `loop.md`의 "실행 증거 없는 통과는 무효" 원칙과 정렬.
- **L2(LLM 판단)**은 "LLM이 봤다"가 아니라 **증거 생성 단계**다 — 모델/프롬프트 버전·입력 bundle hash·파일 인용·항목별 PASS/FAIL JSON·reviewer timestamp를 남기고, wrapper가 exit code를 내야 한다(평가 산출물 스키마는 §8).
- **L3(강제 보안 백엔드)**는 codeSecurity 프리셋 또는 심층 작업 시에만 발동하는 비용 계층 — 외부 조사(PoC·공급망 평판·RAG 데이터 출처)를 담당.

---

## 1. 평가 계층 정의

| 계층 | 실행자 | 산출 | 비용 |
|---|---|---|---|
| **L1 정적 분석** | semgrep·gitleaks·trufflehog·npm/pip/cargo audit (스택 자동 감지) | exit code + 매칭 목록 | 도구 런타임 |
| **L2 LLM 체크리스트** | Judge/Synth CLI (기존 Fusion 라운드 안에서 평가) | 항목별 PASS/FAIL + 근거 인용 | 기존 호출 안 (0 추가) |
| **L3 강제 보안 백엔드** | 별도 백엔드 1회 (codeSecurity 시) | PoC·외부 조사·공급망 평판 | +1 호출 |

---

## 2. 평가자 분배 원칙 (결정 트리)

항목을 어느 계층에 배정할지 판단하는 기준:

1. **정확한 패턴/시그니처로 잡히는가?** (인젝션·시크릿·약한 알고리즘·CVE) → **L1**.
2. **패턴은 잡히나 사용 맥락이 판단을 가르는가?** (역직렬화 신뢰경계·설정 의도·SSRF 검증) → **L1+L2**.
3. **맥락·플로우·설계 판단이 필요한가?** (접근제어 비즈니스 로직·인증 플로우·위협 모델링) → **L2**.
4. **코드 밖(외부 조사·데이터 출처·모델 평판)을 봐야 하는가?** → **L3**.

⚠️ **보수적 fallback**: "이 항목은 L1인지 L2인지 모르겠다" → L2로. 도구가 못 잡는 것을 도구에 맡기는 것보다 LLM이 과대평가하는 쪽이 안전(위협 우선).

⚠️ **내적 모순 금지**: 매트릭스의 L1 열에 도구명(예: `semgrep AI(prompt-taint)`)을 적어놓고 정작 배정은 순수 L2로 두면 안 된다 — 도구가 부분 탐지라도 한다면 L1+L2로 올려야 한다(교차검증에서 발견된 사례: T2-1/6/7/10).

---

## 3. 체크리스트 — Tier 1: OWASP Top 10 (2021 기준, 2025 매핑 병기)

> OWASP 2025가 발표됐으나 현업 양쪽 체계가 혼용 중이므로 병기한다.
> **2025 정확명 주의**: A06 = Insecure Design(유지, [CWE-1441](https://cwe.mitre.org/data/definitions/1441.html)), A10 = "Mishandling of Exceptional Conditions"(신규, [CWE-1445](https://cwe.mitre.org/data/definitions/1445.html)) — "Improper Error Handling"은 비공식 약칭.

| # | 항목 | 2021 | 2025 | CWE | 배정 | L1 도구 | L2 루브릭 |
|---|---|---|---|---|---|---|---|
| T1-1 | 인젝션 (SQL/NoSQL/Command/LDAP/Template) | A03 | A05 | 89/77 | **L1** | semgrep injection | — |
| T1-2 | 암호화 실패 (평문/약해시/약알고리즘) | A02 | A04 | 327/328 | **L1+L2** | semgrep crypto + gitleaks | 사용 맥락 |
| T1-3 | 시크릿 노출 (하드코딩 키/토큰) | A02 | A04 | 798 | **L1** | gitleaks + trufflehog | — |
| T1-4 | 접근제어 결함 (IDOR/권한상승/누락인가) | A01 | A01 | 284/862 | **L1+L2** | semgrep access-control | 비즈니스 로직 |
| T1-5 | 안전하지 않은 설계 (위협모델링/신뢰경계) | A04 | **A06**(유지) | 209(부적절 — 설계 항목이라 구조적 판단) | **L2** | — | 설계 판단 |
| T1-6 | 보안 설정 오류 (CORS/기본자격/에러노출/디버그) | A05 | A02 | 16 | **L1+L2** | semgrep config | 의도적 노출 여부 |
| T1-7 | 취약한 컴포넌트 (의존성 CVE) | A06 | A03+A06 | 1104 | **L1** | npm/pip/cargo audit | — |
| T1-8 | 인증·인가 로직 결함 (세션고정/자동화대응/JWT) | A07 | A07 | 287/306 | **L1+L2** | semgrep auth(jwt/session/middleware) | 플로우 설계 |
| T1-9 | 데이터·소프트웨어 무결성 실패 (역직렬화/서명) | A08 | A08 | 502/345 | **L1+L2** | semgrep deserialize | 신뢰경계 |
| T1-10 | SSRF (외부 요청 검증 부재) | A10 | (분산) | 918 | **L1+L2** | semgrep ssrf | 검증 로직 |

---

## 4. 체크리스트 — Tier 2: OWASP LLM Top 10 (2025)

> LLM 특화 — Semgrep AI Security Rules(~27종)가 코드 통합 측면을 부분 커버.
> **CWE 정확 매핑 주의**: T2-1은 [CWE-1427](https://cwe.mitre.org/data/definitions/1427.html)(Improper Neutralization of Input Used for LLM Prompting) — 1036은 OWASP 2017 로깅 카테고리라 **금지**. T2-5는 [CWE-1426](https://cwe.mitre.org/data/definitions/1426.html)(Improper Validation of Generative AI Output) 또는 sink별 CWE-77/89/79/94 — 787(out-of-bounds write)은 **부적절**.

| # | 항목 | LLM 2025 | CWE | 배정 | L1 | L2 | L3 |
|---|---|---|---|---|---|---|---|
| T2-1 | 프롬프트 인젝션 (직접) | LLM01 | **1427**(≠1036) | **L1+L2, L3 조건부** | semgrep AI(prompt-taint) | 입력 검증 흐름 | L3(codeSecurity) |
| T2-2 | 민감정보 노출 (입력/출력 PII·시크릿) | LLM02 | 200 | **L1+L2** | gitleaks + semgrep PII | 데이터 흐름 | — |
| T2-3 | 공급망 (모델/플러그인 출처) | LLM03 | 1357 | **L1+L2+L3** | npm/pip audit(lockfile·패키지) | 패키지 검증 | 외부 조사(모델/플러그인 출처·평판) |
| T2-4 | 데이터·모델 독성 (파인튜닝/RAG ingestion) | LLM04 | — | **L2+L3** | — | ingestion/RAG control 설계 판단 | 외부 데이터 provenance |
| T2-5 | 부적절한 출력 처리 (LLM→exec/SQL) | LLM05 | **1426**(≠787) 또는 sink별 77/89/79/94 | **L1+L2** | semgrep AI(output-handling) | 검증 체인 | — |
| T2-6 | 과도한 권한 (Excessive Agency) | LLM06 | 269 | **L1+L2** | semgrep AI(tool-perms) | 최소권한 설계 | — |
| T2-7 | 시스템 프롬프트 누출 | LLM07 | — | **L1+L2** | semgrep AI(hardcoded-prompt) | 노출 경로 | — |
| T2-8 | 벡터DB/임베딩 취약 (RAG) | LLM08 | — | **L2+L3** | — | tenant filter/ACL/RAG 설계 | 외부 벡터DB·모델 설정 |
| T2-9 | 환각·거짓정보 (신뢰할 수 없는 출력) | LLM09 | — | **L2** | — | 출력 검증 의무화 | — |
| T2-10 | 리소스 소진 (DoS) | LLM10 | 400 | **L1+L2** | semgrep(rate-limit/token-cap/max-body) | 비용/abuse 모델 | — |

---

## 5. 체크리스트 — Tier 3: CWE/SANS Top 25 + 언어별 패턴 (20개)

| # | 항목 | CWE | 배정 | L1 도구 |
|---|---|---|---|---|
| T3-1 | XSS (반사/저장/DOM) | 79 | **L1** | semgrep xss |
| T3-2 | CSRF | 352 | **L1+L2** | semgrep csrf + 토큰검증 판단 |
| T3-3 | 경로 Traversal | 22 | **L1** | semgrep path-traversal |
| T3-4 | 역직렬화 상세 (pickle/yaml/marshal) | 502 | **L1+L2** | semgrep deserialize |
| T3-5 | ReDoS (정규식 DoS) | 1333 | **L1** | semgrep redos |
| T3-6 | XXE (XML 외부 엔티티) | 611 | **L1** | semgrep xxe |
| T3-7 | Open Redirect | 601 | **L1** | semgrep open-redirect |
| T3-8 | 파일 업로드 (검증 없는 업로드) | 434 | **L1+L2** | semgrep file-upload + 타입검증 판단 |
| T3-9 | 레이스컨디션/TOCTOU | 362/367 | **L1+L2** | semgrep(check-then-use/lockless) |
| T3-10 | 하드코딩 패스워드 | 259/798 | **L1** | semgrep + gitleaks |
| T3-11 | 버퍼 오버플로우 (C/C++) | 120/787 | **L1** | semgrep memory |
| T3-12 | NULL 포인터 역참조 | 476 | **L1** | semgrep null-deref |
| T3-13 | 정수 오버플로우 | 190 | **L1** | semgrep integer |
| T3-14 | 로깅·모니터링 누락 | 778 | **L2** | — |
| T3-15 | 메모리 누수/Use-After-Free | 401/416 | **L1** | semgrep memory |
| T3-16 | 클릭재킹 (Clickjacking) | 1021 | **L1** | semgrep(`X-Frame-Options`/CSP `frame-ancestors`) |
| T3-17 | HTTP 응답 분할 | 113 | **L1** | semgrep response-splitting |
| T3-18 | 비결정적 랜덤 (약한 난수) | 330/338 | **L1** | semgrep weak-random |
| T3-19 | 정보 누출 (상세 에러/스택트레이스) | 209 | **L1+L2** | semgrep info-leak |
| T3-20 | 안전하지 않은 통신 (평문 HTTP/약 TLS) | 319/295 | **L1+L2** | semgrep tls(HTTP/`verify=false`) |

---

## 6. 누락 추가 항목 (3개 — 교차검증으로 식별)

| # | 항목 | CWE | 배정 | L1 도구 | 비고 |
|---|---|---|---|---|---|
| T4-1 | 예외조건 오처리/fail-open | 755/248/636 | **L1+L2** | semgrep(empty-catch·broad-exception) | OWASP 2025 A10 본질. T3-19와 별도(fail-open·rollback 누락·auth-guard skip 잡기) |
| T4-2 | Prototype Pollution | 1321 | **L1**(JS/Node 한정) | semgrep prototype-pollution | framework/merge 유틸 맥락은 L2 |
| T4-3 | Mass Assignment/Over-posting | 915 | **L1+L2** | semgrep mass-assignment | API·ORM 앱. 접근제어 하위로 명시 가능 |

---

## 7. 분배 매트릭스 총괄표 (43개 항목)

> 40개 원본 + 3개 누락 추가 = **43개**.

| 계층 | 항목 수 | 특징 |
|---|---|---|
| **순수 L1** | 14 | 인젝션·시크릿·CVE·XSS·Traversal·ReDoS·XXE·Redirect·하드코딩PW·버퍼오버플로우·NULL역참조·정수오버플로우·UAF·응답분할·약한난수·평문통신(일부)·클릭재킹 |
| **L1+L2 혼합** | 18 | 암호화·접근제어·설정오류·역직렬화·SSRF·CSRF·파일업로드·클릭재킹·정보누출·TLS·레이스컨디션·인증로직·LLM(민감정보/출력처리/과도한권한/프롬프트누출/DoS)·예외오처리·Mass Assignment |
| **순수 L2** | 5 | 설계·로깅누락·LLM 환각대응·데이터독성(설계부분)·벡터DB(설계부분) |
| **L2+L3** | 3 | 데이터독성(외부)·벡터DB(외부) — 설계는 L2, 외부 provenance는 L3 |
| **L1+L2+L3** | 1 | LLM 공급망(lockfile=L1, 패키지검증=L2, 모델평판=L3) |
| **L3 단독** | 0 | (L3는 항상 L1/L2와 짝) |

**L2 담당 합계**: 순수 5 + 혼합 18 + L2+L3의 L2 부분 2 + L1+L2+L3의 L2 부분 1 = **26개**.

### L2 평가 부하 분할 (희석 방지)

26개를 한 번에 평가하면 품질 희석. **3묶음**으로 분할(codex 권고 채택):

- **묶음 A (전통 AppSec 맥락)**: 접근제어·역직렬화·SSRF·설정오류·암호화맥락·CSRF·파일업로드·정보누출·TLS·레이스컨디션·인증로직·예외오처리·Mass Assignment (13개)
- **묶음 B (LLM/논리 판단)**: 설계·과도한권한·프롬프트인젝션흐름·시스템프롬프트누출·환각·DoS·로깅 + LLM 민감정보/출력처리 (8개)
- **묶음 C (공급망·데이터·RAG provenance)**: LLM 공급망(패키지검증)·데이터독성·벡터DB (3개) — L3와 중복되는 외부 조사 영역

---

## 8. L1 도구 매핑 (항목 → 구체적 룰셋/명령)

`run-secure-l1.sh`이 스택을 자동 감지해 적절한 도구를 조합한다.

| 스택 감지 | 도구 | 커버 항목 |
|---|---|---|
| 모든 스택(기본) | `semgrep --config=auto` | T1-1/2/4/6/9/10, T2-1/2/5/6/7/10, T3-1~9, T4-1/2/3 |
| 모든 스택(기본) | `gitleaks detect` 또는 `trufflehog filesystem` | T1-3, T3-10, T2-2(시크릿 부분) |
| Node.js (`package-lock.json`/`yarn.lock`) | `npm audit --json` | T1-7, T2-3(lockfile 부분) |
| Python (`requirements.txt`/`Pipfile.lock`/`pyproject.toml`) | `pip-audit` 또는 `safety check` | T1-7, T2-3 |
| Rust (`Cargo.lock`) | `cargo audit` | T1-7, T2-3 |
| Ruby (`Gemfile.lock`) | `bundle audit` | T1-7, T2-3 |
| Go (`go.sum`) | `govulncheck` | T1-7, T2-3 |

**L1 산출 규약**: 각 도구는 JSON으로 출력 → `run-secure-l1.sh`가 통합해 `$RUN/l1-findings.json` 생성. exit code:
- `0` = 발견 0 (PASS)
- `1` = 발견 있음 (FAIL — 보안 게이트 차단)
- `2` = 도구 자체 오류 (WARN — L2로 폴백, 산출에 표기)

⚠️ **L1 한계 (실전 검증 2026-06-22 확인)**: 정적 분석은 **패턴 매칭 + taint tracking**에 의존한다.
- 잘 잡는 것: 명확한 시그니처(약한 해시 MD5/SHA1·pickle 역직렬화·SQL 문자열 결합·semgrep 레지스트리의 시크릿 패턴).
- 놓치는 것: **taint source가 추적 불가능한 단편 코드**(`def f(x): os.system(x)` — x가 어디서 오는지 맥락 없으면 잡기 어려움)·**맥락 의존 권한 결함**(IDOR·비즈니스 로직).
- 따라서 **L1 PASS가 "안전하다"가 아니라 "도구가 잡을 수 있는 패턴 위험이 없다"** — L2(LLM 판단)가 맥락을 보완해야 한다(L1+L2 혼합 항목이 많은 이유).
- **룰셋 주의**: `--config=auto`는 편의용이라 핵심 룰 일부를 빼먹는다(실전 검증에서 command injection·AWS key·hardcoded password 누락 확인). `run-secure-l1.sh`는 명시적 멀티 룰셋(`p/default` + `p/security-audit` + `p/owasp-top-ten` + `p/secrets`)을 사용한다.

---

## 9. L2 루브릭 (Judge/Synth 템플릿에 주입되는 평가 기준)

각 L2 항목별 "무엇을 보고 판단할 것인가" 체크포인트. Judge/Synth 템플릿(`fusion-judge-secu.md.tmpl`·`fusion-synth-secu.md.tmpl`)이 이 루브릭을 참조.

### 묶음 A (전통 AppSec)
- **접근제어(T1-4)**: 각 권한 검사 지점이 인증된 사용자의 소유권을 확인하는가? IDOR(직접 객체 참조) — URL/파라미터로 타인 자원 접근 가능?
- **역직렬화(T1-9, T3-4)**: 신뢰경계 밖 데이터를 역직렬화하는가?pickle/yaml/marshal에 `safe_load`/allowlist 적용?
- **SSRF(T1-10)**: 외부 요청 URL의 호스트/IP를 검증하는가? 내부망(169.254.0.0, 127.0.0.1, 메타데이터 엔드포인트) 차단?
- **설정오류(T1-6)**: 디버그 플래그·상세 에러·CORS `*`가 프로덕션에서 켜져 있는가? (의도적 노출인지 확인)
- **암호화맥락(T1-2)**: 약한 알고리즘(MD5/SHA1/DES)을 비밀번호·토큰·서명에 쓰는가? 평문 저장?
- **CSRF(T3-2)**: 상태 변경 요청에 CSRF 토큰·SameSite 쿠키가 있는가?
- **파일업로드(T3-8)**: 확장자·MIME·매직바이트 검증? 업로드 경로가 웹루트 밖?
- **정보누출(T3-19)**: 스택트레이스·SQL 에러·내부 경로가 사용자에게 노출?
- **TLS(T3-20)**: `verify=False`/평문 HTTP/만료 인증서?
- **레이스컨디션(T3-9)**: check-then-use 패턴에 락/트랜잭션?
- **인증로직(T1-8)**: 세션 고정·자동화 공격(rate-limit) 대응·JWT 검증(`alg=none` 거부)?
- **예외오처리(T4-1)**: 빈 catch·포괄적 exception swallow·fail-open(인증 우회)?
- **Mass Assignment(T4-3)**: ORM 모델에 사용자 입력을 직접 바인딩? `role`/`isAdmin` 필드 보호?

### 묶음 B (LLM/논리)
- **설계(T1-5)**: 위협 모델링 수행? 신뢰경계 명시? (A06:2025 — [CWE-1441](https://cwe.mitre.org/data/definitions/1441.html))
- **과도한권한(T2-6)**: 에이전트 도구 권한이 최소권한? 쓰기/삭제/실행 권한 범위?
- **프롬프트인젝션(T2-1)**: 사용자 입력이 LLM 프롬프트로 흐를 때 검증/이스케이프? (CWE-1427)
- **시스템프롬프트누출(T2-7)**: 클라이언트 번들/로그에 시스템 프롬프트 하드코딩?
- **환각(T2-9)**: LLM 출력을 코드 실행/DB 쿼리에 쓰기 전 검증?
- **DoS(T2-10)**: rate-limit·token-cap·max body?
- **로깅(T3-14)**: 보안 이벤트(인증 실패·권한 거부·예외)를 로깅? (PII 마스킹)
- **LLM 민감정보(T2-2)**: 프롬프트에 PII/시크릿 유입? 응답에 민감정보 노출?
- **LLM 출력처리(T2-5)**: LLM 출력이 exec/SQL/eval로 흐를 때 검증? (CWE-1426)

### 묶음 C (공급망·데이터·RAG)
- **공급망(T2-3)**: 패키지 출처(공식 레지스트리)·pin 여부·재현 빌드?
- **데이터독성(T2-4)**: 파인튜닝/RAG 데이터 출처 검증? ingestion 제어?
- **벡터DB(T2-8)**: tenant 분리·ACL·임베딩 출처?

---

## 10. L3 백엔드 지시서 (codeSecurity 프리셋 시 별도 위임용)

L3는 codeSecurity 프리셋 또는 사용자 명시("보안 검증해줘"/"secure")일 때만 발동. 별도 백엔드 1회에 아래 임무를 위임:

- **PoC 작성**: 발견된 취약점(T1/T2/T3)에 대해 실제 익스플로잇 가능성을 PoC로 확인.
- **공급망 평판 조사(T2-3)**: 모델/플러그인/패키지 출처·유지보수 상태·과거 CVE 이력.
- **데이터 출처 조사(T2-4, T2-8)**: 파인튜닝/RAG/벡터DB 데이터의 provenance·라이선스·독성 가능성.

**L3 산출 규약**: `$RUN/l3-report.md`(발견 PoC·외부 조사 결과·권고). L3 발견이 있으면 synthesis에 명시 — 단, L3는 단일 백엔드라 교차검증이 아니므로 "L3 단독 발견(미교차검증)" 표기.

---

## 11. OWASP 2021 ↔ 2025 매핑 참고표

| 2021 | 2025 | 변화 |
|---|---|---|
| A01 Broken Access Control | A01 Broken Access Control | 유지 |
| A02 Cryptographic Failures | A04 Cryptographic Failures | 강등 |
| A03 Injection | A05 Injection | 강등 |
| A04 Insecure Design | **A06 Insecure Design** (유지, [CWE-1441](https://cwe.mitre.org/data/definitions/1441.html)) | 재배치 (사라지지 않음) |
| A05 Security Misconfiguration | A02 Server-Side Request Forgery 흡수 + 분산 | 재구성 |
| A06 Vulnerable Components | A03 Software Supply Chain + A06(일부) | 상향·분할 |
| A07 Auth Failures | A07 Auth Failures | 유지 |
| A08 Integrity Failures | A08 Integrity Failures | 유지 |
| A09 Logging Failures | A09 Logging Failures | 유지 |
| A10 SSRF | 분산(여러 카테고리로 흡수) | 해체 |
| (신규) | **A10 Mishandling of Exceptional Conditions** ([CWE-1445](https://cwe.mitre.org/data/definitions/1445.html), 24개 CWE) | 신규 추가 |

> 매트릭스는 2021 코드(A0X)를 기본 표기하되 2025 코드를 병기한다. 2025 단독 항목(A10 예외처리)은 T4-1로 별도 추가.
