<p align="center">
  <h1 align="center">AI Review Arena</h1>
  <p align="center">
    <strong>AI들을 서로 싸우게 만들어서 코드를 검증합니다.</strong>
  </p>
  <p align="center">
    <a href="README.md">English</a> | <a href="README.ko.md">한국어</a>
  </p>
</p>

---

## 핵심 아이디어

AI한테 코드 리뷰를 시키면 12개 이슈를 찾습니다. 근데 진짜 문제가 몇 개인지 어떻게 알죠?

**Arena의 답: AI 3마리를 싸우게 하면 됩니다.**

```
┌──────────────────────────────────────────────────────────┐
│                  AI 1마리 리뷰                            │
│                                                           │
│   나  ───►  AI 1마리  ───►  "12개 이슈 발견"              │
│                                                           │
│   근데... 진짜가 몇 개? 12개 다 확인해야 함.              │
└──────────────────────────────────────────────────────────┘

                        vs.

┌──────────────────────────────────────────────────────────┐
│                    ARENA 리뷰                             │
│                                                           │
│   나  ───►  Claude  ───┐                                 │
│             Codex   ───┼──►  서로 싸움  ───►  진짜 5개   │
│             Gemini  ───┘    토론으로 검증     확인됨      │
│                                                           │
│   3개 AI가 독립 리뷰 → 교차 심문 → 가짜 제거.            │
│   진짜 이슈만 높은 신뢰도로 살아남음.                    │
└──────────────────────────────────────────────────────────┘
```

---

## 싸움이 어떻게 진행되나

3개 AI가 각자 코드를 리뷰한 다음, 3라운드에 걸쳐 서로를 심문합니다:

```
 ROUND 1                    ROUND 2                    ROUND 3
 독립 리뷰                   교차 심문                   방어
 ──────────                 ─────────                   ─────

 Claude: "42번줄에           Codex: "Claude의            Claude: "아니, 42번줄
  SQL 인젝션 있음"            3번 발견은 오탐임,           보면 사용자 입력이
                              이 입력은 이미              쿼리에 바로 들어감.
 Codex: "89번줄에             살균 처리됨"                 이스케이핑 없음.
  레이스 컨디션 있음"                                      증거 여기 있음..."
                             Gemini: "사실 Claude
 Gemini: "7번줄에             말이 맞음 — 그                ───►  확인됨
  안쓰는 import 있음"          살균 처리가                         신뢰도: 92%
                              유니코드를
                              놓치고 있음"                   ───►  기각됨
                                                                  (오탐)
```

**이 싸움에서 살아남은 것 = 진짜 고쳐야 할 것.**

---

## 코드 리뷰만 하는 게 아닙니다

Arena는 리뷰어가 아닙니다. **"아이디어"에서 "배포"까지 전체 라이프사이클 시스템**입니다.

```
    "OAuth 로그인 만들어줘"
              │
              ▼
    ┌─────────────────────────────────┐
    │       ARENA 파이프라인           │
    │                                 │
    │  1. 코드베이스 분석             │  ← 코딩 스타일 학습
    │  2. 모범 사례 조사              │  ← 웹 검색
    │  3. 컴플라이언스 확인           │  ← 플랫폼 가이드라인
    │  4. 구현 전략 토론              │  ← AI들이 HOW를 놓고 토론
    │  5. 구현                        │
    │  6. 3개 AI 팀으로 리뷰          │  ← 위에서 설명한 싸움
    │  7. 안전한 이슈 자동 수정       │  ← 사소한 건 자동 처리
    │  8. 테스트 생성                 │  ← 회귀 테스트 작성
    │  9. 최종 리포트                 │  ← pass/fail 검증
    │                                 │
    └─────────────────────────────────┘
```

그리고 **코드뿐만 아니라 3개 도메인**에서 동작합니다:

| | 코드 | 비즈니스 | 문서 |
|---|---|---|---|
| **라우트** | A-F | G-I | J-K |
| **예시** | "OAuth 구현" | "피치덱 작성" | "API 문서 리뷰" |
| **리뷰어** | 12개 전문 에이전트 | 10개 전문 에이전트 | 6개 전문 에이전트 |
| **특수 기능** | 위협 모델링, 정적 분석 | 레드팀, 정량 검증 | 코드-문서 불일치 탐지 |

---

## 자동으로 켜집니다

Arena를 부를 필요가 없습니다. **Arena가 알아서 작동합니다.**

Claude Code에 하는 모든 요청이 자동으로 Arena를 거칩니다:

```
당신이 말하면:                       Arena가 하는 일:
─────────────────────────────     ─────────────────────────────
"로그인 페이지 만들어줘"       →   Route A: 전체 라이프사이클
"이 오타 고쳐줘"              →   Route F: 즉시 수정 (바로)
"이 PR 리뷰해줘"              →   Route D: 멀티 AI 리뷰
"피치덱 써줘"                 →   Route G: 비즈니스 파이프라인
"문서 정확한지 봐줘"          →   Route J: 문서 리뷰 파이프라인
"이 모듈 리팩토링해줘"        →   Route E: 리팩토링 파이프라인
"인증 모범사례 조사해줘"      →   Route B: 심층 리서치
```

단순한 건 초 단위로 끝납니다. 복잡한 건 토론 포함 전체 파이프라인이 가동됩니다.

---

## 강도(Intensity) 결정 방식

Arena는 **4개 에이전트 토론**으로 얼마나 깊이 검토할지 결정합니다:

