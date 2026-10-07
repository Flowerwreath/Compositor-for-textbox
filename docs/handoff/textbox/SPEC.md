# 텍스트 상자 버그 수정 인수인계 사양서

작성: 2026-10-07 · 이전 세션: `dragbar-error-fix-cd33f1`

다음 세션은 이 문서부터 읽으세요. **검증됨**은 이전 세션에서 코드를 실행해 확인한 내용이고, **가설**은 아직 확인하지 않은 추정입니다.

---

## 0. 현재 상태

| 항목 | 값 |
|---|---|
| 작업 디렉터리(worktree) | `/Users/shinminwoo/Compositor-for-textbox/.claude/worktrees/dragbar-error-fix-cd33f1` |
| 브랜치 | `claude/dragbar-error-fix-cd33f1` |
| 브랜치 HEAD | `6cabd51` "Keep a short leading's first line inside its text box" (main `11d8d7a`에서 fast-forward) |
| `6cabd51` 상태 | `claude/new-session-fvzitx` 브랜치의 커밋. origin에 push됨. **main에는 아직 병합되지 않음** |
| 커밋 안 된 변경 | `Compositor/Rendering/InlineTextEditor.swift`, `CompositorTests/TypeToolTests.swift` (IME 수정, §3) |
| 이 문서와 스크린샷 | `docs/handoff/textbox/` (git에 추가하지 않은 상태) |
| `/Applications/Compositor.app` | 이 worktree의 Release 빌드(`6cabd51` + 커밋 안 된 IME 수정). 버전 문자열은 1.4.5 |
| 이전 설치본 백업 | `~/.Trash/Compositor-6cabd51.app` (`6cabd51` 빌드). 공식 1.4.5 빌드도 휴지통에 있음 |

> 사용자의 스크린샷은 `/Applications`에 설치된 빌드에서 찍은 것입니다. 1~3번은 `6cabd51` 빌드, 4번도 같은 빌드에서 찍었습니다. main 기준 코드가 아닙니다.

---

## 1. 사용자 작업 규칙

- 답은 **해요체**로 하세요. 사용자가 하오체로 써도 따라 하지 마세요.
- 사용자가 "기다려"라고 하면 **분석하지 말고** 받아 적기만 하세요. 사용자가 시작하라고 할 때까지 코드를 읽지 마세요.
- 사용자가 "이것만"이라고 범위를 정하면, 범위 밖에서 찾은 문제는 고치지 말고 목록에만 추가하세요.
- 커밋과 push는 사용자가 요청할 때만 하세요.
- 저장소 탐색에는 codedb 도구나 `git grep`을 쓰세요. hook이 Bash에서 `grep`, `cat` 등을 막습니다. `git grep`은 동작합니다.

---

## 2. 빌드, 테스트, 설치 명령

```bash
# 단위 테스트(전체)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Compositor.xcodeproj -scheme Compositor -destination 'platform=macOS' test -only-testing:CompositorTests CODE_SIGN_IDENTITY=-

# 특정 스위트나 케이스
... -only-testing:CompositorTests/TypeToolTests
... "-only-testing:CompositorTests/TypeToolTests/textBeingComposedShowsOnTheCanvas()"

# 실패 메시지 꺼내기: 로그에는 실패 내용이 없음. xcresult에서 읽어야 함
xcrun xcresulttool get test-results tests --path <로그 마지막의 .xcresult 경로>

# 로컬 Release 빌드(앱 설치용). hardened runtime을 끄지 않으면 ad-hoc 서명 앱이 Sparkle 로드에서 죽음
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Compositor.xcodeproj -scheme Compositor -configuration Release -destination 'platform=macOS' -derivedDataPath <scratch>/dd build CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO
# 결과물: <scratch>/dd/Build/Products/Release/Compositor.app
# 설치: 기존 앱을 ~/.Trash로 옮긴 뒤 ditto로 복사. 실행 중인 앱은 강제로 끄지 말고 사용자에게 ⌘Q 후 다시 열어 달라고 요청
```

