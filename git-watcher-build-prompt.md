# Git Watcher — 구현 프롬프트 (PLAN.md)

> 이 문서는 Claude Code 빌드 프롬프트 겸 PLAN.md다. 단계(Phase)를 순서대로 진행하고, 각 단계의 수용 기준(Acceptance)을 통과한 뒤 다음 단계로 넘어간다. 어떤 단계에서도 아래 **Hard Constraints**를 위반해서는 안 된다.

---

## 0. 개요

Git Watcher는 macOS 네이티브 앱으로, **여러 로컬 git 리포지토리의 변경 현황을 한 화면에서 실시간 모니터링**하는 읽기 전용 도구다.

- 사용자는 단독 개발자로, 동시에 10여 개의 로컬 리포를 작업하며 변경 상태를 추적해야 한다.
- 기존 git 클라이언트(GitKraken/Fork/Sourcetree 등)는 "한 리포, 한 워킹 디렉토리, 그 위에서 조작"이라는 전제로 설계되어 멀티 리포 수동 모니터링에 맞지 않고, git write 오퍼레이션이 가능해 실수 리스크가 있다.
- Git Watcher는 그 두 문제를 동시에 해결한다: **멀티 리포 라이브 모니터링** + **읽기 전용(조작 불가)**.
- 리포 중 하나(메인 서비스 `methii`)만 git worktree로 구성되어 있고, 나머지는 모두 독립 단일 리포다.

---

## 1. Hard Constraints (절대 위반 금지)

1. **읽기 전용(read-only).** git의 write/state-changing 명령을 절대 실행하지 않는다. 허용 서브커맨드 화이트리스트만 사용한다(§4). `checkout/commit/add/push/pull/fetch/merge/rebase/reset/stash/clean/gc/worktree add/remove/branch -d` 등은 코드 어디에도 존재하지 않아야 한다.
2. **로컬 전용.** 원격/네트워크/인증/자격증명을 일절 다루지 않는다.
3. **명령 실행은 인자 배열로.** `Process`에 셸 문자열을 넘기지 말고 argument array(`["-C", path, "status", "--porcelain=v2"]`)로 실행한다. 경로/브랜치명을 셸 문자열에 보간하지 않는다(인젝션 방지).
4. **플랫폼.** macOS 전용, SwiftUI. 크로스플랫폼 추상화 도입 금지.

---

## 2. 기술 스택

- **SwiftUI** — 앱 셸, 대시보드, 커밋 그래프(네이티브 `Canvas`/`GraphicsContext`로 직접 렌더링).
- **WKWebView** (`NSViewRepresentable`로 래핑) — diff 뷰어. 웹 라이브러리(`diff2html` 또는 동급)로 렌더링. 네이티브 diff 재구현은 비용 대비 이득이 없어 의도적으로 웹뷰를 쓴다.
- **Git 접근** — 시스템 `git` 바이너리를 읽기 전용 plumbing 명령으로 셸아웃. 모든 호출에 `git -C <path>`를 사용해 cwd 의존을 없앤다.
- **FSEvents** — 라이브 변경 감지(`DispatchSource`/FSEvents API 직접 또는 얇은 래퍼).

---

## 3. 데이터 모델

핵심: **카드 타입을 두 개 만들지 않는다.** 모델을 하나로 통일한다.

```
Repo
 ├─ id / displayPath / displayName / (optional) subtitle
 └─ worktrees: [Worktree]   // 항상 ≥ 1

Worktree
 ├─ path           // 워킹 디렉토리 절대경로
 ├─ branch         // 현재 브랜치 (detached면 sha)
 ├─ isMainWorktree // git worktree list의 첫 항목 여부
 ├─ status         // clean / dirty(changedFiles, +ins/-del)
 └─ divergence?    // trunk 대비 ahead/behind (worktree가 여럿일 때만 계산)
```

- `git worktree list --porcelain`은 **어떤 리포에서든** 동작한다. 독립 리포는 worktree 1개를 리턴(→ 플랫 카드), `methii`는 3개를 리턴(→ 그룹 카드). 데이터 레이어에서 `methii`를 특별 분기하지 않는다. UI가 `worktrees.count`에 따라 자연스럽게 degrade된다.
- **감시·상태조회 단위는 Repo가 아니라 Worktree(워킹 디렉토리)다.** `methii`는 워킹 디렉토리 3개가 하나의 `.git` object DB를 공유한다. 워처와 `git status`는 worktree를 평탄화해서 순회한다.