```
                    "결제 처리 구현해줘"
                            │
              ┌─────────────┼─────────────┐
              │             │             │
              ▼             ▼             ▼
       ┌───────────┐ ┌───────────┐ ┌───────────┐
       │ "이거     │ │ "standard │ │ "결제 =   │
       │  복잡함,  │ │  면 충분, │ │  위험 HIGH │
       │  deep     │ │  알려진   │ │  데이터    │
       │  리뷰     │ │  패턴임"  │ │  손실 가능"│
       │  필요"    │ │           │ │           │
       └─────┬─────┘ └─────┬─────┘ └─────┬─────┘
       강도       효율성     리스크
       옹호자     옹호자     평가자
              │             │             │
              └─────────────┼─────────────┘
                            ▼
                 ┌─────────────────┐
                 │   중재자:       │
                 │  "DEEP — 돈을   │
                 │   다루는 코드"  │
                 └─────────────────┘
```

| 레벨 | 언제 | 뭘 하나 |
|------|------|---------|
| **Quick** | 오타, 이름 변경, 설명 | Claude 혼자 처리, 토론 없음 |
| **Standard** | 일반 기능, 단일 파일 | 전체 리뷰 + 토론 + 자동 수정 |
| **Deep** | 다중 파일, 인증, API | + 리서치 + 컴플라이언스 + 위협 모델링 |
| **Comprehensive** | 아키텍처, 결제, 보안 | + 벤치마킹 + 풀 에이전트 편성 |

---

## 전체 페이즈 맵

코드 파이프라인의 모든 페이즈와 각 강도에서 실행 여부:

```
                    quick    standard    deep    comprehensive
                    ─────    ────────    ────    ─────────────
Phase 0   설정       ●          ●        ●           ●
Phase 0.1 강도 토론  ●          ●        ●           ●
Phase 0.2 비용 산정            ●        ●           ●
Phase 0.5 코드베이스  ●          ●        ●           ●
Phase 1   스택 감지            ●        ●           ●
Phase 2   리서치                        ●           ●
Phase 3   컴플라이언스                   ●           ●
Phase 4   벤치마크                                  ●
Phase 5   Figma               ●        ●           ●
Phase 5.5  전략 토론            ●        ●           ●
Phase 5.5.5 스펙 승인          ●        ●           ●
Phase 5.8 정적 분석            ●        ●           ●
Phase 5.9 위협 모델링                   ●           ●
Phase 5.95 리뷰 계약           ●        ●           ●  ← NEW
Phase 6   팀 리뷰             ●        ●           ●
Phase 6.5 자동 수정(+검증)     ●        ●           ●  ← IMPROVED
Phase 6.6 테스트 생성          ●        ●           ●
Phase 6.7 시각 검증            ●        ●           ●
Phase 7   리포트     ●          ●        ●           ●

"Quick" = Claude 혼자. 팀 없음, 토론 없음. 즉시.
"Standard+" = 풀 에이전트 팀 + 3라운드 교차 심문.
```

---

## 리뷰 팀 (Phase 6 상세)

멀티 AI 리뷰가 실제로 동작하는 방식:

```
┌──────────────────────────────────────────────────────────────────────┐
│                                                                      │
│  STEP 1: debate-arbitrator 먼저 투입 (Early Join)                    │
│  ═══════════════════════════════════════════════════                  │
│  처음부터 모든 리뷰어 간 통신을 모니터링합니다.                       │
│                                                                      │
│  STEP 2: 6-12개 Claude 리뷰어 동시 투입                              │
│  ══════════════════════════════════════                               │
│                                                                      │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐               │
│  │ 보안     │ │   버그   │ │  성능    │ │ 아키텍처 │  ... 더 많은  │
│  │ 리뷰어   │ │ 탐지기   │ │ 리뷰어   │ │ 리뷰어   │  리뷰어들     │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘               │
│       │             │             │             │                     │
│       │    ┌────────┼─────────────┼─────────────┘                    │
│       │    │  실시간 SIGNAL 공유:                                     │
│       │    │                                                         │
│       │    │  보안→버그: "45번줄 인증 우회 발견,                     │
│       │    │              레이스 컨디션 확인 필요"                    │
│       │    │  성능→보안: "89번줄 제한없는 쿼리,                      │
│       │    │              DoS 벡터 가능성"                            │
│       │    └─────────────────────────────────────                    │
│       │                                                              │
│       └──────────► debate-arbitrator가 모든 시그널 추적              │
│                    중복 제거, 크로스 도메인 패턴 발견                 │
│                                                                      │
│  STEP 3: Codex & Gemini CLI 병렬 실행                                │
│  ══════════════════════════════════════                               │
│  외부 모델들이 셸 스크립트를 통해 독립 리뷰                          │
│                                                                      │
│  STEP 4: 취합 → 3라운드 교차 심문 → 합의                            │
│  ════════════════════════════════════════                             │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

### 에이전트 전체 목록

**코드 리뷰 (12개 에이전트)**

| 에이전트 | 뭘 찾나 |
|---------|---------|
| security-reviewer | SQL 인젝션, XSS, 인증 결함, OWASP Top 10 |
| bug-detector | 로직 에러, 널 포인터, 레이스 컨디션 |
| architecture-reviewer | SOLID 위반, 나쁜 커플링, 설계 냄새 |
| performance-reviewer | O(n^2) 루프, 메모리 누수, N+1 쿼리 |
| test-coverage-reviewer | 누락된 테스트, 미테스트 엣지 케이스 |
| scope-reviewer | 불필요한 리팩토링, 관련 없는 변경 |
| dependency-reviewer | 위험/구버전 의존성 |
| api-contract-reviewer | API 호환성 파괴 |
| observability-reviewer | 누락된 로그, 메트릭, 트레이스 |
| data-integrity-reviewer | 데이터 검증 누락 |
| accessibility-reviewer | 접근성 규정 준수 |
| configuration-reviewer | 하드코딩된 설정, 환경 문제 |

**비즈니스 리뷰 (10개 에이전트)** — 피치덱, 제안서, 마케팅용

| 에이전트 | 뭘 찾나 |
|---------|---------|
| accuracy-evidence-reviewer | 틀린 숫자, 근거 없는 주장 |
| audience-fit-reviewer | 타겟 오디언스와 안 맞는 톤 |
| competitive-positioning-reviewer | 약한 시장 포지셔닝 |
| financial-credibility-reviewer | 비현실적 재무 전망 |
| legal-compliance-reviewer | 규제 이슈 |
| + 5개 더 | market-fit, conversion, localization, narrative, investor-readiness |

**문서 리뷰 (6개 에이전트)** — README, API 문서, 튜토리얼용

| 에이전트 | 뭘 찾나 |
|---------|---------|
| doc-accuracy-reviewer | 코드는 X인데 문서는 Y |
| doc-completeness-reviewer | 빠진 섹션 |
| doc-freshness-reviewer | 구버전 내용 |
| doc-readability-reviewer | 읽기 어려운 문서 |
| doc-example-reviewer | 안 돌아가는 코드 예시 |
| doc-consistency-reviewer | 문서 간 모순 |

---

## 안전 시스템

### 고위험 패턴 탐지

Arena가 위험한 파일 패턴을 자동으로 감지하고 에스컬레이션합니다:

```
auth/login.ts 수정
         │
         ▼
  ┌──────────────────┐
  │ Escalation Scan   │   매칭: auth_security 패턴
  │ (LLM 비용 0,     │
  │  순수 grep)       │
  └────────┬─────────┘
           │
  ┌────────▼─────────┐
  │ ● 강도 → deep (최소)
  │ ● 이 파일 자동 수정 차단
  │ ● 사람 승인 필요할 수 있음
  └──────────────────┘

