# UI 한국어화 설계 사양서

작성: 2026-10-08 · 브랜치: `Flowerwreath/fix-textbox-spec-issues` (`330a906`) · 관련 문서: `docs/handoff/localization/HANDOFF.md`

**검증됨**은 이번 세션에서 코드나 명령으로 확인한 내용이에요. **가설**은 아직 확인하지 않은 추정이에요.

---

## 1. 목적

macOS 언어가 한국어일 때 Compositor의 UI에서 **아이콘을 뺀, 글자가 보이는 곳은 모두 한국어**로 보이게 해요. "100%"는 수사적인 표현이에요. 문자열 하나하나를 세는 기준이 아니라 화면에서 영어가 보이지 않는 것이 기준이에요.

### 사용자가 정한 것

- **방식:** String Catalog로 한국어를 추가해요(인수인계 메모의 A안). 영어 원문은 코드에 그대로 두고, 앱은 macOS 언어 설정을 따라요. 앱 안의 언어 전환 UI는 만들지 않아요.
- **범위:** 아이콘을 뺀 모든 UI 문구예요(§3).
- **용어:** Photoshop 한국어판 용어를 따라요(예: Multiply=곱하기, Color Dodge=색상 닷지, Gaussian Blur=가우시안 흐림 효과, Marquee=선택 윤곽, Leading=행간, Tracking=자간).
- **명령 팔레트:** 한국어와 영어 둘 다로 검색돼요. 화면에는 한국어만 보여요.
- **구현 방식:** 섞기(③안)예요. SwiftUI 리터럴은 자동 추출에 맡겨요. 반복되는 패턴은 함수 한 곳에서 번역해요. 한 번씩 나오는 문자열만 그 자리에서 감싸요(§4.2).

### 사용자에게 알리고 이의가 없었던 가정

- 이 Mac에서 직접 쓰는 용도예요.
- upstream(`robbietilton/Compositor`)을 계속 병합해요. 그래서 upstream 코드는 가능한 한 적게 고쳐요.
- 프로젝트 파일 형식은 바꾸지 않아요.
- 접근성 라벨은 화면에 보이지 않지만 같은 방식으로 추출돼서 함께 번역해요.
- RGB, HSL, px, % 같은 약어와 단위는 번역하지 않아요.
- 초성 검색(ㄱㅇㅅ → 가우시안)은 넣지 않아요.

### 범위 밖

- 앱 안의 언어 전환 UI(macOS의 앱별 언어 설정을 써요).
- 한국어 외의 언어.
- 사용자가 만든 내용: 직접 지은 레이어 이름, 파일 이름, 글꼴 이름.
- 앱 이름 "Compositor", 키 기호(⌘⇧⌥⌃).
- 프로젝트 파일과 PSD의 키·값, 저장되는 rawValue.

---

## 2. 현재 상태 (검증됨)

- 지역화 파일이 없어요(`.xcstrings`, `.strings`, `.lproj` 모두 없음). `developmentRegion = en`, `knownRegions = (en, Base)`(`project.pbxproj:196–201`).
- 앱 타깃에 `LOCALIZATION_PREFERS_STRING_CATALOGS = YES`, `SWIFT_EMIT_LOC_STRINGS = YES`가 켜져 있어요(`project.pbxproj:336`, `:440`, `:479`). 컴파일러가 문자열을 추출할 수 있어요.
- 프로젝트가 폴더 동기화 그룹(`PBXFileSystemSynchronizedRootGroup`, `objectVersion = 77`)을 써요. `Compositor/` 아래에 파일을 넣으면 타깃에 자동으로 포함돼요.
- 이 Mac의 언어 목록은 `ko-KR, en-KR, ja-KR`이에요. `ko` 번역을 넣으면 앱이 설정 없이 한국어로 떠요.
- scheme의 TestAction에는 언어·지역 설정이 없어요. 그래서 `ko`를 넣는 순간 **테스트 호스트도 한국어로 돌아요.** 영어 문자열을 비교하는 테스트(`TextFlipTests`의 "Flip Horizontal" 등)가 깨지니 §4.1에서 고정해요.
- 앱은 샌드박스 안에서 돌아요(`Config/Compositor.entitlements`). 그래서 테스트가 저장소의 소스 파일을 읽어 검사하는 방식은 쓰지 않아요.
- `DocumentHistory`는 저장되지 않아요. 실행 취소 이름은 기록할 때 번역해도 돼요. Edit 메뉴는 `Button("Undo \(session.history.undoName)")`(`CompositorApp.swift:41`)로 이름을 보여 줘요.
- 단축키 목록(`KeyboardShortcuts.swift`)은 항목을 단축키 조합으로 찾아요. 다만 `title`과 `group`("Menus")은 식별자로도 쓰여요(`:68`, `:72`).
- 명령 팔레트(`CommandPalette.swift:105–135`)는 열릴 때마다 실행 중인 메뉴의 제목을 읽어요. 그래서 메뉴를 번역하면 팔레트 항목도 자동으로 번역돼요.
- 로컬 `upstream/main`은 `af30c45`(1.4.7)이고, `d21ff29`로 이미 병합돼 있어요. fetch는 하지 않았어요.