---

## 4. Git 질의 레이어 (전부 읽기 전용)

허용 서브커맨드 화이트리스트: `log`, `status`, `show`, `diff`, `diff-tree`, `worktree list`, `for-each-ref`, `rev-list`, `rev-parse`, `cat-file`. 이 외의 호출은 레이어 진입점에서 거부(assert/throw)한다.

| 목적 | 명령 |
|---|---|
| worktree 열거 | `git -C <repo> worktree list --porcelain` |
| 워킹트리 상태(브랜치·dirty·변경파일) | `git -C <wt> status --porcelain=v2 --branch` |
| trunk 대비 divergence | `git -C <repo> rev-list --left-right --count <trunk>...<branch>` → `"<ahead> <behind>"` |
| 그래프 데이터 | `git -C <repo> log --all --date-order --pretty=format:'%H%x1f%P%x1f%an%x1f%aI%x1f%s'` |
| ref 매핑 | `git -C <repo> for-each-ref --format='%(objectname) %(refname:short) %(HEAD)'` |
| 커밋별 변경 파일 | `git -C <repo> diff-tree --no-commit-id --name-status -r <sha>` |
| 커밋 내 파일 diff | `git -C <repo> show <sha> -- <path>` |
| 워킹트리 파일 diff | `git -C <wt> diff HEAD -- <path>` |
| 히트맵용 일자별 커밋 | `git -C <repo> log --all --since='30 days ago' --pretty=%cd --date=short` (Swift에서 일자별 count 집계) |

- `--porcelain=v2 --branch`는 gitignore를 자동 적용하므로, dirty 판정에 node_modules·빌드 산출물이 끼지 않는다.
- 필드 구분자는 `%x1f`(US, 0x1F)를 써서 제목에 `|`가 들어가도 안전하게 파싱한다.

---

## 5. UX 구조 (3단)

### 5.1 Dashboard (첫 화면)
- **상단 히트맵**: 행 = 리포(또는 worktree), 열 = 날짜, 셀 강도 = 일자별 커밋 수. `Last 30 days / All time` 토글.
- **카드 그리드**: 등록된 리포마다 카드 1개. 카드 계층은 **"지금" 우선** — 누적 스탯이 아니라 라이브 워킹트리 상태가 맨 위.
  - 헤더: 폴더 아이콘 + 리포명 (+ 서브타이틀) / 우측: 현재 브랜치 pill + 상태 dot.
  - 라이브 상태(가장 크게): `N files changed · +ins −del` 또는 `clean`.
  - 보조 스탯(muted): `총 commits · last commit Nm ago`.
  - worktree가 N>1이면: 각 worktree 서브로우(브랜치 + 상태 + `X↑ Y↓ vs <trunk>`). N==1이면 서브로우·펼침 UI 없음(플랫).
  - (선택) 변경 분포 바: 모노레포일 때 "어느 패키지가 변경됐나" 스택 바.
  - 스파크라인: 일자별 커밋 추이. 데이터 없으면 `No recent activity`.
  - 하단: 플래그 pill(예: `web: 3 uncommitted`) + `Open graph →`.

### 5.2 Repo Drill-down (그래프)
- 카드 클릭 → GitKraken 스타일 커밋 그래프(네이티브 렌더). worktree가 여럿이어도 `.git`을 공유하므로 `--all`로 한 그래프에 통합되고, 각 worktree HEAD는 마커로 표시.

### 5.3 Commit Detail
- 그래프에서 커밋 선택 → 커밋 정보 + 변경 파일 목록.
- 파일 클릭 → diff 뷰(웹뷰). 같은 diff 뷰가 두 맥락을 재사용: 커밋 diff(`show <sha>`)와 대시보드 워킹트리 diff(`diff HEAD`).

