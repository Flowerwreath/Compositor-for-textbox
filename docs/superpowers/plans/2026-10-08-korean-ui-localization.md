# UI 한국어화 구현 계획서

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOS 언어가 한국어일 때 Compositor의 UI에서 아이콘을 뺀, 글자가 보이는 곳이 모두 한국어로 보이게 해요. 영어 원문은 코드에 그대로 둬요.

**Architecture:** String Catalog(`Localizable.xcstrings`, `InfoPlist.xcstrings`)에 `ko` 번역을 넣어요. 문자열은 세 갈래로 처리해요.
- SwiftUI 리터럴은 컴파일러가 자동으로 추출해요.
- 반복되는 패턴은 함수 한 곳에서 번역해요. 화면 문자열을 받는 매개변수는 `LocalizedStringResource`로, enum은 `displayName`으로 바꿔요.
- 한 번씩 나오는 문자열만 `String(localized:)`로 감싸요.

컴파일러가 보지 못하는 키(enum rawValue, 단축키 제목)는 손으로 넣고 테스트로 지켜요.

**Tech Stack:** Swift 5 모드(Swift 6.2 컴파일러), SwiftUI와 AppKit, Swift Testing, Xcode 27 `xcodebuild`, Python 3(카탈로그 도구), Orca CLI(Codex 리뷰)

**Spec:** `docs/superpowers/specs/2026-10-08-korean-ui-localization-design.md`

## Global Constraints

- 영어 원문 리터럴은 코드에 그대로 둬요. 영어 문자열을 한국어로 직접 바꾸지 않아요.
- 저장되는 rawValue, Codable 키, UserDefaults 키, PSD 키, 식별자로 쓰는 문자열은 바꾸지 않아요.
- upstream 파일은 정의 쪽만 고치고, 호출하는 쪽은 가능한 한 그대로 둬요. 새 코드는 `Compositor/Localization/` 아래 새 파일에 둬요.
- 용어는 Photoshop 한국어판을 따라요. 기준 문서는 `docs/localization/glossary.md`예요(Task 9에서 만들어요).
- 다음은 번역하지 않아요:
  - 약어와 단위: RGB, HSL, px, %, DPI
  - 앱 이름 "Compositor"
  - 키보드 키 이름: Delete, Return, Esc, Tab, Space
  - 키 기호: ⌘⇧⌥⌃
- 테스트는 영어 로케일(`en`, `US`)에서 돌아요. 앱은 macOS 언어 설정을 따라요. 앱 안의 언어 전환 UI는 만들지 않아요.
- 한국어 값의 형식 지정자(`%@`, `%lld` 등)는 키와 종류·개수가 같아야 해요. 어순을 바꿀 때는 위치 지정자(`%1$@`)를 써요.
- 커밋 메시지는 이 저장소의 기존 스타일(영어 한 줄 요약)을 따르고, 끝에 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`을 붙여요.
- GitHub 쓰기 작업(push, PR)은 이 계획의 범위 밖이에요.

## Review Focus

1. **한국어가 고정 폭 라벨에서 잘리는 경우.** 예: `CameraRawColorControls`의 `.frame(width: 88)`, `.frame(width: 78)`. 한국어가 들어가도 라벨이 잘리거나 줄바꿈되지 않아야 해요. 테스트로 잡을 수 없어서 Task 16의 화면 QA 항목으로 넣었어요.
2. **제목으로 무언가를 찾는 코드.** 블렌드 모드 메뉴, 캔버스 크기 배경 옵션, 팔레트의 Window·Help 제외, 단축키 목록 검색은 한국어에서도 영어에서와 똑같이 동작해야 해요. 팔레트 제외는 Task 7의 테스트가 지켜요. 블렌드 모드와 캔버스 옵션은 Task 16의 화면 QA가 확인해요.
3. **형식 지정자가 있는 번역.** 예: `%@ × %@ px · sRGB`, `Save changes to %@?`. 값이 바뀌거나 빠지면 안 돼요. `scripts/l10n.py set`이 지정자를 검사해서 거부해요(Task 1). Task 16의 화면 QA에서도 확인해요.
4. **문서에 저장되는 문자열.** 한국어 UI에서 만든 프로젝트도 rawValue는 영어로 저장돼야 해요. 새 레이어의 기본 이름("레이어 1")과 텍스트 기본 내용("텍스트")이 한국어로 저장되는 것은 의도한 동작이에요. 기존 `ProjectTests`와 `PSDRoundTripTests`가 지켜요. Task 16에서 한국어 UI로 저장한 파일의 `blendMode` 값도 확인해요.
5. **명령 팔레트에 한글을 입력하는 경우.** 조합 중("흐ㄹ")에도 결과가 나오는지 확인해요(가설 H5). Task 16의 화면 QA에서 확인해요.

---

## 실행 방식

- **구현:** 이 세션의 Claude가 작업을 순서대로 구현해요(superpowers:executing-plans).
- **리뷰:** 작업마다 테스트가 통과하면, 커밋하기 전에 Orca orchestration으로 Codex CLI 리뷰어를 띄워 그 작업의 변경을 검토받아요. 리뷰어는 파일을 고치지 않고 보고서만 써요. 고치는 일은 Claude가 해요.
- **커밋:** 작업마다 리뷰를 반영한 뒤 1회 커밋해요. 사용자가 이 계획을 승인하면 이 커밋들을 요청한 것으로 봐요. push는 하지 않아요.
- **멈추는 곳:** Task 9(용어집)가 끝나면 사용자가 용어집을 검토할 때까지 멈춰요.
- **Codex 한도:** 2026-10-08 기준으로 이 Mac의 Codex 화면에 "weekly limit 5% 미만" 경고가 떠 있어요. 리뷰어를 띄우지 못하거나 리뷰어가 한도 오류를 보고하면, 리뷰 없이 진행하지 말고 멈춰서 사용자에게 물어요.

### 공통 변수와 명령

새 셸마다 다시 정해요. `S`는 이번 세션의 scratchpad예요.

```bash
REPO=/Users/shinminwoo/orca/workspaces/Compositor-for-textbox/fireworm
S=/private/tmp/claude-501/-Users-shinminwoo-orca-workspaces-Compositor-for-textbox-fireworm/df505f41-ff3f-4a58-8217-e7a0fe8c21dc/scratchpad
DD="$S/dd"
X() { DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "$REPO/Compositor.xcodeproj" -scheme Compositor -derivedDataPath "$DD" CODE_SIGN_IDENTITY=- "$@"; }
```

- `$DD`에는 Sparkle 패키지(`SourcePackages`)가 이미 복사돼 있어요. 없으면 다음 명령으로 복사해요. `cp -R ~/Library/Developer/Xcode/DerivedData/Compositor-*/SourcePackages "$DD/"`
- 빌드: `X -destination 'platform=macOS' build > "$S/build.log" 2>&1; tail -3 "$S/build.log"`
- 카탈로그 동기화: `X -exportLocalizations -localizationPath "$S/loc" -exportLanguage ko > "$S/sync.log" 2>&1; tail -2 "$S/sync.log"`
  - 소스의 `.xcstrings`를 **그 자리에서** 갱신해요. 새 키를 넣고, 안 쓰는 키는 `stale`로 표시해요.
  - 일반 `build`는 카탈로그 파일을 바꾸지 않아요(사전 확인 결과).
- 테스트 묶음 하나: `X -destination 'platform=macOS' test -only-testing:CompositorTests/<SuiteName> > "$S/test.log" 2>&1; tail -5 "$S/test.log"`
- 전체 테스트(5–8분): `X -destination 'platform=macOS' test -only-testing:CompositorTests > "$S/test-all.log" 2>&1; tail -5 "$S/test-all.log"`
- 실패 메시지는 로그에 없고 xcresult에 있어요. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun xcresulttool get test-results summary --path <로그 끝에 나온 .xcresult 경로>`
- 알려진 로컬 전용 실패 3건은 새 실패로 세지 않아요.
  - `SliderSnapTests.clickingTheTrackSnapsBeforeNativeTrackingBegins`
  - `TiledLayerTests.paintingAtTheLayersEdgeDoesNotChangeIt`
  - `CursorTests.leavingTheCanvasRestoresTheArrowWithEveryTool`
- 저장소를 탐색할 때는 `git grep`을 써요. hook이 Bash의 `grep`과 `cat`을 막을 수 있어요.

### 사전 확인 결과 (2026-10-08, 버린 worktree에서)

- **H2 확인됨:** `LocalizedStringResource` 매개변수로 넘긴 리터럴은 컴파일러가 추출해요. 삼항 연산자 안의 리터럴과 값이 끼는 문장(`"Spike \(n) Count"` → `Spike %lld Count`)도 추출돼요.
- **소스 위치:** 추출 결과는 소스 파일마다 `$DD/Build/Intermediates.noindex/Compositor.build/<구성>/Compositor.build/Objects-normal/arm64/<파일>.stringsdata`(JSON)에 남아요. 키와 소스 위치가 들어 있어요.
- **동기화 결과:** 빈 카탈로그에 `-exportLocalizations`를 돌리면 코드를 고치기 전에도 키가 499개 들어와요. 코드 문자열이 아닌 키(`""`, `"·"`, `"%lld"`, `"100%"` 등)도 섞여 있어요.
- **Info.plist:** `-exportLocalizations`는 Info.plist에서 문서 종류 이름도 뽑아요(`Compositor Project` 등 4개, `CFBundleName`, `NSHumanReadableCopyright`).

### Codex 리뷰 절차 (작업마다)

**처음 한 번(Task 1의 Step 1)**

```bash
cd "$REPO"
orca status --json
orca orchestration run-create --objective "UI 한국어화: 작업별 Codex 리뷰" --json   # 결과의 run id를 "$S/orca-run.txt"에 적어 둬요
EXCLUDE=$(git rev-parse --git-path info/exclude)          # 리뷰 보고서가 커밋되지 않게 이 저장소에서만 무시해요
mkdir -p "$(dirname "$EXCLUDE")"; touch "$EXCLUDE"
git check-ignore -q .l10n-reviews/probe || echo '.l10n-reviews/' >> "$EXCLUDE"
mkdir -p .l10n-reviews
```

**작업마다(각 Task의 "리뷰" 단계)**

1. `$S/review-NN.md`에 아래 서식으로 리뷰 요청을 써요. `NN`은 작업 번호, `<결과>`는 그 작업에서 돌린 명령과 결과 요약이에요.

```text
[리뷰 전용] UI 한국어화 구현 계획서 Task NN

Target: 저장소 /Users/shinminwoo/orca/workspaces/Compositor-for-textbox/fireworm (브랜치 Flowerwreath/fix-textbox-spec-issues). 커밋 안 된 변경 전체가 Task NN의 결과예요. `git status --short`, `git diff HEAD`, 새 파일을 보세요.
먼저 읽을 것: docs/superpowers/plans/2026-10-08-korean-ui-localization.md 의 "Global Constraints", "Review Focus", "Task NN", 그리고 docs/superpowers/specs/2026-10-08-korean-ui-localization-design.md.
Change: 코드, 카탈로그, 문서를 고치지 마세요. 찾은 것은 .l10n-reviews/task-NN.md 에만 써요.
확인할 것:
1. Task NN의 요구를 빠짐없이 했는지. 빠진 호출 지점이 있는지(`git grep`으로 직접 찾아보세요).
2. 정확성: 저장되는 값이나 식별자가 번역 경로에 들어갔는지, 형식 지정자 오류, 컴파일은 되지만 영어가 남는 경로, 동작이 바뀐 곳.
3. 범위 밖 변경, upstream 호출부를 불필요하게 고친 곳.
4. (번역 작업이면) docs/localization/glossary.md 와 다른 용어, 어색하거나 틀린 한국어, 문맥에 맞지 않는 번역.
Constraints: xcodebuild를 돌리지 마세요(이 Mac의 Codex 샌드박스에서 실패해요). Claude가 돌린 결과: <결과>
Report: 발견마다 한 줄씩 `- [high|medium|low] 파일:줄 — 문제 — 고칠 방법`. 없으면 "발견 없음". 한국어로 써요.
Acceptance: .l10n-reviews/task-NN.md 를 쓰고, worker_done 을 --outcome succeeded --report-path .l10n-reviews/task-NN.md 로 보내요.
```

2. 리뷰어를 띄우고 기다려요.

