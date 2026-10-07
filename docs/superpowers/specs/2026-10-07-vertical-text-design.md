# 세로쓰기 텍스트 설계 사양서

작성: 2026-10-07 · 브랜치: `Flowerwreath/textbox-esc-vertical` (`72d9ad2`에서 분기) · 관련 문서: `docs/handoff/textbox/SPEC.md` #5

**검증됨**은 이번 세션에서 코드나 파일로 확인한 내용이에요. **가설**은 아직 확인하지 않은 추정이에요.

---

## 1. 목적

Photoshop의 세로 텍스트 레이어를 **픽셀이 아니라 편집할 수 있는 텍스트**로 가져오고, 앱 안에서도 세로 텍스트를 만들고 편집할 수 있게 해요.

### 사용자가 정한 것

- 주목적: Photoshop 세로 텍스트 호환.
- 범위: PSD 가져오기와 툴바의 방향 전환 버튼. 새 텍스트를 세로로 쓰고, 기존 텍스트를 가로↔세로로 바꿀 수 있어요.
- 기술 방식: A안. 편집기와 캔버스 모두 TextKit 1 세로 레이아웃을 써요(§4).
- 샘플 PSD: 받았어요(§3). 두 번째 샘플은 사용자가 만들어 줄 예정이에요(§9).

### 사용자에게 알리고 이의가 없었던 가정

- 글자는 위에서 아래로 쓰고, 줄(열)은 오른쪽에서 왼쪽으로 넘어가요.
- 한자·가나·한글은 똑바로 서고, 영문·숫자는 시계 방향으로 90° 눕혀요(Photoshop 기본값).
- 정렬 버튼의 왼쪽·가운데·오른쪽은 세로에서 위·가운데·아래가 돼요.
- Leading은 열 사이 간격, Tracking은 열 안의 글자 간격이에요.
- 방향은 레이어 전체에 하나예요(Photoshop과 같음).
- Option+화살표 단축키는 그대로 둬요.

### 범위 밖

- 가로 짜기(tate-chu-yoko), 영문 세워 쓰기(Standard Vertical Roman Alignment), 와리추, 세로 전용 구두점 조정 옵션.
- PSD 내보내기. 지금도 텍스트를 픽셀로 쓰므로 바뀌는 게 없어요.
- 열 단위나 글자 단위로 방향을 섞는 것.

---

## 2. 현재 상태 (검증됨)

- `LayerTextStyle`(`Compositor/Document/TypeTool.swift:7`)에는 방향 필드가 없어요. synthesized Codable이에요.
- PSD 가져오기는 세로 텍스트를 만나면 텍스트로 읽지 않고(`PSDText.swift:42`, `Ornt == "Vrtc"`이면 `nil`) 픽셀 레이어로 남겨요.
- 캔버스는 편집 중인 텍스트를 `EditorSession.textImage(draft.style)`로 그려요(`EditorCanvas.swift:29` `draftText`). 편집기(`CanvasTextView`)의 글자는 투명해요. 그래서 **캔버스 렌더링과 편집기 레이아웃이 어긋나면 커서와 선택 영역이 글자에서 벗어나요.**
- 프로젝트 형식 버전은 텍스트 필드가 늘 때마다 올렸어요: `colorRuns` 10, `fontRuns` 11(`ProjectStore.swift:15`, `docs/project-format.md:35-37`). 로드할 때 버전보다 새 필드가 있으면 거부해요. 예전 버전 앱은 더 높은 버전의 파일을 열지 못해요.
- 가로 전용 계산이 있는 곳:
  - `EditorSession.firstLine`, `letterMetrics`, `textBoxSize`(`boundingRect` 사용), `textImage`(`TypeTool.swift:419-503`)
  - `beginText(at:)`의 클릭 위치 계산(`TypeTool.swift:257`, 첫 baseline을 포인터에 맞춤)
  - 포인트 텍스트가 커질 때 왼쪽 위 모서리를 고정하는 계산(`InlineTextEditor.synchronize`, `applyText` `TypeTool.swift:288-296`)
  - 편집기의 텍스트 컨테이너 배치와 짧은 leading 보정(`InlineTextEditor.swift:265-275`)
  - 하이라이트와 커서 보정(`SeeThroughSelectionLayout`, `CanvasTextView.drawInsertionPoint`)
  - PSD 포인트 텍스트 기준점(`PSDText.render`의 `horizontalAnchor`, `baseline`)

