# UI 한글화 인수인계

작성: 2026-10-08 · 이전 세션: 텍스트 상자 회전과 후속 작업(fireworm worktree)

다음 세션은 이 문서부터 읽으세요. **검증됨**은 이전 세션에서 코드나 명령으로 확인한 내용이에요. **가설**은 아직 확인하지 않은 추정이에요.

---

## 0. 현재 상태 (검증됨)

| 항목 | 값 |
|---|---|
| 작업 디렉터리(worktree) | `/Users/shinminwoo/orca/workspaces/Compositor-for-textbox/fireworm` |
| 브랜치 | `Flowerwreath/fix-textbox-spec-issues` (push 안 함) |
| 기준 | `d21ff29` (upstream Compositor 1.4.7을 병합한 커밋) |
| 커밋 안 된 변경 | 없음 |
| `/Applications/Compositor.app` | `8488937`의 로컬 Release 빌드(ad-hoc 서명). 버전 문자열은 1.4.7 |
| 이전 설치본 | `~/.Trash/Compositor-followups.app`, `~/.Trash/Compositor-rotation.app`, `~/.Trash/Compositor-before-rotation.app` |

이전 세션에서 커밋한 것(오래된 순서):

1. `e0aedf0` 모서리 바깥 드래그로 텍스트 상자 회전. 새 텍스트 레이어가 회전을 유지
2. `e341430` Type 도구 바의 각도 칸. 드래그·각도 칸·반전이 `TextDraft.place` 하나로 배치를 바꿈
3. `d03dc92` 방향 버튼이 현재 방향을 보여 주고 누를 때마다 전환
4. `79cf419` ㄱ자 회전 커서(`TextRotationCursor`). 드래그는 가장 짧은 각도로 저장
5. `f4f4a8e` 텍스트 우클릭 Flip Horizontal / Flip Vertical
6. `8488937` 방향 버튼 라벨이 `ABC`/`가나다` 두 줄(세로는 ABC 열이 왼쪽)

사용자가 실제 앱에서 1의 동작 6가지를 확인했어요(전부 통과). 2–6은 설치까지 했고, 6의 라벨은 사용자가 보고 "이제 좀 낫네"라고 했어요.

---

## 1. 사용자 작업 규칙

- 답은 **해요체**로 하세요. 사용자가 하오체로 써도 따라 하지 마세요.
- 사용자가 "기다려"라고 하면 분석하지 말고 받아 적기만 하세요.
- 사용자가 "이것만"이라고 범위를 정하면, 범위 밖에서 찾은 문제는 고치지 말고 목록에만 추가하세요.
- **커밋과 push는 사용자가 요청할 때만** 하세요.
- 이 저장소는 `robbietilton/Compositor`의 fork예요. GitHub에 쓰는 작업은 `Flowerwreath/Compositor-for-textbox`에만, `--repo`를 명시해서 하세요. upstream에는 PR을 만들지 마세요.
- 새 기능은 설계를 먼저 승인받고 구현하세요. 사용자가 에이전트 사용 방식을 정해 주기도 해요(이전 세션: 처음에는 Haiku/Sonnet, 후속 작업은 "Codex를 마구마구").
- 저장소 탐색에는 codedb 도구나 `git grep`을 쓰세요. hook이 Bash의 `grep`, `cat`을 막을 수 있어요.

---

## 2. 빌드, 테스트, 설치 (검증됨)

```bash
# 단위 테스트 (전체, 약 5–8분)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Compositor.xcodeproj -scheme Compositor \
  -destination 'platform=macOS' -derivedDataPath <scratch>/dd test -only-testing:CompositorTests CODE_SIGN_IDENTITY=-

# 실패 메시지: 로그에는 없어요. xcresult에서 읽어요. xcresulttool에도 DEVELOPER_DIR이 필요해요
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun xcresulttool get test-results summary --path <.xcresult>

# 로컬 Release 빌드(설치용). hardened runtime을 끄지 않으면 ad-hoc 앱이 Sparkle 로드에서 죽어요
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Compositor.xcodeproj -scheme Compositor \
  -configuration Release -destination 'platform=macOS' -derivedDataPath <scratch>/dd build \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO
# 설치: 기존 앱을 ~/.Trash로 옮긴 뒤 ditto로 복사. 실행 중이면 강제로 끄지 말고 사용자에게 ⌘Q를 부탁해요
```