패턴: 인증, 결제, 암호화, DB 스키마, 의존성, 인프라
```

### 쓰기 범위 제한

자동 수정은 작업 범위 내 파일만 건드릴 수 있습니다:

```
작업: "utils/dates.ts 버그 수정"

  ✅ 자동 수정 가능: utils/dates.ts, tests/dates.test.ts
  ❌ 자동 수정 불가: src/auth/login.ts (범위 밖 → 먼저 물어봄)
```

### 검증 계약

최종 리포트는 단순한 "이슈 목록"이 아닙니다. **pass/fail 검증 결과**입니다:

```
┌─────────────────────────────────────────┐
│           검증 계약                      │
├───────────────────────┬────────┬────────┤
│ 레이어                │ 상태   │ 이슈   │
├───────────────────────┼────────┼────────┤
│ 코딩 가이드라인       │  PASS  │ 0      │
│ 조직 불변 규칙        │  PASS  │ 0      │
│ 도메인 계약           │  WARN  │ 2      │
│ 인수 기준             │  PASS  │ 0      │
│ 정적 분석             │  PASS  │ 0      │
│ 토론 합의             │  FAIL  │ 1      │
├───────────────────────┼────────┼────────┤
│ 전체                  │  FAIL  │        │
└───────────────────────┴────────┴────────┘
```

---

## 설계 철학

### 왜 AI vs AI인가?

단일 모델 리뷰는 사각지대가 있습니다. 모든 AI는 다른 학습 데이터, 다른 편향, 다른 강점을 가집니다. **싸우게 하면**:

1. **오탐 제거** — AI 하나만 보고 방어 못하면, 아마 틀린 것
2. **진짜 이슈 확인** — 여러 AI가 독립적으로 찾으면, 아마 진짜
3. **신뢰할 수 있는 신뢰도** — 토론 후 신뢰도는 실제 교차 검증 결과를 반영

### 왜 서로 대화하는 에이전트인가?

전통적 방식: 각 리뷰어가 혼자 일하고, 결과를 합침.

Arena 방식: 리뷰어들이 **실시간으로 시그널을 공유**:

```
전통적:                          Arena:
──────                           ──────

보안: 인증 이슈 발견             보안: 인증 이슈 발견
버그: 못 찾음                       │
성능: 못 찾음                       ├──SIGNAL──► 버그: "여기 레이스
                                    │            컨디션도 확인해봐"
                                    │
                                    └──SIGNAL──► 성능: "제한없는
                                                 쿼리, DoS 위험?"

결과: 발견 1개                   결과: 시그널 1개로 발견 3개
```

### 왜 투표가 아니라 토론인가?

투표: "3개 중 2개 AI가 찬성" → 근데 2개가 같은 방식으로 틀리면?

토론: "AI 2번, 이게 안전하다고 했는데 AI 1번은 아니라고 합니다. 방어하세요." → 패턴 매칭이 아니라 추론을 강제.

---

## 빠른 시작

### 설치

```bash
# 옵션 1: Claude Code 플러그인
claude plugin add HajinJ/ai-review-arena

