# ARENA-ROUTER.md - AI Review Arena Always-On Routing System

Natural language always-on routing for AI Review Arena v2.1 plugin commands.
ORCHESTRATOR.md의 라우팅 시스템을 확장하여 **모든 코드 관련 요청**을 Arena 파이프라인으로 자동 라우팅.

## Core Principle: Always-On

**모든 코드 관련 요청은 Arena를 거친다.** 패스스루는 비개발 작업(설명, 커밋, 질문)에만 적용.
간단한 수정도 최소한 코드베이스 분석(Phase 0.5)을 거쳐 기존 컨벤션과 재활용 가능 코드를 파악한 후 작업한다.

## Routing Architecture

**Position**: ORCHESTRATOR.md 라우팅 전에 Arena 패턴을 먼저 평가
**Precedence**: `--no-arena` > 명시적 `/command` > 자동 라우팅 > ORCHESTRATOR 라우팅

## Bypass Mechanism

- **`--no-arena`**: 모든 Arena 자동 라우팅 비활성화. ORCHESTRATOR로 패스스루.
- **`--arena-route=[arena|research|stack|review]`**: 특정 Arena 커맨드 강제 지정.
- **명시적 슬래시 커맨드**: `/arena`, `/arena-research`, `/arena-stack`, `/multi-review` 직접 입력 시 자동 라우팅 우회.

## Routing Overview

```
모든 사용자 입력
  │
  ├── 비개발 작업 ─────────────── PASSTHROUGH (일반 Claude Code)
  │     "설명해줘", "커밋해줘", "뭐야?", 비코드 대화
  │
  └── 코드 관련 작업 ──────────── Arena 라우팅 (항상)
        │
        ├── 복합 구현/개발     → /arena --intensity auto        (Route 1)
        ├── 연구/조사          → /arena-research                (Route 2)
        ├── 스택 문의          → /arena-stack                   (Route 3)
        ├── 코드 리뷰          → /multi-review                  (Route 4)
        ├── 리팩토링/개선/정리  → /arena --phase codebase,review (Route 5)
        └── 간단한 코드 변경    → /arena --intensity quick       (Route 6, Catch-All)
```

## Route Definitions

### Route 1: `/arena` (Full Lifecycle Orchestration)

**목적**: 복합 기능 구현 요청 → 코드베이스 분석 + 스택 감지 + 사전 연구 + 컴플라이언스 + 벤치마크 + 리뷰

**Primary Keywords** (+0.3 each, cap 0.6):
```yaml
ko: ["구현해줘", "구현하자", "만들어줘", "개발해줘", "빌드해줘",
     "기능 추가", "피처 개발", "전체 리뷰", "라이프사이클"]
en: ["implement", "build", "develop", "create feature",
     "full lifecycle", "full review", "end-to-end"]
```

**Secondary Keywords** (+0.15 each, cap 0.3):
```yaml
ko: ["리뷰해줘"(+구현 컨텍스트), "분석하고 구현", "연구하고 개발", "설계하고 만들어"]
en: ["review"(+implementation scope), "research and implement", "analyze and build"]
```

**Context Signals** (additive):
```yaml
figma_url_present: +0.35     # figma.com URL 감지
compliance_keywords: +0.2    # auth, payment, chat, camera, location, notification, game
multi_layer_scope: +0.2      # frontend+backend, API+UI, 서버+클라이언트
complex_feature: +0.15       # 인증 시스템, 결제 플로우, 실시간 채팅
pr_scope: +0.1               # --pr 또는 PR 번호
```

**Argument Extraction**:
```yaml
scope: 사용자 원래 요청 텍스트
figma_url: "https?://[\w.]*figma\.com/[\w/\-?=&%#@!+]*" 패턴 매칭
intensity: "빠르게"|"quick" → quick, "심층"|"deep" → deep, "종합"|"comprehensive" → comprehensive
pr_number: "--pr\s*(\d+)" 또는 "PR\s*#?(\d+)"
focus: "보안"|"security", "버그"|"bugs", "아키텍처"|"architecture", "성능"|"performance"
interactive: "확인하면서"|"단계별"|"step by step" → --interactive
skip_cache: "캐시 무시"|"새로 조사"|"skip cache" → --skip-cache
phase: "리서치만"|"research only" → --phase research
```