알려진 로컬 전용 실패:
- `SliderSnapTests.clickingTheTrackSnapsBeforeNativeTrackingBegins`: 항상 실패. 이번 작업과 무관.
- `CursorTests.leavingTheCanvasRestoresTheArrowWithEveryTool`: 전체 실행에서는 실패하고 단독 실행에서는 통과. 여러 테스트가 공유하는 NSCursor 상태 때문으로 보임.

---

## 3. 완료: #3 IME 조합 중인 글자가 보이지 않음 (커밋 안 됨)

**증상:** 한자, 히라가나, 가타카나를 입력할 때 Enter로 확정하기 전까지 캔버스에 글자가 보이지 않았습니다. 조합 밑줄만 보였습니다. 스크린샷: `4-ime-invisible.png`.

**원인(검증됨):**
- 편집기(`CanvasTextView`)의 글자는 투명하고, 캔버스는 `session.textDraft.style.content`만 그립니다(`EditorCanvas.swift:30` `draftText`).
- draft 내용은 `textDidChange`에서만 갱신됩니다.
- `NSTextView.setMarkedText`는 `shouldChangeTextIn`만 호출하고 `textDidChange`는 보내지 않습니다. 확정(`insertText`)할 때만 보냅니다. 스크래치 스크립트로 확인했습니다.

**수정:**
- `CanvasTextView.setMarkedText`를 override해서 `super`를 호출한 뒤 `editor?.takeText()`를 부릅니다(`InlineTextEditor.swift:150`).
- 기존 `textDidChange` 본문을 `takeText()`로 옮기고, `textDidChange`는 `takeText()`만 호출합니다(`InlineTextEditor.swift:324-327`).
- 색과 폰트 run은 기존처럼 `shouldChangeTextIn`의 `pendingStyle`이 따라갑니다.

**테스트:** `TypeToolTests.textBeingComposedShowsOnTheCanvas` (`TypeToolTests.swift:354`)
- `setMarkedText("まみ")` 후 draft가 `"abcまみ"`이고, 캔버스 스냅샷이 바뀌는지 확인합니다.
- 조합 취소(`setMarkedText("")`) 후 draft가 `"abc"`인지 확인합니다.
- `insertText("真美")`로 확정한 뒤 draft가 `"abc真美"`인지 확인합니다.
- 수정 전에는 같은 이유로 실패했습니다(draft가 `"abc"`이고 스냅샷이 같음).

**실행 기록:**
- 새 테스트(수정 전): 실패. 1회 실행.
- `TypeToolTests`(수정 후): 28개 통과, 0개 실패. 1회 실행.
- 전체 `CompositorTests`: 594개 통과, 2개 실패(§2의 두 건). 1회 실행.
- `CursorTests` 단독: 통과. 1회 실행.
- Release 빌드: 성공. 서명 검증 통과. 설치된 실행 파일이 빌드 결과물과 같음을 `cmp`로 확인.

**확인 안 된 것:** 실제 일본어/중국어 입력기로 앱에서 직접 입력해 보지는 않았습니다. 사용자의 확인을 기다리는 중입니다.

---

## 4. 남은 작업

### #1 선택 하이라이트가 leading을 따라감

**요구사항(사용자 표현):** 하이라이트는 **폰트 크기에 맞춰** 글자를 덮어야 합니다. 지금은 leading 값을 따라가서 글자가 아닌 엉뚱한 곳을 칠합니다.

**완료 기준:**
- leading 값과 상관없이, 각 줄의 하이라이트가 그 줄 글자의 ascender 위부터 descender 아래까지를 덮습니다. leading이 짧아 줄이 겹칠 때도, 길 때도, Auto(120%)일 때도 같습니다.
- 겹치는 줄의 하이라이트가 겹쳐도 더 진하게 칠해지지 않습니다. `6cabd51`은 하나의 path로 칠하도록 의도했습니다.
- 자동 테스트가 있습니다. 예를 들어 편집기를 `cacheDisplay`로 렌더링해서 하이라이트 픽셀 행이 글자 잉크 행과 일치하는지 확인합니다. 기존 `inkRows` 헬퍼(`TypeToolTests.swift`)를 활용할 수 있습니다.