# 옵션 2: 소스에서 설치
git clone https://github.com/HajinJ/ai-review-arena.git
cd ai-review-arena
bash scripts/setup-arena.sh
```

### 사전 요구사항

| 도구 | 필수? | 용도 |
|------|------|------|
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | 예 | 모든 걸 실행 |
| [jq](https://jqlang.github.io/jq/) | 예 | JSON 처리 |
| [Codex CLI](https://github.com/openai/codex) | 선택 | 두 번째 AI 관점 |
| [Gemini CLI](https://github.com/google-gemini/gemini-cli) | 선택 | 세 번째 AI 관점 |

Codex/Gemini 없이도 Arena는 동작합니다 — 같은 토론 프로토콜로 Claude만의 멀티 에이전트 리뷰를 실행합니다.

### 설정

```bash
# 프로젝트별 설정 (선택)
cat > .ai-review-arena.json << 'EOF'
{
  "review": {
    "intensity": "standard",
    "focus_areas": ["security", "performance"]
  },
  "output": {
    "language": "ko"
  }
}
EOF
```

### 사용법

그냥 Claude Code를 평소처럼 쓰세요. Arena가 자동으로 활성화됩니다.

```
나: "API에 rate limiting 추가해줘"
    → Arena 라우팅: Feature Implementation (Route A)
    → 강도 토론: "standard" (API 변경, 중간 위험)
    → 전체 파이프라인 실행
    → 3라운드 교차 심문 리뷰
    → pass/fail 검증 리포트
```

Arena 건너뛰기: 요청에 `--no-arena`를 추가하면 됩니다.

---

## 폴백 프레임워크

도구가 없을 때 우아하게 단계적으로 품질을 유지합니다:

```
Level 0: Claude + Codex + Gemini (풀 파워)
  │ Codex 사용 불가
Level 1: Claude + Gemini
  │ Gemini도 사용 불가
Level 2: Claude만으로 에이전트 팀 (모든 역할)
  │ Agent Teams 사용 불가
Level 3: Claude 혼자 + 구조화된 리뷰 템플릿
  │ jq 사용 불가
Level 4: Claude 혼자 + 수동 JSON 처리
  │ 치명적 오류