```bash
orca orchestration worker-start --worktree current --agent codex --spec "$(cat "$S/review-NN.md")" --json
orca orchestration check --wait --types "worker_done,escalation,question" --timeout-ms 900000 --json
```

3. 기다린 결과에 따라 처리해요.
   - `question`이면 `orca orchestration reply --id <message_id> --body "<답>" --json`으로 답하고 다시 기다려요.
   - `worker_done`이면 `.l10n-reviews/task-NN.md`를 읽어요.
   - 그다음 `orca orchestration worker-release --dispatch <dispatch_id> --json`, 이어서 `orca orchestration check --ack <delivery_id> --json` 순서로 처리해요.
   - 기다림이 세 번 연속 비면 `orca orchestration worker-list --include-remote --json`을 보고 그 행의 `projection.nextAction`을 따라요.
4. 발견을 하나씩 검증해요(superpowers:receiving-code-review).
   - 맞는 것은 고치고, 영향받은 확인 명령을 다시 돌려요.
   - 틀린 것은 이유와 함께 커밋 메시지 본문에 한 줄로 남겨요.
   - `high`를 고쳤으면 같은 절차로 재리뷰를 한 번 받아요. 요청문 첫 줄은 "[재리뷰] Task NN: 지난 보고서의 high 항목이 고쳐졌는지만"으로 써요.

---

## 파일 구조

| 파일 | 역할 | 작업 |
|---|---|---|
| `Compositor/Localizable.xcstrings` | 앱 문자열 카탈로그(en 원문 키 + ko) | 1, 이후 계속 |
| `Compositor/InfoPlist.xcstrings` | 문서 종류 이름 카탈로그 | 14 |
| `Compositor/Localization/L10n.swift` | 실행 중 조회(`L10n.text`), `LocalizedDisplayName`, 번호 붙은 이름 | 2 |
| `Compositor/Localization/DisplayNames.swift` | 화면 enum의 프로토콜 채택, 손으로 넣는 키 목록(`ManualKeys`) | 3, 6 |
| `Compositor/Localization/EnglishTitles.swift` | 팔레트 영어 검색용 역방향 사전 | 7 |
| `scripts/l10n.py` | 카탈로그 상태, 번역 적용, 수동 키, 소스별 키 목록 | 1 |
| `docs/localization/glossary.md` | 영→한 용어집 | 9 |
| `CompositorTests/LocalizationTests.swift` | 테스트 언어, 조회, 커버리지 테스트 | 1, 2, 10, 14, 15 |
| `CompositorTests/CommandPaletteTests.swift` | 팔레트 영어 검색, 메뉴 제외 테스트 추가 | 7 |
| `Compositor.xcodeproj/project.pbxproj` | `knownRegions`에 `ko` | 1 |
| `Compositor.xcodeproj/xcshareddata/xcschemes/Compositor.xcscheme` | 테스트 언어 고정 | 1 |
| 기존 Swift 파일 다수 | 작업별 목록 참고 | 3–8 |

---

### Task 1: 인프라 — 카탈로그, ko 지역, 테스트 언어 고정, 카탈로그 도구

**Files:**
- Create: `Compositor/Localizable.xcstrings`
- Create: `scripts/l10n.py`
- Create: `scripts/test_l10n.py` (리뷰 반영: 형식 인자·manual 검사)
- Create: `CompositorTests/LocalizationTests.swift`
- Modify: `Compositor.xcodeproj/project.pbxproj:198-201`
- Modify: `Compositor.xcodeproj/xcshareddata/xcschemes/Compositor.xcscheme` (TestAction)

**Interfaces:**
- Produces:
  - `scripts/l10n.py status|set|manual|symbols|where` (사용법은 아래 코드의 docstring)
  - 카탈로그 경로 `Compositor/Localizable.xcstrings`
  - 테스트 스위트 `LocalizationTests`

- [ ] **Step 1: 리뷰 준비.** 위 "Codex 리뷰 절차 → 처음 한 번"을 실행해요. run id를 `$S/orca-run.txt`에 적어요.

- [ ] **Step 2: 실패하는 테스트를 써요(가설 H1)**

`CompositorTests/LocalizationTests.swift`:

```swift
import Foundation
import Testing
@testable import Compositor

struct LocalizationTests {
    /// Tests compare English titles ("Flip Horizontal"), so they run in English even on a Mac set to Korean, while
    /// the app itself carries Korean.
    @Test func testsRunInEnglishWithKoreanAvailable() {
        #expect(Bundle.main.localizations.contains("ko"))
        #expect(Bundle.main.preferredLocalizations.first == "en")
    }
}
```

- [ ] **Step 3: 실패를 확인해요**

실행: `X -destination 'platform=macOS' test -only-testing:CompositorTests/LocalizationTests > "$S/test.log" 2>&1; tail -5 "$S/test.log"`
기대: `TEST FAILED`. 첫 번째 `#expect`가 실패해요(`ko` 없음).

- [ ] **Step 4: 카탈로그와 `ko` 지역을 추가해요**

`Compositor/Localizable.xcstrings`:

```json
{
  "sourceLanguage" : "en",
  "strings" : {

  },
  "version" : "1.0"
}
```

`Compositor.xcodeproj/project.pbxproj`의 `knownRegions`:

```
			knownRegions = (
				en,
				Base,
				ko,
			);
```

- [ ] **Step 5: `scripts/l10n.py`를 써요**

```python
#!/usr/bin/env python3
"""Helpers for Compositor's String Catalogs (Korean).

  scripts/l10n.py status [--list]
      Keys that still need Korean in Compositor/Localizable.xcstrings and Compositor/InfoPlist.xcstrings. Stale
      keys and keys marked do-not-translate don't count. Exits 1 while any remain.
  scripts/l10n.py set FILE.json
      Applies {"English key": "한국어", "Other key": null} to every catalog that holds each key; null marks the key
      do-not-translate. The Korean must read the same format arguments as the key, each as the same type (reorder
      them with numbered specifiers such as %2$@). Nothing is written if any pair fails.
  scripts/l10n.py manual KEY [KEY...]
      Adds keys the compiler can't see (enum raw values, shortcut titles) to Localizable.xcstrings, marked manual so
      syncs keep them.
  scripts/l10n.py symbols
      Marks keys with no letters ("%lld", "·", "100%") do-not-translate.
  scripts/l10n.py where DERIVED_DATA [PATH_PREFIX...] [--untranslated]
      Prints "file<TAB>key<TAB>korean" for keys used in source files starting with the prefixes, from the last
      build's .stringsdata files.

Run a catalog sync (xcodebuild -exportLocalizations) after `set`, `manual` or `symbols`; it rewrites the catalog in
Xcode's own layout.
"""
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOGS = [os.path.join(ROOT, "Compositor", name) for name in ("Localizable.xcstrings", "InfoPlist.xcstrings")]
# A printf-style specifier: optional argument number, flags (no space, so "50% off" isn't one), width, precision,
# length and conversion. "%%" is a literal percent sign. A "*" width or precision reads an argument of its own; it's
# captured so it can be refused.
SPECIFIER = re.compile(r"%(?:(\d+)\$)?[-+#0]*(\*|\d*)(?:\.(\*|\d+))?(hh|h|ll|l|q|z|t|j|L)?([@dDiuUxXoOfFeEgGaAcCsSp%])")


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def save(path, catalog):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2, separators=(",", " : "))
        f.write("\n")


def catalogs():
    return [(path, load(path)) for path in CATALOGS if os.path.exists(path)]


def korean(entry):
    unit = entry.get("localizations", {}).get("ko", {}).get("stringUnit", {})
    return unit.get("value") if unit.get("state") == "translated" else None


def needs_korean(entry):
    return entry.get("shouldTranslate", True) and entry.get("extractionState") != "stale" and korean(entry) is None


def arguments(text):
    """Every format argument `text` reads, as sorted (argument number, conversion) pairs, one per use; None when it
    numbers some arguments and not others, or uses a "*" width or precision."""
    found, unnumbered, numbered = [], 0, False
    for match in SPECIFIER.finditer(text):
        number, width, precision, length, conversion = match.groups()
        if conversion == "%":
            continue
        if width == "*" or precision == "*":
            return None
        if number is None:
            unnumbered += 1
            index = unnumbered
        else:
            numbered = True
            index = int(number)
        found.append((index, (length or "") + conversion))
    if numbered and unnumbered:
        return None
    return sorted(found)


def same_arguments(key, value):
    """True when `value` reads exactly the arguments `key` does, as often and each as the same type; numbered
    specifiers ("%2$@") may reorder them."""
    wanted = arguments(key)
    return wanted is not None and arguments(value) == wanted


def cmd_status(args):
    total = 0
    for path, catalog in catalogs():
        missing = [key for key, entry in catalog["strings"].items() if needs_korean(entry)]
        total += len(missing)
        print(f"{os.path.relpath(path, ROOT)}: {len(missing)} untranslated")
        if "--list" in args:
            for key in missing:
                print("  " + json.dumps(key, ensure_ascii=False))
    return 1 if total else 0


def cmd_set(args):
    pairs = load(args[0])
    loaded = catalogs()
    errors = []
    for key, value in pairs.items():
        # A key can be in both catalogs ("Compositor Project" is a document type and may be UI text too).
        found = [catalog["strings"][key] for _, catalog in loaded if key in catalog["strings"]]
        if not found:
            errors.append(f"not in any catalog (sync first, or add it with `manual`): {key!r}")
            continue
        if value is not None and not same_arguments(key, value):
            errors.append(f"format specifiers differ: {key!r} -> {value!r}")
            continue
        for entry in found:
            if value is None:
                entry["shouldTranslate"] = False
                entry.get("localizations", {}).pop("ko", None)
            else:
                entry.pop("shouldTranslate", None)
                entry.setdefault("localizations", {})["ko"] = {"stringUnit": {"state": "translated", "value": value}}
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    for path, catalog in loaded:
        save(path, catalog)
    print(f"set {len(pairs)} keys")
    return 0


def cmd_manual(args):
    path, catalog = catalogs()[0]
    added = 0
    for key in args:
        # An extracted or stale key is marked too: a run-time lookup still needs it after the literal that was
        # extracted goes away. Its translation stays.
        entry = catalog["strings"].setdefault(key, {})
        if entry.get("extractionState") != "manual":
            entry["extractionState"] = "manual"
            added += 1
    save(path, catalog)
    print(f"added {added} manual keys")
    return 0


def cmd_symbols(args):
    path, catalog = catalogs()[0]
    marked = 0
    for key, entry in catalog["strings"].items():
        if entry.get("shouldTranslate", True) and not any(ch.isalpha() for ch in SPECIFIER.sub("", key)):
            entry["shouldTranslate"] = False
            marked += 1
    save(path, catalog)
    print(f"marked {marked} keys do-not-translate")
    return 0


def cmd_where(args):
    untranslated = "--untranslated" in args
    args = [arg for arg in args if arg != "--untranslated"]
    derived, prefixes = args[0], args[1:]
    entries = {key: entry for _, catalog in catalogs() for key, entry in catalog["strings"].items()}
    pattern = os.path.join(derived, "Build/Intermediates.noindex/Compositor.build/*/Compositor.build/"
                                    "Objects-normal/*/*.stringsdata")
    rows = set()
    for data in glob.glob(pattern):
        info = load(data)
        source = os.path.relpath(os.path.realpath(info["source"]), os.path.realpath(ROOT))
        if source.startswith("..") or not os.path.exists(os.path.join(ROOT, source)):
            continue
        if prefixes and not any(source.startswith(prefix) for prefix in prefixes):
            continue
        for item in info["tables"].get("Localizable", []):
            entry = entries.get(item["key"], {})
            if untranslated and not needs_korean(entry):
                continue
            rows.add((source, item["key"], korean(entry) or ""))
    for source, key, value in sorted(rows):
        print(f"{source}\t{json.dumps(key, ensure_ascii=False)}\t{value}")
    return 0


def main():
    commands = {"status": cmd_status, "set": cmd_set, "manual": cmd_manual, "symbols": cmd_symbols,
                "where": cmd_where}
    if len(sys.argv) < 2 or sys.argv[1] not in commands:
        print(__doc__)
        return 2
    return commands[sys.argv[1]](sys.argv[2:])


if __name__ == "__main__":
    sys.exit(main())
```

`chmod +x scripts/l10n.py`

- [ ] **Step 6: 동기화하고 기호 키를 정리해요**