### 번역 지점 분포 (`git grep` 기준 대략값)

| 종류 | 위치와 개수 |
|---|---|
| SwiftUI 리터럴 | `Compositor/UI/` 아래 약 25개 파일, `CompositorApp.swift` 등 |
| rawValue를 그대로 표시 | 약 30곳. `BrushControls.swift:12,19,26`, `CameraRawColorControls.swift:16,23,275,283,436`, `CameraRawControls.swift:132,190,232,248`, `CameraRawGeometryCalibrationControls.swift:13,39,98`, `CanvasSizeSheet.swift:75`, `CurvesControls.swift:11`, `FilterSheet.swift:73,189,238,252`, `GradientControls.swift:12,18`, `GridSettingsSheet.swift:59`, `ImageSizeSheet.swift:150`, `BlendModePicker.swift:13`, `TransformInspector.swift:37` 등 |
| `beginEdit` 실행 취소 이름 | 리터럴로 시작하는 호출 39곳, 삼항 연산자·변수 호출 9곳(`CanvasRotation.swift:40`, `Filters.swift:675` 등). 함수는 `EditorSession.swift:669` 하나 |
| `NSMenuItem(title:)` | 19곳. 그중 15곳이 `NativeLayerList.swift` |
| NSAlert 문구 | `LiveLayerMask.swift:109`, `ProjectController.swift:332`, `ProjectController+ExternalChanges.swift:91` 등 6곳. 버튼 9개 |
| `errorDescription` | 9개 타입(`ContentFill`, `ImageTrim`, `MagicWand`, `ObjectSelection`, `SubjectRemoval`, `ImageExporter`, `ImageImporter`, `PSDTypes`, `ProjectStore`) |
| 변수를 넘기는 `.help` | 40곳. 대부분 `title`과 `help`를 `String`으로 받는 행 도우미 |
| 변수를 넘기는 `accessibilityLabel` | 15곳 |
| 기본 이름 | `"Layer \(n)"`(`EditorSession.swift:684`, `SelectionClipboard.swift:271`), `"Background"`(`EditorSession.swift:1007`), `"Text"`(`TypeTool.swift:12`, `:575`) |
| 도구 이름 | `EditorSession.swift:99`의 `label`(삼항 연산자 한 줄) |
| Info.plist | 문서 종류 이름 6개(`CFBundleTypeName`, `UTTypeDescription`). 저장 패널의 형식 목록과 Finder의 "종류"에 보여요 |

---

## 3. 범위

**번역할 것**
- 메뉴 막대, 툴바, 패널, 시트, 툴팁(`.help`), 접근성 라벨
- 알림과 오류 문구
- Edit 메뉴의 실행 취소·재실행 이름
- 명령 팔레트, 단축키 목록
- 새 레이어의 기본 이름("레이어 1", "배경", "텍스트")
- 블렌드 모드나 필터 이름처럼 enum 값을 그대로 보여 주던 곳. 저장되는 값은 영어로 두고, 화면에 보일 이름만 따로 만들어요.
- Info.plist의 문서 종류 이름. 새 파일 `InfoPlist.xcstrings`로 처리해요.

