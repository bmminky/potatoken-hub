# potatoken hub

[한국어](#한국어) · [English](#english) · [日本語](#日本語) · [中文](#中文)

Claude와 Codex의 남은 사용량을 macOS 메뉴바에서 보여주는 로컬 전용 앱.

## 스크린샷

| 메뉴바 | 소형 창 | 대형 창 |
|---|---|---|
| ![menu bar](Resources/Screenshots/menu-bar.jpg) | ![small panel](Resources/Screenshots/small-panel.jpg) | ![large panel](Resources/Screenshots/large-panel.jpg) |

---

## 한국어

Mac에 이미 저장되어 있는 로컬 사용량 기록만 읽습니다. 계정, 분석 도구, 제공자 API 키가 없고
네트워크 통신도 하지 않습니다.

### 기능

- **메뉴바 표시** — 각 제공자의 가장 빠듯한 남은 비율을 `Cl 74%  Cx 55%` 형태로 표시
- **두 가지 창 크기** — 마우스로 창을 드래그하면 소형/대형 중 가까운 쪽으로 스냅
  - 소형: Claude/Codex 각각 한 줄 요약 + 사용량 막대
  - 대형: 창(5시간/주간/7일)별 상세 게이지, 리셋 예상 시각, 새로고침·숨기기
- **15초마다 자동 새로고침**
- **로컬 알림** — 사용량이 0%가 되는 순간과 리셋되는 순간 각각 1회씩
- **우클릭 메뉴** — 로그인 시 자동 실행 토글, 앱 종료
- **위치·크기 기억** — 창을 닫은 자리에 그대로 다시 열림
- **4개 언어** — 한국어·English·日本語·中文, 시스템 언어 자동 감지 또는 트레이 메뉴에서 수동 전환
- Dock 아이콘 없음 (`LSUIElement`)

### 데이터 출처

| 제공자 | 로컬 경로 | 비고 |
|---|---|---|
| Claude | `~/Library/Application Support/Claude/plan-usage-history.json` | 5시간·주간 사용률. 파일에 리셋 시각이 없어 과거 사용량이 급감한 지점으로 추정하며, 추정값은 `약`으로 표시 |
| Codex | `~/.codex/sessions/**/*.jsonl` | 가장 최근 `rate_limits` 기록. `resets_at`이 있어 리셋 시각이 정확함 |

두 파일 모두 읽기 전용으로 열며, 대화 내용은 읽지 않습니다.

### 요구 사항

- macOS 13 Ventura 이상
- Swift 6 툴체인 (`swift --version`)
- Xcode Command Line Tools

### 빌드

```bash
./Scripts/build-app.sh
ditto ".build/potatoken hub.app" "/Applications/potatoken hub.app"
open "/Applications/potatoken hub.app"
```

빌드 스크립트가 릴리스 바이너리 컴파일, 앱 번들 생성, 애드혹 서명, 검증까지 수행합니다.

`swift run`이 아니라 앱 번들로 실행해야 합니다 — 알림과 로그인 시 자동 실행은 안정적인
번들 식별자가 필요합니다.

### 테스트

```bash
swift test
```

### 구조

| 경로 | 역할 |
|---|---|
| `Sources/TokenGaugeCore` | 파싱, 검증, 리셋 추정, 알림 스케줄링 등 테스트 가능한 로직 |
| `Sources/TokenGauge` | SwiftUI/AppKit 메뉴바 셸과 시스템 연동 |
| `Tests/TokenGaugeCoreTests` | 리셋 추정 로직 단위 테스트 |
| `Scripts/build-app.sh` | 릴리스 빌드, 번들 조립, 서명, 검증 |

### 참고

이 앱은 서명이 애드혹이고 Apple 공증을 받지 않았습니다. 개인용으로 직접 빌드해 쓰는 것을
전제로 합니다.

OpenAI, Anthropic과 무관한 개인 프로젝트입니다.

[↑ 언어 선택으로](#potatoken-hub)

---

## English

A local-only macOS menu bar app that shows your remaining Claude and Codex
usage. It only reads usage records already stored on your Mac — no accounts,
no analytics, no provider API keys, no network calls.

### Features

- **Menu bar readout** — each provider's tightest remaining percentage, shown as `Cl 74%  Cx 55%`
- **Two panel sizes** — drag the window and it snaps to the nearer of small/large
  - Small: a one-line summary and usage bar per provider
  - Large: a detailed gauge per window (5h/weekly/7d), estimated reset time, refresh/hide
- **Auto-refresh every 15 seconds**
- **Local notifications** — once when a window hits 0%, once when it resets
- **Right-click menu** — toggle launch at login, quit
- **Remembers position and size** — reopens exactly where you left it
- **4 languages** — Korean/English/Japanese/Chinese, auto-detected from the system or switched manually from the tray menu
- No Dock icon (`LSUIElement`)

### Data sources

| Provider | Local path | Notes |
|---|---|---|
| Claude | `~/Library/Application Support/Claude/plan-usage-history.json` | 5-hour and weekly usage. The file has no reset timestamp, so it's estimated from where past usage dropped sharply — estimated values are marked "(est.)" |
| Codex | `~/.codex/sessions/**/*.jsonl` | The most recent `rate_limits` record. `resets_at` is present, so the reset time is exact |

Both files are opened read-only; conversation content is never read.

### Requirements

- macOS 13 Ventura or later
- Swift 6 toolchain (`swift --version`)
- Xcode Command Line Tools

### Build

```bash
./Scripts/build-app.sh
ditto ".build/potatoken hub.app" "/Applications/potatoken hub.app"
open "/Applications/potatoken hub.app"
```

The build script compiles the release binary, assembles the app bundle, ad-hoc signs it, and verifies it.

Run it as the app bundle, not `swift run` — notifications and launch-at-login both need a stable bundle identifier.

### Tests

```bash
swift test
```

### Layout

| Path | Role |
|---|---|
| `Sources/TokenGaugeCore` | Parsing, validation, reset estimation, notification scheduling — the testable logic |
| `Sources/TokenGauge` | The SwiftUI/AppKit menu bar shell and system integration |
| `Tests/TokenGaugeCoreTests` | Unit tests for the reset estimation logic |
| `Scripts/build-app.sh` | Release build, bundle assembly, signing, verification |

### Note

This app is ad-hoc signed and not notarized by Apple. It's meant to be built and run locally for personal use.

An independent personal project, unaffiliated with OpenAI or Anthropic.

[↑ Back to language picker](#potatoken-hub)

---

## 日本語

Mac にすでに保存されているローカルの使用量記録だけを読み取るローカル専用アプリです。
アカウント、分析ツール、プロバイダーの API キーはなく、ネットワーク通信も行いません。

### 機能

- **メニューバー表示** — 各プロバイダーの最も逼迫した残り割合を `Cl 74%  Cx 55%` の形式で表示
- **2種類のウィンドウサイズ** — ドラッグすると近い方(小/大)にスナップ
  - 小: Claude/Codex それぞれ1行の要約と使用量バー
  - 大: ウィンドウ(5時間/週間/7日)ごとの詳細ゲージ、リセット予想時刻、更新・非表示
- **15秒ごとに自動更新**
- **ローカル通知** — 使用量が0%になった瞬間とリセットされた瞬間にそれぞれ1回
- **右クリックメニュー** — ログイン時の自動起動の切り替え、アプリ終了
- **位置・サイズを記憶** — 閉じた場所にそのまま再度開く
- **4言語対応** — 한国語・English・日本語・中文、システム言語の自動検出またはトレイメニューから手動切り替え
- Dock アイコンなし (`LSUIElement`)

### データソース

| プロバイダー | ローカルパス | 備考 |
|---|---|---|
| Claude | `~/Library/Application Support/Claude/plan-usage-history.json` | 5時間・週間の使用率。ファイルにリセット時刻がないため、過去の使用量が急減した地点から推定し、推定値には「約」を表示 |
| Codex | `~/.codex/sessions/**/*.jsonl` | 直近の `rate_limits` 記録。`resets_at` があるためリセット時刻は正確 |

両ファイルとも読み取り専用で開き、会話内容は読み取りません。

### 動作要件

- macOS 13 Ventura 以降
- Swift 6 ツールチェーン (`swift --version`)
- Xcode Command Line Tools

### ビルド

```bash
./Scripts/build-app.sh
ditto ".build/potatoken hub.app" "/Applications/potatoken hub.app"
open "/Applications/potatoken hub.app"
```

ビルドスクリプトがリリースバイナリのコンパイル、アプリバンドルの組み立て、アドホック署名、検証まで行います。

`swift run` ではなくアプリバンドルとして実行してください — 通知とログイン時自動起動には
安定したバンドル識別子が必要です。

### テスト

```bash
swift test
```

### 構成

| パス | 役割 |
|---|---|
| `Sources/TokenGaugeCore` | パース、検証、リセット推定、通知スケジューリングなどテスト可能なロジック |
| `Sources/TokenGauge` | SwiftUI/AppKit のメニューバーシェルとシステム連携 |
| `Tests/TokenGaugeCoreTests` | リセット推定ロジックの単体テスト |
| `Scripts/build-app.sh` | リリースビルド、バンドル組み立て、署名、検証 |

### 補足

このアプリはアドホック署名のみで、Apple の公証は受けていません。個人用にローカルで
ビルドして使うことを前提としています。

OpenAI、Anthropic とは無関係の個人プロジェクトです。

[↑ 言語選択に戻る](#potatoken-hub)

---

## 中文

只读取 Mac 上已经保存的本地使用量记录的本地专用应用。没有账户、没有分析工具、没有
服务商 API 密钥,也不进行任何网络通信。

### 功能

- **菜单栏显示** — 以 `Cl 74%  Cx 55%` 的形式显示各服务商最紧张的剩余比例
- **两种窗口尺寸** — 拖动窗口会自动吸附到最近的小/大尺寸
  - 小尺寸:Claude/Codex 各一行摘要 + 使用量条
  - 大尺寸:每个窗口(5小时/每周/7天)的详细进度条、预计重置时间、刷新/隐藏
- **每15秒自动刷新**
- **本地通知** — 使用量降到0%时和重置时各通知一次
- **右键菜单** — 切换开机自启动、退出应用
- **记住位置和大小** — 关闭后下次在原位置重新打开
- **支持4种语言** — 한国语·English·日本语·中文,自动检测系统语言,或在托盘菜单中手动切换
- 无 Dock 图标 (`LSUIElement`)

### 数据来源

| 服务商 | 本地路径 | 备注 |
|---|---|---|
| Claude | `~/Library/Application Support/Claude/plan-usage-history.json` | 5小时·每周使用率。文件中没有重置时间戳,因此根据历史使用量骤降的位置进行估算,估算值会标注"大约" |
| Codex | `~/.codex/sessions/**/*.jsonl` | 最近一次的 `rate_limits` 记录。因为存在 `resets_at`,重置时间是精确的 |

两个文件都以只读方式打开,不会读取对话内容。

### 系统要求

- macOS 13 Ventura 或更高版本
- Swift 6 工具链 (`swift --version`)
- Xcode Command Line Tools

### 构建

```bash
./Scripts/build-app.sh
ditto ".build/potatoken hub.app" "/Applications/potatoken hub.app"
open "/Applications/potatoken hub.app"
```

构建脚本会完成发布版二进制编译、应用包组装、临时签名(ad-hoc)以及验证。

请以应用包的形式运行,而不是用 `swift run` —— 通知和开机自启动都需要稳定的
应用包标识符。

### 测试

```bash
swift test
```

### 项目结构

| 路径 | 作用 |
|---|---|
| `Sources/TokenGaugeCore` | 解析、校验、重置时间估算、通知调度等可测试逻辑 |
| `Sources/TokenGauge` | SwiftUI/AppKit 菜单栏外壳与系统集成 |
| `Tests/TokenGaugeCoreTests` | 重置估算逻辑的单元测试 |
| `Scripts/build-app.sh` | 发布构建、应用包组装、签名、验证 |

### 说明

本应用仅进行临时签名(ad-hoc),未经过 Apple 公证。默认前提是自行本地构建后
个人使用。

与 OpenAI、Anthropic 无关的个人项目。

[↑ 返回语言选择](#potatoken-hub)
