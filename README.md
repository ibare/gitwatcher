# Git Watcher

여러 로컬 git 리포지토리의 변경 현황을 **한 화면에서 실시간으로 모니터링**하는 macOS 네이티브 앱입니다. 기존 git 클라이언트가 "한 리포 · 한 워킹 디렉토리 · 그 위에서 조작"을 전제로 설계된 것과 달리, Git Watcher는 **멀티 리포 라이브 모니터링**과 **읽기 전용(조작 불가)** 두 가지에 집중합니다.

> 동시에 여러 리포를 오가며 작업하는 단독 개발자가, 각 리포의 상태를 한눈에 추적하고 실수로 git을 건드릴 위험 없이 들여다보기 위한 도구입니다.

## 특징

- **멀티 리포 대시보드** — 등록한 리포마다 카드 하나. 라이브 워킹트리 상태가 맨 위에 오는 "지금 우선" 레이아웃.
- **읽기 전용(read-only)** — git의 write/state-changing 명령을 절대 실행하지 않습니다. 허용된 읽기 전용 plumbing 서브커맨드만 화이트리스트로 사용하며, write 커맨드는 타입 레벨에서 표현 자체가 불가능합니다.
- **로컬 전용** — 원격/네트워크/인증/자격증명을 일절 다루지 않습니다. (리모트 브랜치 위치는 로컬 `refs/remotes`만 읽어 표시하며, fetch/pull은 하지 않습니다.)
- **라이브 갱신** — FSEvents로 변경을 감지하고 디바운스 후 `git status`(gitignore 적용)로 판정해, 외부에서 파일을 수정·커밋하면 수동 새로고침 없이 카드가 갱신됩니다.
- **worktree 지원** — `git worktree`로 구성된 리포는 worktree들을 평탄화해 한 카드 안에 서브로우로 보여주고, 커밋 그래프는 `--all`로 통합합니다.

## 주요 기능

### 대시보드
- 리포 카드: 현재 브랜치 · 라이브 상태(`N files changed · +ins −del` / `clean`) · 총 커밋 수 · 마지막 커밋 시각 · 최근 커밋 10개 목록 · worktree 서브로우(divergence 포함).
- 정렬: `Recent`(최근 변경) / `Commits`(많은 커밋) / `Stale`(오래 방치) / `Name` / `Changed`(변경 우선). 선택값은 영속화됩니다.

### 커밋 그래프 (네이티브 Canvas)
- GitKraken 스타일 3컬럼 레이아웃: `BRANCH / TAG` · `GRAPH` · `COMMIT MESSAGE`.
- 브랜치 · 태그 · 리모트 브랜치 · worktree HEAD를 라벨로, 라벨→노드 연결선으로 소속 표시.
- 미커밋 변경은 그래프 최상단에 **점선 WIP 노드**로 표시.
- 키보드(↑/↓) 내비게이션.

### 커밋 상세 / diff
- 우측 패널: 커밋 정보(제목 · 본문 · author · 날짜 · parent · 변경 요약) + 변경 파일 목록.
- 파일 선택 시 좌측이 diff 오버레이로 전환. **Diff / File 뷰 전환**(전체 코드에서 변경 줄만 강조), 파일별 **변경 히스토리** 추적.

### 파일 탐색기
- 좌측 lazy 디스크 트리 + 우측 코드 뷰어.
- highlight.js 기반 신택스 하이라이트(atom-one-dark) + 라인 넘버. 이미지/바이너리/대용량 가드.

## 기술 스택

- **SwiftUI** — 앱 셸, 대시보드, 커밋 그래프(`Canvas` 직접 렌더링)
- **WKWebView** — diff/코드 뷰어. highlight.js를 번들에 내장(런타임 네트워크 없음)
- **시스템 `git`** — 읽기 전용 plumbing 명령으로 셸아웃. 모든 호출에 `git -C <path>` 사용, 인자는 배열로만 전달(셸 인젝션 방지)
- **FSEvents** — 라이브 변경 감지

## 빌드 / 실행

- macOS + **Xcode**(26 이상) 필요. 시스템에 `git`이 설치되어 있어야 합니다.
- `GitWatcher.xcodeproj`를 Xcode에서 열고 실행하면 됩니다.
- 명령줄 빌드:
  ```sh
  xcodebuild -project GitWatcher.xcodeproj -scheme GitWatcher -configuration Debug -destination 'platform=macOS' build
  ```
- App Sandbox는 꺼져 있습니다 — 임의의 로컬 리포에 `git`을 셸아웃하는 것이 샌드박스와 호환되지 않기 때문이며, 로컬 전용 · 읽기 전용 개인 도구라는 성격에 따른 결정입니다.

첫 실행 시 툴바의 **+** 버튼으로 로컬 git 리포 폴더를 추가하면 카드가 나타납니다.

## 범위 밖 (의도적 비범위)

git write 오퍼레이션 전부 · 원격/인증/push/pull/fetch · 머지/충돌 해결 · 스테이징/커밋 작성 · 크로스플랫폼 · 멀티 유저. 스코프를 좁힌 것이 이 도구의 강점입니다.