**자동으로 처리되는 것(번역하지 않고 확인만)**
- macOS가 제공하는 표준 메뉴 항목(복사, 붙여넣기, 종료, 서비스, 윈도우 메뉴 등)
- Sparkle 업데이트 창

---

## 4. 설계

### 4.1 인프라

**새로 추가해요**(upstream에는 없는 파일이라 병합 때 충돌하지 않아요)
- `Compositor/Localizable.xcstrings`: 원문 언어는 `en`, 번역은 `ko`예요.
- `Compositor/InfoPlist.xcstrings`: 문서 종류 이름 6개를 담아요.
- `Compositor/Localization/DisplayName.swift`
  - `LocalizedDisplayName` 프로토콜(`RawRepresentable`, `RawValue == String`)이 `displayName: String`을 제공해요. rawValue를 키로 카탈로그에서 찾고, 없으면 rawValue를 그대로 돌려줘요.
  - 화면에 표시되는 enum은 **이 파일 안에서** 확장(extension)으로 프로토콜을 채택해요. upstream의 enum 정의 파일은 건드리지 않아요.
  - 채택한 타입의 목록(`allDisplayNameTypes`)을 함께 둬요. 커버리지 테스트(§5.1)가 이 목록을 써요.
- `Compositor/Localization/EnglishTitles.swift`: 명령 팔레트의 영어 검색을 맡아요(§4.3).
- `docs/localization/glossary.md`: Photoshop 한국어판 기준의 영→한 용어집이에요.
- 카탈로그 미번역 개수를 세는 스크립트예요(§5.2).

**조금 고쳐요**
- `project.pbxproj`: `knownRegions`에 `ko`를 추가해요.
- `Compositor.xcscheme`의 TestAction: 테스트 언어를 `en`, 지역을 `US`로 고정해요. Xcode에서 돌리든 `xcodebuild`로 돌리든, CI에서도 테스트는 영어로 돌아요.
  - **가설:** TestAction에 `language`와 `region` 속성을 쓰면 테스트 호스트에 적용돼요. 고친 뒤 테스트 안에서 `Bundle.main.preferredLocalizations.first == "en"`인지 확인해요. 안 되면 테스트 호스트 실행 인자로 `-AppleLanguages (en)`을 넘겨요.

**upstream 병합 후의 흐름:** upstream이 문구를 바꾸거나 추가하면, 다음 동기화 때 카탈로그에 번역 없는 키로 들어가거나 "오래됨"으로 표시돼요. 화면에는 영어가 나오고 앱은 깨지지 않아요. §5.2의 스크립트로 미번역 목록을 보고 채워요.

**병합할 때마다 빌드와 테스트를 한 번 돌려요.** §4.2의 ②는 공용 함수(`beginEdit`, 행 도우미)의 매개변수 타입을 `String`에서 `LocalizedStringResource`로 바꿔요. 그래서 upstream의 새 코드가 이 함수에 `String` 변수를 넘기면, git 충돌 없이 병합된 뒤에도 빌드 오류가 나요. 고치는 법은 §4.2의 규칙과 같아요. 오류가 난 줄에서 이미 번역된 이름이면 `beginEdit(named:)`로, 리터럴에서 온 변수면 그 변수의 타입을 바꿔요.

### 4.2 문자열 종류별 처리 규칙

원칙은 하나예요. **upstream 코드는 가능한 한 정의 쪽만 고치고 호출하는 쪽은 그대로 둬요.**

| 종류 | 처리 | 예 |
|---|---|---|
| ① SwiftUI에 리터럴을 바로 넘기는 곳 | 고치지 않아요(자동 추출) | `Text("Opacity")`, `Button("Cancel")`, `Text("Undo \(name)")` |
| ② 화면 문자열을 받는 이 앱의 함수·뷰 | 매개변수 타입만 `String` → `LocalizedStringResource`로 바꿔요. 호출부 리터럴은 그대로 두고 자동 추출돼요 | `beginEdit(_:)`, `title:`과 `help:`를 받는 행 도우미들 |
| ③ enum rawValue를 보여 주는 곳 | `$0.rawValue` → `$0.displayName`. 카탈로그에는 손으로 넣고 §5.1의 테스트로 지켜요 | 블렌드 모드, 필터, 디더 스타일, 샘플링 |
| ④ 식별자로도 쓰는 문자열 | 원문은 그대로 두고 화면에 보일 때만 번역해요 | 단축키 목록의 `title`과 `group`, `CanvasSizeSheet`의 배경 옵션 |
| ⑤ 한 번씩 나오는 AppKit 문구, 알림, 오류, 계산된 문자열 | 그 자리에서 `String(localized:)`로 감싸요 | NSAlert, `NSMenuItem(title:)`, `errorDescription`, `tool.label`, `"Layer \(n)"` |