**실행 예시**:
```
입력: "피그마 보고 로그인 API 구현해줘 https://figma.com/file/xxx"
라우팅: /arena "로그인 API 구현" --figma https://figma.com/file/xxx
신뢰도: 0.3(구현해줘) + 0.35(figma) + 0.2(auth compliance) = 0.85 → 자동 실행

입력: "채팅 기능 만들어줘 심층으로"
라우팅: /arena "채팅 기능" --intensity deep
신뢰도: 0.3(만들어줘) + 0.2(chat compliance) + 0.15(complex feature) = 0.65 → 자동 실행
```

---

### Route 2: `/arena-research` (Pre-Implementation Research)

**목적**: 구현 전 사전 연구 - BP 조사, 기술 비교, 가이드라인 확인

**Primary Keywords** (+0.3 each, cap 0.6):
```yaml
ko: ["어떻게 구현하면 좋을까", "구현 방법", "베스트 프랙티스",
     "사전 조사", "기술 조사", "리서치해줘", "방법 알려줘",
     "어떻게 하면 좋을까", "기술 검토"]
en: ["best practices for", "how should I implement", "research",
     "feasibility study", "tech comparison", "implementation guide",
     "pre-implementation", "before I start", "recommended approach"]
```

**Secondary Keywords** (+0.15 each, cap 0.3):
```yaml
ko: ["기술 비교", "패턴 조사", "가이드라인 확인", "컴플라이언스 확인",
     "규정 확인", "피그마 분석"(구현 의도 없이)]
en: ["compliance check", "guideline review", "pattern research",
     "what's the best way to", "pros and cons"]
```

**Context Signals**:
```yaml
question_form: +0.2          # "?", "좋을까", "할까", "될까" 로 끝남
no_code_scope: +0.15         # 파일 경로, git diff 없음
comparison_intent: +0.15     # "vs", "비교", "차이점", "장단점"
figma_url_no_impl: +0.1      # Figma URL 있지만 구현 키워드 없음
```

**Disqualifiers**:
- 구현 동사 존재 ("구현해줘", "만들어줘", "빌드") → Route 1로
- 파일 수정 의도 감지
- Git diff/PR 스코프 제공 (이미 코드 존재)

**Argument Extraction**:
```yaml
feature_desc: 플래그/커맨드 제거 후 남은 텍스트
figma_url: Route 1과 동일 패턴
stack_override: "--stack" 또는 기술명 콤마 리스트 → --stack <list>
compliance_flag: compliance 키워드 감지 → --compliance
output_format: "JSON" 감지 → --output json
ttl: "--ttl \d+" 또는 "N일" 감지 → --ttl N
```

**실행 예시**:
```
입력: "Redis 캐싱 어떻게 구현하면 좋을까?"
라우팅: /arena-research "Redis 캐싱 구현" --stack redis
신뢰도: 0.3(어떻게 구현하면 좋을까) + 0.2(question_form) = 0.5 → 자동 실행

입력: "SpringBoot에서 OAuth 베스트 프랙티스 리서치해줘"
라우팅: /arena-research "SpringBoot OAuth" --stack springboot --compliance
신뢰도: 0.3(베스트 프랙티스) + 0.3(리서치해줘) = 0.6 → 자동 실행
```

---

### Route 3: `/arena-stack` (Stack Detection)

**목적**: 프로젝트 기술 스택 분석

**Primary Keywords** (+0.35 each, cap 0.7 - 높은 가중치: 매우 구체적):
```yaml
ko: ["스택 뭐야", "기술 스택", "스택 분석", "스택 감지",
     "뭘 쓰고 있어", "어떤 기술", "기술 구성",
     "프레임워크 뭐야", "언어 뭐야", "기술 스택 알려줘"]
en: ["what stack", "tech stack", "detect stack", "analyze stack",
     "what technologies", "what framework", "what language",
     "project technologies", "stack detection"]
```

**Secondary Keywords** (+0.15 each, cap 0.3):
```yaml
ko: ["의존성", "라이브러리", "인프라 구성"]
en: ["dependencies", "tooling", "infrastructure"]
```