실행 순서:
1. 동기화 명령을 돌려요.
2. `python3 scripts/l10n.py symbols`
3. 동기화를 다시 돌려요.
4. `python3 scripts/l10n.py status`

기대: `Localizable.xcstrings: N untranslated`(N은 약 480–499). 파일 앞부분이 Xcode 형식(`"key" : {`)인지 확인해요.

- [ ] **Step 7: `ko` 번역을 하나 넣어 `ko.lproj`가 생기게 해요**

`$S/t1.json`:

```json
{ "Cancel" : "취소" }
```

실행: `python3 scripts/l10n.py set "$S/t1.json"`를 돌리고 동기화해요.
기대: `set 1 keys`. `Cancel` 키가 없다고 나오면 `python3 scripts/l10n.py status --list | head -40`에서 실제로 있는 짧은 버튼 문구 하나(예: `OK`)를 골라 대신 넣어요.

- [ ] **Step 8: 테스트 실패가 바뀌었는지 확인해요**

실행: Step 3과 같아요.
기대: 여전히 `TEST FAILED`예요. 이번에는 두 번째 `#expect`가 실패해요(`preferredLocalizations.first`가 `ko`). 이 Mac에서 테스트가 한국어로 돈다는 문제가 실제로 확인돼요.

- [ ] **Step 9: scheme의 테스트 언어를 고정해요**

`Compositor.xcscheme`의 `<TestAction` 여는 태그에 속성 두 개를 추가해요.

```xml
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      language = "en"
      region = "US"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
```

- [ ] **Step 10: 통과를 확인해요**

실행: Step 3과 같아요.
기대: `TEST SUCCEEDED`.

여전히 실패하면 가설 H1이 틀린 거예요. 그때는:
1. Step 9의 속성을 되돌려요.
2. 이 계획서의 모든 테스트 명령(`X ... test`)에 `-testLanguage en -testRegion US`를 붙여요. 이 파일의 "공통 변수와 명령"과 Task 16도 함께 고쳐요.
3. `.github/workflows/verify.yml`의 `xcodebuild ... test` 줄에도 같은 플래그를 붙여요.
4. 다시 돌려 통과를 확인해요.

- [ ] **Step 11: 기존 테스트 일부가 영어로 그대로 통과하는지 확인해요**

실행: `X -destination 'platform=macOS' test -only-testing:CompositorTests/TextFlipTests -only-testing:CompositorTests/CommandPaletteTests > "$S/test.log" 2>&1; tail -5 "$S/test.log"`
기대: `TEST SUCCEEDED`.

- [ ] **Step 12: 리뷰.** "Codex 리뷰 절차 → 작업마다"를 Task 01로 실행해요. 발견을 반영해요.

- [ ] **Step 13: 커밋**

```bash
git add Compositor/Localizable.xcstrings scripts/l10n.py CompositorTests/LocalizationTests.swift Compositor.xcodeproj/project.pbxproj Compositor.xcodeproj/xcshareddata/xcschemes/Compositor.xcscheme
git commit -m "Add a Korean string catalog; tests run in English"
```

H1의 대안을 썼다면 `verify.yml`도 함께 추가해요.

---

### Task 2: 조회 도구 — `L10n`, `LocalizedDisplayName`, 번호 붙은 이름

**Files:**
- Create: `Compositor/Localization/L10n.swift`
- Test: `CompositorTests/LocalizationTests.swift`

**Interfaces:**
- Produces:
  - `nonisolated enum L10n`
    - `static func text(_ english: String, bundle: Bundle = .main) -> String`
    - `static var koreanBundle: Bundle?`
    - `static func firstFreeName(_ name: (Int) -> String, avoiding taken: Set<String>) -> String`
  - `nonisolated protocol LocalizedDisplayName: RawRepresentable, CaseIterable where RawValue == String`
    - `static var displayKeys: [String] { get }`
    - 확장으로 `var displayName: String`

- [ ] **Step 1: 실패하는 테스트를 써요** (`LocalizationTests`에 추가)

```swift
    @Test func lookupFallsBackToTheEnglishKey() throws {
        let korean = try #require(L10n.koreanBundle)
        #expect(L10n.text("Cancel", bundle: korean) == "취소")
        #expect(L10n.text("Not a key in the catalog", bundle: korean) == "Not a key in the catalog")
        #expect(L10n.text("Cancel") == "Cancel", "tests run in English")
    }

    /// Names are made and checked through one closure, so "레이어 1" is skipped in Korean as "Layer 1" is in English.
    @Test func freeNamesSkipTakenOnesInTheSameLanguage() {
        #expect(L10n.firstFreeName({ "레이어 \($0)" }, avoiding: ["레이어 1", "Layer 2"]) == "레이어 2")
        #expect(L10n.firstFreeName({ "Layer \($0)" }, avoiding: []) == "Layer 1")
    }
```

Task 1의 Step 7에서 `Cancel` 대신 다른 키를 썼다면 여기서도 그 키와 그 한국어를 써요.

- [ ] **Step 2: 실패를 확인해요**

실행: `X -destination 'platform=macOS' test -only-testing:CompositorTests/LocalizationTests > "$S/test.log" 2>&1; tail -5 "$S/test.log"`
기대: 빌드 실패(`cannot find 'L10n' in scope`).

- [ ] **Step 3: 구현해요** (`Compositor/Localization/L10n.swift`)

```swift
import Foundation

/// Text whose English is known only at run time, such as an enum's stored raw value or a shortcut's title, looked up
/// in the string catalog. The compiler can't extract these keys, so they're added to the catalog by hand
/// (`scripts/l10n.py manual`), and `ManualKeys` lists them so a test can check each has Korean.
nonisolated enum L10n {
    /// The translation of `english` in `bundle`'s current language, or `english` itself when there's none.
    static func text(_ english: String, bundle: Bundle = .main) -> String {
        bundle.localizedString(forKey: english, value: english, table: nil)
    }

    /// The Korean translations, for tests that check the catalog while the app runs in English.
    static var koreanBundle: Bundle? {
        Bundle.main.path(forResource: "ko", ofType: "lproj").flatMap(Bundle.init(path:))
    }

    /// "Layer 1", "Layer 2", …: the first `name(n)` not in `taken`. Making and checking a name through the same closure
    /// keeps both in one language.
    static func firstFreeName(_ name: (Int) -> String, avoiding taken: Set<String>) -> String {
        var number = 1
        while taken.contains(name(number)) { number += 1 }
        return name(number)
    }
}

/// An enum the screen shows by name. Its raw value is English and stored in project files, so it's never translated
/// itself; `displayName` is what the screen shows.
nonisolated protocol LocalizedDisplayName: RawRepresentable, CaseIterable where RawValue == String {
    /// Every raw value, for the catalog check.
    static var displayKeys: [String] { get }
}

nonisolated extension LocalizedDisplayName {
    var displayName: String { L10n.text(rawValue) }
    static var displayKeys: [String] { allCases.map(\.rawValue) }
}
```

`nonisolated protocol`이나 `nonisolated extension`이 컴파일되지 않으면 `nonisolated`를 빼고 다시 빌드해요. 이 저장소는 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`예요. 그래서 빼고 나서 `nonisolated` 문맥(예: `nonisolated enum`의 메서드)에서 `displayName`을 쓰다가 오류가 나면, 그 호출부에서만 `L10n.text(x.rawValue)`를 써요.

- [ ] **Step 4: 통과를 확인해요**

실행: Step 2와 같아요.
기대: `TEST SUCCEEDED`.

- [ ] **Step 5: 리뷰.** Task 02로 리뷰 절차를 실행하고 반영해요.

- [ ] **Step 6: 커밋**

```bash
git add Compositor/Localization/L10n.swift CompositorTests/LocalizationTests.swift
git commit -m "Look up run-time English in the string catalog"
```

---

### Task 3: enum의 화면 이름 (설계 ③)과 블렌드 모드 메뉴

**Files:**
- Create: `Compositor/Localization/DisplayNames.swift`
- Modify:
  - `Compositor/UI/BrushControls.swift:12,19,26`
  - `Compositor/UI/CameraRawColorControls.swift:16,23,275,283,436`
  - `Compositor/UI/CameraRawControls.swift:132,137,190,232,248,373`
  - `Compositor/UI/CameraRawGeometryCalibrationControls.swift:13,39,98`
  - `Compositor/UI/CanvasSizeSheet.swift:75`
  - `Compositor/UI/CurvesControls.swift:11`
  - `Compositor/UI/FilterSheet.swift:73,189,238,252`
  - `Compositor/UI/GradientControls.swift:12,18`
  - `Compositor/UI/GridSettingsSheet.swift:59`
  - `Compositor/UI/ImageSizeSheet.swift:150`
  - `Compositor/UI/TransformInspector.swift:37` 근처
  - `Compositor/UI/BlendModePicker.swift:13,26,48,62,64`
  - `Compositor/UI/ColorRangeSheet.swift:18`, `Compositor/UI/HueSaturationSheet.swift:91`, `Compositor/UI/LevelsSheet.swift:112`
  - `Compositor/CompositorApp.swift:269,304`
  - `Compositor/Document/ColorPalette.swift:268-274`
  - `Compositor/Document/ShapeTool.swift:151-157`
  - `Compositor/Document/AdjustmentEditing.swift:59`, `Compositor/Document/LayerAdjustment.swift:200`, `Compositor/Document/Filters.swift:675`
  - 그 밖에 Step 1에서 찾는 곳

**Interfaces:**
- Consumes: Task 2의 `LocalizedDisplayName`, `L10n.firstFreeName`
- Produces: `nonisolated enum ManualKeys { static let displayNameTypes: [any LocalizedDisplayName.Type]; static var displayNames: [String] }`. Task 6에서 단축키 키를 추가하고, Task 15의 커버리지 테스트가 이 목록을 써요.

- [ ] **Step 1: rawValue를 화면에 보여 주는 곳을 전부 찾아요**

실행: `git grep -n "rawValue" -- Compositor/UI Compositor/CompositorApp.swift Compositor/ContentView.swift Compositor/Rendering > "$S/rawvalue.txt"; wc -l "$S/rawvalue.txt"`

각 줄을 다음 둘 중 하나로 분류해 `$S/rawvalue.txt` 옆에 메모해요.
- **화면 표시:** `Text(…rawValue)`, `addItem(withTitle:)`, `.accessibilityLabel`, `.help`, 문장에 끼는 보간
- **로직:** 비교, 저장, `init(rawValue:)`, 키

화면 표시인 곳의 enum 타입이 이 작업의 대상이에요. 사전 조사에서 찾은 타입은 아래와 같아요. Step 1에서 더 나오면 추가해요.

`AdjustmentKind`, `BackgroundQuality`, `BlurToolMode`, `BrushToolMode`, `CameraRawControls.Section`, `CameraRawCurvePage`, `CameraRawGlowStyle`, `CameraRawGradePage`, `CameraRawMixerPage`, `CameraRawMixerTab`, `CameraRawPointChannel`, `CameraRawProcessVersion`, `CameraRawProjection`, `CameraRawUprightMode`, `CameraRawVignetteStyle`, `CameraRawWhiteBalance`, `CanvasUnit`, `ColorRange`, `DitherColors`, `DitherPixelShape`, `DitherStyle`, `FilterKind`, `GradientShape`, `GradientStyle`, `GridAppearance.Preset`, `GridAppearance.Style`, `HueSampleMode`, `LayerBlendMode`, `LayerSampling`, `LevelsChannel`, `SelectionMode`, `ShapeKind`, `SpotHealingMode`, `WandMode`

`ColorPalette.swift:272`의 `kind` 타입도 정의를 찾아 확인해요(`git grep -n "case effect(" -- Compositor/Document/ColorPalette.swift`).

- [ ] **Step 2: 프로토콜을 채택하고 목록을 만들어요** (`Compositor/Localization/DisplayNames.swift`)

```swift
import Foundation