---

## 3. 샘플 PSD 분석 (검증됨)

파일: 사용자가 준 `allitell-1279022261136056320-0.psd`(1969×2924, RGB 8bit, 레이어 18개, 텍스트 레이어 17개). 다른 사람의 작품이라 **저장소에 넣지 않아요.** 테스트에는 아래 숫자만 써요.

세로 레이어는 2개이고, 둘 다 한글 단락(상자) 텍스트예요. EngineData는 `/ShapeType 1`이고, 세로 레이어에만 `/Procession 1`이 있어요. 둘 다 `warpNone`, transform은 단위 행렬이에요.

| 항목 | `우왁` (레이어 11) | `향수` (레이어 16) |
|---|---|---|
| transform tx, ty | −127.0323, 266.1304 | 865.1927, 885.9565 |
| `bounds` (L, T, R, B) | 0, 0, 430.1314, 597.5056 | −16.4665, 0, 83.5335, 212.8416 |
| `boundingBox` (L, T, R, B) | 240.5383, 3.7020, 422.9289, 388.8895 | 6.1870, 14.4686, 65.8902, 191.4686 |
| 레이어 픽셀 상자 (l, t, r, b) | 113, 269, 296, 655 | 870, 900, 932, 1077 |
| 글꼴 / 크기 | `DXCtnB-KSCpc-EUC-H` / 200 | `Cafe24Shiningstar` / 100 |
| Leading | Auto (1.2) | 75 |
| Justification | 0 (위) | 2 (가운데) |

`boundingBox`에 transform을 더하면 레이어 픽셀 상자와 1px 안에서 맞아요.

**첫 열 위치 규칙(가설, 근거 2개):** 첫 열의 중심선은 `bounds.R − fontSize / 2`에 있어요. 즉 첫 열의 글자 칸(em box)이 상자 오른쪽 끝에 붙어요.
- `우왁`: 규칙 330.13, 글자 상자 중심 331.73 (차이 1.6)
- `향수`: 규칙 33.53, 글자 상자 중심 36.04 (차이 2.5)

차이는 글자 모양이 좌우 대칭이 아니어서 생긴 것으로 보여요.

**가운데 정렬(가설):** `향수`의 글자 칸 두 개(2 × 100)를 상자 높이 212.84 가운데에 놓으면 6.42–206.42이에요. 잉크 14.47–191.47이 그 안에 들어가요.

**한계:** 두 글꼴 모두 이 Mac에 설치돼 있지 않아요(검증됨). 그래서 Photoshop 픽셀과 앱의 렌더링을 직접 비교할 수 없어요. 세로 **포인트** 텍스트는 샘플에 없어요.

---

## 4. 기술 방식: TextKit 1 세로 레이아웃 (검증됨)

버린 scratch probe로 확인한 내용이에요.

- `NSTextContainer`를 상속해 `layoutOrientation`이 `.vertical`을 돌려주게 하고, 크기를 가로·세로 바꿔 넣은 `NSLayoutManager`를 쓰면 세로로 배치돼요. 한자·가나는 서고, 영문·숫자는 눕고, 구두점은 세로 모양(오른쪽 위)으로 바뀌고, 줄은 오른쪽에서 왼쪽으로 진행해요.
- 그리는 방법: 위쪽 원점(flipped) 컨텍스트에서 `translate(x: 폭, y: 0)` 후 `rotate(+90°)`를 하고 `drawGlyphs`를 호출해요. 컨테이너 좌표 `(x, y)`가 뷰 좌표 `(폭 − y, x)`로 가요.
- 같은 글자를 `NSTextView.setLayoutOrientation(.vertical)`에 넣고 `convert`로 얻은 위치와 비교했어요. 글자 5개(첫 글자, 영문, 줄 끝, 둘째 줄 처음과 끝)가 **0pt 차이**로 같았어요.
- 세로 NSTextView는 `boundsRotation = 90`을 써요(frame 300×360 → bounds 360×300). `cacheDisplay`와 `displayIgnoringOpacity`는 이 회전을 적용하지 않아요. 그래서 **편집기를 비트맵으로 찍어 비교하는 테스트는 세로에서 쓸 수 없어요.** 테스트는 좌표 변환(`convert`, `firstRect`)으로 비교해요.