**Context Signals**:
```yaml
project_path_provided: +0.1  # 특정 디렉토리 경로 언급
no_feature_context: +0.1     # 순수 스택 문의, 기능 작업 없음
```

**Disqualifiers**:
- 구현/리뷰 의도 존재 → 다른 라우트로
- 연구 의도 존재 → Route 2로
- 기능 개발 컨텍스트 → Route 1로

**Argument Extraction**:
```yaml
target_path: 디렉토리 경로 또는 프로젝트 루트 기본값
deep_flag: "상세"|"자세히"|"deep"|"detailed" → --deep
search_practices: "베스트 프랙티스도"|"BP도"|"with best practices" → --search-practices
output_format: "JSON" → --output json
```

**실행 예시**:
```
입력: "이 프로젝트 기술 스택 뭐야?"
라우팅: /arena-stack
신뢰도: 0.35(기술 스택) + 0.35(뭐야) + 0.1(no_feature) = 0.8 → 자동 실행
```

---

### Route 4: `/multi-review` (Code Review Only)

**목적**: 기존 코드의 멀티-AI 적대적 리뷰

**Primary Keywords** (+0.3 each, cap 0.6):
```yaml
ko: ["코드 리뷰해줘", "코드 리뷰", "리뷰해줘"(구현 컨텍스트 없이),
     "코드 점검", "코드 검사", "코드 분석해줘",
     "보안 점검", "보안 검사", "취약점 확인", "취약점 스캔"]
en: ["code review", "review my code", "review this code",
     "security review", "find bugs", "check for vulnerabilities",
     "review the changes", "review the diff"]
```

**Secondary Keywords** (+0.15 each, cap 0.3):
```yaml
ko: ["PR 리뷰", "풀리퀘스트 리뷰", "디프 확인",
     "버그 찾아줘", "문제 찾아줘", "변경사항 리뷰", "커밋 리뷰"]
en: ["PR review", "pull request review", "review PR",
     "find issues", "check quality", "audit code"]
```

**Context Signals**:
```yaml
existing_code_scope: +0.2   # 파일 경로, git diff, --pr 존재
post_implementation: +0.15  # "작성한 코드", "written code", "these changes"
pr_context: +0.15           # PR 번호, "pull request", "머지 전에"
staged_changes: +0.1        # 이미 코드가 존재함을 암시
```

**Disqualifiers**:
- 구현 의도 ("구현해줘", "만들어줘", "implement") → Route 1로
- 연구 의도 ("어떻게", "best practices", "방법") → Route 2로
- 스택 문의 → Route 3로

**Argument Extraction**:
```yaml
scope: 파일 경로, 디렉토리 경로 추출
pr_number: "--pr\s*(\d+)" 또는 "PR\s*#?(\d+)"
intensity: Route 1과 동일 매핑
focus: Route 1과 동일 추출
models: 모델명 감지 → --models claude,codex,gemini
no_debate: "토론 없이"|"빠르게"|"no debate" → --no-debate
interactive: Route 1과 동일
```

**실행 예시**:
```
입력: "코드 리뷰해줘"
라우팅: /multi-review
신뢰도: 0.3(코드 리뷰해줘) + 0.1(staged_changes) = 0.4 → 자동 실행

입력: "PR 42번 보안 점검해줘 심층으로"
라우팅: /multi-review --pr 42 --focus security --intensity deep
신뢰도: 0.3(보안 점검) + 0.15(PR 리뷰) + 0.15(pr_context) = 0.6 → 자동 실행
```

---

### Route 5: Refactoring/Improvement (코드 개선)

**목적**: 기존 코드의 리팩토링, 개선, 정리, 최적화 → 코드베이스 분석 후 리뷰 기반 개선

**Primary Keywords** (+0.3 each, cap 0.6):
```yaml
ko: ["리팩토링해줘", "리팩토링하자", "개선해줘", "클린업해줘",
     "정리해줘", "최적화해줘", "성능 개선", "코드 정리",
     "구조 개선", "코드 개선", "품질 개선"]
en: ["refactor", "refactoring", "improve code", "cleanup",
     "clean up", "optimize", "restructure", "simplify",
     "improve quality", "reduce complexity"]
```

