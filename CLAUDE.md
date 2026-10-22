# MenuTerm 프로젝트 메모

macOS 메뉴바 상주형 터미널 세션 관리자. AppKit + SwiftTerm, SwiftPM 전용(Xcode 프로젝트 없음).
사용법과 구조는 README.md 참고. 설계 문서: https://claude.ai/artifact/5eCYriPGhW8QKM1nJCLgpU

## 빌드/검증 명령

```bash
swift build                              # 디버그 (약 3초, 최초는 SwiftTerm 컴파일로 1~2분)
Scripts/build-app.sh release             # build/MenuTerm.app
MENUTERM_CONFIG_DIR=/tmp/mt-test .build/out/Products/Debug/MenuTerm   # 격리된 설정으로 실행
```

검증 절차(수동): 테스트 설정 디렉터리에 `python3 -m http.server 48765` 세션을 넣고 앱 실행 →
`curl 127.0.0.1:48765` 200 확인 → `kill -TERM <app pid>` → `pgrep -lf "http.server 48765"` 가 비어야 한다.

## 설계상 주의점 (실측으로 확인한 사실)

- 세션 명령은 `zsh -lic "<cmd>"` 가 아니라 **인터랙티브 셸(`zsh -l -i`)을 띄운 뒤 명령을 PTY에 입력**한다.
  이 사용자의 `.zshrc`(oh-my-zsh + p10k + autosuggestions) 환경에서 `-c` 모드는 정상 종료 뒤에도
  플러그인 워커 zsh 프로세스 2개를 ppid 1 로 남긴다. 인터랙티브 셸 + `exit` 는 깨끗하게 끝난다.
- `zsh -l`(비인터랙티브)만 쓰면 pyenv/rbenv/jenv/deno PATH 가 빠진다. 그래서 `interactive` 기본값은 true.
- 실행 중 판단은 `proc_listchildpids(shellPid)` 로 셸의 자식 유무를 1초마다 확인한다.
- `NSMenuItem.subtitle` 은 macOS 14.4+ 이므로 Package.swift 의 platforms 가 `"14.4"` 다.
- `SessionConfig` 는 키가 없으면 기본값을 쓰는 커스텀 `init(from:)` 을 가진다. 필드를 추가하면 거기에도 추가할 것.
- `NSHomeDirectory()` 는 HOME 환경 변수를 따르지 않는다. 테스트 격리는 `MENUTERM_CONFIG_DIR` 로 한다.

- 액세서리 앱은 메인 메뉴가 없어서 ⌘C/⌘V/⌘A 가 first responder 에 전달되지 않는다. `installMainMenu()` 의
  Edit 메뉴가 그 역할을 한다. 지우면 입력 폼과 터미널 뷰에서 복붙이 다시 막힌다.
- 상태 메뉴 항목의 keyEquivalent 는 메뉴가 열려 있을 때만 동작해서 쓰지 않는다. 전역 단축키는 Carbon
  `RegisterEventHotKey`(`HotKey.swift`)로 등록한다. 접근성 권한이 필요 없다.
- 서브메뉴가 달린 NSMenuItem 은 클릭으로 action 이 실행되지 않으므로 세션 서브메뉴 첫 항목이 "창 열기"다.

## 미완/후속 아이디어

- 로그인 항목 자동 등록(SMAppService), 세션별 색상/테마, 세션 순서 변경, 출력 검색.
- 메뉴 열림 상태에서 마지막 줄 실시간 갱신(현재는 메뉴가 열릴 때마다 갱신).