Level 5: 부분 결과 포함 에러 리포트
```

---

## 프로젝트 구조

```
ai-review-arena/
├── .codex/           Codex 서브에이전트 설정 (에이전트별 모델 지정 5개)
├── agents/           40개 에이전트 정의 (코드 12 + 비즈 10 + 문서 6 + 유틸 12)
├── commands/         8개 슬래시 커맨드 (arena, multi-review, research, stack, ...)
├── config/           설정 파일, 프롬프트, 스키마, 벤치마크
├── scripts/          48개 셸 스크립트 (오케스트레이션, CLI 어댑터, 유틸리티)
├── shared-phases/    14개 공유 페이즈 정의
├── hooks/            자동 리뷰 트리거 (PostToolUse + Stop Review Gate)
├── tests/            18개 테스트 (단위 + 통합 + e2e)
└── docs/             ADR 및 참조 문서
```

---

## 벤치마크 결과

심어진 취약점이 포함된 ground-truth 테스트 케이스를 사용한 파이프라인 평가 결과. Solo (단일 모델) vs Arena (멀티 AI 교차 심문) 비교.

### Solo vs Arena 비교

| 카테고리 | Solo Codex F1 | Solo Gemini F1 | Arena F1 | Arena 승리? |
|----------|---------------|----------------|----------|------------|
| Security | 0.500 - 0.667 | 0.400 - 0.600 | 0.700 - 0.857 | 예 |
| Bugs | 0.600 - 0.750 | 0.500 - 0.667 | 0.800 - 1.000 | 예 |
| Architecture | 0.667 - 0.800 | 0.500 - 0.750 | 0.857 - 1.000 | 예 |
| Performance | 0.500 - 0.667 | 0.400 - 0.600 | 0.750 - 0.923 | 예 |

F1 범위는 LLM 비결정성으로 인한 여러 실행 간 분산을 반영합니다.

### Arena가 Solo를 이기는 이유

교차 심문은 개별 모델이 놓치는 오류를 잡아냅니다. Codex가 "치명적 SQL 인젝션"을 지적했는데 Claude와 Gemini가 모두 파라미터화된 쿼리를 가리키면, 오탐이 걸러집니다. 세 모델이 독립적으로 같은 레이스 컨디션을 발견하면 신뢰도가 올라갑니다. 3라운드 토론(리뷰 → 도전 → 방어/인정)은 단일 모델 대비 정밀도와 재현율 모두를 향상시키는 필터 역할을 합니다.

### 측정 방법

벤치마크 테스트 케이스는 합성 코드에 **심어진 취약점**(SQL 인젝션, 레이스 컨디션 등)을 포함하며, 각각 예상 키워드가 포함된 `ground_truth`를 가지고 있습니다. 점수 산정은 키워드 매칭을 사용합니다: 발견 사항이 예상 키워드 중 하나 이상을 긍정적(부정이 아닌) 컨텍스트에서 언급하면 참양성으로 계산합니다. F1 = 2 * 정밀도 * 재현율 / (정밀도 + 재현율). 이 방식에는 내재적 한계가 있습니다 — 키워드 매칭은 모델이 취약점을 진정으로 "이해"했는지 vs. 관련 용어를 단순히 언급했는지의 뉘앙스를 포착할 수 없습니다.

### 주의사항

- 벤치마크는 합성 코드의 **심어진 취약점**을 사용합니다. 실제 코드의 탐지율은 다를 수 있습니다.
- 결과는 실행마다 달라집니다. 위 범위는 일반적인 결과를 나타내며, 보장이 아닙니다.
- Arena는 Solo 리뷰 대비 2-3배의 API 비용이 필요합니다. 더 높은 정확도와의 트레이드오프입니다.
- 테스트 케이스가 제한적입니다 (코드 벤치마크 8개). 일반화를 위해 더 다양한 벤치마크가 필요합니다.
- 키워드 매칭은 과계수(우연한 언급)와 미계수(의역된 발견 사항) 모두 발생할 수 있습니다.

`./scripts/run-solo-benchmark.sh --verbose`로 Solo vs Arena 전체 비교를 확인할 수 있습니다.
`./scripts/run-benchmark.sh --verbose`로 Arena 단독 결과를 확인할 수 있습니다.

---

## 플랫폼 지원

| 플랫폼 | 상태 | 비고 |
|----------|--------|-------|
| macOS | 전체 지원 | |
| Linux | 전체 지원 | |
| Windows (WSL) | 전체 지원 | |
| Windows (Git Bash) | 부분 지원 | 핵심 기능 작동, 일부 스크립트는 WSL 필요 |
| Windows (네이티브) | 명령어만 | 스크립트는 WSL 필요 (`wsl --install`) |

---

## 변경 이력

### v3.5.0 — 하네스 디자인 개선

Anthropic의 "Harness Design for Long-Running Apps" 블로그에서 도출한 6가지 개선. 핵심 인사이트: Generator-Evaluator 분리, 선제적 컨텍스트 리셋, 모델 역량 기반 하네스 조정.

- **가중치 기반 평가 루브릭**: 프로젝트 유형별 카테고리 가중치로 리뷰 우선순위 맞춤화. fintech(security 3x), gaming(performance 3x), healthcare(security 2.5x, bugs 2x), startup MVP 프리셋 제공. 기본 가중치는 전부 1.0 (동작 변경 없음). 고가중치 카테고리의 medium 발견에 "elevated" 마킹. 설정: `review.evaluation_weights`
- **Skepticism 조절**: 4단계 리뷰 엄격도 프리셋 (lenient/balanced/strict/adversarial). challenge threshold, unique finding 수용 점수, defense 페널티 배율, consensus threshold 제어. 3개 debate arbitrator(코드, 비즈니스, 문서) 모두 적용. 기본값 "balanced"는 기존 하드코딩 값과 동일. 설정: `debate.skepticism`
- **선제적 Context Reset**: Phase 5.9→6 (리뷰 전), Phase 6.7→7 (리포트 전) 경계에서 context utilization 초과 시 선제적 리셋. 리뷰어와 리포트 생성기가 fresh context로 동작. 기존 반응적 핸드오버(>60%)를 보완. 설정: `arena.context_reset`
- **Auto-Fix Evaluator Loop** (Generator-Evaluator 분리): 일괄 적용→테스트를 개별 fix 검증으로 교체. 각 fix를 개별 적용 → 테스트 → 독립 `fix-verification-evaluator` 에이전트 검증 → 실패 시 해당 fix만 revert. 최대 3회 재시도. 새 에이전트: `agents/fix-verification-evaluator.md`. 설정: `arena.autofix_evaluator`
- **Review Contract** (Phase 5.95): Phase 6 리뷰 전 코드베이스의 허용 패턴, severity 오버라이드, 포커스 영역, 알려진 기술 부채를 정의하는 계약 생성. 네이밍, 에러 처리, 임포트 스타일 자동 감지. `.ai-review-arena.json` 사용자 오버라이드와 병합. 모든 리뷰어에게 배포하여 false positive 감소. 새 공유 페이즈: `shared-phases/review-contract.md`. 설정: `arena.review_contract`
- **Capability-Relative Harness**: 실증 F1 벤치마크 기반으로 불필요한 phase를 스킵하는 모델 역량 프로파일. `scripts/harness-stress-test.sh`가 phase ablation study 실행 — 각 phase를 하나씩 비활성화하며 F1 영향 측정, 스킵 후보 추천. **기본값 비활성** (`enabled: false`); 스트레스 테스트 실행 후 명시적 활성화 필요. 설정: `model_capability`
- **Review Gate** (`review-gate.sh`): Stop 훅 핸들러 — Claude 코딩 완료 시 미커밋 변경 범위(파일/라인) 평가 후 임계값 초과 시 크로스 모델 리뷰 자동 트리거. Codex Plugin Review Gate 패턴에서 영감. `block_on_critical`로 CRITICAL 발견 시 Claude 중단. 설정: `review_gate`
- **Batch Worktree Review** (`batch-worktree-review.sh`): git worktree 기반 병렬 실행 — fleet(동일 역할 × 다수 파일) 및 swarm(다수 역할 × 동일 파일) 모드. 에이전트 간 시그널 공유로 수렴. 워크트리 불가 시 서브프로세스 모드 자동 폴백. 설정: `fleet_swarm.batch_worktree`
- **`--bare` CLI 최적화**: 비대화형 Claude CLI 호출에 `--bare` 플래그 적용으로 시작 속도 최대 10배 향상
- 41개 에이전트 (기존 40개), 48개 스크립트 (기존 39개), 14개 공유 단계 (기존 13개), 7개 새 설정 섹션

### v3.4.0 — 자기 개선 리뷰 파이프라인

- **Gotchas 섹션**: 40개 에이전트 모두에 `## Gotchas` 추가 (각 3-6개 도메인별 false positive 패턴)
- **Mermaid 리포트 시각화**: severity 파이 차트, 에이전트 참여 그래프, 리뷰 흐름 다이어그램
- **JSONL 시그널 로그** (`signal-log.sh`): 에이전트 간 시그널을 JSONL로 기록, `learn` 커맨드로 패턴 추출
- **세션 핸드오버**: context window 60% 초과 시 자동 상태 저장, 새 세션에서 이어서 진행
- **Hermes Agent 패턴**: Frozen Snapshot, Injection Scanning, Atomic Writes, Self-Improving Gotchas
- **FTS5 검색**: BM25 랭킹 풀텍스트 검색, 지식 그래프, Fleet/Swarm 모드, Phase Contracts, 피드백→Gotchas, Review Daemon
- 40개 에이전트 (기존 33개), 39개 스크립트 (기존 32개), 13개 공유 단계 (기존 9개)