**Secondary Keywords** (+0.15 each, cap 0.3):
```yaml
ko: ["중복 제거", "추상화", "분리해줘", "모듈화",
     "가독성", "유지보수", "기술 부채"]
en: ["extract", "decouple", "modularize", "readability",
     "maintainability", "technical debt", "DRY"]
```

**Context Signals**:
```yaml
existing_code_scope: +0.2   # 파일 경로, 디렉토리 경로 존재
broad_scope: +0.15          # "전체", "모든", "프로젝트", "all", "entire"
quality_focus: +0.1          # "깨끗하게", "클린", "clean"
```

**Disqualifiers**:
- 새 기능 구현 의도 ("기능 추가", "만들어줘") → Route 1로
- 순수 리뷰만 원함 ("리뷰만", "분석만") → Route 4로
- 순수 연구 ("방법 알려줘") → Route 2로

**Routing**: `/arena --phase codebase,review --intensity standard`

**Argument Extraction**:
```yaml
scope: 파일/디렉토리 경로 또는 전체 프로젝트
focus: "성능"|"performance", "구조"|"architecture", "가독성"|"readability"
intensity: 기본 standard, "심층"|"deep" → deep, "빠르게"|"quick" → quick
```

**실행 예시**:
```
입력: "이 코드 리팩토링해줘"
라우팅: /arena --phase codebase,review --intensity standard
신뢰도: 0.3(리팩토링해줘) + 0.2(existing_code) = 0.5 → 자동 실행

입력: "src/services/ 최적화해줘 성능 위주로"
라우팅: /arena --phase codebase,review --intensity standard --focus performance src/services/
신뢰도: 0.3(최적화해줘) + 0.2(existing_code) + 0.1(quality_focus) = 0.6 → 자동 실행
```

---

### Route 6: Simple Code Changes (Catch-All)

**목적**: 간단한 코드 수정/추가/삭제 → 최소한 코드베이스 분석 후 기존 컨벤션에 맞춰 작업

**Primary Keywords** (+0.25 each, cap 0.5):
```yaml
ko: ["바꿔줘", "추가해줘", "삭제해줘", "수정해줘", "변경해줘",
     "고쳐줘", "빼줘", "넣어줘", "교체해줘", "업데이트해줘"]
en: ["change", "add", "remove", "fix", "update", "delete",
     "modify", "rename", "move", "replace"]
```

**Secondary Keywords** (+0.15 each, cap 0.3):
```yaml
ko: ["파라미터", "타입", "변수", "함수", "메서드", "클래스",
     "import", "값", "이름", "리턴", "인자", "필드", "속성"]
en: ["parameter", "type", "variable", "function", "method", "class",
     "import", "value", "name", "return", "argument", "field", "property"]
```

**Context Signals**:
```yaml
specific_target: +0.15      # 구체적 파일/함수/변수명 언급
small_scope: +0.1           # 단일 파일, 단일 변경
code_element: +0.1          # 코드 요소(함수, 타입 등) 언급
```

**Routing**: `/arena --intensity quick`

**실행 방식**:
- Phase 0.5 (Codebase Analysis)만 실행
- Agent Team 미생성, 외부 모델 미호출
- Claude 단독으로 코드베이스 분석 → 컨벤션 파악 → 작업 수행
- 작업 완료 후 간단한 자체 리뷰

**Argument Extraction**:
```yaml
scope: 사용자 원래 요청 텍스트
target_file: 파일 경로 감지
target_element: 함수/변수/클래스명 감지
```

**실행 예시**:
```
입력: "파라미터 빼줘"
라우팅: /arena --intensity quick
동작: 코드베이스 분석 → 관련 코드 찾기 → 컨벤션에 맞춰 수정

입력: "이 함수 이름 바꿔줘"
라우팅: /arena --intensity quick
동작: 코드베이스 분석 → 기존 네이밍 컨벤션 파악 → 이름 변경

입력: "UserService에 getById 메서드 추가해줘"
라우팅: /arena --intensity quick
동작: 코드베이스 분석 → 기존 서비스 패턴 파악 → 기존 패턴에 맞춰 메서드 추가
```

---

### Passthrough: 비개발 작업만

