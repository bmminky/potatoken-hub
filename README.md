# potatoken hub

Claude와 Codex의 남은 사용량을 macOS 메뉴바에서 보여주는 로컬 전용 앱.

Mac에 이미 저장되어 있는 로컬 사용량 기록만 읽습니다. 계정, 분석 도구, 제공자 API 키가 없고
네트워크 통신도 하지 않습니다.

## 기능

- **메뉴바 표시** — 각 제공자의 가장 빠듯한 남은 비율을 `Cl 74%  Cx 55%` 형태로 표시
- **두 가지 창 크기** — 마우스로 창을 드래그하면 소형/대형 중 가까운 쪽으로 스냅
  - 소형: Claude/Codex 각각 한 줄 요약 + 사용량 막대
  - 대형: 창(5시간/주간/7일)별 상세 게이지, 리셋 예상 시각, 새로고침·숨기기
- **15초마다 자동 새로고침**
- **로컬 알림** — 사용량이 0%가 되는 순간과 리셋되는 순간 각각 1회씩
- **우클릭 메뉴** — 로그인 시 자동 실행 토글, 앱 종료
- **위치·크기 기억** — 창을 닫은 자리에 그대로 다시 열림
- Dock 아이콘 없음 (`LSUIElement`)

## 데이터 출처

| 제공자 | 로컬 경로 | 비고 |
|---|---|---|
| Claude | `~/Library/Application Support/Claude/plan-usage-history.json` | 5시간·주간 사용률. 파일에 리셋 시각이 없어 과거 사용량이 급감한 지점으로 추정하며, 추정값은 `약`으로 표시 |
| Codex | `~/.codex/sessions/**/*.jsonl` | 가장 최근 `rate_limits` 기록. `resets_at`이 있어 리셋 시각이 정확함 |

두 파일 모두 읽기 전용으로 열며, 대화 내용은 읽지 않습니다.

## 요구 사항

- macOS 13 Ventura 이상
- Swift 6 툴체인 (`swift --version`)
- Xcode Command Line Tools

## 빌드

```bash
./Scripts/build-app.sh
ditto ".build/potatoken hub.app" "/Applications/potatoken hub.app"
open "/Applications/potatoken hub.app"
```

빌드 스크립트가 릴리스 바이너리 컴파일, 앱 번들 생성, 애드혹 서명, 검증까지 수행합니다.

`swift run`이 아니라 앱 번들로 실행해야 합니다 — 알림과 로그인 시 자동 실행은 안정적인
번들 식별자가 필요합니다.

## 테스트

```bash
swift test
```

## 구조

| 경로 | 역할 |
|---|---|
| `Sources/TokenGaugeCore` | 파싱, 검증, 리셋 추정, 알림 스케줄링 등 테스트 가능한 로직 |
| `Sources/TokenGauge` | SwiftUI/AppKit 메뉴바 셸과 시스템 연동 |
| `Tests/TokenGaugeCoreTests` | 리셋 추정 로직 단위 테스트 |
| `Scripts/build-app.sh` | 릴리스 빌드, 번들 조립, 서명, 검증 |

## 참고

이 앱은 서명이 애드혹이고 Apple 공증을 받지 않았습니다. 개인용으로 직접 빌드해 쓰는 것을
전제로 합니다.

OpenAI, Anthropic과 무관한 개인 프로젝트입니다.