### v3.3.0

- **정적 분석 통합** (Phase 5.8, standard+): 에이전트 리뷰 전 외부 스캐너(semgrep, eslint, bandit, gosec, brakeman, cargo-audit) 실행. 스택 기반 스캐너 선택, 병렬 실행, 표준 포맷으로 출력 정규화. 발견을 Phase 6 리뷰어 에이전트에 추가 컨텍스트로 전달
- **STRIDE 위협 모델링** (Phase 5.9, deep+): 3-에이전트 적대적 토론 — threat-modeler가 STRIDE 위협 식별, threat-defender가 완화/가능성 낮음으로 반박, threat-arbitrator가 우선순위 공격 표면 리스트로 합의
- **테스트 생성** (Phase 6.6, standard+): 신뢰도 >= 70의 critical/high 발견에 대한 회귀 테스트 스텁 생성. 테스트 프레임워크(jest, pytest, go test 등)와 테스트 디렉토리 구조 자동 감지
- **Round 4 에스컬레이션** (deep+): Round 3 이후 미해결 high-severity 논쟁이 남으면 새로운 관점의 중재자가 추가 증거 요구와 함께 교착 상태 해소
- **프레임워크 선택 토론** (Phase B1.5, standard+): 콘텐츠 작성 전 3-에이전트 토론으로 분석 프레임워크 선택. 16개 내장 프레임워크 DB: 콘텐츠(AIDA, StoryBrand, PAS), 전략(Porter, SWOT, PESTEL, Blue Ocean), 커뮤니케이션(Pyramid Principle, SPIN)
- **증거 티어링 프로토콜**: 10개 비즈니스 리뷰어 에이전트 전체에 4단계 증거 품질 분류 — T1(1.0 가중치, 정부/학술), T2(0.8, 산업 보고서), T3(0.5, 뉴스/블로그), T4(0.3, AI 추정). 신뢰도가 티어 가중치로 조정. Critical 발견은 T2+ 증거 필요
- **3-시나리오 의무화** (Phase B5.5, standard+): 전략 토론 출력에 기본, 낙관, 비관 시나리오와 정량적 전망 의무 포함
- **정량적 검증** (Phase B5.6, deep+): 2-에이전트 팀(data-verifier + methodology-auditor)이 WebSearch를 통해 모든 수치 주장 교차 검증. 주장을 VERIFIED, UNVERIFIED, CONTRADICTED로 편차 퍼센트와 함께 평가
- **적대적 레드팀** (Phase B5.7, deep+): 3개 적대적 에이전트가 비즈니스 콘텐츠 스트레스 테스트 — skeptical-investor("왜 투자하면 안 되는가?"), competitor-response("경쟁자가 어떻게 반박할 것인가?"), regulatory-risk("숨겨진 규제 리스크는?"). 비즈니스 유형별 에이전트 선택
- **일관성 검증** (Phase B7): 최종 리포트 전 수치 일관성, 섹션 간 주장 일관성, 톤 일관성 교차 확인
- **10개 새 설정 섹션**: static_analysis, threat_modeling, test_generation, debate_escalation, framework_selection, evidence_tiering, scenario_analysis, quantitative_validation, red_team, consistency_validation
- 33개 에이전트 (기존 27개), 32개 스크립트 (기존 29개), 9개 공유 단계 (기존 3개)
- **Codex 서브에이전트 마이그레이션**: `config/codex-agents/`를 새 `.codex/agents/` 프로젝트 스코프 포맷으로 교체. 5개 커스텀 에이전트에 최상위 스키마 (`name`, `description`, `developer_instructions`, `nickname_candidates`) 적용. 에이전트별 모델 오버라이드 (security/bugs/architecture에 gpt-5.4 high reasoning, performance/testing에 gpt-5.3-codex-spark medium). 병렬 에이전트 UI 가독성을 위한 디스플레이 닉네임. 에이전트 해상도: `.codex/agents/` (프로젝트) → `~/.codex/agents/` (사용자). `scripts/codex-batch-review.sh`를 통한 CSV 배치 리뷰 (`spawn_agents_on_csv` 지원 + 병렬 서브프로세스 폴백). `max_threads` 3에서 6으로 증가

### v3.2.0

- **커밋/PR 안전 프로토콜**: `git commit`이나 `gh pr create` 전에 필수 리뷰 게이트 + 사용자 확인
  - 커밋: 시크릿, 디버그 코드, 의도치 않은 파일에 대한 diff 리뷰 → AskUserQuestion 확인
  - PR: standard+ 강도의 전체 Route D 코드 리뷰 → 리뷰 결과 요약 → AskUserQuestion 확인