검토했지만 고르지 않은 방식:
- **B. 캔버스는 CoreText 세로 프레임, 편집기는 NSTextView:** 엔진이 둘이라 글자 위치가 어긋나요.
- **C. 가로로 그리고 이미지를 돌리기:** 한자·가나·한글이 옆으로 누워요.

---

## 5. 설계

### 5.1 데이터 모델과 프로젝트 형식

- `nonisolated enum TextOrientation: String, Codable, CaseIterable, Sendable { case horizontal = "Horizontal", vertical = "Vertical" }`. `TextAlignment`와 같은 방식이에요.
- `LayerTextStyle`에 `var orientation: TextOrientation? = nil`을 추가해요. `nil`이면 가로예요. synthesized Codable이 예전 JSON(키 없음)을 읽을 수 있도록 optional로 둬요. `var isVertical: Bool { orientation == .vertical }`도 추가해요.
- 가로로 되돌릴 때는 `.horizontal`이 아니라 `nil`로 저장해요. 가로 텍스트의 JSON이 지금과 똑같이 유지돼요.
- 프로젝트 형식 버전을 **12**로 올려요(`ProjectManifest.current`). 로드 검증에 `text.orientation == nil || manifest.version >= 12`를 추가해요. `docs/project-format.md`에 버전 12 항목과 `orientation` 설명을 추가해요. 버전 11을 기대하는 기존 테스트(5개 파일 6곳: `GroupTests`, `GuideTests`, `LayerAppearanceTests`, `LayerMaskTests` 2곳, `TypeToolTests`)도 12로 바꿔요.
- 결과: 예전 버전 앱은 새로 저장한 프로젝트를 열지 못해요. `colorRuns`, `fontRuns`를 추가할 때와 같은 동작이에요.

### 5.2 렌더링 (`textImage`, `textBoxSize`)

- `textAttributes`는 그대로 써요. paragraph의 `minimumLineHeight == maximumLineHeight == lineHeight`가 세로에서는 열 폭(열 사이 간격)이 되고, `.kern`은 열 안의 글자 간격이 돼요. 정렬은 세로에서 위·가운데·아래가 돼요.
- 세로 레이아웃 도우미를 하나 만들어 `textImage`, `textBoxSize`, PSD 렌더, 테스트가 같이 써요. 예: `EditorSession.verticalLayout(style, size:) -> (storage, layoutManager, container)`.
  - 컨테이너 크기는 `(상자 높이 − 2·padding, 상자 폭 − 2·padding − 보정)`이에요(회전된 좌표).
  - `textImage`는 §4의 변환으로 그려요.
- **첫 열 위치:** 첫 열의 글자 칸이 상자 오른쪽 padding 안쪽 끝에 붙어요(§3 규칙). TextKit이 열 조각(line fragment) 안 어디에 글자를 놓는지에 따라 보정값이 필요할 수 있어요. 이 값은 가로의 `firstLine`처럼 계산하고, 테스트로 고정해요.
- **짧은 leading:** leading이 글자 칸보다 좁으면 열이 겹쳐요. 첫 열은 그래도 상자 안에 있어야 해요. 가로에서 `6cabd51`이 첫 줄을 처리한 방식(`firstLine.overflow`)을 축만 바꿔 적용해요.
- **포인트 텍스트 크기(`textBoxSize`):** 세로 레이아웃으로 사용 영역(used rect)을 재요. 폭은 열들의 폭, 높이는 가장 긴 열의 길이에요. 빈 텍스트도 열 하나만큼의 폭을 가져요.

### 5.3 포인트 텍스트의 기준점

- **클릭 위치:** 새 세로 포인트 텍스트는 클릭한 점이 **첫 열 중심선의 위쪽 끝**이 되게 놓아요(Photoshop과 같다고 가정, §9). 가로의 "첫 baseline을 포인터에 맞춤"(`TypeTool.swift:257`)에 대응해요.
- **커질 때 고정점:** 세로 포인트 텍스트는 **오른쪽 위 모서리**를 고정해요. 열이 늘면 왼쪽으로 커져요. 바꿀 곳:
  - `InlineTextEditor.synchronize`: 지금은 `transform.point(.zero)`를 고정해요. 세로면 `transform.point(CGPoint(x: 1, y: 0))`을 고정해요. 새 레이어(`draft.transform == nil`)도 오른쪽 끝이 유지되도록 origin을 계산해요.
  - `applyText`(`TypeTool.swift:288-296`): 같은 규칙이에요.