**스크린샷:**
- `1-highlight-short-leading.png`: 200px, leading 10. 두 줄이 거의 겹쳐 있고, 하이라이트는 글자 아래쪽의 얇은 띠입니다. 두 줄의 띠가 겹치는 부분(왼쪽에서 "textbox" 너비까지)이 더 진합니다.
- `2-highlight-offset.png`: 툴바의 Leading 칸은 10인데, 줄 간격은 겹치지 않은 정상 간격처럼 보입니다. 둘째 줄 하이라이트가 글자보다 위로 어긋나 있습니다. **원인을 모릅니다.** 입력 칸 값이 아직 적용되지 않은 상태일 수 있습니다. 재현해서 확인해야 합니다.

**검증된 사실:**
- TextKit 1에서 `minimumLineHeight == maximumLineHeight == leading`일 때 baseline은 항상 **줄 조각(line fragment) 아래에서 descent만큼 위**에 놓입니다. Helvetica 200px로 측정한 값입니다(ascender ≈154, descent ≈46).

  | leading | fragment y / h | baseline | 글자 위 | 글자 아래 |
  |---|---|---|---|---|
  | 10 | 0 / 10 | −36 | −190 | 10 |
  | 200 | 0 / 200 | 154 | 0 | 200 |
  | 240 (Auto) | 0 / 240 | 194 | 40 | 240 |

  NSTextView의 기본 하이라이트는 fragment(높이 = leading)를 칠합니다. 그래서 하이라이트가 leading을 따라갑니다. 글자 영역은 `[fragment 아래 − (ascent + descent), fragment 아래]`입니다.
- `textView.textContainer?.replaceLayoutManager(SeeThroughSelectionLayout())`를 호출하면 TextKit 2 텍스트 뷰가 TextKit 1로 바뀌고, `textView.layoutManager`는 이 서브클래스가 됩니다. 따라서 "서브클래스가 쓰이지 않는다"는 원인은 배제됩니다.

**현재 코드(`6cabd51`):**
- `SeeThroughSelectionLayout`(`InlineTextEditor.swift:10`)이 `drawBackground`(`:18`)에서 하이라이트 사각형을 모아 하나의 path로 칠합니다.
- 각 사각형은 `coveringLetters`(`:55`)로 **위쪽만** 글자 꼭대기까지 늘립니다. 아래쪽은 fragment 아래 그대로입니다.
- `reach`(= `letterMetrics(...).overflow`, 즉 `max(0, ascent + descent − leading)`)가 0이면 기본 동작으로 돌아갑니다. 그래서 leading ≥ 글자 높이(Auto 포함)일 때는 하이라이트가 fragment 전체(글자 위 빈 공간 포함)를 칠합니다. "폰트 크기에 맞춘다"는 요구와 맞지 않습니다.
- leading 10에서는 계산상 글자를 덮어야 합니다. 그런데 스크린샷 1은 얇은 띠입니다. **왜 늘어나지 않았는지는 확인하지 못했습니다.** 하이라이트가 이 경로(`drawBackground` → `highlights`)를 거치지 않았을 가능성이 있습니다. 겹친 부분이 진하다는 점이 그 근거입니다. 먼저 재현 테스트로 실제로 어떤 경로를 타는지 확인하세요.

### #2 텍스트 커서(I-beam 막대)가 폰트 크기에 맞지 않음

**요구사항:** leading이 작아도 커서는 폰트 크기에 맞는 높이로, 글자 위치에 맞게 그려져야 합니다. 지금은 높이와 위치가 제멋대로입니다.

**완료 기준:**
- 커서 높이와 위치가 그 줄 글자의 ascender부터 descender까지에 맞습니다. 빈 줄이면 typing font로 계산합니다.
- leading 10, 200, Auto에서 같은 규칙을 따릅니다.
- 자동 테스트가 있습니다.