**②의 세부 규칙**
- `beginEdit(_ name: LocalizedStringResource)` 안에서 `String(localized: name)`으로 바꿔 `history.begin`에 넘겨요. 실행 취소 이름은 기록할 때 번역돼요.
- `String` 변수를 넘기는 호출부(예: `beginEdit(name)`, `beginEdit(edit.kind.rawValue)`)는 컴파일 오류가 나요. 그 자리만 고쳐요. enum이면 `displayName`을, 이미 번역된 문자열이면 그대로 넘기는 오버로드를 써요.
- 행 도우미가 `title`을 비교나 식별자로도 쓰면 ④로 다뤄요.

**값이 끼어드는 문장:** `String(localized: "Save changes to \(name)?")`의 키는 `Save changes to %@?`예요. 한국어 번역은 "%@의 변경 사항을 저장할까요?"처럼 어순을 바꿔 쓸 수 있어요. 문장 안에 enum 값이 끼면 rawValue 대신 `displayName`을 넣어요(예: `"New \(kind.rawValue) Adjustment"` → `"New \(kind.displayName) Adjustment"`).

**같이 고칠 함정**
1. `BlendModePicker`(`:13`, `:26`, `:66`)는 영어 제목으로 항목을 찾아 선택해요. 태그(`tag` 또는 `representedObject`)로 선택하게 바꿔요.
2. `CanvasSizeSheet`(`:59`, `:126`)는 `"Background"` 같은 문자열을 태그로 쓰고 `switch`로 비교해요. 태그와 비교는 영어로 두고, 화면 표시만 번역해요.
3. `CommandPalette`는 "Window"와 "Help" 메뉴를 영어 제목으로 비교해 빼요. 번역된 제목으로 비교하게 바꿔요.
4. 기본 이름 "Layer N"은 이름을 만드는 곳과 중복 검사(`EditorSession.swift:684`, `SelectionClipboard.swift:271`)가 같은 번역 형식을 쓰게 맞춰요.

**번역하면 안 되는 것:** 저장되는 rawValue(예: `LayerSampling`의 "High quality", `TextAlignment`, `TextOrientation`, 블렌드 모드), Codable 키, UserDefaults 키, 식별자로 쓰는 문자열, PSD 키(`docs/project-format.md` 참고).

**가설:** ②는 컴파일러가 `LocalizedStringResource` 매개변수로 넘어간 리터럴을 추출한다는 전제에 기대요. Apple 문서의 안내예요. 첫 빌드 뒤 카탈로그에 `beginEdit` 이름들이 들어왔는지 확인해요. 들어오지 않았으면 그 호출부만 ⑤ 방식으로 바꿔요.

### 4.3 명령 팔레트의 영어 검색

**동작:** 화면에는 한국어 경로(예: "필터 › 가우시안 흐림 효과…")만 보여요. 검색할 때는 한국어 경로와 영어 경로를 각각 점수 매겨 높은 쪽을 써요. "blur", "가우", "흐림" 모두 같은 항목을 찾아요. 순위 규칙(단어 시작 일치 > 부분 일치, 짧은 제목 우선)은 지금 것을 그대로 쓰고, 맞은 쪽 언어의 제목 길이로 비교해요.

**영어 경로를 얻는 법**
- 앱 번들의 현재 언어 번역표(`Bundle.main.preferredLocalizations.first`의 `Localizable.strings`)를 읽어 `번역 → 영어 키` 역방향 사전을 한 번 만들어요.
- 메뉴 경로의 각 단계를 이 사전으로 바꿔 영어 경로를 만들어요.
- 사전에 없는 제목은 영어 경로에서 빠지고 한국어로만 찾아져요. 값이 끼는 제목("브러시 획 실행 취소")이나 AppKit이 직접 번역한 시스템 항목이 여기에 해당해요.
- 앱이 영어로 돌 때는 사전이 비어서 지금과 똑같이 동작해요.