// Enums the screen shows by name. Their raw values stay English because project files store them; each case's Korean
// is a manual key in the catalog.
nonisolated extension AdjustmentKind: LocalizedDisplayName {}
nonisolated extension BackgroundQuality: LocalizedDisplayName {}
nonisolated extension BlurToolMode: LocalizedDisplayName {}
nonisolated extension BrushToolMode: LocalizedDisplayName {}
nonisolated extension CameraRawControls.Section: LocalizedDisplayName {}
nonisolated extension CameraRawCurvePage: LocalizedDisplayName {}
nonisolated extension CameraRawGlowStyle: LocalizedDisplayName {}
nonisolated extension CameraRawGradePage: LocalizedDisplayName {}
nonisolated extension CameraRawMixerPage: LocalizedDisplayName {}
nonisolated extension CameraRawMixerTab: LocalizedDisplayName {}
nonisolated extension CameraRawPointChannel: LocalizedDisplayName {}
nonisolated extension CameraRawProcessVersion: LocalizedDisplayName {}
nonisolated extension CameraRawProjection: LocalizedDisplayName {}
nonisolated extension CameraRawUprightMode: LocalizedDisplayName {}
nonisolated extension CameraRawVignetteStyle: LocalizedDisplayName {}
nonisolated extension CameraRawWhiteBalance: LocalizedDisplayName {}
nonisolated extension CanvasUnit: LocalizedDisplayName {}
nonisolated extension ColorRange: LocalizedDisplayName {}
nonisolated extension DitherColors: LocalizedDisplayName {}
nonisolated extension DitherPixelShape: LocalizedDisplayName {}
nonisolated extension DitherStyle: LocalizedDisplayName {}
nonisolated extension FilterKind: LocalizedDisplayName {}
nonisolated extension GradientShape: LocalizedDisplayName {}
nonisolated extension GradientStyle: LocalizedDisplayName {}
nonisolated extension GridAppearance.Preset: LocalizedDisplayName {}
nonisolated extension GridAppearance.Style: LocalizedDisplayName {}
nonisolated extension HueSampleMode: LocalizedDisplayName {}
nonisolated extension LayerBlendMode: LocalizedDisplayName {}
nonisolated extension LayerSampling: LocalizedDisplayName {}
nonisolated extension LevelsChannel: LocalizedDisplayName {}
nonisolated extension SelectionMode: LocalizedDisplayName {}
nonisolated extension ShapeKind: LocalizedDisplayName {}
nonisolated extension SpotHealingMode: LocalizedDisplayName {}
nonisolated extension WandMode: LocalizedDisplayName {}

