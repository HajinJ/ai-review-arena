# AI Review Arena

[English](README.md) | [한국어](README.ko.md)

AI 모델들이 코드와 **비즈니스 콘텐츠**를 놓고 서로 논쟁하게 만드는 [Claude Code](https://docs.anthropic.com/en/docs/claude-code) 플러그인입니다.

## 문제

AI에게 코드 리뷰를 요청하면 12개의 이슈를 찾아냅니다. 하지만 그 중 실제 문제는 몇 개일까요? 단일 모델 리뷰는 시간을 낭비하게 하는 오탐(false positive)을 생성하고, 한 모델의 사각지대 때문에 실제 취약점은 빠져나갑니다. 어떤 발견을 신뢰할 수 있는지 알 방법이 없습니다.

비즈니스 콘텐츠도 같은 문제가 있습니다. 잘못된 시장 규모나 과대 표현된 제품 역량이 담긴 피치 덱은 투자 라운드를 망칠 수 있습니다. 리뷰어 하나로는 모든 것을 잡아낼 수 없습니다.

## Arena가 하는 일

Arena는 Claude, OpenAI Codex, Google Gemini가 **코드나 비즈니스 콘텐츠를 독립적으로 리뷰한 후, 3라운드 적대적 토론에서 서로의 발견을 교차 심문**하게 합니다. 모델들은 서로 도전하고, 자신의 입장을 방어하거나, 틀렸을 때 인정합니다. 살아남은 것은 여러 AI 관점에서 검증된 발견들이며, 각각 실제로 신뢰할 수 있는 신뢰도 점수를 가집니다.

**두 파이프라인, 하나의 시스템:**

- **코드 파이프라인** (Route A-F): 코드베이스 컨벤션 분석, 모범 사례 조사, 컴플라이언스 확인, 모델 벤치마킹, 정적 분석 스캐너 실행, 구현 전략 토론, 6-12개 전문 에이전트로 코드 리뷰 (강도에 따라 스케일링), 회귀 테스트 생성, 안전한 발견 자동 수정, 테스트 스위트로 검증. deep+ 강도에서 STRIDE 위협 모델링과 Round 4 에스컬레이션 토론 추가
- **비즈니스 파이프라인** (Route G-I): 문서에서 비즈니스 컨텍스트 추출, 시장 데이터 조사, 토론을 통한 분석 프레임워크 선택, 주장의 정확성 감사, 비즈니스 콘텐츠 모델 벤치마킹, 3-시나리오 의무화된 콘텐츠 전략 토론, 증거 티어링을 적용한 5-10개 전문 에이전트 + 외부 CLI로 리뷰 (강도에 따라 스케일링), deep+에서 정량적 검증과 적대적 레드팀 실행, 일관성 검증과 함께 콘텐츠 자동 수정

Arena는 자동으로 작동합니다. 따로 호출할 필요 없습니다. Claude Code를 평소처럼 사용하면 파이프라인이 백그라운드에서 실행됩니다.

## 빠른 시작

### 옵션 1: Claude Code 플러그인 마켓플레이스 (권장)

```
/install-plugin HajinJ/ai-review-arena
```

### 옵션 2: 소스에서 설치

```bash
git clone https://github.com/HajinJ/ai-review-arena.git
cd ai-review-arena
./install.sh  # macOS / Linux / WSL
```

Agent Teams 활성화 (멀티 에이전트 토론에 필요):

```bash
echo 'export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=true' >> ~/.zshrc
source ~/.zshrc
```

끝입니다. 이제 모든 Claude Code 세션이 Arena를 통해 자동으로 실행됩니다.

### 사전 요구사항

| 도구 | 필수 여부 | 이유 |
|------|----------|-----|
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | 필수 | 기반 플랫폼 |
| [jq](https://jqlang.github.io/jq/) | 권장 | 스크립트 내 JSON 처리 |
| [OpenAI Codex CLI](https://github.com/openai/codex) | 선택 | 두 번째 AI 관점 |
| [Google Gemini CLI](https://github.com/google-gemini/gemini-cli) | 선택 | 세 번째 AI 관점 |
| [Python 3](https://www.python.org/) + `openai>=2.22.0` | 선택 | WebSocket 토론 가속 (~40% 빠름) |

Codex나 Gemini 없이도 Arena는 Claude 에이전트만으로 전체 파이프라인을 실행합니다. 폴백 프레임워크가 모든 단계에서 우아한 성능 저하를 보장합니다.

### 제거

```bash
./uninstall.sh
```

---

## 작동 방식

### 평소처럼 입력하면 됩니다

Arena는 모든 요청을 가로채서 무엇을 할지 결정합니다. 슬래시 명령어도, 특별한 문법도 필요 없습니다. 어떤 언어든 상관없습니다.

| 입력 | Arena의 동작 |
|---|---|
| "로그인 API 구현해" | 풀 코드 파이프라인: 리서치, 컴플라이언스, 구현, 3라운드 리뷰, 자동 수정 |
| "프로덕션 데드락 고쳐" | 에이전트들이 심각도 토론, 교차 심문과 함께 심층 분석 실행 |
| "이 변수 이름 바꿔" | 컨벤션 확인을 위한 빠른 코드베이스 스캔 후 변경 |
| "PR #42 보안 리뷰해" | 보안 중심 멀티 AI 적대적 리뷰 |
| "캐싱 어떻게 구현하면 좋을까?" | 모범 사례와 함께 구현 전 리서치 |
| "비즈니스 플랜 작성해" | 풀 비즈니스 파이프라인: 시장 조사, 정확성 감사, 5개 에이전트 리뷰 |
| "투자자 피치 덱 작성해" | 심층 정확성 + 오디언스 적합성 리뷰와 함께 비즈니스 파이프라인 |
| "투자자 질문에 답변 작성해" | 커뮤니케이션 파이프라인, quick 또는 standard 강도 |

### 파이프라인이 스스로 강도를 결정합니다

요청을 하면 Arena는 하드코딩된 규칙이 아닌, 에이전트 팀을 소환하여 해당 질문을 **토론**합니다:

```
사용자: "프로덕션 데드락 고쳐"

intensity-advocate:   "데드락은 동시성 버그. 잘못된 수정은 새로운 레이스
                       컨디션을 만듦. 심층 분석 필요."
efficiency-advocate:  "락 순서 지정 같은 알려진 패턴이면 표준 분석으로 충분."
risk-assessor:        "프로덕션 장애. 서비스 중단 위험. 최소 심층 분석 필요."
intensity-arbitrator: "Deep. 프로덕션 리스크가 속도보다 중요."
```

중재자가 네 가지 수준 중 하나를 선택합니다:

| 수준 | 코드 파이프라인 | 비즈니스 파이프라인 |
|-------|-----------|------|
| **quick** | 코드베이스 스캔, Claude 단독 | 비즈니스 컨텍스트 스캔, Claude 단독 |
| **standard** | + 스택 감지, 정적 분석, 전략 토론, 리뷰, 3라운드 교차 심문, 테스트 생성, 자동 수정 | + 시장 조사, 프레임워크 선택 토론, 전략 토론(+3 시나리오), 5개 에이전트 리뷰 + 외부 CLI (교차 리뷰), 자동 수정(+일관성 검증) |
| **deep** | + 리서치, 컴플라이언스, 위협 모델링, Round 4 에스컬레이션, 강도 체크포인트 | + 모범 사례 조사, 정확성 감사, 정량적 검증, 적대적 레드팀, 강도 체크포인트 |
| **comprehensive** | + 모델 벤치마킹, Figma 분석, 전체 토론 | + 비즈니스 모델 벤치마킹, 벤치마크 기반 외부 CLI 역할 |

**강도는 파이프라인 도중에 변경될 수 있습니다.** 리서치 완료 후 (Phase 2.9 / B2.9), Arena는 결정된 강도가 여전히 적절한지 재평가합니다. 리서치에서 숨겨진 복잡성이 드러나면 업그레이드를 권장하고, 작업이 예상보다 단순하면 다운그레이드를 권장합니다. 양방향 조정이 지원됩니다.

### 실행 전 비용 추정

강도가 결정된 후, Arena는 실행 전에 비용과 시간을 추정합니다 (Phase 0.2 / B0.2). 내역을 확인하고 진행, 강도 조정, 취소를 선택할 수 있습니다. `$5.00` 미만(설정 가능)이면 자동으로 진행됩니다. Claude의 프리픽스 캐싱을 사용할 때 정확한 비용 예측을 위한 프롬프트 캐시 할인 설정을 지원합니다.

---

## 3라운드 교차 심문

Arena의 핵심입니다. 세 AI 모델 패밀리가 단순히 독립적으로 리뷰하는 것이 아닙니다. 서로 **논쟁**합니다.

### 1라운드: 독립 리뷰

세 모델이 서로를 모른 채 병렬로 리뷰합니다:

```
Claude Agent Team          Codex CLI            Gemini CLI
  security-reviewer          (독립 리뷰)          (독립 리뷰)
  bug-detector
  architecture-reviewer
  performance-reviewer
  test-coverage-reviewer
  scope-reviewer
  + observability, dependency, api-contract, data-integrity,
    accessibility, configuration (높은 인텐시티에서)
         |                       |                     |
         v                       v                     v
  findings-claude.json    findings-codex.json   findings-gemini.json
```

비즈니스 리뷰도 같은 구조로, 도메인별 리뷰어(정확성-증거, 오디언스, 커뮤니케이션-내러티브, 경쟁 포지셔닝, 시장 적합성, 높은 인텐시티에서 추가 리뷰어) + 외부 CLI가 참여합니다. `comprehensive` 강도에서는 벤치마크 점수가 외부 모델의 역할(1라운드 주 리뷰어 vs 2라운드 교차 리뷰어)을 결정합니다.

### 2라운드: 교차 심문

각 모델이 나머지 두 모델의 발견을 읽고 공격하거나 지지합니다:

- **Codex**: Claude + Gemini 발견을 읽고 각각 판정: `AGREE`, `DISAGREE`, `PARTIAL`
- **Gemini**: Claude + Codex 발견을 읽고 같은 판정
- **Claude 리뷰어들**: Codex + Gemini 발견을 읽고 같은 판정

각 판정에는 `confidence_adjustment` (-30 ~ +30)와 인용된 증거가 포함됩니다. 모델들은 다른 모델이 놓친 **새로운 관찰**도 보고할 수 있습니다.

### 3라운드: 방어

2라운드의 도전은 원래 발견을 한 모델에게 돌아갑니다. 각 모델은 반드시 응답해야 합니다:

- **DEFEND** — "입장을 유지합니다. 놓친 추가 증거가 있습니다."
- **CONCEDE** — "맞습니다, 오탐이었습니다." (발견 철회)
- **MODIFY** — "이슈는 실재하지만 심각도를 잘못 판단했습니다." (조정)

2라운드 교차 리뷰어로만 참여한 외부 모델은 `implicit_defend`를 받습니다 — 다시 호출할 수 없으므로 현재 신뢰도에서 발견이 유지됩니다.

### 합의

debate-arbitrator가 세 라운드를 종합하여 최종 신뢰도 점수를 산출합니다:

```
final_confidence = original_score
  + round2_adjustments          # 교차 심문에서
  + cross_exam_boost            # 2+ 동의: +15, 2+ 반대: -20
  + defense_boost               # 방어: +10, 인정: -25
  + consensus_bonus             # 다중 모델 합의 보너스
```

최종 리포트의 모든 발견에는 세 라운드에 걸쳐 각 모델이 말한 내용을 보여주는 `cross_examination_trail`이 포함됩니다.

### 이 설계의 이유

**단일 라운드 리뷰는 근본적으로 한계가 있습니다.** Codex가 "치명적 SQL 인젝션"을 지적했는데 Claude와 Gemini가 모두 이를 방지하는 파라미터화된 쿼리를 가리킨다면, 그것은 오탐입니다. 교차 심문 없이는 조사하느라 시간을 낭비하게 됩니다. 반대로, 세 모델이 독립적으로 같은 레이스 컨디션을 지적하면 신뢰도가 크게 올라갑니다.

**인정(concession)은 강력한 신호입니다.** 모델이 자신의 발견에 대한 반박 증거를 검토하고 "맞습니다, 제가 틀렸습니다"라고 말할 때, 그것은 어떤 신뢰도 점수보다 더 신뢰할 수 있습니다. 완고하게 입장을 방어하는 것이 아니라 실제로 반박 증거를 처리했다는 의미입니다.

**상태 없는(stateless) CLI도 토론할 수 있습니다.** Codex와 Gemini는 CLI 도구이지 대화형 에이전트가 아닙니다. Arena는 여러 CLI 호출에 누적된 컨텍스트를 파이프하여 다중 라운드 토론을 구현합니다. 2라운드 입력에는 다른 모델의 1라운드 발견이, 3라운드 입력에는 2라운드 도전이 포함됩니다. 팀 리더가 데이터 흐름을 조율합니다. 비즈니스 리뷰 스크립트는 카테고리별 프롬프트와 함께 이중 모드(`--mode round1` 독립 리뷰, `--mode round2` 교차 리뷰)를 지원합니다.

---

## 자동 수정 루프 (Phase 6.5)

3라운드 토론이 합의에 도달한 후, Arena는 안전하고 높은 신뢰도의 발견을 자동으로 수정할 수 있습니다.

### 코드 파이프라인

엄격한 기준 — 다음 **모든** 조건을 충족하는 수정만:

| 기준 | 요구사항 |
|-----------|------------|
| 심각도 | `medium` 또는 `low`만 (critical/high는 절대 불가) |
| 신뢰도 | 토론 후 >= 90% |
| 합의 | 만장일치 또는 과반수 |
| 범위 | <= 10줄 코드 |
| 카테고리 | 다음만: 네이밍, 임포트, 미사용 코드, 타입, null 체크, 문서 |

보안 취약점, 로직 오류, 레이스 컨디션, 아키텍처, 성능 이슈는 **절대** 자동 수정하지 않습니다.

수정 적용 후, Arena는 테스트 스위트를 실행합니다 (자동 감지: `npm test`, `pytest`, `go test`, `cargo test`). 테스트가 실패하면 `git checkout -- .`로 **모든 수정이 되돌려지고** "auto-fix-failed, manual review required"로 표시됩니다.

### 비즈니스 파이프라인

비즈니스 자동 수정은 더 적극적입니다: 합의 발견에 기반하여 콘텐츠를 수정하고 (critical/high 심각도 포함), 과대 표현된 역량을 업데이트하고, 톤/오디언스 불일치를 수정합니다.

---

## 리뷰 유효성 검증

Arena는 git 해시 기반 무효화 시스템으로 코드 신선도를 추적합니다. 리뷰가 시작되면 현재 `HEAD` 커밋 해시가 저장됩니다. 발견을 집계하기 전에 현재 `HEAD`와 저장된 해시를 비교합니다. 리뷰 중 코드가 변경된 경우:

- 모든 발견에 `stale: true` 표시
- 리포트에 경고 배너 표시: **"리뷰 이후 코드가 변경됨 — findings 재검증 필요"**
- 발견은 참고용으로 보존 (삭제되지 않음) 되지만, 재검증이 필요한 것으로 표시

리뷰 도중 코드 변경이 발생했을 때 오래된 발견에 기반한 조치를 방지합니다.

---

## 비즈니스 모델 벤치마킹

`comprehensive` 강도에서 Arena는 Claude, Codex, Gemini를 **12개의 오류가 심어진 비즈니스 문서** (카테고리당 3개)로 벤치마킹하여 각 유형의 이슈를 가장 잘 잡는 모델을 결정합니다:

| 카테고리 | 테스트 케이스 | 심어진 오류 |
|----------|-----------|----------------|
| **정확성** | 피치 덱, 사업 계획서, 투자자 업데이트 | 잘못된 시장 규모, 부풀린 성장률, 잘못 인용된 데이터 |
| **오디언스** | 피치 덱, 블로그 포스트, 내부 메모 | 잘못된 톤, 누락된 지표, 유출된 용어 |
| **포지셔닝** | 경쟁 분석, 랜딩 페이지, 영업 덱 | 허위 경쟁사 주장, 근거 없는 "업계 최고" |
| **증거** | 사업 계획서, 시장 리포트, 사례 연구 | 미인용 통계, 방법론 결함, 생존자 편향 |

각 모델의 발견은 **F1** (정밀도 x 재현율)로 점수가 매겨지고, 카테고리당 3개 테스트의 평균을 냅니다. 각 카테고리에서 최고 점수 모델이 해당 카테고리의 **1라운드 주 리뷰어**가 됩니다. 낮은 점수의 모델은 2라운드 교차 리뷰어로 참여합니다.

`standard`와 `deep` 강도 (벤치마킹 데이터 없음)에서는 외부 모델이 항상 2라운드 교차 리뷰어로 참여합니다.

---

## 설계 철학

### 왜 규칙이 아닌 에이전트 토론인가

초기 버전은 키워드 매칭을 사용했습니다: 요청에 "auth"나 "security"가 언급되면 강도가 `deep`이 되었습니다. 이건 계속 깨졌습니다. "프로덕션 데드락 고쳐"에는 보안 키워드가 없지만, 잘못된 수정이 새로운 레이스 컨디션을 만드는 동시성 버그입니다. 키워드 목록으로는 처리할 수 없습니다.

에이전트 토론은 **새로운 시나리오에 대해 추론**할 수 있기 때문에 이를 해결합니다. risk-assessor는 프로덕션 장애가 심각하다는 것을 이해합니다. efficiency-advocate는 철저함이 정당화되지 않을 때 반대합니다. 중재자가 양측을 저울질합니다. 이것은 키워드 사전을 관리할 필요 없이 어떤 요청에든, 어떤 도메인에든 작동합니다.

### 왜 에이전트가 긍정적 프레이밍을 사용하는가

에이전트 사양은 부정적 지시("X를 보고하지 마라") 대신 긍정적 기준("기준이 충족될 때만 보고")을 사용합니다. 이는 [AGENTS.md 벤치마크 논문](https://arxiv.org/abs/2602.11988)에 기반한 것으로, 부정적 지시가 포함된 컨텍스트 파일이 "핑크 코끼리 효과"를 유발한다는 것을 발견했습니다 — 에이전트에게 무언가를 하지 말라고 지시하면 역설적으로 제외된 패턴에 대한 주의가 증가하여, SWE-bench 성공률 0.5% 감소, AgentBench 2% 감소, 추론 비용 20-23% 증가를 초래합니다.

33개 모든 에이전트는 발견이 보고 가능하려면 모두 참이어야 하는 3개의 AND 기준으로 된 **Reporting Threshold**를 정의하고, 완화를 확인하는 **Recognized Patterns** 목록을 포함합니다. 예를 들어, security-reviewer는 발견이 악용 가능(Exploitable) AND 미완화(Unmitigated) AND 프로덕션 도달 가능(Production-reachable)일 때만 보고하며, "파라미터화된 쿼리" 같은 패턴을 SQL 인젝션이 완화되었다는 확인으로 나열합니다.

### 왜 외부 CLI 프롬프트가 핵심 지시를 반복하는가

외부 CLI 스크립트(Codex, Gemini)는 [Duplicate Prompt Technique](https://arxiv.org/abs/2512.14982)을 사용합니다 — 핵심 리뷰 지시를 프롬프트 끝에 반복합니다. 이 기법은 47/70 벤치마크에서 비추론 LLM 정확도를 향상시켰으며 손실은 0입니다. Gemini Flash-Lite 정확도가 한 벤치마크에서 21.33%에서 97.33%로 향상되었습니다. 추론 모드 모델에는 효과가 없으므로(긍정적이든 부정적이든), 외부 CLI에만 적용됩니다.

### 왜 성공 기준이 코드 작성 전에 존재하는가

[Karpathy의 Goal-Driven Execution 원칙](https://github.com/forrestchang/andrej-karpathy-skills)에서 영감을 받았습니다. 구현 시작 전, 전략 토론이 **구체적이고 테스트 가능한 성공 기준**을 생성합니다:

```
1. 유효한 입력에 API가 200 반환     -> 검증: 샘플 페이로드로 curl
2. 유효하지 않은 토큰에 401 반환    -> 검증: 만료된 토큰으로 curl
3. 분당 100건 레이트 리미팅         -> 검증: k6로 부하 테스트
```

구현 후, Phase 7이 각 검증을 실행하고 PASS/FAIL을 보고합니다. 작업 완료 여부에 대한 모호함이 없습니다.

### 왜 scope-reviewer가 존재하는가

역시 Karpathy에서 (Surgical Changes). AI 구현은 범위가 넓어지는 경향이 있습니다. 로그인 엔드포인트를 요청하면 재포매팅된 임포트, 이름이 바뀐 변수, 아무도 요청하지 않은 추상화 계층, 존재하지 않는 기능을 위한 설정 옵션이 따라옵니다. scope-reviewer 에이전트는 실제 diff를 전략과 비교하여 다음을 표시합니다:

- **SCOPE_VIOLATION** -- 계획에 없던 파일 변경
- **DRIVE_BY_REFACTOR** -- 관련 없는 이름 변경이나 재포매팅
- **GOLD_PLATING** -- 아무도 요청하지 않은 기능이나 추상화
- **UNNECESSARY_CHANGE** -- 작업 범위 밖의 외관적 편집

모든 것이 범위 안에 있으면 판정은 `CLEAN`입니다.

### 왜 코드베이스 분석이 먼저 실행되는가

코드를 작성하기 전에, Arena는 프로젝트의 네이밍 컨벤션, 디렉토리 패턴, 임포트 스타일, 에러 처리 방식, 기존 유틸리티를 스캔합니다. 생성된 코드는 이미 있는 것과 일치합니다. `snake_case` 프로젝트에 `camelCase`가 들어가지 않습니다. `src/utils/`에 이미 있는 유틸리티를 재발명하지 않습니다.

### 왜 모든 단계에 폴백이 존재하는가

외부 CLI는 타임아웃될 수 있습니다. Agent Teams는 생성에 실패할 수 있습니다. 리서치 쿼리는 아무것도 반환하지 않을 수 있습니다. Arena는 이 모든 것을 구조화된 폴백 프레임워크(코드 6단계, 비즈니스 5단계)로 처리하여 우아하게 성능을 저하시킵니다. Codex가 타임아웃되면 Claude가 혼자 처리합니다. Agent Teams가 실패하면 Task 서브에이전트가 토론 없이 실행됩니다. 모든 것이 실패하면 Claude가 인라인 분석을 합니다. 최종 리포트는 항상 어떤 폴백 수준이 활성화되었고 무엇이 건너뛰어졌는지 보여줍니다.

---

## 파이프라인 단계

### 코드 파이프라인

```
Phase 0     인수 파싱 + MCP 의존성 감지
Phase 0.1   강도 결정                   * 에이전트가 얼마나 철저할지 토론
Phase 0.2   비용 & 시간 추정              사용자가 실행 전 취소/조정 가능
Phase 0.5   코드베이스 분석               컨벤션, 재사용 가능 코드, 구조 스캔
Phase 1     스택 감지                     프레임워크, 언어, 의존성 (7일 캐시)
Phase 2     구현 전 리서치              * 에이전트가 무엇을 조사할지 토론 (deep+)
Phase 2.9   강도 체크포인트               양방향: 발견에 따라 업그레이드/다운그레이드
Phase 3     컴플라이언스 확인           * 에이전트가 적용할 규칙 토론 (deep+)
Phase 4     모델 벤치마킹                 카테고리별 각 AI 점수화 (comprehensive, 14일 캐시)
Phase 5     Figma 디자인 분석             Figma MCP 사용 가능 시
Phase 5.5   구현 전략                   * 에이전트가 접근법 토론 + 성공 기준 정의
Phase 5.8   정적 분석                    스캐너 실행 (semgrep, eslint, bandit, gosec) (standard+)
Phase 5.9   위협 모델링                 * 3-에이전트 STRIDE 위협 토론 (deep+)
Phase 6     구현 + 코드 리뷰 + 3라운드 교차 심문 (+deep+에서 Round 4 에스컬레이션)
Phase 6.5   자동 수정 루프                안전한 발견 수정, 테스트 검증, 실패 시 롤백
Phase 6.6   테스트 생성                   critical/high 발견에 대한 회귀 테스트 스텁 (standard+)
Phase 7     최종 리포트 + 피드백          성공 기준 PASS/FAIL, 범위 판정, 비용 내역
```

9개 결정 포인트(*)가 정적 규칙 대신 적대적 토론을 사용합니다.

### 비즈니스 파이프라인

```
Phase B0     인수 파싱 + MCP 의존성 감지
Phase B0.1   강도 결정                    * 에이전트가 토론 (노출도, 브랜드 리스크, 정확성)
Phase B0.2   비용 & 시간 추정              사용자가 실행 전 취소/조정 가능
Phase B0.5   비즈니스 컨텍스트 분석         문서에서 추출: 제품, 가치 제안, 브랜드 보이스
Phase B1     시장/산업 컨텍스트             WebSearch로 시장 데이터, 경쟁사, 트렌드
Phase B1.5   프레임워크 선택             * 3-에이전트 토론으로 분석 프레임워크 선택 (standard+)
Phase B2     모범 사례 조사               * 에이전트가 조사 방향 토론 (deep+)
Phase B2.9   강도 체크포인트               시장/리서치 발견에 따른 양방향 조정
Phase B3     정확성 & 일관성 감사         * 에이전트가 검증 범위 토론 (deep+)
Phase B4     비즈니스 모델 벤치마킹         12개 오류 삽입 테스트, F1 점수화 (comprehensive)
Phase B5.5   콘텐츠 전략 토론             * 에이전트가 메시징 토론 + 3-시나리오 분석 의무화
Phase B5.6   정량적 검증                   2-에이전트 수치 교차 검증 (deep+)
Phase B5.7   적대적 레드팀               * 회의적 투자자, 경쟁사, 규제 에이전트 (deep+)
Phase B6     5개 에이전트 리뷰 + 외부 CLI + 3라운드 교차 심문 (증거 티어링 적용)
Phase B6.5   발견 적용                    합의에 따른 콘텐츠 자동 수정
Phase B7     최종 리포트 + 피드백          품질 스코어카드 + 일관성 검증
```

---

## 라우트

Arena는 의도를 9개 라우트 중 하나로 분류합니다:

### 코드 라우트 (A-F)

| 라우트 | 대상 | 파이프라인 |
|-------|------|----------|
| **A: 기능 구현** | 새로운 기능, 복잡한 작업 | 적용 가능한 모든 단계의 풀 코드 파이프라인 |
| **B: 리서치** | "어떻게 구현하면 좋을까..." 질문 | 구현 전 조사 |
| **C: 스택 분석** | 프로젝트 기술 이해 | 프레임워크/의존성 감지 |
| **D: 코드 리뷰** | 기존 코드 또는 PR 리뷰 | 멀티 AI 적대적 리뷰 |
| **E: 리팩토링** | 기존 코드 구조 개선 | 코드베이스 분석 + 코드 리뷰 |
| **F: 간단한 변경** | 작고 명확한 수정 | Quick 강도, Claude 단독 |

### 비즈니스 라우트 (G-I)

| 라우트 | 대상 | 파이프라인 |
|-------|------|----------|
| **G: 비즈니스 콘텐츠** | 사업 계획서, 피치 덱, 제안서, 마케팅 카피 | 풀 비즈니스 파이프라인 |
| **H: 비즈니스 분석** | 시장 조사, 경쟁 분석, SWOT, 전략 | 전략 중심 비즈니스 파이프라인 |
| **I: 커뮤니케이션** | 투자자 Q&A, 고객 이메일, 프레젠테이션 스크립트 | 오디언스/톤 중심 비즈니스 파이프라인 |

### 멀티 라우트 요청

두 파이프라인에 걸친 요청은 분해되어 **컨텍스트 포워딩**과 함께 순차적으로 실행됩니다:

```
"피치 덱 작성하고 그걸 기반으로 랜딩 페이지 만들어"

  Route G (사업 계획) -> Route A (랜딩 페이지)
                      ^
                      |
          컨텍스트 포워딩: key_themes, tone, audience
          (계층적 제한: 2K 요약, 15K 콘텐츠, 1K 메타데이터, 20K 총 제한)
```

---

## 설정

### 프로젝트 수준

프로젝트 루트에 `.ai-review-arena.json`을 생성합니다:

```json
{
  "models": {
    "claude": { "enabled": true, "roles": ["security", "bugs"] },
    "codex": { "enabled": true },
    "gemini": { "enabled": true, "roles": ["architecture"] }
  },
  "review": {
    "intensity": "standard",
    "focus_areas": ["security", "bugs"]
  },
  "output": {
    "language": "ko"
  }
}
```

### 전역 설정

`~/.claude/.ai-review-arena.json`에 모든 프로젝트의 기본값을 설정합니다.

### 설정 병합 순서

설정은 우선순위 순으로 딥 머지됩니다: **기본값** (내장) → **전역** (`~/.claude/.ai-review-arena.json`) → **프로젝트** (`.ai-review-arena.json`). 프로젝트 수준 값이 전역을 덮어쓰고, 전역이 기본값을 덮어씁니다.

### 환경 변수

```bash
ARENA_INTENSITY=deep               # 강도 강제 (토론 건너뜀)
ARENA_SKIP_CACHE=true              # 모든 캐시 우회
MULTI_REVIEW_INTENSITY=standard    # 기본 리뷰 강도
MULTI_REVIEW_LANGUAGE=ko           # 출력 언어
```

### Arena 우회

```bash
# 단일 요청에서 Arena 건너뛰기
"이 오타 수정해 --no-arena"

# 강도 강제 (토론 건너뜀)
"이거 구현해 --intensity deep"

# 슬래시 명령어 직접 사용 (자동 라우팅 우회)
/multi-review --focus security
```

---

## 슬래시 명령어

라우터가 모든 것을 처리하므로 보통은 불필요하지만, 직접 사용할 수 있습니다:

| 명령어 | 설명 |
|---------|-------------|
| `/arena` | 풀 코드 라이프사이클 파이프라인 |
| `/arena-business` | 풀 비즈니스 라이프사이클 파이프라인 |
| `/arena-research` | 구현 전 리서치만 |
| `/arena-stack` | 기술 스택 감지 |
| `/multi-review` | 멀티 AI 코드 리뷰만 |
| `/multi-review-config` | 리뷰 설정 관리 |
| `/multi-review-status` | 리뷰 세션 상태 확인 |

---

## 폴백 프레임워크

Arena는 파이프라인을 절대 크래시시키지 않습니다. 무언가 실패하면 우아하게 성능을 저하시킵니다:

### 코드 파이프라인 (6단계)

| 수준 | 트리거 | 동작 |
|-------|---------|--------|
| 0 | 없음 | 전체 운영 |
| 1 | 벤치마크 실패 | 기본 역할 배정 사용 |
| 2 | 리서치 실패 | 컨텍스트 보강 건너뜀 |
| 3 | Agent Teams 실패 | Task 서브에이전트 사용 (토론 없음) |
| 4 | 외부 CLI 실패 | Claude 단독 리뷰 |
| 5 | 전체 실패 | 인라인 Claude 단독 분석 |

### 비즈니스 파이프라인 (5단계)

| 수준 | 트리거 | 동작 |
|-------|---------|--------|
| 0 | 없음 | 전체 운영 |
| 1 | 리서치 실패 | 시장 컨텍스트 건너뜀 |
| 1.5 | 벤치마크 실패 | 기본 역할 배정 사용 |
| 2 | Agent Teams 실패 | Task 서브에이전트 사용 (토론 없음) |
| 2.5 | 외부 CLI 실패 | Claude 단독 리뷰 |
| 3 | 전체 실패 | Claude 단독 인라인 분석 |

최종 리포트는 항상 어떤 폴백 수준이 활성화되었고 무엇이 건너뛰어졌는지 보여줍니다.

---

## 피드백 루프

각 리뷰 세션 후, Arena는 선택적으로 발견에 대한 피드백을 수집합니다 (유용 / 유용하지 않음 / 오탐). 피드백은 JSONL 형식으로 저장되며 두 가지 목적으로 사용됩니다:

1. **정확도 리포트** — 모델별, 카테고리별 품질 추적:

```
모델 품질 리포트 (최근 30일):
| 모델   | 유용 | 유용하지 않음 | 오탐 | 정확도 |
|--------|------|-------------|------|--------|
| Claude | 45   | 8           | 3    | 80.4%  |
| Codex  | 38   | 12          | 5    | 69.1%  |
| Gemini | 41   | 10          | 4    | 74.5%  |
```

2. **라우팅 최적화** — 결합 점수 (60% 피드백 정확도 + 40% 벤치마크 F1)가 향후 세션에서 어떤 모델이 어떤 카테고리를 리뷰할지 결정합니다.

---

## 컨텍스트 밀도

Arena는 각 리뷰 에이전트에게 역할에 맞는 컨텍스트를 제공합니다. 전체 코드베이스를 모든 에이전트에게 보내는 대신, 역할별 패턴으로 필터링합니다:

| 역할 | 우선 패턴 |
|------|---------------------|
| security | `auth`, `login`, `password`, `token`, `session`, `csrf`, `inject`, `eval` |
| bugs | `catch`, `throw`, `error`, `null`, `undefined`, `async`, `await`, `race`, `lock`, `mutex`, `retry` |
| performance | `for`, `while`, `map`, `query`, `select`, `cache`, `Promise.all`, `stream`, `circuit`, `pool`, `metric` |
| architecture | `import`, `export`, `class`, `interface`, `extends`, `module`, `provider` |
| testing | `describe`, `it`, `test`, `expect`, `mock`, `jest`, `vitest`, `pytest` |
| api_contract | `route`, `endpoint`, `handler`, `controller`, `schema`, `swagger`, `openapi`, `graphql` |
| observability | `log`, `logger`, `trace`, `span`, `metric`, `monitor`, `alert`, `health`, `sentry` |
| data_integrity | `schema`, `validate`, `migration`, `transaction`, `rollback`, `zod`, `prisma`, `typeorm` |
| accessibility | `aria`, `role`, `tabindex`, `alt`, `label`, `focus`, `a11y`, `wcag`, `sr-only` |
| configuration | `env`, `config`, `secret`, `credential`, `docker`, `kubernetes`, `terraform`, `pipeline` |

각 에이전트는 최대 8,000 토큰의 역할 관련 컨텍스트를 받습니다 (설정 가능). 200줄 이하 파일은 필터링을 우회하고 전체가 전송됩니다.

---

## 메모리 계층

Arena는 리뷰 세션 간 학습을 위한 4계층 메모리 아키텍처를 유지합니다:

| 계층 | 범위 | TTL | 추적 내용 |
|------|------|-----|--------|
| **Working** | 현재 세션 | 세션 | 파이프라인 변수, 현재 컨텍스트 |
| **Short-term** | 프로젝트별 | 7일 | 반복되는 발견, 최근 리뷰 패턴 |
| **Long-term** | 세션 간 | 90일 | 카테고리별 모델 정확도, 피드백 추세 |
| **Permanent** | 프로젝트별 | 무기한 | 팀 코딩 표준, 아키텍처 결정 |

Short-term과 Long-term 계층은 라우팅 결정과 에이전트 컨텍스트에 참고됩니다. Permanent 계층은 수동으로 관리됩니다.

---

## Arena 로딩 방식

설치 프로그램이 `~/.claude/CLAUDE.md`에 `@ARENA-ROUTER.md`를 추가합니다. Claude Code가 이 파일을 모든 세션의 시스템 프롬프트에 로드하여 라우터가 항상 활성화됩니다.

```
~/.claude/CLAUDE.md
  +-- @ARENA-ROUTER.md       <- 모든 세션에 로드
        +-- Context Discovery   git, GitHub, Figma 컨텍스트 수집
        +-- Route Selection     의도 기반 분류 (9개 라우트)
        +-- Pipeline Execution  명령 .md 파일 로드 및 실행
```

라우터는 슬래시 명령어가 아닌 Read 도구로 명령 파일을 읽습니다. 이는 무한 재귀를 방지합니다.

요청에 MCP 서버(Figma, Playwright, Notion)가 필요하지만 설치되어 있지 않으면, Arena가 이를 감지하고 설치를 제안합니다. 거절하면 파이프라인은 해당 기능 없이 계속됩니다.

---

## 프로젝트 구조

```
ai-review-arena/
+-- ARENA-ROUTER.md              # 상시 작동 라우팅 로직 (9개 라우트, 컨텍스트 포워딩)
+-- CLAUDE.md                    # 플러그인 개발 규칙
+-- install.sh                   # 설치 프로그램 (macOS / Linux / WSL)
+-- uninstall.sh                 # 제거 프로그램
+-- requirements.txt             # Python 의존성 (openai>=2.22.0)
|
+-- hooks/                       # 자동 리뷰 훅
|   +-- hooks.json               # Claude Code PostToolUse 훅
|   +-- gemini-hooks.json        # Gemini CLI AfterTool 훅 어댑터 설정
|
+-- commands/                    # 파이프라인 정의 (7개 명령)
|   +-- arena.md                 # 코드 파이프라인 (~2500줄)
|   +-- arena-business.md        # 비즈니스 파이프라인 (~2900줄)
|   +-- arena-research.md        # 리서치 파이프라인
|   +-- arena-stack.md           # 스택 감지
|   +-- multi-review.md          # 코드 리뷰 파이프라인
|   +-- multi-review-config.md   # 설정 관리
|   +-- multi-review-status.md   # 상태 대시보드
|
+-- agents/                      # 에이전트 역할 정의 (33개 에이전트)
|   +-- security-reviewer.md     # OWASP, 인증, 인젝션, 데이터 노출
|   +-- bug-detector.md          # 로직 오류, null 처리, 에러 핸들링, 동시성
|   +-- architecture-reviewer.md # SOLID, 패턴, 결합도
|   +-- performance-reviewer.md  # 복잡도, 메모리, I/O, 장애 복구, 스케일
|   +-- test-coverage-reviewer.md # 누락된 테스트, 테스트 품질
|   +-- scope-reviewer.md        # 변경 범위 검증
|   +-- dependency-reviewer.md   # 의존성 건강성, 버전 관리
|   +-- api-contract-reviewer.md # API 스키마, 버전관리, 브레이킹 체인지
|   +-- observability-reviewer.md # 로깅, 트레이싱, 모니터링
|   +-- data-integrity-reviewer.md # 데이터 유효성, 마이그레이션 안전성
|   +-- accessibility-reviewer.md # WCAG, ARIA, 키보드 네비게이션
|   +-- configuration-reviewer.md # 환경설정, 시크릿, IaC
|   +-- threat-modeler.md        # STRIDE 위협 식별
|   +-- threat-defender.md       # 위협 완화 방어
|   +-- threat-arbitrator.md     # 위협 모델 합의
|   +-- debate-arbitrator.md     # 코드 리뷰 3라운드 합의
|   +-- research-coordinator.md  # 구현 전 리서치
|   +-- design-analyzer.md       # Figma 디자인 추출
|   +-- compliance-checker.md    # OWASP, WCAG, GDPR 컴플라이언스
|   +-- accuracy-evidence-reviewer.md      # 비즈니스: 사실 정확성 + 증거 티어링
|   +-- audience-fit-reviewer.md           # 비즈니스: 오디언스 적합성 + 증거 티어링
|   +-- competitive-positioning-reviewer.md # 비즈니스: 시장 포지셔닝 + 증거 티어링
|   +-- communication-narrative-reviewer.md # 비즈니스: 작문 품질 + 증거 티어링
|   +-- market-fit-reviewer.md             # 비즈니스: 제품-시장 적합성, TAM/SAM/SOM
|   +-- financial-credibility-reviewer.md  # 비즈니스: 재무 모델 신뢰성
|   +-- legal-compliance-reviewer.md       # 비즈니스: 법률/규제 컴플라이언스
|   +-- localization-reviewer.md           # 비즈니스: 다국어/다문화 현지화
|   +-- investor-readiness-reviewer.md     # 비즈니스: 투자 유치 준비도
|   +-- conversion-impact-reviewer.md      # 비즈니스: 전환율 최적화
|   +-- skeptical-investor-agent.md        # 레드팀: 투자 회의론자
|   +-- competitor-response-agent.md       # 레드팀: 경쟁 대응 전략
|   +-- regulatory-risk-agent.md           # 레드팀: 규제/법적 리스크
|   +-- business-debate-arbitrator.md      # 비즈니스: 3라운드 합의 + 외부 모델 처리
|
+-- scripts/                     # 셸/Python 스크립트 (31개)
|   +-- codex-review.sh          # Codex 1라운드 코드 리뷰
|   +-- gemini-review.sh         # Gemini 1라운드 코드 리뷰
|   +-- codex-cross-examine.sh   # Codex 2 & 3라운드 (코드)
|   +-- gemini-cross-examine.sh  # Gemini 2 & 3라운드 (코드)
|   +-- codex-business-review.sh # Codex 비즈니스 리뷰 (이중 모드: round1/round2)
|   +-- gemini-business-review.sh # Gemini 비즈니스 리뷰 (이중 모드: round1/round2)
|   +-- benchmark-models.sh      # 코드 모델 벤치마킹
|   +-- benchmark-business-models.sh # 비즈니스 모델 벤치마킹 (12개 테스트, F1)
|   +-- benchmark-utils.sh       # 공유 벤치마크 헬퍼 (메트릭스, 텍스트 추출)
|   +-- evaluate-pipeline.sh     # 파이프라인 평가 (정밀도/재현율/F1)
|   +-- feedback-tracker.sh      # 리뷰 품질 피드백 기록 + 리포팅
|   +-- orchestrate-review.sh    # 리뷰 오케스트레이션 + 리뷰 유효성 검증
|   +-- aggregate-findings.sh    # 발견 집계 + 유효성 표시
|   +-- run-debate.sh            # 토론 실행
|   +-- run-benchmark.sh         # 벤치마크 실행기 (Codex + Gemini + Arena)
|   +-- run-solo-benchmark.sh    # Solo vs Arena 비교 벤치마크
|   +-- generate-report.sh       # 리포트 생성 + 유효성 경고 배너
|   +-- detect-stack.sh          # 스택 감지
|   +-- search-best-practices.sh # 모범 사례 검색
|   +-- search-guidelines.sh     # 컴플라이언스 가이드라인 검색
|   +-- cache-manager.sh         # 캐시 관리
|   +-- cost-estimator.sh        # 토큰 비용 추정 + 캐시 할인
|   +-- context-filter.sh        # 역할 기반 코드 필터링 (리뷰 에이전트용)
|   +-- normalize-severity.sh    # 심각도 정규화 유틸리티
|   +-- validate-config.sh       # 설정 유효성 검증
|   +-- utils.sh                 # 공유 유틸리티
|   +-- openai-ws-debate.py      # WebSocket 토론 클라이언트 (Responses API)
|   +-- gemini-hook-adapter.sh   # Gemini 훅 → Arena 리뷰 어댑터
|   +-- static-analysis.sh       # 정적 분석 스캐너 실행기 (Phase 5.8)
|   +-- normalize-scanner-output.sh # 스캐너 출력 정규화 (SARIF/JSON → 표준 포맷)
|   +-- setup-arena.sh           # Arena 설정
|   +-- setup.sh                 # 일반 설정
|
+-- shared-phases/               # 공통 단계 정의 (9개, 코드 + 비즈니스 공유)
|   +-- intensity-decision.md    # Phase 0.1/B0.1: Agent Teams 강도 토론
|   +-- cost-estimation.md       # Phase 0.2/B0.2: 비용 & 시간 추정
|   +-- feedback-routing.md      # 피드백 기반 모델-카테고리 역할 배정
|   +-- static-analysis.md       # Phase 5.8: 정적 분석 통합 (standard+)
|   +-- threat-modeling.md       # Phase 5.9: STRIDE 3-에이전트 위협 토론 (deep+)
|   +-- test-generation.md       # Phase 6.6: 회귀 테스트 스텁 생성 (standard+)
|   +-- framework-selection.md   # Phase B1.5: 분석 프레임워크 선택 토론 (standard+)
|   +-- quantitative-validation.md # Phase B5.6: 수치 교차 검증 (deep+)
|   +-- adversarial-red-team.md  # Phase B5.7: 적대적 스트레스 테스트 (deep+)
|
+-- config/
|   +-- default-config.json      # 모든 기본 설정 (모델, 리뷰, 토론, 아레나, 캐시,
|   |                            #   벤치마크, 컴플라이언스, 라우팅, 폴백, 비용,
|   |                            #   피드백, 컨텍스트 포워딩, 컨텍스트 밀도,
|   |                            #   메모리 계층, 파이프라인 평가, 정적 분석,
|   |                            #   위협 모델링, 테스트 생성, 증거 티어링,
|   |                            #   프레임워크 선택, 시나리오 분석, 정량적
|   |                            #   검증, 레드팀, 일관성 검증)
|   +-- compliance-rules.json    # 기능-가이드라인 매핑
|   +-- tech-queries.json        # 기술-검색 쿼리 매핑 (31개 기술)
|   +-- review-prompts/          # 구조화된 프롬프트 (9개 템플릿)
|   +-- schemas/                 # Codex 구조화된 출력 JSON 스키마 (5개)
|   |   +-- codex-review.json, codex-cross-examine.json, codex-defend.json
|   |   +-- codex-business-review.json, codex-business-cross-review.json
|   +-- codex-agents/            # Codex 멀티에이전트 TOML 설정 (5개)
|   |   +-- security.toml, bugs.toml, performance.toml
|   |   +-- architecture.toml, testing.toml
|   +-- benchmarks/              # 모델 벤치마크 테스트 케이스 (20개)
|       +-- security-test-{01,02,03}.json    # 코드: 보안 (3개)
|       +-- bugs-test-{01,02,03}.json        # 코드: 버그 (3개)
|       +-- architecture-test-01.json        # 코드: 아키텍처
|       +-- performance-test-01.json         # 코드: 성능
|       +-- business-accuracy-test-{01,02,03}.json    # 비즈니스: 정확성 (3개)
|       +-- business-audience-test-{01,02,03}.json    # 비즈니스: 오디언스 (3개)
|       +-- business-positioning-test-{01,02,03}.json # 비즈니스: 포지셔닝 (3개)
|       +-- business-evidence-test-{01,02,03}.json    # 비즈니스: 증거 (3개)
|       +-- pipeline/            # 파이프라인 평가 ground truth
|
+-- docs/                        # 문서
|   +-- adr-001-bash-architecture.md  # ADR: 왜 bash인지 (트레이드오프)
|   +-- adr-002-markdown-pipelines.md # ADR: 왜 마크다운-as-코드 파이프라인인지
|   +-- config-reference.md      # 설정 레퍼런스 (전체 설정, 환경 변수, 예제)
|   +-- router-examples.md       # 라우터 예시 추출 (12개)
|   +-- context-forwarding.md    # 컨텍스트 포워딩 인터페이스 스펙
|   +-- safety-protocol.md       # Commit/PR 안전 게이트 상세
|   +-- example-output.md        # 리뷰 출력 예시
|   +-- TODO-external-integrations.md  # 리서치 기반 TODO 항목
|
+-- tests/                       # 테스트 스위트 (18개 테스트 파일)
|   +-- run-tests.sh             # 테스트 실행기 (--unit, --integration, --e2e)
|   +-- run-shellcheck.sh        # ShellCheck 린트 실행기
|   +-- test-helpers.sh          # 공유 테스트 유틸리티
|   +-- unit/                    # 유닛 테스트 (8개)
|   +-- integration/             # 통합 테스트 (8개)
|   +-- e2e/                     # E2E 테스트 (2개, CLI 필요)
|
+-- Makefile                     # 빌드 타겟 (test, lint, benchmark, e2e)
+-- .github/workflows/test.yml   # CI 파이프라인 (JSON 검증, shellcheck, 테스트)
|
+-- cache/                       # 런타임 캐시 (gitignored)
    +-- feedback/                # 피드백 JSONL 저장소
    +-- short-term/              # 단기 메모리 (7일 TTL)
    +-- long-term/               # 장기 메모리 (90일 TTL)
    +-- permanent/               # 영구 메모리 (수동 관리)
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
- 33개 에이전트 (기존 27개), 31개 스크립트 (기존 29개), 9개 공유 단계 (기존 3개)

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
- **Codex 멀티에이전트 서브에이전트**: Codex 실험적 멀티에이전트 기능용 5개 TOML 에이전트 설정 (security, bugs, performance, architecture, testing). 이중 게이트: 설정 플래그 AND 런타임 기능 확인. `models.codex.multi_agent.enabled` 설정 (기본값: `true`). 기능 미지원 시 자동으로 단일 에이전트 경로 폴백
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
| **마켓플레이스** | `/install-plugin HajinJ/ai-review-arena` | 예 |
| **소스에서** | `git clone` + `./install.sh` | 수동 (`git pull`) |

대부분의 사용자에게 마켓플레이스 방법을 권장합니다. 소스 설치는 개발 도구 (`make test`, `make lint`, `make benchmark`)에 접근할 수 있습니다.

---

## 라이선스

MIT
