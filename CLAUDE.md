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
- 존재하지 않는 `currentDirectory` 로 `startProcess` 하면 셸이 조용히 깨진다(명령 미실행, 자식 없음). `Session.start()` 가
  폴더 유무를 확인해 없으면 홈으로 대체하고 터미널에 안내를 찍는다.

- 액세서리 앱은 메인 메뉴가 없어서 ⌘C/⌘V/⌘A 가 first responder 에 전달되지 않는다. `installMainMenu()` 의
  Edit 메뉴가 그 역할을 한다. 지우면 입력 폼과 터미널 뷰에서 복붙이 다시 막힌다.
- 상태 메뉴 항목의 keyEquivalent 는 메뉴가 열려 있을 때만 동작해서 쓰지 않는다. 전역 단축키는 Carbon
  `RegisterEventHotKey`(`HotKey.swift`)로 등록한다. 접근성 권한이 필요 없다.
- 서브메뉴가 달린 NSMenuItem 은 클릭으로 action 이 실행되지 않는다. 세션 행은 `SessionMenuRow`(커스텀 뷰)라서
  뷰의 mouseUp 으로 창을 열고, 서브메뉴 첫 항목 "창 열기"는 그대로 둔다. 커스텀 뷰 항목은 AppKit 이 ▸ 화살표와
  하이라이트를 그려 주지 않으므로 뷰가 직접 그린다.
- 세션 폴링 타이머는 `RunLoop.main.add(_, forMode: .common)` 이다. `Timer.scheduledTimer` 는 메뉴가 열린 동안
  (메뉴 추적 런루프 모드) 멈춰서 CPU/MEM·마지막 줄 실시간 갱신이 안 된다.
- CPU/메모리는 `proc_pid_rusage(RUSAGE_INFO_V4)` 로 셸 + 자손 전체를 합산한다. `ri_user_time`/`ri_system_time` 은
  mach absolute time 단위라 `mach_timebase_info` 로 ns 변환해야 한다(안 하면 Apple Silicon 에서 약 42배 과장).
  메모리는 `ri_phys_footprint`(활성 상태 보기의 "메모리" 열과 같은 값). 실측: 바쁜 루프 96%, 300MB 할당 313MB.
- `MENUTERM_DEBUG_STATS=1` 로 띄우면 샘플 값이 NSLog 로 나온다. 메뉴를 열지 않고 수치를 검증할 때 쓴다.
- 앱 아이콘은 그림 파일 없이 `AppIcon.swift` 가 그린다. `build-app.sh` 가 빌드된 바이너리를
  `--write-iconset` 으로 실행해 PNG 를 뽑고 `iconutil` 로 `AppIcon.icns` 를 만든다. 실행 중에도
  `NSApp.applicationIconImage` 에 같은 그림을 넣어 NSAlert 아이콘을 덮는다.
- 자주 쓰는 세션(`favorite`)은 한 개만 허용한다. `AppDelegate.commit(_:into:)` 이 저장 시 다른 세션의 값을 끈다.
  복제 실행(`spawnFavorite`)은 `디렉터리-N` 중 폴더도 없고 다른 세션도 안 쓰는 가장 작은 N 을 고른다.
- 터미널에 보조 접근 권한이 없어 AppleScript 로 메뉴를 열어 스크린샷을 찍는 검증은 실패한다. 메뉴 모양은 사용자가 확인한다.

## 이력

- 2026-10-22 1·2차: 초기 구현, 복붙 수정, 서브메뉴, 반반 분할 윗줄, ⌘⇧T. GitHub 공개(ic4r/menuterm).
- 2026-10-23: 세션 행 두툼하게 + 마지막 출력 3줄, 윗줄·자주 쓰는 세션을 버튼형 행(`SplitMenuRow`)으로, 단축키 ⌃⇧⌘T 로 변경
  (⌘⇧T 가 브라우저 "닫은 탭 다시 열기"와 겹쳐서).
- 2026-10-22 3차: 앱 아이콘, 세션 폼 재배치 + `createDirectory`, 자주 쓰는 세션 복제, 세션별 CPU/MEM 과 메모리 순위 바탕색,
  메뉴 열린 상태 실시간 갱신. 작업 디렉터리를 `~/tmp/cli-server` 에서 `~/tmp/menuterm` 으로 옮김.
- 커밋에는 `Co-Authored-By: Claude` 꼬리표를 붙이지 않는다(사용자 결정).

## 미완/후속 아이디어

- 로그인 항목 자동 등록(SMAppService), 세션별 색상/테마, 세션 순서 변경, 출력 검색.
- 복제 세션의 디렉터리 이름 규칙(날짜, 브랜치명 등)과 git worktree 연동.