/// Catalog keys the compiler can't see, so a test can check each has Korean.
nonisolated enum ManualKeys {
    static let displayNameTypes: [any LocalizedDisplayName.Type] = [
        AdjustmentKind.self, BackgroundQuality.self, BlurToolMode.self, BrushToolMode.self, CameraRawControls.Section.self,
        CameraRawCurvePage.self, CameraRawGlowStyle.self, CameraRawGradePage.self, CameraRawMixerPage.self,
        CameraRawMixerTab.self, CameraRawPointChannel.self, CameraRawProcessVersion.self, CameraRawProjection.self,
        CameraRawUprightMode.self, CameraRawVignetteStyle.self, CameraRawWhiteBalance.self, CanvasUnit.self,
        ColorRange.self, DitherColors.self, DitherPixelShape.self, DitherStyle.self, FilterKind.self, GradientShape.self,
        GradientStyle.self, GridAppearance.Preset.self, GridAppearance.Style.self, HueSampleMode.self,
        LayerBlendMode.self, LayerSampling.self, LevelsChannel.self, SelectionMode.self, ShapeKind.self,
        SpotHealingMode.self, WandMode.self,
    ]

    static var displayNames: [String] { displayNameTypes.flatMap { $0.displayKeys } }
}
```

Step 1에서 타입이 더 나오면 두 곳(채택 줄과 `displayNameTypes`)에 모두 추가해요. `ColorPalette.swift:272`의 effect 종류 타입도 여기에 포함돼요.

타입 이름이 위와 다르면 빌드 오류가 나요. 예를 들어 `ColorRange`가 실제로는 다른 이름의 중첩 타입일 수 있어요. 그때는 Step 1에서 찾은 `ForEach(…allCases)`의 정확한 타입 이름으로 바꿔요.

어떤 타입이 `CaseIterable`이 아니면 그 타입의 선언에 `CaseIterable`을 추가해요. 한 단어만 바꾸는 거예요.

`CameraRawControls.Section`은 `private`이에요. `CameraRawControls.swift:373`의 `private enum Section`을 `nonisolated enum Section`으로 바꿔요. 이 줄만 고쳐요.

- [ ] **Step 3: 화면 표시 지점을 바꿔요**

| 지금 | 바꾼 뒤 |
|---|---|
| `ForEach(X.allCases, id: \.self) { Text($0.rawValue).tag($0) }` | `ForEach(X.allCases, id: \.self) { Text($0.displayName).tag($0) }` |
| `Text(section.rawValue).font(.headline)` / `.accessibilityLabel(section.rawValue)` | `Text(section.displayName)…` / `.accessibilityLabel(section.displayName)` |
| `Button("\(kind.rawValue)…")` (`CompositorApp.swift:269,304`) | `Button("\(kind.displayName)…")` |
| `.accessibilityLabel("\(mode.rawValue) color")` | `.accessibilityLabel("\(mode.displayName) color")` |
| `.accessibilityLabel("Original \(settings.channel.rawValue) histogram")` | `.accessibilityLabel("Original \(settings.channel.displayName) histogram")` |
| `beginEdit("Edit \(original.kind.rawValue) Adjustment")` | `beginEdit("Edit \(original.kind.displayName) Adjustment")` |
| `beginEdit("New \(kind.rawValue) Adjustment")` | `beginEdit("New \(kind.displayName) Adjustment")` |
| `beginEdit(edit.kind.rawValue)` (`Filters.swift:675`) | `beginEdit(edit.kind.displayName)` (Task 4에서 `beginEdit(named:)`로 바꿔요) |

`ColorPalette.swift`의 `title`은 모든 경우를 감싸요.

```swift
    var title: String {
        switch self {
        case .text: return String(localized: "Color Picker (Text Color)")
        case .effect(let kind): return String(localized: "Color Picker (\(kind.displayName) Color)")
        case .palette(let background):
            return background ? String(localized: "Color Picker (Background Color)") : String(localized: "Color Picker (Foreground Color)")
```

나머지 경우(`dialog(title:)` 등)는 지금 코드 그대로 둬요. `dialog`의 `title`은 호출하는 쪽에서 오는 값이라 Task 8에서 봐요.

`ShapeTool.swift`:

```swift
    /// "Rectangle 1", "Ellipse 2", … skipping names already in the document.
    func nextShapeName(_ kind: ShapeKind) -> String {
        L10n.firstFreeName({ "\(kind.displayName) \($0)" }, avoiding: Set(document?.layers.map(\.name) ?? []))
    }
```

- [ ] **Step 4: 블렌드 모드 메뉴가 제목 대신 rawValue로 항목을 찾게 해요** (`BlendModePicker.swift`)

```swift
            for mode in group {
                button.addItem(withTitle: mode.displayName)
                button.lastItem?.representedObject = mode.rawValue
            }
```

`updateNSView`:

```swift
            button.selectItem(at: button.indexOfItem(withRepresentedObject: (session.activeLayer?.blendMode ?? .normal).rawValue))
```

`Coordinator`에 도우미를 하나 추가해요.

```swift
        private func mode(of item: NSMenuItem?) -> LayerBlendMode? {
            (item?.representedObject as? String).flatMap(LayerBlendMode.init(rawValue:))
        }
```

`willHighlight`의 `guard let mode = item.flatMap({ LayerBlendMode(rawValue: $0.title) })`는 `guard let mode = mode(of: item)`로 바꿔요.

`choose`도 바꿔요.

```swift
                  let mode = highlightedMode ?? mode(of: button.selectedItem) else { return }
            session.setLayerBlendMode(mode)
            button.selectItem(at: button.indexOfItem(withRepresentedObject: mode.rawValue))
```

- [ ] **Step 5: 빌드하고 관련 테스트를 돌려요**

실행: `X -destination 'platform=macOS' test -only-testing:CompositorTests/LayerAppearanceTests -only-testing:CompositorTests/BlendShortcutTests -only-testing:CompositorTests/ShapeToolTests -only-testing:CompositorTests/FilterTests -only-testing:CompositorTests/AdjustmentLayerTests -only-testing:CompositorTests/CameraRawTests -only-testing:CompositorTests/DitherTests -only-testing:CompositorTests/LocalizationTests > "$S/test.log" 2>&1; tail -5 "$S/test.log"`
기대: `TEST SUCCEEDED`. 영어 테스트에서는 `displayName == rawValue`라서 동작이 그대로예요.

- [ ] **Step 6: 남은 rawValue 표시가 없는지 확인해요**

실행: `git grep -n -E "Text\(\\\$0\.rawValue\)|withTitle: [a-z.]*rawValue|\\\\\([a-zA-Z.]*\.rawValue\)" -- Compositor/UI Compositor/CompositorApp.swift Compositor/ContentView.swift`
기대: 출력 없음. 남은 줄이 로직이면 Step 1 메모에 이유를 적어요.

- [ ] **Step 7: 리뷰.** Task 03으로 리뷰 절차를 실행하고 반영해요.

- [ ] **Step 8: 커밋**

```bash
git add -A Compositor/Localization Compositor/UI Compositor/CompositorApp.swift Compositor/Document
git commit -m "Show enums by display name, keeping stored raw values"
```

---

### Task 4: 화면 문자열을 받는 매개변수를 `LocalizedStringResource`로 (설계 ②)

**Files:**
- Modify: `Compositor/Document/EditorSession.swift:668-671`
- Modify: `Compositor/Document/BrushStroke.swift:167`
- Modify: `Compositor/Document/SelectionClipboard.swift:187,251`
- Modify: `Compositor/Document/EditorSession+Brush.swift:185`
- Modify: `Compositor/Document/LayerMerge.swift` (`plan.action` 정의, `:67`)
- Modify: `Compositor/Document/Filters.swift:675`
- Modify: 행 도우미가 있는 UI 파일들(아래 표)
- Modify: `Compositor/IO/ProjectController.swift:343` (`showError`)

**Interfaces:**
- Produces:
  - `func beginEdit(_ name: LocalizedStringResource)`: 리터럴 호출부는 그대로 컴파일되고 추출돼요.
  - `func beginEdit(named name: String)`: 이미 번역된 이름(예: `displayName`)을 넘길 때 써요.

- [ ] **Step 1: `beginEdit`을 바꿔요** (`EditorSession.swift`)

```swift
    /// Nestable transaction boundary; future tools can group a complete gesture. The name shows in Edit › Undo, so it's
    /// translated here, and literals passed in are extracted into the string catalog.
    func beginEdit(_ name: LocalizedStringResource) {
        beginEdit(named: String(localized: name))
    }

    /// For a name that's already translated, such as a filter's `displayName`.
    func beginEdit(named name: String) {
        history.begin(name, document: document, selection: activeLayerID)
    }
```

- [ ] **Step 2: 빌드해서 컴파일 오류 목록을 받아요**

실행: `X -destination 'platform=macOS' build > "$S/build.log" 2>&1; python3 -c "import sys;[print(l.rstrip()) for l in open(sys.argv[1]) if ': error:' in l]" "$S/build.log" | sort -u > "$S/errors.txt"; wc -l "$S/errors.txt"`

오류마다 아래 규칙으로 고쳐요.

| 오류 지점 | 고치는 법 |
|---|---|
| 리터럴로만 이뤄진 `String` 변수나 매개변수가 `beginEdit`으로 가는 곳: `editName: String`(`SelectionClipboard.swift:187,251`), `BrushStroke.editName: String?`, `commitRasterEdit(_:name: String)` | 타입을 `LocalizedStringResource`(옵셔널이면 `LocalizedStringResource?`)로 바꿔요. 기본값 리터럴(`= "Duplicate Layer"`)은 그대로 둬요 |
| 이미 번역된 `String`을 넘기는 곳: `beginEdit(edit.kind.displayName)`, `beginEdit(plan.action)` | `beginEdit(named: …)`로 바꿔요. `plan.action`의 정의 쪽 리터럴은 `String(localized: "Merge Down")`처럼 감싸요(이 값은 `NativeLayerList`의 메뉴 제목 `mergeTitle`에도 쓰여요) |
| `stroke.editName ?? (… ? "Paint Mask" : …)` | 타입만 바뀌면 그대로 컴파일돼요 |

- [ ] **Step 3: 행 도우미의 매개변수 타입을 바꿔요**

아래 함수들의 `title`, `label`, `name`, `help` 매개변수를 `String`에서 `LocalizedStringResource`로 바꿔요. 함수 본문은 이렇게 맞춰요.
- `Text(title)`: 그대로 둬요.
- `.help(help)`: `.help(Text(help))`
- `.accessibilityLabel(title)`: `.accessibilityLabel(Text(title))`
- 문자열 보간·비교·식별자로 쓰는 곳: `String(localized: title)`

| 파일:줄 | 함수 |
|---|---|
| `CameraRawColorControls.swift:120,124,306,400,469,488` | `amount`, `slider`, `colorSlider`, `pointSlider`, `wheel`, `slider` |
| `CameraRawControls.swift:295` | `slider` |
| `CameraRawDetailOpticsControls.swift:44,65,144,164` | `sharpenSlider`, `slider`, `opticsSlider`, `hueRange` |
| `CameraRawGeometryCalibrationControls.swift:65,124` | `geometrySlider`, `calibrationSlider` |
| `ColorPickerSheet.swift:124` | `channelRow` |
| `EffectsSheet.swift:170` | `slider` |
| `FilterSheet.swift:296,352` | `control`, `swatch` |
| `FloatingPanel.swift:35` | `show(title:)`. `NSPanel.title`에는 `String(localized: title)`을 넣어요 |
| `HueSaturationSheet.swift:125` | `slider`. `unit`도 화면 문구면 함께 바꿔요 |
| `LassoControls.swift:146` | `modifyControl` |
| `LevelsSheet.swift:89` | `field` |
| `NewCanvasSheet.swift:203` | `dimension` |
| `RawDevelopSheet.swift:78` | `slider` |
| `TransformInspector.swift:67` | `field` |
| `ProjectController.swift:343` | `showError(_ title:)`. `alert.messageText = String(localized: title)` |

호출부에서 `String` 변수를 넘겨 컴파일 오류가 나는 곳은 Task 8(전수 조사)의 규칙으로 처리해요. 그 자리가 화면 문구 리터럴에서 온 변수면 변수의 타입을 `LocalizedStringResource`로 바꾸고, 사용자 내용이면 `LocalizedStringResource(stringLiteral:)`를 쓰지 말고 도우미에 `verbatim` 오버로드를 하나 더 만들어요.

`.help`가 리터럴 대신 `String` 변수를 받던 줄 중 이 표에 없는 것(예: `CameraRawColorControls.swift:318`의 계산된 `help`)은 Task 8에서 처리해요.

- [ ] **Step 4: 빌드가 되는지 확인해요**

실행: Step 2의 빌드 명령을 다시 돌려요.
기대: `** BUILD SUCCEEDED **`, `$S/errors.txt` 0줄.

- [ ] **Step 5: 추출되는지 확인해요(실제 코드에서 H2 확인)**

실행: 동기화를 돌린 뒤 `python3 scripts/l10n.py where "$DD" Compositor/Document/EditorSession+Brush.swift Compositor/Document/SelectionClipboard.swift Compositor/UI/CameraRawControls.swift | head -40`
기대: `"Brush Stroke"`, `"Paste"`, `"Layer via Copy"`가 보이고, `CameraRawControls.swift`의 슬라이더 제목(예: `"Exposure"`)도 보여요.

- [ ] **Step 6: 관련 테스트를 돌려요**

실행: `X -destination 'platform=macOS' test -only-testing:CompositorTests/HistoryTests -only-testing:CompositorTests/BrushTests -only-testing:CompositorTests/LayerTests -only-testing:CompositorTests/SelectionClipboardTests -only-testing:CompositorTests/FilterTests -only-testing:CompositorTests/CameraRawSliderTests -only-testing:CompositorTests/HueSaturationTests -only-testing:CompositorTests/LevelsTests > "$S/test.log" 2>&1; tail -5 "$S/test.log"`
기대: `TEST SUCCEEDED`.

- [ ] **Step 7: 리뷰.** Task 04로 리뷰 절차를 실행하고 반영해요.

- [ ] **Step 8: 커밋**

```bash
git add -A Compositor Compositor/Localizable.xcstrings
git commit -m "Take user-facing names as LocalizedStringResource so they're extracted"
```

---

### Task 5: 한 번씩 나오는 AppKit 메뉴, 알림, 오류 문구 (설계 ⑤)

**Files:**
- Modify:
  - `Compositor/Rendering/EditorCanvas.swift:1719`
  - `Compositor/Rendering/InlineTextEditor.swift:196` 근처
  - `Compositor/UI/NativeLayerList.swift:119-220`
  - `Compositor/UI/ProjectTabs.swift` (`items`의 제목 정의, `:267` `projectTabOverflowLabel`)
  - `Compositor/UI/TypeControls.swift:200` 근처
  - `Compositor/Document/LiveLayerMask.swift:105-115`
  - `Compositor/IO/ProjectController.swift:330-340`
  - `Compositor/IO/ProjectController+ExternalChanges.swift:88-96`
  - `errorDescription`이 있는 9개 파일: `ContentFill`, `ImageTrim`, `MagicWand`, `ObjectSelection`, `SubjectRemoval`, `ImageExporter`, `ImageImporter`, `IO/PSD/PSDTypes`, `IO/ProjectStore`
  - `Compositor/Document/EditorSession.swift:99` (`tool.label`)

**Interfaces:**
- Consumes: Task 3의 `displayName`
- Produces: 없음(지점별 수정)

- [ ] **Step 1: AppKit 메뉴 제목을 감싸요**

리터럴은 `NSMenuItem(title: String(localized: "Duplicate Layer"), …)`처럼 감싸요. `deleteTitle`처럼 계산한 제목은 대입하는 곳마다 감싸요(`deleteTitle = String(localized: "Delete Mask")`).

텍스트 반전 메뉴(두 파일 모두):

```swift
        for (title, horizontal) in [(String(localized: "Flip Horizontal"), true), (String(localized: "Flip Vertical"), false)] {
```

`ProjectTabs`의 `items`와 `TypeControls:200`의 `multiple`은 정의를 찾아 화면 문구 리터럴을 같은 방식으로 감싸요.

- [ ] **Step 2: NSAlert 문구와 버튼을 감싸요**

```swift
        alert.messageText = String(localized: "Save changes to \(session.projectURL?.lastPathComponent ?? String(localized: "Untitled"))?")
        alert.informativeText = String(localized: "Your changes will be lost if you don’t save them.")
        alert.addButton(withTitle: String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let dontSaveButton = alert.addButton(withTitle: String(localized: "Don’t Save"))
```

같은 방식으로 감쌀 곳:
- `LiveLayerMask.swift:109-110`: 삼항 연산자는 양쪽 리터럴을 각각 감싸요. 버튼 3개도 감싸요.
- `ProjectController+ExternalChanges.swift:91-92`와 버튼 2개
- `ProjectController.swift`의 나머지 `addButton(withTitle:)`: `git grep -n "addButton(withTitle:" -- Compositor`로 남은 곳이 없는지 확인해요.

- [ ] **Step 3: 오류 문구를 감싸요**

`errorDescription`이 돌려주는 리터럴을 모두 `String(localized: "…")`로 감싸요. 예(`ImageTrim.swift`):

```swift
        case .noContentToTrim:
            return String(localized: "No content remained after trimming.")
        case .invalidDimensions:
            return String(localized: "The trimmed image dimensions are invalid.")
```

값이 끼는 문장도 같은 방식이에요. 예: `String(localized: "Couldn’t read \(name).")`

- [ ] **Step 4: 도구 이름(`tool.label`)을 감싸요** (`EditorSession.swift:99`)

삼항 연산자로 된 긴 줄은 그대로 두고, 앞의 선언만 바꿔요.

```swift
    var label: String { String(localized: labelResource) }
    private var labelResource: LocalizedStringResource { self == .type ? "Type (T)" : … 기존 줄의 나머지 그대로 … }
```

기존 줄의 `var label: String {`를 `private var labelResource: LocalizedStringResource {`로 바꾸고, 그 위에 `var label` 줄을 추가하는 거예요. 줄의 나머지는 건드리지 않아요.

- [ ] **Step 5: 빌드하고 남은 곳을 확인해요**

실행: 빌드한 뒤 아래 두 명령을 돌려요.
- `git grep -n -E 'NSMenuItem\(title: "|addButton\(withTitle: "|messageText = "|informativeText = "' -- Compositor`
- `git grep -n -E 'return "[A-Z]' -- Compositor/Document/ContentFill.swift Compositor/Document/ImageTrim.swift Compositor/Document/MagicWand.swift Compositor/Document/ObjectSelection.swift Compositor/Document/SubjectRemoval.swift Compositor/IO/ImageExporter.swift Compositor/IO/ImageImporter.swift Compositor/IO/PSD/PSDTypes.swift Compositor/IO/ProjectStore.swift`

기대: 빌드 성공. 두 명령 모두 출력 없음. 두 번째 명령에서 나온 줄이 `errorDescription`이 아니면 이유를 메모해요.

- [ ] **Step 6: 관련 테스트를 돌려요**

실행: `X -destination 'platform=macOS' test -only-testing:CompositorTests/TextFlipTests -only-testing:CompositorTests/ExternalChangeTests -only-testing:CompositorTests/ProjectTests -only-testing:CompositorTests/ImageTrimTests -only-testing:CompositorTests/LiveMaskTests -only-testing:CompositorTests/LayerMaskTests -only-testing:CompositorTests/ProjectTabLayoutTests -only-testing:CompositorTests/CursorTests > "$S/test.log" 2>&1; tail -5 "$S/test.log"`
기대: `TEST SUCCEEDED`. `CursorTests`의 알려진 간헐 실패는 제외해요.

- [ ] **Step 7: 리뷰.** Task 05로 리뷰 절차를 실행하고 반영해요.

- [ ] **Step 8: 커밋**

```bash
git add -A Compositor
git commit -m "Translate AppKit menus, alerts and error messages"
```

---

### Task 6: 식별자로도 쓰는 문자열과 기본 이름 (설계 ④)

**Files:**
- Modify: `Compositor/UI/KeyboardShortcuts.swift:45,177,243-246`
- Modify: `Compositor/UI/CanvasSizeSheet.swift:126`
- Modify: `Compositor/Localization/DisplayNames.swift` (`ManualKeys`)
- Modify: `Compositor/Document/EditorSession.swift:682-685,1007-1008`
- Modify: `Compositor/Document/SelectionClipboard.swift:268-273`
- Modify: `Compositor/Document/TypeTool.swift:12,575`

**Interfaces:**
- Consumes: `L10n.text`, `L10n.firstFreeName`, `ManualKeys`
- Produces:
  - `ManualKeys.shortcutNames: [String]`
  - `@MainActor ManualKeys.canvasExtensionChoices: [String]`
  - `CanvasSizeSheet.extensionChoices: [String]`

- [ ] **Step 1: 단축키 목록은 화면에서만 번역해요**

`KeyboardShortcuts.swift:243-246`:

```swift
                    ForEach(["Menus", "Canvas & Layers", "Text Editing"], id: \.self) { group in
                        Text(L10n.text(group)).font(.headline).padding(.top, 8)
                        ForEach(ShortcutDefinition.all.filter { $0.group == group && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || L10n.text($0.title).localizedCaseInsensitiveContains(search)) }) { definition in
                            HStack {
                                Text(L10n.text(definition.title))
```

충돌 메시지(`:177`):

```swift
            if let other = assigned[chord] {
                return String(localized: "\(chord.label) is assigned to both \(L10n.text(other)) and \(L10n.text(definition.title)).")
            }
```

`:45`의 키 이름(Delete, Return 등)은 전역 제약에 따라 그대로 둬요.

- [ ] **Step 2: 캔버스 크기의 배경 옵션** (`CanvasSizeSheet.swift`)

목록을 정적 상수로 빼고, 화면 표시만 번역해요. `switch`의 영어 비교는 그대로 둬요.

```swift
    /// What fills the added canvas. These English names are the picker's tags and what `fill` switches on.
    static let extensionChoices = ["Transparent", "Foreground", "Background", "Black", "White", "Custom"]
```

```swift
                ForEach(Self.extensionChoices, id: \.self) { Text(L10n.text($0)) }
```

- [ ] **Step 3: 손으로 넣을 키 목록에 추가해요** (`DisplayNames.swift`의 `ManualKeys`)

```swift
    /// Keyboard Shortcuts keeps titles and groups in English as ids; the list shows them translated.
    static var shortcutNames: [String] {
        Array(Set(ShortcutDefinition.all.flatMap { [$0.title, $0.group] } + ["Menus", "Canvas & Layers", "Text Editing"])).sorted()
    }

    @MainActor static var canvasExtensionChoices: [String] { CanvasSizeSheet.extensionChoices }
```

`ShortcutDefinition.all`이 MainActor 격리라 `nonisolated` 문맥에서 컴파일되지 않으면 `shortcutNames`에도 `@MainActor`를 붙여요.

- [ ] **Step 4: 기본 이름을 번역해요**

`EditorSession.swift:682-685`:

```swift
        let names = Set(document.layers.map(\.name))
        var layer = ImageLayer(name: L10n.firstFreeName({ String(localized: "Layer \($0)") }, avoiding: names), blankSize: document.size)
```

이 블록의 `var number`와 `while` 줄은 지워요.

`SelectionClipboard.swift:268-273`(`nextLayerName`)도 같은 형식이에요.

```swift
        return L10n.firstFreeName({ String(localized: "Layer \($0)") }, avoiding: names)
```

`EditorSession.swift:1007-1008`: `"Background"` 두 곳을 `String(localized: "Background")`로 바꿔요.

`TypeTool.swift:12`: `var content = String(localized: "Text")`

`TypeTool.swift:575`: `return flattened.isEmpty ? String(localized: "Text") : String(flattened.prefix(40))`

- [ ] **Step 5: 빌드하고 관련 테스트를 돌려요**

실행: `X -destination 'platform=macOS' test -only-testing:CompositorTests/LayerTests -only-testing:CompositorTests/SelectionClipboardTests -only-testing:CompositorTests/TypeToolTests -only-testing:CompositorTests/CanvasSizeTests -only-testing:CompositorTests/PSDRoundTripTests -only-testing:CompositorTests/LocalizationTests > "$S/test.log" 2>&1; tail -5 "$S/test.log"`
기대: `TEST SUCCEEDED`. 영어에서는 기본 이름이 "Layer 1", "Text" 그대로예요.

- [ ] **Step 6: 리뷰.** Task 06으로 리뷰 절차를 실행하고 반영해요.

- [ ] **Step 7: 커밋**

```bash
git add -A Compositor
git commit -m "Translate shortcut names, canvas fill choices and default names on screen only"
```

---

### Task 7: 명령 팔레트 — 영어 검색, 메뉴 제외, 도구 이름

**Files:**
- Create: `Compositor/Localization/EnglishTitles.swift`
- Modify:
  - `Compositor/UI/CommandPalette.swift:4-27`(항목), `:89-98`(순위), `:104-140`(메뉴 수집), `:175-226`(레이어 명령·도구)
  - `Compositor/UI/CommandPaletteView.swift:75,87`
- Test: `CompositorTests/CommandPaletteTests.swift`

**Interfaces:**
- Produces:
  - `nonisolated struct EnglishTitles`
    - `init(bundle: Bundle = .main)`
    - `init(table: [String: String])`
    - `func english(for title: String) -> String?`
    - `func english(forPath titles: [String]) -> String?`
  - `CommandPaletteEntry.englishTitle: String?`
    - init: `init(id:title:englishTitle:shortcut:isEnabled:isOn:perform:)`. `englishTitle`은 기본값 `nil`이에요.
  - `CommandPaletteMenu.entries(in:skipping:skippingMenus:english:)`
  - `CommandPaletteEntry.palettePath(_ parts: LocalizedStringResource...) -> (id: String, title: String)`

- [ ] **Step 1: 실패하는 테스트를 써요** (`CommandPaletteTests`에 추가)

```swift
    /// A Korean menu is still found by its English: "blur" finds 가우시안 흐림 효과, and so does "흐림".
    @Test func translatedEntriesAreFoundInEitherLanguage() {
        let english = EnglishTitles(table: ["Filter": "필터", "Gaussian Blur": "가우시안 흐림 효과",
                                            "Layer": "레이어", "Duplicate Layer": "레이어 복제"])
        #expect(english.english(forPath: ["필터", "가우시안 흐림 효과…"]) == "Filter › Gaussian Blur…")
        let blur = CommandPaletteEntry(id: "필터 › 가우시안 흐림 효과…",
                                       englishTitle: english.english(forPath: ["필터", "가우시안 흐림 효과…"]),
                                       shortcut: nil, isEnabled: true, perform: {})
        let duplicate = CommandPaletteEntry(id: "레이어 › 레이어 복제",
                                            englishTitle: english.english(forPath: ["레이어", "레이어 복제"]),
                                            shortcut: nil, isEnabled: true, perform: {})
        #expect(CommandPaletteSearch.rank([duplicate, blur], query: "blur").map(\.id) == [blur.id])
        #expect(CommandPaletteSearch.rank([duplicate, blur], query: "흐림").map(\.id) == [blur.id])
        #expect(CommandPaletteSearch.rank([blur, duplicate], query: "dup").first?.id == duplicate.id)
    }

    /// Running in English there's nothing to translate back, and search is as it was.
    @Test func withoutTranslationsThereIsNoEnglishPath() {
        let english = EnglishTitles(table: [:])
        #expect(english.english(forPath: ["Filter", "Gaussian Blur…"]) == nil)
        #expect(EnglishTitles(table: ["Same": "Same"]).english(for: "Same") == nil)
    }

    /// Window and Help are left out by menu, not by title, so they stay out once AppKit translates their titles.
    @Test func skippedMenusAreLeftOutWhateverTheirTitle() {
        let bar = NSMenu()
        for title in ["App", "편집", "윈도우"] {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title)
            submenu.addItem(NSMenuItem(title: "\(title) item", action: #selector(NSText.copy(_:)), keyEquivalent: ""))
            item.submenu = submenu
            bar.addItem(item)
        }
        let window = bar.items[2].submenu!
        let ids = CommandPaletteMenu.entries(in: bar, skipping: [], skippingMenus: [window]).map(\.id)
        #expect(ids == ["편집 › 편집 item"])
    }

    /// The menus skipped by identity are known to AppKit in the running app.
    @Test func appKitKnowsTheWindowAndHelpMenus() {
        #expect(NSApp.windowsMenu != nil)
        #expect(NSApp.helpMenu != nil)
    }
```

- [ ] **Step 2: 실패를 확인해요**

실행: `X -destination 'platform=macOS' test -only-testing:CompositorTests/CommandPaletteTests > "$S/test.log" 2>&1; tail -5 "$S/test.log"`
기대: 빌드 실패(`EnglishTitles` 없음, `englishTitle` 인자 없음).

- [ ] **Step 3: `EnglishTitles`를 구현해요** (`Compositor/Localization/EnglishTitles.swift`)

```swift
import Foundation

/// The English behind translated menu titles, so the command palette finds "필터 › 가우시안 흐림 효과…" by "blur" too.
nonisolated struct EnglishTitles {
    /// Translation → English key.
    private let english: [String: String]

    /// From `bundle`'s `Localizable.strings` in its current language; empty when the app runs in English.
    init(bundle: Bundle = .main) {
        guard let language = bundle.preferredLocalizations.first, language != "en",
              let path = bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil,
                                     forLocalization: language),
              let table = NSDictionary(contentsOfFile: path) as? [String: String] else {
            self.init(table: [:])
            return
        }
        self.init(table: table)
    }

    /// `table` maps English keys to translations, as a `.strings` file does. When two keys share a translation, the
    /// first in sorted order wins, so the result doesn't depend on dictionary order.
    init(table: [String: String]) {
        var english: [String: String] = [:]
        for key in table.keys.sorted() {
            guard let value = table[key], value != key, english[value] == nil else { continue }
            english[value] = key
        }
        self.english = english
    }

    /// One title in English: as it is, or without the trailing "…" a format such as "%@…" added.
    func english(for title: String) -> String? {
        if let key = english[title] { return key }
        if title.hasSuffix("…"), let key = english[String(title.dropLast())] { return key + "…" }
        return nil
    }

    /// A menu path in English, part by part, keeping parts that have no English; nil when no part has any.
    func english(forPath titles: [String]) -> String? {
        let parts = titles.map(english(for:))
        guard parts.contains(where: { $0 != nil }) else { return nil }
        return zip(titles, parts).map { $1 ?? $0 }.joined(separator: " › ")
    }
}
```

- [ ] **Step 4: 항목과 순위를 바꿔요** (`CommandPalette.swift`)

`CommandPaletteEntry`:

```swift
    /// Its path in English when the menus are translated, searched alongside `title` but never shown.
    let englishTitle: String?
```

```swift
    init(id: String, title: String? = nil, englishTitle: String? = nil, shortcut: String?, isEnabled: Bool,
         isOn: Bool = false, perform: @escaping @MainActor () -> Void) {
        self.id = id
        self.title = title ?? id
        self.englishTitle = englishTitle
```

`rank`의 점수 계산:

```swift
        let scored = entries.enumerated().compactMap { index, entry in
            [score(query, in: entry.title), entry.englishTitle.flatMap { score(query, in: $0) }]
                .compactMap { $0 }.max().map { (entry, $0, index) }
        }
```

- [ ] **Step 5: 메뉴 수집에 제외 메뉴와 영어 경로를 넘겨요**

```swift
    /// `skipping` holds titles left out: single items (the palette's own). `skippingMenus` leaves out whole menus
    /// (Window, Help) by identity, since AppKit translates their titles. The app menu, the first in the bar, is always
    /// left out.
    static func entries(in menu: NSMenu, skipping: Set<String>, skippingMenus: [NSMenu] = [],
                        english: EnglishTitles = EnglishTitles(table: [:])) -> [CommandPaletteEntry] {
        var seen: [String: Int] = [:]
        return collect(menu, root: menu, path: [], skipping: skipping, skippingMenus: skippingMenus, english: english,
                       seen: &seen)
    }
```

`collect`의 시그니처와 재귀 호출에 같은 두 인자를 추가해요. 제외 조건(`:121`) 바로 뒤에 한 줄을 넣어요.

```swift
            if let submenu = item.submenu, skippingMenus.contains(where: { $0 === submenu }) { continue }
```

항목을 만드는 곳(`:134-135`)에는 `englishTitle: english.english(forPath: titles),`를 추가해요.

- [ ] **Step 6: 팔레트 화면에서 넘겨요** (`CommandPaletteView.swift`)

```swift
    static var skipped: Set<String> { ["Search Commands…", String(localized: "Search Commands…"), "Window", "Help", "Services"] }
```

```swift
        let entries = (bar.map { CommandPaletteMenu.entries(in: $0, skipping: Self.skipped,
                                                            skippingMenus: [NSApp.windowsMenu, NSApp.helpMenu, NSApp.servicesMenu].compactMap { $0 },
                                                            english: EnglishTitles()) } ?? []) + CommandPaletteEntry.layerCommands(for: session)
```

- [ ] **Step 7: 코드에서 만든 항목(도구, 레이어 명령)을 번역해요** (`CommandPalette.swift:175-226`)

`CommandPaletteEntry` 확장에 경로 도우미를 하나 추가해요.

```swift
    /// A palette path from catalog keys: its English ("Tool › Lasso") as the id and search alias, its translation as
    /// the title.
    static func palettePath(_ parts: LocalizedStringResource...) -> (id: String, title: String) {
        (parts.map(\.key).joined(separator: " › "), parts.map { String(localized: $0) }.joined(separator: " › "))
    }
```

도구 목록의 튜플 첫 요소 타입을 `LocalizedStringResource`로 바꿔요(`let tools: [(LocalizedStringResource, String, NavigationTool, Setup?)]`). 리터럴 줄은 그대로 둬요. 항목은 이렇게 만들어요.

```swift
        return tools.map { name, key, tool, setup in
            let route = palettePath("Tool", name)
            return CommandPaletteEntry(id: route.id, title: route.title, englishTitle: route.id, shortcut: key,
                                       isEnabled: session.document != nil,
```

클로저 본문이 여러 줄이 되니 `return`을 붙여요. `perform:` 이하는 지금 코드 그대로예요.

레이어 명령도 같은 방식이에요. 예:

```swift
        let reveal = selected ? palettePath("Layer", "Add Layer Mask from Selection") : palettePath("Layer", "Add Layer Mask")
        let hide = selected ? palettePath("Layer", "Add Layer Mask Hiding Selection") : palettePath("Layer", "Add Layer Mask (Hide All)")
        return [
            CommandPaletteEntry(id: reveal.id, title: reveal.title, englishTitle: reveal.id, shortcut: nil, isEnabled: canAdd,
                                perform: { [weak session] in session?.addMask(revealing: true) }),
            CommandPaletteEntry(id: hide.id, title: hide.title, englishTitle: hide.id, shortcut: nil, isEnabled: canAdd,
                                perform: { [weak session] in session?.addMask(revealing: false) }),
        ]
```

`id`는 영어 그대로라 기존 테스트의 `id` 비교가 유효해요.

- [ ] **Step 8: 통과를 확인해요**

실행: Step 2와 같아요.
기대: `TEST SUCCEEDED`.

`appKitKnowsTheWindowAndHelpMenus`만 실패하면 SwiftUI가 `NSApp.helpMenu`를 정하지 않는다는 뜻이에요. 그때는:
1. `CommandPaletteView`에서 메뉴 막대의 마지막 최상위 항목(Help)의 `submenu`를 `skippingMenus`에 추가해요.
2. 그 테스트에서 `helpMenu` 검사를 빼요.
3. 이유를 테스트 주석에 적어요.

- [ ] **Step 9: 리뷰.** Task 07로 리뷰 절차를 실행하고 반영해요.

- [ ] **Step 10: 커밋**

```bash
git add Compositor/Localization/EnglishTitles.swift Compositor/UI/CommandPalette.swift Compositor/UI/CommandPaletteView.swift CompositorTests/CommandPaletteTests.swift
git commit -m "Find translated palette commands by their English too"
```

---

### Task 8: 남은 변수 문자열 전수 조사

**Files:**
- Modify: 조사 결과에 따라 `Compositor/` 아래 여러 파일

**Interfaces:**
- Consumes: Task 2–7의 모든 도구(`L10n.text`, `displayName`, `LocalizedStringResource` 매개변수, `ManualKeys`)

- [ ] **Step 1: 후보를 뽑아요**

```bash
cd "$REPO"
{
  git grep -n -E 'Text\([^"\)][^)]*\)' -- 'Compositor/*.swift'
  git grep -n -E '\.help\([^"T]' -- 'Compositor/*.swift'
  git grep -n -E 'accessibilityLabel\([^"T]' -- 'Compositor/*.swift'
  git grep -n -E '(Button|Toggle|Picker|Label|Menu|Section|TextField|navigationTitle)\([a-z][A-Za-z.]*[,)]' -- 'Compositor/*.swift'
  git grep -n -E '\.(title|stringValue|placeholderString|toolTip) = [a-z]' -- 'Compositor/*.swift'
} | sort -u > "$S/audit.txt"; wc -l "$S/audit.txt"
```

- [ ] **Step 2: 줄마다 분류하고 처리해요**

결과는 `$S/audit.md`에 `파일:줄 — 분류 — 처리`로 적어요.

| 분류 | 판단 기준 | 처리 |
|---|---|---|
| 사용자 내용·숫자·포맷된 값 | 레이어 이름, 파일 이름, 글꼴 이름, `NumberFormatter`나 `ByteCountFormatter` 결과, 좌표 | 그대로 둬요 |
| 리터럴에서 온 화면 문구 | 변수나 계산 속성이 결국 리터럴(삼항 포함)에서 와요 | 정의 쪽에서 `String(localized:)`로 감싸요. 매개변수면 타입을 `LocalizedStringResource`로 바꿔요 |
| enum rawValue | Task 3에서 놓친 것 | `displayName`으로 바꾸고, 타입을 `DisplayNames.swift`에 추가해요 |
| 식별자 겸용 | 같은 문자열을 비교·저장·태그에도 써요 | 화면 쪽에서만 `L10n.text(x)`로 바꾸고, 키를 `ManualKeys`에 목록으로 추가해요 |
| 값이 끼는 화면 문장 | 예: `CameraRawColorControls.swift:318`의 `"\(… .rawValue) of \(names[index])."` | `String(localized: "\(tab.displayName) of \(name).")`처럼 감싸요. 낀 값이 enum이면 `displayName`을 써요 |

`CameraRawMixerSettings.names`처럼 정적 배열로 된 화면 문구는 "식별자 겸용" 규칙을 따라요. 쓰는 곳에서 `L10n.text(name)`으로 바꾸고, 배열을 `ManualKeys`에 추가해요.

- [ ] **Step 3: 빌드하고 넓게 테스트해요**

실행: 빌드 → 동기화 → 전체 테스트(`$S/test-all.log`)
기대: 빌드 성공, 새 실패 0건(알려진 3건 제외).

- [ ] **Step 4: 리뷰.** Task 08로 리뷰 절차를 실행해요. 요청문의 `<결과>`에 `$S/audit.md`의 분류 요약(분류별 개수와 "그대로 둠"으로 분류한 줄 목록)을 넣어요. 리뷰어가 "그대로 둠" 분류를 검증하게 해요.

- [ ] **Step 5: 커밋**

```bash
git add -A Compositor
git commit -m "Route the remaining computed UI strings through the catalog"
```

---

### Task 9: 용어집 초안과 사용자 검토 (게이트)

**Files:**
- Create: `docs/localization/glossary.md`

- [ ] **Step 1: 자주 나오는 용어를 뽑아요**

실행: 동기화한 뒤 다음을 돌려요.

```bash
python3 -I -c "
import json, re, sys, collections
strings = json.load(open(sys.argv[1]))['strings']
words = collections.Counter()
for key, entry in strings.items():
    if entry.get('shouldTranslate', True) is False: continue
    for w in re.findall(r\"[A-Z][a-z]+(?: [A-Z][a-z]+)*\", key): words[w] += 1
for w, n in words.most_common(200): print(n, w)
" Compositor/Localizable.xcstrings > "$S/terms.txt"; head -60 "$S/terms.txt"
```

- [ ] **Step 2: 용어집을 써요**

`docs/localization/glossary.md`의 서식:

```markdown
# 영→한 용어집 (Photoshop 한국어판 기준)

Compositor를 한국어로 옮길 때의 기준이에요. 번역할 때 이 표를 먼저 봐요. 표에 없는 새 용어가 반복되면 여기에 추가해요.

## 원칙

- Photoshop 한국어판에 있는 용어는 그 번역을 따라요.
- 없는 용어는 Photoshop의 비슷한 기능에 맞춰 짓고, 비고에 "자체"라고 적어요.
- 번역하지 않는 것: RGB, HSL, px, %, DPI, Compositor, 키보드 키 이름(Delete, Return, Esc, Tab, Space)
- 메뉴 항목 끝의 "…"는 그대로 둬요.
- 버튼과 메뉴는 명사형이나 "~하기" 대신 Photoshop 한국어판처럼 짧은 명사구를 써요(예: "레이어 복제", "선택 해제").

## 일반

| 영어 | 한국어 | 비고 |
|---|---|---|
| Layer | 레이어 | |
...
```

절은 일반, 파일, 편집, 레이어, 선택, 도구, 문자, 필터·조정, 블렌드 모드, Camera Raw, 보기·안내선 순서로 나눠요. Step 1의 상위 용어를 모두 넣어요. 블렌드 모드 절은 아래 표로 시작해요(Photoshop 한국어판 기준).

| 영어 | 한국어 |
|---|---|
| Normal | 표준 |
| Darken | 어둡게 하기 |
| Multiply | 곱하기 |
| Color Burn | 색상 번 |
| Linear Burn | 선형 번 |
| Lighten | 밝게 하기 |
| Screen | 스크린 |
| Color Dodge | 색상 닷지 |
| Linear Dodge (Add) | 선형 닷지(추가) |
| Overlay | 오버레이 |
| Soft Light | 소프트 라이트 |
| Hard Light | 하드 라이트 |
| Vivid Light | 선명한 라이트 |
| Linear Light | 선형 라이트 |
| Pin Light | 핀 라이트 |
| Hard Mix | 하드 혼합 |
| Difference | 차이 |
| Exclusion | 제외 |
| Subtract | 빼기 |
| Divide | 나누기 |
| Hue | 색조 |
| Saturation | 채도 |
| Color | 색상 |
| Luminosity | 광도 |

기억에 의존한 번역 중 확신이 없는 것은 비고에 "확인 필요"라고 적어요. 사용자 검토에서 정해요.

- [ ] **Step 3: 리뷰.** Task 09로 리뷰 절차를 실행해요(Photoshop 한국어판과 다른 곳, 일관성). 반영해요.

- [ ] **Step 4: 사용자 검토 — 여기서 멈춰요.** 사용자에게 다음을 알려요.
  - 용어집 경로
  - "확인 필요" 항목 목록
  - 리뷰에서 바뀐 점

  사용자가 승인하거나 고칠 때까지 Task 10으로 넘어가지 않아요.

- [ ] **Step 5: 커밋(승인 뒤)**

```bash
git add docs/localization/glossary.md
git commit -m "Add the English-Korean glossary"
```

---

### 번역 묶음 공통 절차 (Task 10–15)

각 묶음 Task는 아래 단계를 따라요. `PREFIXES`는 묶음마다 정해요.

1. 빌드하고 동기화한 다음 아래 명령을 돌려요. 결과가 이 묶음의 번역 대상이에요.

   `python3 scripts/l10n.py where "$DD" $PREFIXES --untranslated > "$S/batch-NN.tsv"; wc -l "$S/batch-NN.tsv"`

2. `$S/batch-NN.json`에 `{"English key": "한국어"}`를 써요.
   - 용어집을 따라요.
   - 키의 형식 지정자를 그대로 유지해요. 어순을 바꾸려면 위치 지정자(`%1$@`, `%2$@`)를 써요.
   - 번역하지 않을 키는 값을 `null`로 써요.
   - 문맥이 애매하면 `batch-NN.tsv`의 파일 이름을 보고 그 줄의 코드를 읽어 확인해요.
3. `python3 scripts/l10n.py set "$S/batch-NN.json"`을 돌리고 동기화해요.
   - 기대: `set N keys`
   - 형식 지정자 오류가 나면 고쳐서 다시 돌려요.
4. 1번 명령을 다시 돌려 0줄인지 확인해요.
5. 묶음별 테스트가 있으면 돌려요.
6. 빌드해서 카탈로그가 컴파일되는지 확인해요.
7. 리뷰 절차를 실행해요. 요청문의 `<결과>`에 `$S/batch-NN.json`의 경로와 줄 수를 넣어요. 리뷰어가 그 JSON 파일을 직접 읽게 해요.
8. 커밋: `git add Compositor/Localizable.xcstrings`(필요하면 다른 파일도) → `git commit -m "Translate <묶음 이름> into Korean"`

### Task 10: 번역 — 메뉴 막대, 단축키 목록, 명령 팔레트

**Files:**
- Modify: `Compositor/Localizable.xcstrings`
- Test: `CompositorTests/LocalizationTests.swift`

`PREFIXES="Compositor/CompositorApp.swift Compositor/UI/KeyboardShortcuts.swift Compositor/UI/CommandPalette Compositor/UI/ProjectTabs Compositor/UI/ProjectWindowBridge"`

- [ ] **Step 1: 실패하는 커버리지 테스트를 써요** (`LocalizationTests`에 추가)

```swift
    /// Keyboard Shortcuts shows its English ids translated; every one needs Korean.
    @MainActor @Test func everyShortcutNameHasKorean() throws {
        let korean = try #require(L10n.koreanBundle)
        let missing = ManualKeys.shortcutNames.filter { L10n.text($0, bundle: korean) == $0 }
        #expect(missing.isEmpty, "add with scripts/l10n.py manual, then translate: \(missing)")
    }
```

- [ ] **Step 2: 실패를 확인해요.** `-only-testing:CompositorTests/LocalizationTests`로 돌려요. 실패 메시지(xcresult)에서 빠진 키 목록을 받아요.

- [ ] **Step 3: 손으로 넣을 키를 추가해요.** `python3 scripts/l10n.py manual <빠진 키들>`을 돌리고 동기화해요.

- [ ] **Step 4: 공통 절차 1–4를 실행해요.** 손으로 넣은 키는 `where`에 나오지 않아요. 그래서 이 키들도 `$S/batch-10.json`에 함께 넣어요.

- [ ] **Step 5: 테스트를 다시 돌려요.** 기대: `TEST SUCCEEDED`.

- [ ] **Step 6: 공통 절차 6–8을 실행해요.** 리뷰 번호는 Task 10, 커밋 메시지는 `Translate the menu bar, shortcuts and palette into Korean`이에요.

### Task 11: 번역 — 도구 바와 도구 옵션

**Files:**
- Modify: `Compositor/Localizable.xcstrings`

`PREFIXES="Compositor/ContentView.swift Compositor/UI/NavigationToolHeader Compositor/UI/ToolHeaderStyle Compositor/UI/TypeControls Compositor/UI/BrushControls Compositor/UI/LassoControls Compositor/UI/GradientControls Compositor/UI/ShapeControls Compositor/UI/CropControls Compositor/UI/TransformInspector Compositor/UI/ColorPaletteControls Compositor/UI/ColorPickerSheet Compositor/UI/NumericScrub Compositor/UI/SliderSnap"`

- [ ] **Step 1: 공통 절차 1–8을 실행해요.** 커밋 메시지는 `Translate the toolbar and tool options into Korean`이에요.

### Task 12: 번역 — 레이어 패널, 블렌드 모드, 마스크

**Files:**
- Modify: `Compositor/Localizable.xcstrings`

`PREFIXES="Compositor/UI/LayersPanel Compositor/UI/NativeLayerList Compositor/UI/LayerAppearanceControls Compositor/UI/LayerMaskMenu Compositor/UI/BlendModePicker Compositor/UI/EffectsSheet Compositor/UI/CanvasThumbnail Compositor/UI/FloatingPanel"`

- [ ] **Step 1: 공통 절차 1–8을 실행해요.** 블렌드 모드 이름은 enum이라 손으로 넣는 키예요. Task 15에서 다뤄요. 커밋 메시지는 `Translate the Layers panel into Korean`이에요.

### Task 13: 번역 — 필터와 조정 시트

**Files:**
- Modify: `Compositor/Localizable.xcstrings`

`PREFIXES="Compositor/UI/FilterSheet Compositor/UI/CameraRaw Compositor/UI/CurvesControls Compositor/UI/LevelsSheet Compositor/UI/HueSaturationSheet Compositor/UI/ColorRangeSheet Compositor/UI/RawDevelopSheet Compositor/UI/TrimSheet"`

- [ ] **Step 1: 공통 절차 1–8을 실행해요.** Camera Raw 용어는 용어집의 Camera Raw 절을 따라요. 커밋 메시지는 `Translate filter and adjustment sheets into Korean`이에요.

### Task 14: 번역 — 문서와 파일, 문서 종류 이름

**Files:**
- Create: `Compositor/InfoPlist.xcstrings`
- Modify: `Compositor/Localizable.xcstrings`
- Test: `CompositorTests/LocalizationTests.swift`

`PREFIXES="Compositor/UI/CanvasSizeSheet Compositor/UI/ImageSizeSheet Compositor/UI/NewCanvasSheet Compositor/UI/JPEGExportSheet Compositor/UI/PSDConversionSheet Compositor/UI/GridSettingsSheet Compositor/UI/CanvasRulers Compositor/IO"`

- [ ] **Step 1: 실패하는 테스트를 써요** (`LocalizationTests`에 추가)

```swift
    /// Canvas Size keeps its fill choices in English as tags; the picker shows them translated.
    @MainActor @Test func everyCanvasFillChoiceHasKorean() throws {
        let korean = try #require(L10n.koreanBundle)
        let missing = ManualKeys.canvasExtensionChoices.filter { L10n.text($0, bundle: korean) == $0 }
        #expect(missing.isEmpty, "add with scripts/l10n.py manual, then translate: \(missing)")
    }

    /// The save panel's format menu and Finder's Kind column show the document types' names.
    @Test func documentTypeNamesHaveKorean() throws {
        let korean = try #require(L10n.koreanBundle)
        let name = korean.localizedString(forKey: "Compositor Project", value: nil, table: "InfoPlist")
        #expect(name != "Compositor Project")
    }
```

- [ ] **Step 2: 실패를 확인해요.** 기대: 두 테스트 모두 실패해요.

- [ ] **Step 3: InfoPlist 카탈로그를 만들어요.**
  1. `Compositor/InfoPlist.xcstrings`를 Task 1 Step 4와 같은 빈 내용으로 만들어요.
  2. 동기화를 돌려요.
  3. `python3 scripts/l10n.py status`에 `Compositor/InfoPlist.xcstrings` 줄이 나오는지 확인해요.
  4. 문서 종류 이름 4개(`Compositor Project`, `Compositor Layer`, `Adobe Photoshop Document`, `Adobe Photoshop Large Document`)를 번역해요. 목록에 `Images`(Info.plist의 `CFBundleTypeName`)가 나오면 그것도 번역해요.
  5. `CFBundleName`과 `NSHumanReadableCopyright`는 `null`(번역 안 함)로 둬요.

- [ ] **Step 4: 공통 절차 1–4를 실행해요.** 손으로 넣을 배경 옵션 키는 `python3 scripts/l10n.py manual Transparent Foreground Background Black White Custom`으로 먼저 추가하고 함께 번역해요.

- [ ] **Step 5: 테스트를 다시 돌려요.** 기대: `TEST SUCCEEDED`.

- [ ] **Step 6: 공통 절차 6–8을 실행해요.** `git add`에 `Compositor/InfoPlist.xcstrings`도 넣어요. 커밋 메시지는 `Translate document and file screens into Korean`이에요.

### Task 15: 번역 — 실행 취소 이름, 오류, 기본 이름, enum 이름(나머지 전부)

**Files:**
- Modify: `Compositor/Localizable.xcstrings`
- Test: `CompositorTests/LocalizationTests.swift`

`PREFIXES="Compositor"` (남은 모든 파일)

- [ ] **Step 1: 실패하는 커버리지 테스트를 써요** (`LocalizationTests`에 추가)

```swift
    /// Every enum the screen shows by name has Korean for every case, so a case added upstream fails here instead of
    /// showing up in English.
    @Test func everyDisplayNameHasKorean() throws {
        let korean = try #require(L10n.koreanBundle)
        // Names that read the same in Korean (marked do-not-translate in the catalog).
        let sameInKorean: Set<String> = ["RGB", "HSL", "ASCII"]
        let missing = Array(Set(ManualKeys.displayNames.filter {
            !sameInKorean.contains($0) && L10n.text($0, bundle: korean) == $0
        })).sorted()
        #expect(missing.isEmpty, "add with scripts/l10n.py manual, then translate: \(missing)")
    }
```

- [ ] **Step 2: 실패를 확인하고 빠진 키를 받아요.** 그 키들로 `python3 scripts/l10n.py manual …`을 돌리고 동기화해요.

- [ ] **Step 3: 공통 절차 1–4를 실행해요.** 손으로 넣은 enum 키도 같은 JSON에 넣어요.

  원문 그대로 두는 이름(예: RGB, HSL, ASCII)은 JSON 값을 `null`로 써요. 그리고 테스트의 `sameInKorean`이 이 키들과 정확히 같은지 맞춰요. 키를 빼거나 더하면 둘을 함께 고쳐요.

- [ ] **Step 4: 전체 상태가 0인지 확인해요.** `python3 scripts/l10n.py status` → 기대: 두 카탈로그 모두 `0 untranslated`, 종료 코드 0. 남으면 `--list`로 보고 같은 절차로 처리해요.

- [ ] **Step 5: 테스트를 다시 돌려요.** `LocalizationTests`를 돌려요. 기대: `TEST SUCCEEDED`.

- [ ] **Step 6: 공통 절차 6–8을 실행해요.** 커밋 메시지는 `Translate undo names, errors, default names and enum names into Korean`이에요.

---

### Task 16: 최종 검증, 설치, 화면 QA, 전체 리뷰

**Files:**
- 고칠 게 나오면 해당 파일과 카탈로그

- [ ] **Step 1: 전체 테스트(영어 로케일)**

실행: 전체 테스트 명령. 결과: `$S/test-all.log`, xcresult 요약.
기대: 새 실패 0건(알려진 3건 제외). 실행 횟수와 테스트 케이스 수를 따로 기록해요.

- [ ] **Step 2: 카탈로그 상태.** `python3 scripts/l10n.py status` → 기대: 종료 코드 0.

- [ ] **Step 3: Release 빌드와 설치**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "$REPO/Compositor.xcodeproj" -scheme Compositor \
  -configuration Release -destination 'platform=macOS' -derivedDataPath "$DD" build \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO > "$S/release.log" 2>&1; tail -2 "$S/release.log"
ls "$DD/Build/Products/Release/Compositor.app/Contents/Resources/ko.lproj"
```

기대: `Localizable.strings`, `InfoPlist.strings`가 있어요.

설치 순서:
1. Compositor가 실행 중이면(`pgrep -lf Compositor.app`) 사용자에게 ⌘Q를 부탁하고 기다려요. 강제로 끄지 않아요.
2. 기존 앱을 휴지통으로 옮겨요. `mv /Applications/Compositor.app ~/.Trash/Compositor-before-korean.app`
3. 새 앱을 복사해요. `ditto "$DD/Build/Products/Release/Compositor.app" /Applications/Compositor.app`

- [ ] **Step 4: 화면 QA (한국어)**

`computer-use` 스킬로 앱을 열고, 화면 묶음마다 스크린샷을 찍어 `$S/qa/`에 저장해요. 영어가 남은 곳, 잘린 라벨, 동작 이상을 `$S/qa.md`에 적어요.

| 묶음 | 열어 볼 화면 |
|---|---|
| 메뉴 막대·단축키·팔레트 | 모든 최상위 메뉴; 단축키 창; 팔레트에서 "blur", "흐림", "흐ㄹ"(조합 중) 입력 결과(H5); 팔레트에 윈도우·도움말 항목이 없는지 |
| 도구 | 각 도구를 고르고 도구 옵션 바; 도구 툴팁 2–3개 |
| 레이어 | 레이어 패널, 우클릭 메뉴, 블렌드 모드 메뉴(고르면 실제로 바뀌는지), 효과 시트, 새 레이어 이름("레이어 1") |
| 필터·조정 | 가우시안 흐림 효과, Camera Raw(모든 섹션 펼치기, 라벨 잘림 확인), 곡선, 레벨, 색조/채도 |
| 문서·파일 | 새 캔버스, 캔버스 크기(배경 옵션을 바꾸면 실제 색이 바뀌는지), 이미지 크기, 저장 알림(수정 후 닫기), 저장 패널의 형식 이름 |
| 그 밖 | Edit 메뉴의 "실행 취소 …" 이름(브러시 한 획 뒤), 오류 하나(빈 선택으로 내용 인식 채우기), 업데이트 확인 창(Sparkle, H4), 시스템 설정 → 일반 → 언어 및 지역 → 응용 프로그램 목록에서 Compositor 선택 가능 여부(H3) |

저장 값 확인(Review Focus 4):
1. 한국어 UI에서 블렌드 모드를 곱하기로 바꾼 레이어가 있는 프로젝트를 `$S/qa/ko.comp`로 저장해요.
2. 파일 안의 블렌드 모드 값이 `Multiply`인지 확인해요. 형식은 `docs/project-format.md`를 보고, 압축 여부에 맞게 읽어요.

- [ ] **Step 5: QA에서 나온 문제를 고쳐요.** 문제가 속한 묶음의 규칙으로 고쳐요. 고친 뒤에는 관련 테스트와 `status`를 다시 돌리고, 해당 화면만 다시 확인해요.

- [ ] **Step 6: 브랜치 전체 리뷰.** 리뷰 절차를 "Task 16(브랜치 전체)"로 실행해요. 요청문의 Target은 `git diff dccc11d..HEAD`, `<결과>`는 Step 1–5의 결과 요약이에요.

- [ ] **Step 7: 커밋(고친 것이 있을 때만)**

```bash
git add -A Compositor CompositorTests scripts docs/localization
git commit -m "Fix issues found in Korean UI QA"
```

- [ ] **Step 8: 정리.**
  - `orca orchestration worker-list --run "$(cat "$S/orca-run.txt")" --terminal-state reclaimable --json`가 비었는지 확인해요.
  - 사용자에게 결과를 보고해요. 확인한 것과 확인하지 못한 것, H1–H5 결과, 남은 문제를 나눠서 알려요.
