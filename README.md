# MenuTerm

**Multi-Terminal in macOS Menu Bar**

macOS 메뉴바(트레이)에 상주하면서 상시 실행 서버용 터미널 세션을 관리하고, 단발성 명령용 소형 터미널을 띄우는 앱입니다.
AppKit + [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) 으로 작성했으며 Xcode 없이 Swift Package Manager 만으로 빌드됩니다.

## 요구 사항

- macOS 14.4 이상 (메뉴 항목 부제목 API 사용)
- Swift 5.9 이상 툴체인 (`xcode-select --install` 로 설치되는 Command Line Tools 로 충분)

## 빌드와 실행

```bash
make app        # build/MenuTerm.app 생성
make run        # 빌드 후 실행
make install    # /Applications/MenuTerm.app 으로 복사
swift build     # 라이브러리 포함 디버그 빌드만
```

## 사용법

메뉴바의 터미널 아이콘을 누르면 메뉴가 열립니다.

```
 ⚡ Quick Command  │  ＋ 새 세션      ← 한 줄을 반으로 나눈 버튼 (왼쪽: 소형 터미널, 오른쪽: 등록 폼)
──────────────
● api-server                ▸         ← 세션 (부제목: 터미널 마지막 출력 줄)
   Listening on :8080                    ▸ 창 열기 / 시작 / 재시작 / 중지 / 편집 / 삭제
○ worker                    ▸
──────────────
MenuTerm 종료
```

전역 단축키 **⌘⇧T** 는 어디서든 Quick Command 패널을 토글합니다 (앞에 떠 있으면 숨김, 숨김 상태의 셸은 유지). 브라우저의 "닫은 탭 다시 열기"(⌘⇧T)보다 우선하니 주의하세요.

| 상태 | 의미 |
| --- | --- |
| ○ | 셸을 아직 띄우지 않음 |
| ● | 명령 실행 중 (셸에 자식 프로세스가 있음) |
| ◐ | 명령이 끝나 프롬프트에서 대기 중 |
| ✕ | 셸 자체가 종료됨 |

### 세션 동작 방식

- 세션마다 로그인 셸(`$SHELL -l -i`)을 PTY 위에 띄우고, 설정한 명령을 입력해 줍니다.
  `.zshrc` 에서 잡는 PATH(pyenv, nvm 등)가 그대로 적용되고, 플러그인 워커가 고아 프로세스로 남지 않습니다.
- 세션 창을 닫아도 숨기기만 하며 프로세스는 계속 실행됩니다.
- **중지**는 Ctrl-C 를 보내고, 3 초 뒤에도 살아 있으면 자식 프로세스에 SIGTERM 을 보냅니다.
- **재시작**은 중지 후 프롬프트로 돌아오면 명령을 다시 입력합니다.
- 앱 종료 시 모든 세션에 Ctrl-C 와 `exit` 를 보내고 최대 2.5 초 기다린 뒤 PTY 를 닫습니다.
- Quick Command 패널은 닫기 버튼으로 닫는 순간 셸이 종료됩니다. `exit` 를 입력해도 닫힙니다. ⌘⇧T 로 숨긴 경우에는 셸이 유지됩니다.

### 설정 파일

`~/.config/menuterm/sessions.json` (환경 변수 `MENUTERM_CONFIG_DIR` 로 디렉터리 변경 가능)

```json
[
  {
    "id": "6F1E2C9A-0000-0000-0000-000000000000",
    "name": "api-server",
    "command": "npm run dev",
    "directory": "~/work/api",
    "autostart": true,
    "interactive": true
  }
]
```

| 키 | 설명 |
| --- | --- |
| `name` | 메뉴와 창 제목에 쓰는 이름 |
| `command` | 셸에 입력할 명령 |
| `directory` | 작업 디렉터리 (`~` 사용 가능, 생략 시 홈) |
| `autostart` | 앱 시작 시 자동 실행 (기본 true) |
| `interactive` | `-i` 로 `.zshrc` 를 읽을지 여부 (기본 true). 끄면 `zsh -l` 만 사용 |

세션 안의 셸에는 `MENUTERM=1`, `MENUTERM_SESSION=<이름>` 환경 변수가 들어갑니다.

## 구조

```
Sources/MenuTerm/
├── main.swift                   앱 진입점 (accessory 정책)
├── AppDelegate.swift            상태 표시줄 아이콘, 메뉴 구성, 액션
├── SessionStore.swift           sessions.json 로드/저장
├── Session.swift                세션 상태 기계 (셸 실행, 명령 입력, 중지/재시작)
├── TerminalWindowController.swift  세션 창 (상태 바 + SwiftTerm 뷰)
├── QuickTerminalPanel.swift     단발성 명령용 플로팅 NSPanel
├── NewSessionDialog.swift       세션 추가/편집 폼
├── SplitMenuRow.swift           메뉴 맨 윗줄(Quick Command | 새 세션) 커스텀 뷰
├── HotKey.swift                 Carbon 전역 단축키 (⌘⇧T)
└── Shell.swift                  셸 경로, 환경 변수, 자식 프로세스 조회/시그널
Scripts/build-app.sh             .app 번들 생성 (Info.plist, LSUIElement, ad-hoc 서명)
```

## 알려진 제약

- Ad-hoc 서명이므로 다른 Mac 에 배포하려면 Developer ID 서명과 공증이 필요합니다.
- 로그인 시 자동 실행은 아직 없습니다. 시스템 설정 > 일반 > 로그인 항목에 수동으로 추가하면 됩니다.

## 라이선스

MIT. 터미널 에뮬레이션은 MIT 라이선스의 [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) 을 사용합니다.