### 5.4 비주얼 언어
- Baden 대시보드의 카드 언어를 따른다(카드/히트맵/스파크라인/스택바/플래그 pill).
- 색 의미 매핑: **clean = green, dirty = amber(빨강 아님 — dirty는 에러가 아니라 정상 상태), diverged/behind = blue/indigo**. 강조 accent는 indigo 계열(Baden과 통일). (선택) 폰트는 Baden과 맞추려면 Pretendard.
- 화면에 표시되는 숫자는 모두 반올림/정수화한다.

---

## 6. 구현 단계 (Phases)

### Phase 1 — Dashboard MVP (여기서 시작)
읽기 전용 git 러너(화이트리스트 강제) → 리포 등록(폴더 피커) + 목록 영속화(UserDefaults/SwiftData/JSON) → worktree 평탄화 순회 → 각 worktree `status --porcelain=v2 --branch` → 카드 렌더 → FSEvents 라이브 갱신.
- **Acceptance**: (1) 폴더를 추가하면 카드가 뜬다. (2) 외부에서 파일을 수정/커밋하면 **수동 새로고침 없이** 해당 카드가 갱신된다. (3) `methii`는 worktree 3개가 서브로우로, 독립 리포는 플랫 카드로 나온다. (4) node_modules 등 ignored 변경으로 이벤트 폭주가 없다(디바운스 + status). (5) write 명령이 코드에 전무하다.

### Phase 2 — 커밋 활동 히트맵
일자별 커밋 수 집계 → 상단 히트맵 + `Last 30 days / All time` 토글.
- **Acceptance**: 리포별 행이 강도 셀로 채워지고 토글이 동작한다.

### Phase 3 — 커밋 그래프 (네이티브)
`log --all` + `for-each-ref` 파싱 → 레인 배치 알고리즘(커밋을 topo/date 순으로 훑으며 활성 레인 관리) → `Canvas`로 노드 + 엣지 + ref/worktree 마커 렌더. 고정 row-height로 hit-test.
- **Acceptance**: 그래프가 GitKraken처럼 읽히고, worktree HEAD가 마커로 표시되며, 커밋 클릭이 선택으로 잡힌다. (대형 리포 가상화는 후순위.)

### Phase 4 — 커밋 상세 + diff (웹뷰 브릿지)
커밋 선택 → `diff-tree --name-status`로 파일 목록 → 파일 클릭 → `show <sha> -- <path>` 결과를 **웜 웹뷰 인스턴스**에 JS로 주입해 `diff2html` 렌더.
- **Acceptance**: 파일 전환이 흰 플래시/재초기화 없이 빠르게 갱신된다. 대시보드의 워킹트리 diff(`diff HEAD`)도 같은 웹뷰로 표시된다.

### Phase 5 — Polish
divergence 플래그(`rev-list --left-right --count`), 스파크라인, (모노레포) 패키지별 변경 분포 바, 키보드 내비, 빈/에러 상태.

---

## 7. 엔지니어링 가이드 / 함정

- **FSEvents**: 커밋·브랜치 변화는 `.git`(refs/HEAD/logs/HEAD)을 직접 감시하면 싸다. 워킹트리 dirty는 워킹 디렉토리를 raw로 감시하면 node_modules·빌드 산출물 때문에 이벤트 폭풍이 나므로, FSEvents를 300~500ms 디바운스 트리거로만 쓰고 실제 판정은 `git status`(gitignore 적용)로 한다. worktree별 코얼레싱 필수.
- **웹뷰 브릿지는 얇게**: 파일마다 새 WKWebView 금지. 인스턴스 하나를 띄워두고 Swift→JS로 unified diff 텍스트만 주입. 웹뷰가 직접 fetch하지 않는다.
- **네이티브 그래프**: 고정 row-height로 click→commit 매핑을 단순화. 대형 그래프는 가시 영역만 그리는 가상화를 나중에 추가.
- **통합 그래프**: `methii`는 `.git` 공유 + `--all`로 세 worktree가 자동 통합된다(별도 머지 로직 불필요).
- **숫자**: 모든 표시 숫자 반올림/정수화.

---

## 8. Out of Scope (명시적 비범위)

git write 오퍼레이션 전부 / 원격·인증·push·pull·fetch / 머지·충돌 해결 / 스테이징·커밋 작성 / 크로스플랫폼 / 멀티 유저·협업. 이 중 무엇도 "편의상" 추가하지 않는다. 스코프를 좁힌 것이 이 도구의 강점이다.