- **방향 전환(사용자 검토 필요):** 가로↔세로를 바꿀 때도 상자의 오른쪽 위를 고정할지, 왼쪽 위를 고정할지 정해야 해요. **제안:** 바꾸기 전 방향의 고정점을 유지해요. 가로→세로는 왼쪽 위, 세로→가로는 오른쪽 위예요. 그래야 전환 순간 텍스트가 크게 튀지 않아요.

### 5.4 편집기 (`InlineTextEditor`, `CanvasTextView`)

- 세로면 `textView.setLayoutOrientation(.vertical)`, 가로면 `.horizontal`을 써요. 스타일이 바뀔 때(`synchronize`의 `shownStyle != style`) 맞춰요.
- `synchronize`의 텍스트 프레임, 컨테이너 크기, `textContainerInset`(짧은 leading 보정)은 축을 바꿔 계산해요. 보정은 첫 열 쪽인 오른쪽에 들어가요.
- 회전(`frameRotation`)과 반전(레이어 변환, `applyMirror`) 위에서 `boundsRotation`이 맞게 동작하는지 테스트로 확인해요. 클릭한 점의 글자 위치(`characterIndexForInsertion(at:)`)와 글자 사각형(`firstRect`)을 캔버스 좌표로 바꿔 비교해요.
- **하이라이트와 커서:** 가로와 같은 규칙이에요. 열 안의 글자 칸(폰트 크기)을 덮고 leading을 따라가지 않아요. 이 코드는 Codex가 #1·#2로 고치고 있어요. 그래서 **Codex의 작업이 `Flowerwreath/fix-textbox-spec-issues`에 들어온 뒤 이 브랜치를 rebase하고 진행해요.**
- IME 조합 글자는 `setMarkedText` override(`f9dd7d1`)로 이미 캔버스에 보여요. 후보 창 위치는 NSTextView의 `firstRect`가 정해요. 실제 앱에서 한국어 입력기로 확인해요.
- `SeeThroughSelectionLayout.reach`와 `letterReach`는 가로 전용이에요. 세로 보정 방식은 Codex의 결과를 본 뒤 정해요.

### 5.5 툴바 (`TypeControls`)

- 정렬 버튼 왼쪽에 방향 전환 토글 버튼을 하나 넣어요. 누르면 `session.changeTextStyle { $0.orientation = $0.isVertical ? nil : .vertical }`을 실행해요. 편집 중인 텍스트, 선택된 텍스트 레이어, 다음 텍스트의 기본값(`textDefaults`)에 기존 스타일 변경과 같은 경로로 적용돼요.
- 아이콘은 SF Symbol을 써요. 구현할 때 macOS 대상 버전에서 쓸 수 있는 것으로 골라요. help와 accessibilityLabel은 "Toggle text orientation"이에요.
- 세로일 때 정렬 버튼의 아이콘은 위·가운데·아래 모양(예: `align.vertical.top/center/bottom`)으로 바꾸고, help 문구도 "Align top/center/bottom"으로 바꿔요. 저장하는 값(`TextAlignment`)은 그대로예요.
- 실행 취소: 다른 스타일 변경과 같이 편집이 끝날 때 "Edit Text" 한 단계로 묶여요.

### 5.6 PSD 가져오기 (`PSDText`)

- `Ornt == "Vrtc"`이면 `style.orientation = .vertical`로 두고 계속 진행해요.
- **세로 단락(상자) 텍스트:** 가로와 같은 방식으로 상자를 만들어요(`boxSize = bounds + padding·2`, 기준점 = `bounds`의 왼쪽 위, `anchorIsFrame = true`). 첫 열 위치는 §5.2의 렌더링 규칙이 맞춰요.
- **세로 포인트 텍스트:** 기준점 `(tx, ty)`가 열의 어디를 가리키는지 아직 몰라요. **두 번째 샘플로 확인하기 전까지는 지금처럼 픽셀로 가져와요.** 세로이면서 단락 프레임이 없으면 `nil`을 돌려줘요.
- **지원하지 않는 세로 옵션:** 두 번째 샘플에서 EngineData 키를 확인할 수 있는 것만 안내 문구를 붙여요(예: "Vertical text options were omitted."). 확인하지 못한 옵션은 이 사양서의 열린 질문으로 남겨요.
- 관련 주석도 고쳐요: 파일 머리 주석의 "vertical text … stays a raster"(`PSDText.swift:10`), `:76`의 "Vertical text already falls back the same way."