- 새 `-derivedDataPath`를 쓸 때는 `~/Library/Developer/Xcode/DerivedData/Compositor-*/SourcePackages`를 그 안에 복사해 두면 Sparkle clone을 건너뛰어요.
- **Codex(`codex:codex-rescue`)는 이 Mac에서 `xcodebuild`를 못 돌려요.** workspace-write 샌드박스가 캐시 쓰기를 막아요(exit 74). Codex가 코드를 바꾸면 테스트는 Claude 쪽 셸에서 돌려요. 읽기 전용 Codex는 scratchpad에 파일을 못 쓰니, 리뷰 결과는 답변으로 받아요.
- 알려진 로컬 전용 실패(새 실패로 세지 않음):
  - `SliderSnapTests.clickingTheTrackSnapsBeforeNativeTrackingBegins`: 항상 실패해요.
  - `TiledLayerTests.paintingAtTheLayersEdgeDoesNotChangeIt`: 창을 쓰는 테스트와 같이 돌 때만 실패해요.
  - `CursorTests.leavingTheCanvasRestoresTheArrowWithEveryTool`: 전체 실행에서 가끔 실패해요.
- 마지막 전체 실행(`8488937`의 바로 앞, 라벨 변경 전): 677개 중 675개 통과, 실패 2건은 위의 알려진 실패예요.

---

## 3. 다음 작업: UI 100% 한글화

사용자 표현: "이제 다음으로 해야할건 ui를 100% 한글화하는건데". 아직 설계는 없어요. 여러 파일과 빌드 설정을 바꾸는 큰 작업이라, brainstorming부터 시작해 사양서를 쓰는 경로가 맞아요.

### 3.1 사용자와 먼저 정할 것

1. **방식**
   - **A. String Catalog로 한국어 추가.** `Localizable.xcstrings`에 `ko`를 추가하고, 앱은 macOS 언어 설정을 따라요. 영어 원문은 그대로 둬요.
   - **B. 영어 문자열을 한국어로 직접 교체.**
   - **C. A + 앱 안에서 한국어 강제.** (예: `AppleLanguages` 기본값)
   - 판단 근거: 이 fork는 upstream을 주기적으로 병합해요(`d21ff29`가 upstream 1.4.7 병합). B는 upstream 병합 때마다 같은 줄에서 충돌이 나요. A나 C는 원문을 그대로 두니 충돌이 거의 없어요. **A나 C를 추천해요.**
2. **"100%"의 범위.** 메뉴 막대, 툴바, 시트, 도움말 툴팁(`.help`), 접근성 라벨, 알림·오류 문구(`LocalizedError`), 실행 취소 이름(`beginEdit("…")` → Edit 메뉴의 "Undo …"), 명령 팔레트 항목과 검색어(한국어로 검색할지, 영어 검색도 남길지), 단축키 목록, 기본 레이어 이름("Layer 1", "Text"), PSD 가져오기 안내 문구, Sparkle 업데이트 창(서드파티).
3. **용어집.** Photoshop 한국어판 용어를 따를지 정해요. 예: Layer=레이어, Leading=행간, Tracking=자간, Mask=마스크, Marquee=선택 윤곽.

### 3.2 현재 코드 상태 (검증됨)