**스크린샷:**
- `3-caret-short-leading.png`: 커서가 짧고, 첫 줄 baseline보다 아래에 있습니다.
- `4-ime-invisible.png`: 둘째 줄의 커서가 매우 길게(글자 높이를 훨씬 넘게) 그려져 있습니다.

**현재 코드:** `CanvasTextView.drawInsertionPoint`(`InlineTextEditor.swift:92`)가 `coveringLetters`로 커서를 위로 늘립니다.

**가설(미검증):** macOS 14부터 NSTextView는 커서를 `NSTextInsertionIndicator` 서브뷰로 따로 그립니다. 그래서 `drawInsertionPoint` override가 호출되지 않고, 시스템 커서가 fragment 높이(= leading)를 그대로 쓸 수 있습니다. 스크린샷에서 커서 길이가 leading에 비례하는 것과 맞습니다. 확인 방법은 편집 중에 `textView.subviews`에 `NSTextInsertionIndicator`가 있는지, 그리고 `drawInsertionPoint`가 호출되는지 확인하는 것입니다.

### #4 IME 변환 중 Esc가 텍스트 편집 전체를 취소함 (발견만 함)

- `CanvasTextView.keyDown`(`InlineTextEditor.swift:124`)이 `super.keyDown`, 즉 입력기보다 먼저 Esc(keyCode 53)를 가로채서 `session.cancelText()`를 호출합니다.
- 그래서 일본어 변환 중에 Esc로 변환만 취소하려 해도 텍스트 상자 편집 전체가 취소될 가능성이 큽니다. 실제 입력기로 확인하지는 않았습니다.
- 수정 후보: `if event.keyCode == 53, !hasMarkedText() { ... }`. 테스트 환경에서는 Esc가 `super.keyDown` → `cancelOperation:` → 자동완성 창으로 갈 수 있으니 테스트 설계에 주의하세요.
- 사용자가 "이것만" 하라고 해서 손대지 않았습니다. 진행하기 전에 사용자에게 확인하세요.

### #5 세로쓰기 모드 (기능 요청)

- 사용자가 "세로쓰기 모드도 없음"이라고 했습니다. 아직 설계는 없습니다.
- 새 기능이므로 구현 전에 범위를 사용자와 정해야 합니다. 정할 것: 일본식 세로쓰기인지, 줄 진행 방향, 영문 회전, 툴바 UI.
- 영향 범위(조사 전 추정):
  - `LayerTextStyle`에 필드를 추가해야 합니다(Codable 기본값 필요, 기존 문서 호환).
  - `textAttributes`, `textImage`, `textBoxSize`를 고쳐야 합니다(`TypeTool.swift:400`, `:478`, `:449`).
  - 편집기(`NSTextView.setLayoutOrientation(.vertical)`)를 바꿔야 합니다.
  - PSD 텍스트 import/export(`PSDText.swift`)도 영향을 받습니다.

---

## 5. 우선순위 제안

1. 사용자가 #3을 실제 앱에서 확인 → 괜찮으면 커밋할지 묻기
2. #1과 #2: 같은 원인(fragment 높이 = leading)을 공유하므로 같이 다루는 게 좋습니다. 다만 커서는 별도 경로(`NSTextInsertionIndicator`)일 수 있습니다.
3. #4: 한 줄짜리 수정. 사용자 확인 후 진행
4. #5: 설계 논의 후 진행

## 6. 스크린샷

| 파일 | 내용 |
|---|---|
| `1-highlight-short-leading.png` | #1, leading 10에서 하이라이트가 얇은 띠로 표시됨 |
| `2-highlight-offset.png` | #1, 하이라이트가 글자보다 위로 어긋남 |
| `3-caret-short-leading.png` | #2, 커서가 짧고 위치가 맞지 않음 |
| `4-ime-invisible.png` | #3 재현(수정 전), #2 긴 커서도 보임 |