---

## 6. 테스트 계획과 완료 기준

모든 기준은 자동 테스트나 명령 결과로 관찰할 수 있어야 해요. 실제 앱에서 눈으로 확인하는 항목은 따로 표시했어요.

### 6.1 모델과 프로젝트 형식
- [ ] `orientation` 키가 없는 `LayerTextStyle` JSON이 가로로 읽혀요.
- [ ] 세로 텍스트 레이어를 프로젝트로 저장했다가 열면 `orientation == .vertical`이 유지되고, 버전은 12예요.
- [ ] 버전 11이라고 적힌 파일에 `orientation`이 있으면 거부해요.

### 6.2 렌더링
- [ ] 세로 `"가\n나"`는 잉크 열이 2개이고, 첫 줄(`가`)이 오른쪽에 있어요.
- [ ] 세로 `"가"`(Apple SD Gothic Neo)의 잉크 폭·높이가 가로 `"가"`와 1px 안에서 같아요(서 있음).
- [ ] 세로 `"A"`의 잉크 폭·높이는 가로 `"A"`의 높이·폭과 1px 안에서 같아요(누워 있음).
- [ ] 열 중심선 사이 거리가 leading과 1px 안에서 같아요(leading 60, 200, Auto).
- [ ] 첫 열의 글자 칸 오른쪽 끝이 `상자 폭 − padding`과 1px 안에서 같아요. leading이 글자 칸보다 짧을 때도 첫 열 잉크가 상자 안에 있어요.
- [ ] 위·가운데·아래 정렬에서 열 안 글자 칸이 상자의 위 끝, 가운데, 아래 끝에 맞아요.
- [ ] 가로 텍스트의 기존 렌더링 테스트가 모두 그대로 통과해요(회귀 없음).

### 6.3 포인트 텍스트 기준점
- [ ] 세로 포인트 텍스트를 클릭으로 시작하면 첫 열 중심선 위쪽 끝이 클릭 위치와 1px 안에서 같아요.
- [ ] 열을 추가해도(Return) 상자 오른쪽 위 모서리가 편집 중과 커밋 후 모두 그대로예요. 회전된 레이어에서도 같아요.
- [ ] 가로↔세로 전환 시 §5.3의 고정점이 유지돼요.