**코드 위치**
- `Localization/EnglishTitles.swift`: 역방향 사전과 경로 변환을 맡아요. 테스트에서 사전을 주입할 수 있게 해요.
- `CommandPalette.swift`: 항목에 영어 경로 필드 하나를 추가하고, 점수 계산에서 둘 중 높은 쪽을 쓰게 해요. §4.2 함정 3의 제외 목록도 고쳐요.

**가설:** 한글을 조합하는 중에도 검색어가 바뀌어 결과가 갱신되는지는 SwiftUI `TextField`의 동작에 달려 있어요. 화면 QA에서 확인하고, 조합이 끝난 뒤에만 갱신되면 그대로 둘지 사용자에게 물어요.

### 4.4 작업 순서와 번역 방법

1. **인프라(§4.1).**
2. **코드 수정(§4.2의 ②–⑤와 함정 4개).** 그다음 빌드하면 컴파일러가 ①②⑤ 문자열을 카탈로그에 채워요. **채워진 카탈로그가 문자열 목록**이 돼요. ③ enum 이름은 `allDisplayNameTypes`에서 키를 뽑아 손으로 넣어요. 변수를 넘기는 `Text(…)` 약 95곳은 하나씩 보고 사용자 내용인지 UI 문구인지 분류해요.
3. **용어집 초안.** 카탈로그에서 반복되는 용어 약 100개를 뽑아 Photoshop 한국어판 기준으로 정리해요. **사용자가 훑어본 뒤에** 대량 번역에 들어가요.
4. **화면별로 묶어 번역해요.**
   1. 메뉴 막대, 단축키 목록, 명령 팔레트
   2. 도구 바와 도구 옵션(문자, 브러시, 올가미, 그레이디언트 등)
   3. 레이어 패널, 블렌드 모드, 마스크
   4. 필터와 조정 시트(Camera Raw, 곡선, 레벨, 색조/채도 등)
   5. 문서와 파일(캔버스 크기, 이미지 크기, 새 문서, 저장 알림, 오류, PSD 가져오기, 문서 종류 이름)
   6. 실행 취소 이름과 enum 이름
5. **검증(§5).**

**카탈로그 편집:** `.xcstrings`는 JSON이라, 번역 표를 스크립트로 넣고 Xcode GUI는 쓰지 않아요. 번역하지 않는 항목(RGB, HSL, px 등)은 `shouldTranslate: false`로 표시해서 미번역 개수에서 빼요.

**커밋과 에이전트:** 커밋은 사용자가 요청할 때만 해요. 번역 묶음은 서로 독립적이라 나눠 맡기기 좋아요. 누구에게 어떻게 맡길지는 구현 계획 단계에서 사용자가 정해요. Codex(`codex:codex-rescue`)는 이 Mac에서 `xcodebuild`를 못 돌려요. 그래서 빌드와 테스트는 Claude 쪽 셸에서 해요.

---

## 5. 검증

### 5.1 자동 테스트 (영어 로케일)

- **기존 전체 테스트:** 새 실패가 없어야 해요. 알려진 로컬 전용 실패 3건은 새 실패로 세지 않아요(`SliderSnapTests.clickingTheTrackSnapsBeforeNativeTrackingBegins`, `TiledLayerTests.paintingAtTheLayersEdgeDoesNotChangeIt`, `CursorTests.leavingTheCanvasRestoresTheArrowWithEveryTool`).
- **새 테스트**
  1. **enum 이름 커버리지:** `allDisplayNameTypes`에 있는 모든 enum의 모든 case에 한국어 번역이 있는지 확인해요. 앱 번들의 `ko.lproj`를 직접 열어서 보니, 테스트가 영어로 돌아도 검사할 수 있어요. upstream이 새 case를 추가하면 이 테스트가 실패해요.
  2. **팔레트 영어 검색:** 사전을 주입해서 세 가지를 확인해요. "blur"와 "흐림"이 같은 항목을 찾는지, 영어로 맞을 때와 한국어로 맞을 때의 순위, 사전이 비었을 때 지금과 결과가 같은지예요.
  3. **기본 레이어 이름:** 번역 형식을 주입해서, 이름을 만드는 곳과 중복 검사가 같은 형식을 쓰는지 확인해요("레이어 1"이 있으면 다음은 "레이어 2").
  4. **테스트 언어:** 테스트 호스트의 `Bundle.main.preferredLocalizations.first`가 `en`인지 확인해요(§4.1의 가설 확인).