**패스스루 조건 (이것만 Arena를 거치지 않음)**:
```yaml
ko: ["설명해줘", "알려줘"(코드 수정 의도 없이), "뭐야?",
     "커밋해줘", "푸시해줘", "풀해줘",
     "왜 그래?", "이해가 안 돼", "차이가 뭐야"]
en: ["explain", "tell me about", "what is", "why",
     "commit", "push", "pull",
     "I don't understand", "what's the difference"]
```

**판별 기준**:
- 코드 수정/생성 의도가 전혀 없는 순수 질문/교육
- Git 작업 (commit, push, pull, merge)
- 코드와 무관한 일반 대화

**동작**: ORCHESTRATOR.md 라우팅 시스템으로 폴스루.

---

## Routing Algorithm

```
STEP 1: BYPASS CHECK
  --no-arena 플래그? → PASSTHROUGH
  명시적 /arena* 또는 /multi-review 커맨드? → DIRECT EXECUTE

STEP 2: FORCE CHECK
  --arena-route=<cmd>? → ROUTE to specified command

STEP 3: PASSTHROUGH CHECK (비개발 작업 필터링)
  순수 설명/질문 요청? → PASSTHROUGH to ORCHESTRATOR
  Git 작업 (commit/push/pull)? → PASSTHROUGH to ORCHESTRATOR
  코드와 무관한 대화? → PASSTHROUGH to ORCHESTRATOR

STEP 4: PARALLEL SCORING (코드 관련 작업 확인됨)
  Route 1~6 각각에 대해:
    a. Primary keyword 매칭 → 가중치 적용 (cap에 따라)
    b. Secondary keyword 매칭 → 가중치 적용 (cap에 따라)
    c. Context signal 합산 (additive)
    d. Disqualifier 체크 → 해당 시 score = 0
    e. Normalize: min(1.0, total)

STEP 5: SELECTION
  highest = max(route_scores)

  IF highest >= 0.4:
    → AUTO-ROUTE to highest scoring route
    → Extract arguments
    → Display: "🎯 Arena Router → /command (confidence: XX%)"
    → Execute routed command

  ELSE:
    → CATCH-ALL: Route 6 (/arena --intensity quick)
    → Display: "🎯 Arena Router → /arena --intensity quick (코드베이스 분석 모드)"
    → 코드베이스 분석 후 작업 수행
```

**핵심 변경: 패스스루 제거**
- 기존: score < 0.60 → 패스스루
- 변경: score < 0.40 → Route 6 (catch-all, `/arena --intensity quick`)
- 코드 관련 작업이면 무조건 Arena를 거침

## Intensity Auto-Detection

라우팅 후 intensity가 명시되지 않은 경우 자동 결정:

```yaml
quick:                    # 간단한 코드 변경
  triggers:
    - Route 6 (catch-all)
    - 단일 파일, 단일 요소 변경
    - "빠르게", "간단하게" 키워드
  phases: [0, 0.5]
  skip: [1, 2, 3, 4, 5, 6]
  phase_7: simplified     # Claude 자체 간단 리뷰
  agent_team: false
  models: 0

standard:                 # 중간 규모 작업
  triggers:
    - Route 5 (refactoring)
    - 중간 규모 변경
    - 기본값 (intensity 미지정)
  phases: [0, 0.5, 1(cached), 6, 7]
  skip: [2, 3, 4, 5]
  agent_team: true (3-5 agents)

deep:                     # 복합 기능
  triggers:
    - Route 1 + 복합 기능
    - "심층", "deep" 키워드
  phases: [0, 0.5, 1, 2, 3, 6, 7]
  skip: [4, 5]
  agent_team: true (5-7 agents)

comprehensive:            # 전체 파이프라인
  triggers:
    - Route 1 + Figma URL + 복합 기능
    - "종합", "comprehensive" 키워드
  phases: [0, 0.5, 1, 2, 3, 4, 5, 6, 7]
  skip: []
  agent_team: true (7-10 agents)
```

## Conflict Resolution

