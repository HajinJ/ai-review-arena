# ARENA-ROUTER.md - AI Review Arena Routing System v2.4

## Core Rule

**모든 요청은 Arena 파이프라인을 거친다.** 예외 없음.
커밋, 설명, 질문이든 코드 구현이든 - 모든 요청은 아래 프로세스를 따른다.

유일한 예외: `--no-arena` 플래그가 명시된 경우, 또는 사용자가 직접 `/arena`, `/multi-review` 등 슬래시 커맨드를 입력한 경우.

---

## Plugin Directory

```
PLUGIN_DIR = ~/.claude/plugins/ai-review-arena
```

모든 커맨드 파일, 에이전트 정의, 설정 파일은 이 디렉토리에 위치한다.

---

## Process: 3단계

```
모든 요청
  │
  ├── Step 1: Context Discovery (컨텍스트 수집)
  │     요청을 이해하기 위해 필요한 외부 정보를 먼저 수집
  │
  ├── Step 2: Route Selection (라우트 결정)
  │     수집된 컨텍스트 + 요청 의도로 적절한 라우트 선택
  │
  └── Step 3: Pipeline Execution (파이프라인 실행)
        선택된 라우트의 커맨드 파일을 Read tool로 읽고
        파일에 정의된 파이프라인을 따라 실행
```

---

## Step 1: Context Discovery

요청을 처리하기 전에, 요청을 완전히 이해하기 위해 필요한 외부 컨텍스트를 먼저 수집한다.

### 발견이 필요한 경우

| 요청 패턴 | 수집 행동 |
|-----------|-----------|
| 이슈/티켓 참조 ("이슈 처리해줘", "next issue", "다음 작업") | `gh issue list` → 이슈 선택 → `gh issue view N` → 이슈 내용 파악 |
| PR 참조 ("PR 리뷰해줘", "PR #42") | `gh pr view N` → PR diff 및 설명 파악 |
| Figma URL 포함 | Figma MCP로 디자인 정보 수집 (미설치 시 설치 제안) |
| 파일/디렉토리 참조 ("이 파일", "src/services/") | Read/Glob으로 대상 코드 파악 |
| 모호한 요청 ("이거 고쳐줘", "이상한데?") | git diff, git status로 최근 변경사항 파악 |
| 외부 라이브러리/프레임워크 언급 | WebSearch 또는 Context7 MCP로 최신 문서 확인 |

### 발견이 불필요한 경우

요청 자체에 충분한 컨텍스트가 포함되어 있으면 즉시 Step 2로 진행:
- "UserService에 getById 메서드 추가해줘" → 대상과 행동이 명확
- "로그인 API 구현해줘" → 구현할 기능이 명확

### 발견 결과의 활용

수집된 컨텍스트는 Step 2의 라우트 결정과 Step 3의 파이프라인 실행에 모두 전달된다.
예: 이슈 내용이 "Add multiplayer lobby system"이면 → 복합 기능 구현으로 판단 → Route A, intensity deep

---

## Step 2: Route Selection

Claude의 자연어 이해 능력으로 요청의 의도를 판단하여 적절한 라우트를 선택한다.
언어에 무관하게 동작한다 (한국어, 영어, 일본어, 프랑스어 등).

### Available Routes

#### Route A: 기능 구현

**의도**: 새로운 기능을 만들거나, 기존 시스템에 새 기능을 추가하는 작업.

- 새 기능 개발, 피처 구현
- 설계부터 구현까지 필요한 복합 작업
- 이슈/티켓 기반 구현 작업 (Context Discovery 이후)
- Figma 디자인 기반 구현

#### Route B: 사전 조사

**의도**: 구현 전에 방법론, 베스트 프랙티스, 기술 비교를 조사하는 작업.

- 구현 방법 조사, 기술 비교
- 베스트 프랙티스/가이드라인 확인
- 아키텍처 결정을 위한 선행 연구
- "어떻게 하면 좋을까?" 류의 탐색적 질문

#### Route C: 스택 분석

**의도**: 프로젝트의 기술 스택, 프레임워크, 의존성을 파악하는 작업.

- 프로젝트 기술 구성 분석
- 사용 중인 프레임워크/라이브러리 식별
- 기술 스택 기반 권장사항

#### Route D: 코드 리뷰

**의도**: 이미 존재하는 코드를 검토하고 문제를 찾는 작업.

- 코드 품질/보안/성능 리뷰
- PR 리뷰
- 취약점 스캔, 버그 탐지
- 변경사항 검토

#### Route E: 리팩토링/개선

**의도**: 기존 코드의 구조, 품질, 성능을 개선하는 작업.

- 리팩토링, 코드 정리
- 성능 최적화
- 구조 개선, 중복 제거
- 기술 부채 해소

#### Route F: 간단한 변경

**의도**: 범위가 작고 명확한 코드 수정.

- 파라미터 추가/제거, 이름 변경
- 타입 변경, import 수정
- 단일 메서드 추가
- 단순 버그 수정
- 커밋, 코드 설명 등 간단한 작업