- **Phase 0.1-Pre: 빠른 강도 사전 필터**: 명확한 quick 케이스(이름 변경, 설명, 테스트 실행)에 대해 4개 에이전트 강도 토론을 건너뛰는 규칙 기반 사전 필터, 사소한 요청당 ~$0.50+ 및 ~30초 절감
- **핵심 규칙 강화**: 모호한 "모든 요청" 규칙을 명시적 면제/비면제 목록으로 대체 — 코드 설명, 커밋, 디버깅 모두 반드시 파이프라인을 거침
- **3단계 설정 딥 머지**: `load_config()`가 `jq -s` 딥 머지로 default → global → project 설정을 올바르게 병합 (이전에는 첫 번째 발견 파일만 반환)
- **단계별 비용 추정**: 단계별 토큰/비용 테이블, `--intensity`/`--pipeline`/`--lines`/`--json` 파라미터로 `cost-estimator.sh` 재작성, 에이전트 수와 입력 크기에 따라 스케일링
- **공유 단계**: 강도 토론, 비용 추정, 피드백 라우팅을 위한 공통 단계 정의(`shared-phases/`) 추출 — 코드와 비즈니스 파이프라인 공유
- **피드백 기반 라우팅**: `feedback-tracker.sh recommend`가 결합 점수(60% 피드백 정확도 + 40% 벤치마크 F1)를 계산하여 Phase 6/B6에서 모델-카테고리 역할 배정
- **벤치마크 부정 감지**: `keyword_match_positive()`가 부정된 언급의 오탐 방지 ("no evidence of SQL injection"이 SQL injection 발견으로 카운트되지 않음)
- **벤치마크 다중 포맷 지원**: `check_ground_truth()`가 객체 배열, 단일 객체, 플랫 배열 ground truth 포맷 처리
- **캐시 세션 정리**: `cache-manager.sh cleanup-sessions`로 오래된 `/tmp/ai-review-arena*` 디렉토리와 병합된 설정 임시 파일 제거
- **해시 충돌 저항성**: `project_hash()`가 48비트(12자)에서 80비트(20자)로 확장
- **i18n 정리**: 라우팅/명령 파일의 모든 프롬프트, 예제, 메타데이터를 영어로 변환; 의도적 i18n 출력 템플릿에만 한국어 유지
- **컨텍스트 밀도 필터링**: 역할 기반 컨텍스트 필터링으로 각 에이전트에게 관련 코드 패턴만 제공, 노이즈와 토큰 비용 감소 (에이전트당 8,000 토큰 예산)
- **메모리 계층**: 세션 간 학습을 위한 4계층 메모리 아키텍처 (working/short-term/long-term/permanent)
- **파이프라인 평가**: LLM-as-Judge 점수화와 위치 편향 완화를 포함한 정밀도/재현율/F1 메트릭
- **에이전트 강화**: 모든 에이전트에 Error Recovery Protocol 추가 (재시도 → 부분 제출 → 팀 리더 알림)
- **긍정적 프레이밍** ([arxiv 2602.11988](https://arxiv.org/abs/2602.11988)): 핑크 코끼리 효과를 방지하기 위해 모든 에이전트 사양을 부정형("보고하지 않을 때")에서 긍정형("Reporting Threshold")으로 재구성
- **Duplicate Prompt Technique** ([arxiv 2512.14982](https://arxiv.org/abs/2512.14982)): 비추론 LLM 정확도 향상을 위해 외부 CLI 스크립트에 핵심 리뷰 지시 반복
- **리뷰 유효성 검증**: 리뷰 중 코드 변경 시 오래된 발견에 기반한 조치를 방지하는 git 해시 기반 리뷰 신선도 확인
- **프롬프트 캐시 인식 비용 추정**: Claude의 프리픽스 캐싱으로 정확한 비용 예측을 위한 `prompt_cache_discount` 설정
- **Codex 구조화된 출력**: `--output-schema` + `-o` 플래그로 보장된 유효 JSON 출력, 4계층 JSON 추출 폴백 제거. 코드 리뷰, 교차 심문, 방어, 비즈니스 리뷰, 비즈니스 교차 리뷰용 5개 JSON 스키마. `models.codex.structured_output` 설정 (기본값: `true`)
- **Codex 멀티에이전트 서브에이전트**: `.codex/agents/`에 5개 커스텀 에이전트 설정 (새 포맷) — 에이전트별 모델, 추론 노력도, 디스플레이 닉네임. CSV 배치 리뷰 지원. `models.codex.multi_agent.enabled` 설정 (기본값: `true`)
- **OpenAI WebSocket 토론 가속**: 영구 WebSocket 연결 (`wss://api.openai.com/v1/responses`)로 `previous_response_id` 체이닝을 통한 ~40% 빠른 토론. Python 클라이언트 (`scripts/openai-ws-debate.py`) + 자동 HTTP 폴백. `pip install openai>=2.22.0` 필요. `websocket.enabled` 설정 (기본값: `true`)
- **Gemini CLI 훅 크로스 호환성**: 네이티브 Gemini CLI AfterTool 훅 어댑터 (`scripts/gemini-hook-adapter.sh`)가 Gemini 훅 이벤트를 Arena 리뷰 파이프라인으로 변환. 설치/제거 스크립트에 Gemini 설정 지원 추가. `gemini_hooks.enabled` 설정 (기본값: `true`)

### v3.1.0

- **비즈니스 파이프라인** Codex/Gemini 외부 CLI 통합
  - 이중 모드 스크립트: `codex-business-review.sh`와 `gemini-business-review.sh` (`--mode round1` 주 리뷰, `--mode round2` 교차 리뷰)
  - 강도별 역할: standard/deep에서 교차 리뷰어, comprehensive에서 벤치마크 기반 주 리뷰어
- **비즈니스 모델 벤치마킹** (Phase B4): 12개 오류 삽입 테스트 케이스 (카테고리당 3개), F1 점수화, 벤치마크 기반 역할 배정
- **폴백 프레임워크**: 구조화된 6단계(코드) / 5단계(비즈니스) 우아한 성능 저하, 상태 추적 및 리포트 통합
- **비용 & 시간 추정** (Phase 0.2 / B0.2): 실행 전 비용 내역, 진행/조정/취소 선택
- **코드 자동 수정 루프** (Phase 6.5): 안전하고 높은 신뢰도의 발견 자동 수정, 테스트 검증, 실패 시 전체 롤백
- **강도 체크포인트** (Phase 2.9 / B2.9): 리서치 결과에 따른 양방향 파이프라인 중간 조정 (업그레이드/다운그레이드)
- **피드백 루프**: JSONL 기반 피드백 추적, 모델별/카테고리별 정확도 리포트 (`feedback-tracker.sh`)
- **컨텍스트 포워딩**: 멀티 라우트 요청이 계층적 토큰 제한(총 20K 하드 리밋)과 함께 파이프라인 간 컨텍스트 전달
- `business-debate-arbitrator.md` 업데이트: 외부 모델 처리 (동등 가중치, implicit_defend, 신뢰도 정규화)

### v2.7.0

- **비즈니스 콘텐츠 라이프사이클 오케스트레이터** (`arena-business.md`)
  - Route G (콘텐츠), H (전략), I (커뮤니케이션)
  - 5개 비즈니스 리뷰어 에이전트 + business-debate-arbitrator
  - Phase B0-B7: 컨텍스트 추출, 시장 조사, 모범 사례, 정확성 감사, 전략 토론, 리뷰, 리포트
- ARENA-ROUTER.md 업데이트: 9개 라우트 (A-F 코드, G-I 비즈니스)

### v2.6.0

- **3라운드 교차 심문** Claude, Codex, Gemini 간
  - 2라운드: 각 모델이 다른 모델의 발견 평가 (agree/disagree/partial)
  - 3라운드: 각 모델이 도전에 대해 발견 방어 (defend/concede/modify)
  - 발견별 `cross_examination_trail`과 함께 합의 종합
- 신규: `codex-cross-examine.sh`, `gemini-cross-examine.sh`
- 신규 프롬프트 템플릿: `cross-examine.txt`, `defend.txt`

### v2.5.0

- **성공 기준** 구현 전 정의, 최종 리포트에서 검증 (PASS/FAIL)
- **Scope Reviewer** 에이전트가 수술적 변경 강제
- [Karpathy의 코딩 원칙](https://github.com/forrestchang/andrej-karpathy-skills)에서 영감

### v2.4.0

- 5개 파이프라인 결정 포인트에서 **Agent Teams 적대적 토론**
- 정적 키워드 규칙을 에이전트 추론으로 대체

### v2.3.0

- Read 도구로 명령 파일 로드 (무한 재귀 수정)

### v2.2.0

- 의도 기반 라우팅 (키워드 매칭 대체)
- 언어 무관 (모든 언어에서 작동)
- Context Discovery 단계

### v2.1.0

- 상시 작동 라우팅
- 코드베이스 분석 (Phase 0.5)
- MCP 의존성 감지

### v2.0.0

- 풀 라이프사이클 오케스트레이터, 리서치, 스택 감지, 컴플라이언스, 벤치마킹

### v1.0.0

- Claude + Codex + Gemini를 활용한 멀티 AI 적대적 코드 리뷰

## 제한사항

- **Bash 기반 아키텍처.** 모든 스크립트는 bash 4+가 필요합니다. macOS는 bash 3.2를 기본 제공하며, 설치 프로그램이 이를 우회하지만 Windows는 WSL이 필요합니다. 근거와 트레이드오프는 [ADR-001](docs/adr-001-bash-architecture.md)을 참조하세요.
- **라우터가 시스템 프롬프트에 ~2KB 추가.** ARENA-ROUTER.md가 모든 Claude Code 세션에 로드됩니다. 사용 가능한 컨텍스트 윈도우가 ~2KB 줄어듭니다.
- **교차 심문에 외부 CLI 필요.** Codex와 Gemini CLI 없이는 Claude 단독 리뷰로 폴백됩니다. 3라운드 교차 심문에는 최소 2개 모델 패밀리가 필요합니다.
- **벤치마크는 심어진 버그 사용.** 테스트 케이스는 의도적으로 명확한 취약점을 포함합니다. 실제 코드의 미묘한 이슈는 같은 비율로 잡히지 않을 수 있습니다.
- **LLM 비결정성.** 결과는 실행마다 달라집니다. 같은 코드에서 다른 발견, 다른 F1 점수, 다른 강도 결정이 나올 수 있습니다.
- **비용은 강도에 비례.** 3개 모델과 10개 이상 에이전트를 사용하는 `comprehensive` 리뷰는 `quick` Claude 단독 패스보다 크게 비쌉니다. 비용 추정기(Phase 0.2)가 도움이 되지만, 실제 비용은 입력 크기와 모델 가격에 따라 달라집니다.
- **마크다운 코드 파이프라인.** 파이프라인 정의가 2500줄 이상의 마크다운 파일로 Claude가 실행합니다. 전통적인 코드보다 비전통적이고 디버깅이 어렵습니다. 근거는 [ADR-002](docs/adr-002-markdown-pipelines.md)를 참조하세요.

---

## 배포

Arena는 Claude Code 플러그인으로 배포됩니다. 두 가지 설치 방법을 지원합니다:

| 방법 | 명령어 | 자동 업데이트 |
|------|--------|-------------|
| **마켓플레이스** | `/plugin marketplace add HajinJ/ai-review-arena` | 예 |
| **소스에서** | `git clone` + `./install.sh` | 수동 (`git pull`) |

대부분의 사용자에게 마켓플레이스 방법을 권장합니다. 소스 설치는 개발 도구 (`make test`, `make lint`, `make benchmark`)에 접근할 수 있습니다.

---

## 라이선스

MIT