- 지역화 파일이 없어요(`.xcstrings`, `.strings`, `.lproj` 없음). `developmentRegion = en`, `knownRegions = (en, Base)`(`project.pbxproj:196–201`).
- 빌드 설정에 `LOCALIZATION_PREFERS_STRING_CATALOGS = YES`, `STRING_CATALOG_GENERATE_SYMBOLS = YES`가 이미 있어요(`project.pbxproj:336`, `:342`, `:397`, `:402`).
- 문자열 분포(대략적인 `git grep` 개수, 정확한 목록은 아님):
  - SwiftUI 리터럴 UI 호출: `CompositorApp.swift` 83, `FilterSheet` 51, `LassoControls` 38, `BrushControls` 31, `CameraRawColorControls` 30, `TypeControls` 19, `CanvasSizeSheet` 19, `ContentView` 18 등 `Compositor/UI/` 아래 약 25개 파일
  - AppKit 제목·알림: `ProjectController` 14, `NativeLayerList` 11, `ProjectController+ExternalChanges` 4, `LiveLayerMask` 4
  - 실행 취소 이름 `beginEdit("…")`: 서로 다른 것 35개
  - `CommandPalette.swift` 리터럴 24개, `KeyboardShortcuts.swift` 54개
  - `LocalizedError`: `ContentFill`, `ImageTrim`, `MagicWand`, `ObjectSelection` 등
- **주의: 화면에 rawValue를 그대로 보여 주는 곳이 많아요.** `ForEach(X.allCases) { Text($0.rawValue) }` 패턴이에요(`BrushControls.swift:12,19,26`, `CameraRawColorControls.swift:16,23,275,283,436`, `CameraRawControls.swift:132,190`). `TransformInspector`의 Sampling(`LayerSampling`)도 같아요. 이 rawValue 중 일부는 **프로젝트 파일에 저장되는 Codable 값**이에요(예: `LayerSampling` "High quality", `TextAlignment`, `TextOrientation`). rawValue를 번역하면 파일 형식이 깨져요. 화면용 이름을 따로 만들어야 해요.
- `Text("리터럴")`은 `LocalizedStringKey`라서 String Catalog가 자동으로 뽑아요. 반면 `Text(문자열 변수)`, `NSMenuItem(title:)`, `.help(String 변수)`, `beginEdit` 이름, 오류 문구는 `String(localized:)`가 필요해요. (가설: 컴파일러 추출 설정이 켜져 있는지 빌드로 확인)
- 테스트 중 영어 문자열을 직접 비교하는 곳이 있어요. 예를 들어 `TextFlipTests`는 메뉴 제목 "Flip Horizontal"을 확인해요. `HistoryTests`, `LayerTests`, `CommandPaletteTests` 등도 이름이나 제목을 비교할 수 있어요. 방식 A에서 테스트를 영어 로케일로 돌리면 그대로 유효해요. (가설: 테스트 호스트 언어 확인 필요)
- 번역하면 안 되는 것: 프로젝트 형식의 키와 값(`docs/project-format.md`), PSD 키, 저장되는 rawValue.

### 3.3 제안 순서

1. brainstorming으로 방식·범위·용어집을 정하고 사양서를 써요(`docs/superpowers/specs/`).
2. 인벤토리: 파일별 문자열 목록과 종류(리터럴, 변수, AppKit, undo, 오류, rawValue 표시)를 만들어요. 에이전트로 나누기 좋은 작업이에요.
3. 인프라: `Localizable.xcstrings`, `knownRegions`에 `ko`, rawValue 화면 이름.
4. 화면별 묶음으로 번역해요.
5. 검증: 영어 로케일로 기존 테스트, 한국어 로케일로 앱을 열어 화면 QA(스크린샷). 빈 번역이 남지 않았는지 카탈로그 상태도 확인해요.

---

## 4. 이전 세션에서 미룬 것

- Move 도구의 회전 핸들 커서는 예전 모양(두 원형 화살표)이에요. 텍스트 상자 커서만 ㄱ자로 바꿨어요.
- 테스트 정리: 회전 드래그 테스트 일부가 끝날 때 `NSCursor`를 되돌리지 않아요. 키 윈도 스텁(`TextEditingWindow`)이 테스트 파일 세 곳에 중복돼 있어요.
- `TextBoxRotationTests`의 포인트 텍스트 커밋 확인은 중심과 회전만 보고 크기는 보지 않아요(래스터 크기 반올림 때문).