### Tie-Breaking (동점 시)
1. **구체성 우선**: `/arena-stack` > `/arena-research` > `/multi-review` > Route 5 > `/arena` > Route 6
2. **Context signal 수**: 더 많은 컨텍스트 시그널 매칭 라우트 우선
3. **구현 vs 리뷰**: 구현 동사 → `/arena`, 리뷰 동사만 → `/multi-review`
4. **연구 vs 구현**: 질문형 + 코드 스코프 없음 → `/arena-research`, 명령형 + 코드 스코프 → `/arena`
5. **리팩토링 vs 간단 수정**: 리팩토링/최적화 키워드 → Route 5, 단순 수정 → Route 6

### "리뷰해줘" 모호성 해소
- "리뷰해줘" + 구현 컨텍스트 (기능 설명, Figma URL, 복합 기술) → `/arena`
- "리뷰해줘" + 기존 코드 컨텍스트 (파일 경로, git diff, PR) → `/multi-review`
- "리뷰해줘" 단독 (컨텍스트 없음) → `/multi-review` (기본: staged changes)

### "고쳐줘"/"수정해줘" 모호성 해소
- "고쳐줘" + 버그/에러 컨텍스트 → Route 6 (`/arena --intensity quick`)
- "고쳐줘" + 구조적 문제 컨텍스트 → Route 5 (refactoring)
- "고쳐줘" + 기능 추가 컨텍스트 → Route 1 (`/arena`)

## SuperClaude Integration

### ORCHESTRATOR.md Master Routing Table 확장

| Pattern | Complexity | Auto-Routes To | Confidence |
|---------|------------|----------------|------------|
| "구현해줘" + 복합 기능 | complex | `/arena` (full lifecycle) | 90% |
| "어떻게 구현" + 질문형 | moderate | `/arena-research` | 88% |
| "스택 뭐야" | simple | `/arena-stack` | 95% |
| "코드 리뷰해줘" | moderate | `/multi-review` | 92% |
| "리팩토링해줘" | moderate | `/arena --phase codebase,review` | 90% |
| "파라미터 빼줘" | simple | `/arena --intensity quick` | 85% |
| "함수 추가해줘" | simple | `/arena --intensity quick` | 85% |
| "타입 변경해줘" | simple | `/arena --intensity quick` | 85% |
| "리뷰해줘" + Figma URL | complex | `/arena` | 95% |
| "보안 점검" + 파일 스코프 | moderate | `/multi-review --focus security` | 88% |
| "best practices for X" | moderate | `/arena-research` | 85% |
| "PR 리뷰" + PR 번호 | moderate | `/multi-review --pr N` | 92% |
| "최적화해줘" | moderate | `/arena --phase codebase,review` | 88% |
| "코드 정리해줘" | moderate | `/arena --phase codebase,review` | 88% |

### Persona Auto-Activation
- `/arena` → architect + security + qa (multi-persona)
- `/arena-research` → analyzer + architect
- `/arena-stack` → analyzer
- `/multi-review` → qa + security + analyzer
- Route 5 (refactoring) → refactorer + architect
- Route 6 (simple) → context-dependent persona

### Flag Passthrough
SuperClaude 플래그는 Arena 커맨드로 전달:
- `--think`, `--think-hard`, `--ultrathink` → Arena intensity에 영향
- `--focus security` → `--focus security`로 매핑
- `--interactive` → `--interactive`로 전달
- `--uc` → Arena 출력에 토큰 압축 적용

## Compliance Keywords Reference

Arena 라우팅 시 컴플라이언스 민감 기능 감지에 사용되는 키워드:

| 기능 | 키워드 | Context Signal |
|------|--------|----------------|
| Auth | auth, login, signup, OAuth, session, 로그인, 인증, 회원가입 | +0.2 |
| Payment | payment, purchase, billing, 결제, 구매, 구독 | +0.2 |
| Chat | chat, message, messaging, 채팅, 메시지, DM | +0.2 |
| Camera | camera, photo, gallery, 카메라, 사진, 갤러리 | +0.15 |
| Location | location, GPS, map, 위치, 지도, 내비게이션 | +0.15 |
| Notification | push, notification, alert, 푸시, 알림 | +0.15 |
| Game | game, score, level, 게임, 점수, 레벨 | +0.15 |
| Storage | storage, upload, download, 저장, 업로드, 다운로드 | +0.1 |
| Network | API, REST, GraphQL, WebSocket | +0.1 |
| Accessibility | a11y, VoiceOver, 접근성, 스크린리더 | +0.1 |