### 6.4 편집기
- [ ] 세로 편집 중 각 글자의 `firstRect`를 캔버스 좌표로 바꾸면 `textImage`의 그 글자 잉크와 겹쳐요. 회전 0°, 30°, 좌우·상하 반전에서 확인해요.
- [ ] 캔버스의 글자 위를 클릭하면 그 글자 앞이나 뒤에 커서가 놓여요.
- [ ] 하이라이트와 커서가 글자 칸을 덮어요(규칙은 Codex의 #1·#2 결과를 따라요).
- [ ] (실제 앱) 한국어 입력기로 세로 입력, 조합 중 글자 표시, 후보 창 위치, Esc(#4)를 확인해요.

### 6.5 툴바
- [ ] 토글 버튼을 누르면 편집 중 텍스트의 방향이 바뀌고, 실행 취소 한 번으로 돌아와요.
- [ ] 텍스트 레이어를 선택하지 않은 상태(편집 중도 아님)에서 누르면 다음 텍스트의 기본 방향이 바뀌어요. 텍스트 레이어가 선택돼 있으면 `changeTextStyle`이 그 레이어를 편집 상태로 열고 방향을 바꿔요(기존 스타일 변경과 같음).

### 6.6 PSD
- [ ] §3의 숫자로 만든 fixture(`PSDFixture.tySh`에 방향과 `bounds`/`boundingBox` 인자 추가)는 세로 상자 텍스트로 들어오고, 레이어 위치가 `bounds`의 왼쪽 위 − padding이에요.
- [ ] 같은 fixture에서 첫 열 중심선이 `bounds.R − fontSize/2`와 1px 안에서 같아요.
- [ ] 세로 포인트 텍스트 fixture는 아직 픽셀 레이어로 들어와요(§5.6).
- [ ] (로컬 전용, 저장소 밖) 사용자의 샘플 PSD를 열면 `우왁`, `향수`가 편집 가능한 세로 텍스트로 들어와요. 글꼴이 없으므로 위치만 확인해요.
- [ ] (두 번째 샘플을 받은 뒤) 설치된 글꼴로 만든 세로 텍스트의 잉크 상자가 Photoshop 픽셀 상자와 2px 안에서 같아요.

### 6.7 최종 확인
- [ ] 전체 `CompositorTests`: 새 실패가 없어요. 알려진 로컬 전용 실패(`SliderSnapTests.clickingTheTrackSnapsBeforeNativeTrackingBegins`, 경우에 따라 `CursorTests.leavingTheCanvasRestoresTheArrowWithEveryTool`)만 허용해요.
- [ ] Release 빌드가 성공해요.

---

## 7. 작업 순서와 의존성

1. **모델·프로젝트 형식** (§5.1)
2. **렌더링과 포인트 텍스트 기준점** (§5.2, §5.3의 `applyText` 부분)
3. **툴바** (§5.5)
4. **PSD 상자 텍스트 가져오기** (§5.6)
5. **편집기** (§5.4, §5.3의 `synchronize` 부분). **선행 조건:** Codex의 #1·#2 작업이 `Flowerwreath/fix-textbox-spec-issues`에 커밋된 뒤 이 브랜치를 rebase해요. 1–4단계는 `InlineTextEditor.swift`를 건드리지 않아 충돌이 없어요. 단, 1–4단계 동안 세로 텍스트를 앱에서 편집하면 편집기는 아직 가로라서 커서가 어긋나 보여요. 그래서 5단계가 끝나기 전에는 앱을 설치하지 않아요.
6. **PSD 포인트 텍스트 가져오기.** **선행 조건:** 두 번째 샘플.

이 브랜치에는 #4(IME 조합 중 Esc) 수정이 커밋되지 않은 상태로 있어요. 커밋은 사용자가 요청할 때 해요.

---

## 8. 위험

- **편집기 회전과 `boundsRotation`:** 레이어 회전·반전과 겹칠 때 AppKit의 layer-backed 뷰가 `boundsRotation`을 제대로 그리는지 확인되지 않았어요. 안 되면 편집기 안에 회전용 중간 뷰를 하나 더 둬요.
- **첫 열 보정값:** TextKit의 열 안 글자 위치가 글꼴마다 다를 수 있어요. 글꼴 두 가지 이상(Apple SD Gothic Neo, Hiragino)으로 테스트해요.
- **Photoshop 규칙 추정:** §3의 규칙은 샘플 2개와 설치되지 않은 글꼴에서 얻었어요. 두 번째 샘플로 확인하기 전까지는 가설이에요.
- **Codex 작업과의 충돌:** 5단계는 Codex가 바꾼 코드 위에서 해야 해요. 순서를 지키지 않으면 같은 함수를 양쪽에서 고치게 돼요.

---

## 9. 열린 질문과 필요한 입력

- **두 번째 샘플 PSD(사용자 준비 중):**
  - 글꼴: 이 Mac에도 설치할 수 있는 글꼴. 예: 본고딕(Source Han Sans K / Noto Sans CJK KR). Adobe Fonts에도 있어요.
  - 레이어: 세로 **포인트** 텍스트 1개, 세로 **상자** 텍스트 1개, 각각 한글·영문·숫자를 섞어서. 가능하면 leading을 Auto와 짧은 값으로 하나씩.
  - 웹 Photoshop에 세로 문자 도구나 방향 전환 버튼이 있는지는 확인되지 않았어요. 없으면 기존 샘플의 세로 레이어를 열어 글꼴과 내용만 바꾸는 방법이 있어요. 이 경우 포인트 텍스트 샘플은 나오지 않아요.
- 세로 포인트 텍스트의 PSD 기준점 `(tx, ty)`가 첫 열의 어디인지(두 번째 샘플로 확인).
- 영문 세워 쓰기, 가로 짜기 같은 세로 옵션의 EngineData 키(두 번째 샘플로 확인).
- 앱에서 클릭으로 세로 포인트 텍스트를 시작할 때 Photoshop과 같은 위치에 놓이는지(§5.3, 가정).