### 라우트 결정 원칙

1. **의도가 명확하면** 해당 라우트로 직행
2. **의도가 복합적이면** 더 포괄적인 라우트 선택 (F보다 A가 더 포괄적)
3. **의도를 모르겠으면** Route A로 — 전체 파이프라인이 알아서 처리
4. **Context Discovery에서 이슈/PR을 읽은 경우** 이슈 내용의 의도에 따라 라우트 결정

---

## Step 3: Pipeline Execution

### 실행 방법 (필수 - 반드시 이 순서를 따른다)

1. **커맨드 파일 로드**: 아래 매핑 테이블에서 선택된 라우트의 커맨드 파일 경로를 확인하고, **Read tool로 해당 파일을 읽는다.**
2. **파이프라인 실행**: 읽은 커맨드 파일에 정의된 Phase 순서, Agent Team 구성, 실행 절차를 **정확히** 따라 실행한다.
3. **인자 전달**: Step 1에서 수집한 컨텍스트와 Step 2에서 추출한 인자(intensity, focus, figma URL 등)를 파이프라인 컨텍스트로 전달한다.

**절대 슬래시 커맨드(`/arena`, `/multi-review` 등)로 호출하지 않는다. 반드시 Read tool로 커맨드 파일을 직접 읽고, 파일 내용의 파이프라인을 따라 실행한다.**

### 커맨드 파일 매핑

| Route | 커맨드 파일 | 전달할 인자 |
|-------|------------|------------|
| A: 기능 구현 | `${PLUGIN_DIR}/commands/arena.md` | `--intensity` (자동 결정) |
| B: 사전 조사 | `${PLUGIN_DIR}/commands/arena-research.md` | 조사 주제 |
| C: 스택 분석 | `${PLUGIN_DIR}/commands/arena-stack.md` | |
| D: 코드 리뷰 | `${PLUGIN_DIR}/commands/multi-review.md` | `--focus`, `--pr` |
| E: 리팩토링 | `${PLUGIN_DIR}/commands/arena.md` | `--phase codebase,review` |
| F: 간단한 변경 | `${PLUGIN_DIR}/commands/arena.md` | `--intensity quick` |

### Intensity 결정

Intensity는 Phase 0.1에서 **Agent Teams 찬반 토론**으로 결정된다. Claude 혼자 판단하지 않는다.

#### Phase 0.1: Intensity Decision (필수)

모든 요청에서 Phase 0 직후에 실행. 3-4개 Claude 에이전트가 적절한 intensity를 토론한다:

- **intensity-advocate**: 더 높은 intensity를 주장. 최악의 시나리오, 보안 리스크, 복잡도 고려.
- **efficiency-advocate**: 더 낮은 intensity를 주장. 실용성, 비용, 범위 고려.
- **risk-assessor**: 프로덕션 영향도, 보안 민감도, 버그 복잡도를 평가.
- **intensity-arbitrator**: 양측 논거를 평가하고 최종 intensity 결정.

토론은 합의에 도달할 때까지 진행. 사용자가 `--intensity`를 명시한 경우 토론을 스킵한다.

#### Intensity별 Phase 범위

| Intensity | Phase 범위 | Decision Debates | Review Agents |
|-----------|-----------|------------------|---------------|
| `quick` | 0 → 0.1 → 0.5 | intensity만 | 없음 (Claude 단독) |
| `standard` | 0 → 0.1 → 0.5 → 1(cached) → 5.5 → 6 → 7 | intensity + 구현전략 | 3-5 agents |
| `deep` | 0 → 0.1 → 0.5 → 1 → 2 → 3 → 5.5 → 6 → 7 | intensity + 리서치방향 + 컴플라이언스범위 + 구현전략 | 5-7 agents |
| `comprehensive` | 0 → 0.1 → 0.5 → 1 → 2 → 3 → 4 → 5 → 5.5 → 6 → 7 | 전체 (4개 디베이트) | 7-10 agents |

#### Decision Debate 적용 범위

| Decision Debate | 목적 | 적용 Intensity |
|----------------|------|---------------|
| Phase 0.1: Intensity Decision | 파이프라인 강도 결정 | 전체 (필수) |
| Phase 2 내 Research Direction Debate | 무엇을 조사할지 방향 결정 | deep, comprehensive |
| Phase 3 내 Compliance Scope Debate | 어떤 컴플라이언스 규칙이 적용되는지 범위 결정 | deep, comprehensive |
| Phase 5.5: Strategy Decision | 구현 전 설계/접근법 토론 | standard, deep, comprehensive |
| Phase 6.10: Code Review Debate | 코드 리뷰 찬반 토론 (기존) | standard, deep, comprehensive |

---

## Argument Extraction

라우트 결정 후, 요청에서 다음을 추출하여 파이프라인 컨텍스트로 전달:

| 추출 대상 | 전달 방식 |
|-----------|-----------|
| Figma URL (`figma.com/...`) | `--figma <url>` |
| PR 번호 | `--pr <number>` |
| 포커스 영역 (보안, 성능, 아키텍처) | `--focus <area>` |
| 대상 파일/디렉토리 경로 | 파이프라인 컨텍스트 |
| 인터랙티브 요청 | `--interactive` |
| 캐시 무시 요청 | `--skip-cache` |
| 명시적 intensity 지정 | `--intensity <level>` |

---

## MCP Dependency Detection

요청 처리 시 필요한 MCP 서버가 감지되면:

1. **ToolSearch로 설치 여부 확인**
2. **설치됨** → 해당 MCP 활용
3. **미설치** → 사용자에게 설치 제안 (AskUserQuestion)
   - 설치하고 계속
   - 해당 기능 없이 계속
   - 취소

감지 패턴:
- Figma URL → Figma MCP
- 테스트/E2E/브라우저 작업 → Playwright MCP
- Notion 참조 → Notion MCP

---

## Examples

### 이슈 기반 작업
```
요청: "내 git 이슈에 있는거 다음 순서 처리해줘"

Step 1: gh issue list → 이슈 목록 확인 → 다음 이슈 선택 → gh issue view N → 내용 파악
Step 2: 이슈 내용이 "Add lobby system" → Route A (기능 구현)
Step 3: Read tool로 ${PLUGIN_DIR}/commands/arena.md 읽기
        → Phase 0 실행 → Phase 0.1 Intensity Debate
          intensity-advocate: "멀티플레이어는 네트워크+보안+동시성 복합 문제. comprehensive 필요"
          efficiency-advocate: "로비만이면 deep이면 충분"
          risk-assessor: "게임 서비스라 보안+컴플라이언스 중요"
          intensity-arbitrator: "deep 결정. 로비 자체는 comprehensive까지는 불필요"
        → deep intensity로 후속 Phase 실행
```

### 데드락 버그 수정
```
요청: "프로덕션에서 데드락 발생하는데 고쳐줘"

Step 1: git diff, 관련 코드 파악
Step 2: 버그 수정 → Route A (기능 구현, 복합 작업이므로)
Step 3: Read tool로 ${PLUGIN_DIR}/commands/arena.md 읽기
        → Phase 0 실행 → Phase 0.1 Intensity Debate
          intensity-advocate: "데드락은 동시성 버그. 잘못 고치면 새 레이스 컨디션 발생. deep 필요"
          efficiency-advocate: "알려진 패턴이면 standard로 충분"
          risk-assessor: "프로덕션 장애. 서비스 중단 리스크. deep 이상 권장"
          intensity-arbitrator: "deep 결정. 프로덕션 리스크 + 동시성 복잡도"
        → deep intensity로 후속 Phase 실행
```

### 간단한 수정
```
요청: "rename this function to calculateScore"

Step 1: 컨텍스트 충분 → 발견 불필요
Step 2: 단순 변경 → Route F (간단한 변경)
Step 3: Read tool로 ${PLUGIN_DIR}/commands/arena.md 읽기
        → Phase 0 실행 → Phase 0.1 Intensity Debate
          intensity-advocate: "이름 변경이 다른 파일에 영향 줄 수 있다"
          efficiency-advocate: "단순 rename이다. quick으로 충분"
          intensity-arbitrator: "quick 결정. 단일 요소 변경"
        → quick intensity로 Phase 0.5만 실행 (Claude 단독)
```

### 인증 시스템 구현
```
요청: "OAuth 로그인 시스템 구현해줘"

Step 1: 컨텍스트 충분
Step 2: 기능 구현 → Route A
Step 3: Read tool로 ${PLUGIN_DIR}/commands/arena.md 읽기
        → Phase 0 실행 → Phase 0.1 Intensity Debate
          intensity-advocate: "인증은 한 번 뚫리면 전체 시스템 위험. comprehensive 필요"
          efficiency-advocate: "OAuth는 표준 프로토콜. deep이면 충분"
          risk-assessor: "인증은 보안 최우선. 모델 벤치마킹으로 최고의 보안 리뷰어 필요"
          intensity-arbitrator: "comprehensive 결정. 보안 최우선 + Phase 4 벤치마킹 필요"
        → comprehensive intensity로 전체 Phase 실행
```

### 코드 리뷰
```
요청: "PR 42번 보안 위주로 봐줘"

Step 1: gh pr view 42 → PR diff 파악
Step 2: 코드 리뷰 → Route D (코드 리뷰)
Step 3: Read tool로 ${PLUGIN_DIR}/commands/multi-review.md 읽기
        → --pr 42 --focus security 로 리뷰 파이프라인 실행
```

### 리팩토링
```
요청: "이 서비스 코드 정리 좀 해줘"

Step 1: 대상 파일/디렉토리 파악
Step 2: 코드 개선 → Route E (리팩토링)
Step 3: Read tool로 ${PLUGIN_DIR}/commands/arena.md 읽기
        → Phase 0 실행 → Phase 0.1 Intensity Debate → intensity 결정
        → --phase codebase,review 로 파이프라인 실행
```