- `BlendModePicker`와 `CanvasSizeSheet`의 태그 비교 수정은 영어 테스트에서는 차이가 드러나지 않아요. 따로 테스트를 넣지 않고 화면 QA로 확인해요.

### 5.2 카탈로그 상태

스크립트로 `ko` 상태가 `translated`가 아닌 키를 세요. `shouldTranslate: false`인 키는 빼요. 목표는 0이에요. `Localizable.xcstrings`와 `InfoPlist.xcstrings` 둘 다 확인해요.

### 5.3 화면 QA (한국어로 실행)

- 로컬 Release 빌드를 설치해요(인수인계 메모 §2의 명령). 기존 앱은 `~/.Trash`로 옮겨요. 앱이 실행 중이면 강제로 끄지 않고 사용자에게 ⌘Q를 부탁해요.
- §4.4의 화면 묶음마다 스크린샷을 찍어 영어가 남았는지 확인해요.
- 함께 확인할 것
  - 시스템 설정 → 일반 → 언어 및 지역 → 응용 프로그램 목록에서 Compositor를 고를 수 있는지(가설)
  - Sparkle 업데이트 창이 한국어로 나오는지(가설)
  - 팔레트에서 한글을 조합하는 중에도 결과가 갱신되는지(§4.3의 가설)
  - 블렌드 모드 선택과 캔버스 크기의 배경 옵션이 제대로 동작하는지
  - 저장 패널의 형식 이름이 한국어인지

### 5.4 완료 기준

1. §5.2의 미번역 키가 0개예요.
2. §5.3의 화면 묶음 스크린샷에 영어가 없어요. 용어집에서 남기기로 한 약어와 단위, 앱 이름, 사용자 내용은 예외예요.
3. 영어 로케일에서 전체 테스트를 돌려 새 실패가 0건이에요. §5.1의 새 테스트 4종도 통과해요.
4. 저장되는 값이 바뀌지 않았어요. rawValue와 Codable 키를 고치지 않았고, 기존 프로젝트 형식 테스트가 통과해요.

---

## 6. 가설 목록

| # | 가설 | 확인 방법 | 안 맞으면 |
|---|---|---|---|
| H1 | scheme TestAction의 `language`·`region` 속성으로 테스트 호스트가 영어로 돌아요 | §5.1의 테스트 4 | 테스트 호스트에 `-AppleLanguages (en)` 인자를 넘겨요 |
| H2 | `LocalizedStringResource` 매개변수로 넘긴 리터럴을 컴파일러가 추출해요 | 첫 빌드 뒤 카탈로그에 `beginEdit` 이름이 있는지 | 그 호출부만 `String(localized:)`로 감싸요 |
| H3 | 앱 번들에 `ko.lproj`가 있으면 앱별 언어 설정 목록에 나와요 | 화면 QA | 기록만 해요(이 Mac은 시스템 언어가 한국어라 영향 없음) |
| H4 | Sparkle이 자체 한국어 번역을 갖고 있어요 | 화면 QA | 범위 밖으로 기록해요 |
| H5 | 한글 조합 중에도 팔레트 검색어가 갱신돼요 | 화면 QA | 사용자에게 물어요 |

---

## 7. 이번 세션 기록

- `git status`: 깨끗함, HEAD `330a906`. `d21ff29`가 조상이에요.
- `/Applications/Compositor.app`: 1.4.7, 번들 ID `com.wonderassembly.compositor`, 실행 중.
- `defaults read -g AppleLanguages`: `ko-KR, en-KR, ja-KR`.
- 빌드와 테스트는 아직 돌리지 않았어요.
