# Unified Mix Feature — Implementation Plan

## Context

The current creation flow has 5 separate full-screen pages (Text, Record, Photo, Import, Embed) in `Create/` and a viewer in `Viewer/`. Each create page instantiates its own `CreateMixViewModel`, duplicates title/save/toolbar patterns, and offers no preview before saving. The viewer lives in a completely separate folder with its own VM.

**This change merges everything into one `Presentation/Mix/` folder** with a single `MixViewModel` class, a unified creator page with tab-based mode switching, and the viewer alongside it. The creator becomes canvas-first — you see exactly what your mix will look like as you build it.

---

## Architecture Decisions

### MixViewModel: Coordinator with Value-Type Sub-States

One `@Observable @MainActor` class with two struct-based state containers:

```
MixViewModel
├── mode: .creating / .viewing
├── CreatorState (struct) — all creation-specific state
├── ViewerState (struct) — all viewing-specific state
├── Shared: title, tags, modelContext, mixType, errorMessage
├── AVPlayer + observers (reference types, top-level)
└── AudioPlaybackCoordinator (viewing only)
```

Structs mutated on an `@Observable` class trigger SwiftUI updates automatically. Separate instances created for creator vs viewer — they don't share state.

### Two-Phase Creator (not three)

- **`browsing`** — No content committed. Tab bar visible, mode-specific input UI shown. User switches modes freely.
- **`committed`** — Content exists. Tab bar hidden, canvas shows final preview, tags appear at bottom.

No separate `inputting` phase — whether the keyboard is up or a recording is in progress is local view state, not a VM phase.

### Creator Layout

```
ZStack {
    canvas (full-size, IS the creation surface)

    // Top chrome (floating, .position based):
    //   browsing: [X button] [Title chip center] [empty]
    //   committed: [X button] [Title chip center] [Create ↑ button]

    // Bottom (floating, .position based):
    //   browsing: CreatorTabBar (5 mode buttons)
    //   committed: Tag bar (same inline scrollable bar as viewer)
}
```

- **Create button** = small arrow (↑) at top-right, not a big bottom button
- **Title** = center chip, simple editable title (no auto-title sparkle for now)
- **Tags** = bottom bar in committed phase — inline scrollable tag chips (same `ViewerTagBar` pattern: selected tags shown as filled chips, "+" button to create new tags). Selected tag IDs are passed to `saveMix()` via `MixCreationRequest.selectedTagIds`. The creator already has full tag management (`loadTags`, `toggleTag`, `createNewTag`, `selectedTagIds`) in `CreateMixViewModel` — this moves into `MixViewModel` and is reused by the inline tag bar.
- **Tab bar** = bottom bar in browsing phase only

---

## File Structure

### New: `Presentation/Mix/`

| File | Contents | Source |
|------|----------|--------|
| `MixViewModel.swift` | Coordinator VM: `CreatorState` struct + `ViewerState` struct + all methods | `CreateMixViewModel.swift` + `MixViewerViewModel.swift` |
| `RecordAudioViewModel.swift` | Audio recording state machine (unchanged, just moved) | `Create/RecordAudioViewModel.swift` |
| `UnifiedCreatorView.swift` | Single creator page: canvas + floating chrome + tab bar + mode views | All 5 `Create*Page.swift` files + `CreateMixView.swift` |
| `CreatorModeViews.swift` | Per-mode input panels: `TextModeView`, `RecordModeView`, `GalleryModeView`, `ImportModeView`, `EmbedModeView` | Body content distilled from each Create*Page |
| `RecordingVisualsView.swift` | `LiveRecordingVisual`, `MicOrbView`, `WaveformBarsView`, `ReviewWaveformView`, `BlinkingModifier`, `ScaleButtonStyle` | `CreateRecordAudioPage.swift:583-931` |
| `TitleEditSheet.swift` | Simple title edit sheet (text field + done/cancel) | `MixViewerView.swift:371-418` private struct |
| `MixViewerView.swift` | Viewer (paging canvas + chrome + mini controls), updated to use `MixViewModel`. Add a save button for tag changes. | `Viewer/MixViewerView.swift` |
| `MixTagBar.swift` | Single tag bar used by both creator and viewer (renamed from `ViewerTagBar`) | Bottom of `Viewer/MixViewerView.swift` |
| `TagSelectionSheet.swift` | Tag selection/creation sheet (moved, updated VM ref) | `Create/TagSelectionSheet.swift` |
| `NewTagSheet.swift` | New tag input sheet (callback-based, no VM changes) | `Viewer/NewTagSheet.swift` |

### Stays in `Presentation/Components/`

- `MixCanvasView.swift` — shared rendering canvas, used by both creator and viewer
- `MixCanvasContent` — move from `CreateMixView.swift` into `MixCanvasView.swift` (it's the static-render sibling, used by `ScreenshotService`)
- All other shared components unchanged (EmbedCardView, AudioWaveView, LoopingVideoView, etc.)

### Deleted

- `Presentation/Create/` — entire folder
- `Presentation/Viewer/` — entire folder
- Files explicitly deleted: `CreateTextPage.swift`, `CreateRecordAudioPage.swift`, `CreatePhotoPage.swift`, `CreateURLImportPage.swift`, `CreateEmbedPage.swift`, `CreateMixView.swift`, `RecordAudioView.swift`, `EmbedLinkSheet.swift`, `ImportURLSheet.swift`

---

## Step-by-Step Implementation

### Step 1: Create MixViewModel

**File:** `App/MixerMind/Presentation/Mix/MixViewModel.swift`

Structure:
```swift
@Observable @MainActor
final class MixViewModel {
    enum Mode { case creating, viewing }
    let mode: Mode

    // Phase (creator only)
    enum CreatorPhase { case browsing, committed }
    var phase: CreatorPhase = .browsing

    enum CreatorMode: String, CaseIterable, Hashable {
        case text, record, gallery, importURL, embed
        var label: String { ... }
        var icon: String { ... }
    }
    var activeMode: CreatorMode = .text

    // Shared state
    var mixType: MixType = .text
    var title: String = ""
    var errorMessage: String?
    var modelContext: ModelContext?

    // Creator-specific state (struct)
    var creator = CreatorState()

    // Viewer-specific state (struct)
    var viewer = ViewerState()

    // Reference-type viewer state (can't be in struct)
    var videoPlayer: AVPlayer?
    private var loopObserver: Any?
    private var timeObserver: Any?
    let coordinator: AudioPlaybackCoordinator = resolve()

    // Tag state
    var selectedTagIds: Set<UUID> = []
    var allTags: [Tag] = []
    // ... tag methods (merged from both VMs)

    // MARK: - Creator Methods (from CreateMixViewModel)
    // loadPhoto, handleAudioFile, setRecordedAudio, importFromURL, setEmbedUrl,
    // saveMix, performCreate, performUpdate, compression methods, etc.

    // Creator convenience:
    func selectMode(_ mode: CreatorMode) { ... }
    func commitContent() { phase = .committed; set mixType from activeMode }
    func discardContent() { clear fields; phase = .browsing }

    // MARK: - Viewer Methods (from MixViewerViewModel)
    // onAppear, onDisappear, loadCurrentMix, startVideoPlayback,
    // togglePause, scrub, syncFromCoordinator, deleteCurrentMix, etc.
}
```

**CreatorState struct** — all value-type creation state:
- `textContent`, `photoData`, `photoThumbnail`, `videoData`, `videoThumbnail`
- `importSourceUrl`, `importMediaData`, `importAudioData`, `importThumbnail`
- `audioData`, `audioFileName`, `isAudioFromTTS`
- `embedUrl`, `embedOg`, `embedOgImageData`, `isFetchingOG`
- `isImportingURL`, `importProgress`, `isGeneratingTTS`, `isCreating`
- `selectedPhotoItem` (PhotosPickerItem)
- Tag-related: `selectedTagOrder`, `mixTagMap` (creator tag management)
- `editingMixId` (for edit mode)

**ViewerState struct** — all value-type viewing state:
- `mixes: [Mix]`, `scrolledID`, `activeID`
- `isScrubbing`, `wasPlayingBeforeScrub`, `tagsForCurrentMix`
- `isAutoScroll`, `videoProgress`, `pendingLoad`, `hasAppeared`, `isDeleting`

**Initializers:**
- `init(mode: .creating)` — fresh creator
- `init(mode: .creating, editing: Mix)` — edit existing mix
- `init(mode: .viewing, mixes: [Mix], startIndex: Int)` — viewer

### Step 2: Extract Recording Visuals

**File:** `App/MixerMind/Presentation/Mix/RecordingVisualsView.swift`

Move these from `CreateRecordAudioPage.swift` as-is (no API changes):
- `LiveRecordingVisual` (line 585)
- `MicOrbView` (line 608)
- `WaveformBarsView` (line 672)
- `ReviewWaveformView` (line 709)
- `BlinkingModifier` (line 908)
- `ScaleButtonStyle` (line 924)

### Step 3: Extract TitleEditSheet

**File:** `App/MixerMind/Presentation/Mix/TitleEditSheet.swift`

Simple title edit sheet from `MixViewerView.swift:371-418`. Just the text field + done/cancel toolbar. No auto-title logic.

### Step 4: Move MixCanvasContent to Components

Move `MixCanvasContent` from `CreateMixView.swift:6-94` into the bottom of `Components/MixCanvasView.swift`. Delete `TextInputSheet` from `CreateMixView.swift` (text editing is now inline on canvas).

### Step 5: Create CreatorModeViews

**File:** `App/MixerMind/Presentation/Mix/CreatorModeViews.swift`

Per-mode input panels rendered ON the canvas during `browsing` phase:

**TextModeView** — Gradient background + centered TextEditor with dynamic font scaling. Placeholder "Type something..." when empty. Keyboard toolbar with "Done". On done: if text non-empty → `commitContent()`.

**RecordModeView** — Idle: `MicOrbView` + record button. Recording: `LiveRecordingVisual` + timer + controls. Review: `ReviewWaveformView` + play/re-record/use. "Use" → `commitContent()`.

**GalleryModeView** — Placeholder prompt. `PhotosPicker` auto-presented by parent. After load → `commitContent()`.

**ImportModeView** — URL text field + Video/Audio download buttons on canvas. Progress during download. After download → `commitContent()`.

**EmbedModeView** — URL text field + Embed button. Spinner during fetch. After OG fetch → `commitContent()`.

### Step 6: Create UnifiedCreatorView

**File:** `App/MixerMind/Presentation/Mix/UnifiedCreatorView.swift`

Accepts `viewModel: MixViewModel` (already in `.creating` mode).

**Layout — mirrors MixViewerView's floating ZStack + .position() pattern:**

```swift
ZStack {
    // Layer 1: Canvas (full size)
    canvasLayer
        .frame(width: canvasSize.width, height: canvasSize.height)

    // Layer 2: Top chrome (floating)
    topChrome
        .position(x: canvasSize.width / 2, y: safeAreaTop + 36)

    // Layer 3: Bottom controls (floating)
    bottomControls
        .position(x: canvasSize.width / 2, y: canvasSize.height - bottomOffset)
}
```

**Canvas layer by phase:**
- `browsing`: Active mode's input view (from CreatorModeViews)
- `committed`: `MixCanvasView` showing the final preview (same as viewer would render)

**Top chrome:**
- Left: X button (dismiss/discard)
- Center: Title chip (tap to edit via TitleEditSheet)
- Right: Create button (↑ arrow) — only visible in `committed` phase

**Bottom controls:**
- `browsing`: `CreatorTabBar` — HStack of 5 mode buttons (glass effect, icons + labels)
- `committed`: Tag bar (same pattern as ViewerTagBar — scrollable tag chips + "+" button)

**X button behavior:**
- `browsing` with no content → `dismiss()` (back to home)
- `committed` → show discard alert → on confirm: `discardContent()` → back to `browsing` (stays in editor)

**Tab bar** (`CreatorTabBar` — inline in this file or a small private struct):
- HStack of 5 buttons: Text, Record, Gallery, Import, Embed
- Active mode: white. Inactive: white.opacity(0.4)
- `.glassEffect()` background, ~64pt height
- Animates in/out with `.transition(.move(edge: .bottom).combined(with: .opacity))`

### Step 7: Move Viewer Files

Move to `Presentation/Mix/`:
- `MixViewerView.swift` — update `@Bindable var viewModel: MixViewerViewModel` → `@Bindable var viewModel: MixViewModel`. Update all property access paths (e.g., `viewModel.mixes` → `viewModel.viewer.mixes`, `viewModel.videoPlayer` stays top-level).
- `MixTagBar` — extract `ViewerTagBar` from bottom of MixViewerView.swift, rename to `MixTagBar` in `MixTagBar.swift`, update to take `MixViewModel`. Used by both creator and viewer.
- `NewTagSheet.swift` — move as-is (callback-based, no VM dependency).

### Step 8: Move Remaining Files + TagSelectionSheet

- Move `RecordAudioViewModel.swift` to `Mix/`
- Move `TagSelectionSheet.swift` to `Mix/`, update to use `MixViewModel`

### Step 9: Update Home Navigation

**HomeViewModel.swift:**
```swift
enum HomeDestination: Hashable {
    case create(MixViewModel.CreatorMode)
}
```

**HomeView.swift navigation:**
```swift
.navigationDestination(for: HomeDestination.self) { dest in
    switch dest {
    case .create(let mode):
        let vm = MixViewModel(mode: .creating)
        vm.activeMode = mode
        UnifiedCreatorView(viewModel: vm)
    }
}
```

**FAB menu:** Keep 5 options, each appends `.create(.gallery)`, `.create(.importURL)`, `.create(.embed)`, `.create(.record)`, `.create(.text)`.

**Viewer:** HomeView creates `MixViewModel(mode: .viewing, mixes:..., startIndex:...)` for viewer overlay — same as before but using new VM type.

### Step 10: Delete Old Folders

Delete `Presentation/Create/` and `Presentation/Viewer/` entirely. Search project for any remaining references to old type names and fix.

---

## Tags in the Creator

The creator's tag flow mirrors the viewer's tag bar — an inline scrollable bar at the bottom of the canvas in the `committed` phase.

**How it works:**
1. When the creator enters `committed` phase, the bottom tab bar is replaced by `MixTagBar` — the same tag bar used by the viewer
2. `MixViewModel` holds `selectedTagIds: Set<UUID>`, `allTags: [Tag]`, and tag management methods (`loadTags`, `toggleTag`, `createNewTag`, `deleteTag`, `renameTag`) — merged from both old VMs
3. Tags load from SwiftData (`LocalTag`) on view appear via `loadTags()`
4. Tapping a tag chip toggles it (selected ↔ unselected). Selected tags fill visually.
5. The "+" button opens `NewTagSheet` (callback-based, creates tag + auto-selects it)
6. On save: `selectedTagIds` is passed to `MixCreationRequest` (line 811 pattern) and also to `tagRepo.setTagsForMix()` (line 1116 pattern)

**One tag bar for everything:** The current `ViewerTagBar` is renamed to `MixTagBar` and takes `@Bindable var viewModel: MixViewModel`. Both the creator (committed phase bottom) and the viewer use the exact same `MixTagBar`. No separate creator/viewer tag bars.

**Tag data in MixViewModel — identical for creator and viewer:**
- `allTags: [Tag]` — all available tags (loaded from SwiftData)
- `selectedTagIds: Set<UUID>` — currently selected tags
- `selectedTagOrder: [UUID]` — insertion order
- `mixTagMap: [UUID: Set<UUID>]` — mix→tags mapping (for frequency sorting)
- `toggleTag(_:)`, `createNewTag(name:)`, `renameTag(id:newName:)`, `deleteTag(id:)` — local-only mutations

**Tags are NOT persisted on each toggle.** In both creator and viewer, tag changes are local. They only persist when:
- **Creator:** tags are included in `saveMix()` as part of `MixCreationRequest.selectedTagIds`
- **Viewer:** a save button somewhere in the viewer UI triggers `tagRepo.setTagsForMix()` to persist the current selection

This replaces the current viewer behavior of fire-and-forget Supabase calls on every tag toggle.

---

## Phase Transition Rules

| From | Trigger | To |
|------|---------|-----|
| `browsing` | Text: "Done" on keyboard with non-empty text | `committed` |
| `browsing` | Record: tap "Use" after recording | `committed` |
| `browsing` | Gallery: photo/video loaded successfully | `committed` |
| `browsing` | Import: download completes | `committed` |
| `browsing` | Embed: OG fetch completes | `committed` |
| `committed` | X → discard alert → confirm | Reset → `browsing` (stay in editor) |
| `committed` | Create button (↑) | Save → dismiss to home |

---

## Critical Files Reference

| File | Role |
|------|------|
| `CreateMixViewModel.swift` | Source of all creation logic to merge |
| `MixViewerViewModel.swift` | Source of all viewing logic to merge |
| `MixViewerView.swift:38-55` | Reference for floating ZStack + .position() layout |
| `CreateRecordAudioPage.swift:583-931` | Recording visual components to extract |
| `CreateTextPage.swift:158-197` | Text canvas + dynamic font pattern to port |
| `HomeView.swift` | Navigation destinations + FAB menu to update |
| `HomeViewModel.swift:4-7` | HomeDestination enum to simplify |
| `MixCanvasView.swift` | Stays in Components/, used as committed-phase preview |
| `ScreenshotService.swift` | Unchanged — captures MixCanvasContent at save time |

---

## Verification

1. **Build:** `cd App && xcodebuild -project MixerMind.xcodeproj -scheme MixerMind -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
2. **Test each mode:** Text → type → Done → see preview → Create (↑). Record → record → Use → see audio waveform → Create. Gallery → pick → see media → Create. Import → URL → download → see video → Create. Embed → URL → fetch → see embed card → Create.
3. **Test tab switching** in browsing phase — no state leaks between modes
4. **Test discard:** committed → X → alert → Discard → back to browsing (stays in editor)
5. **Test X as back:** browsing, no content → X → dismissed to home
6. **Test tags:** committed phase → tag bar at bottom → add/remove tags
7. **Test title:** tap title chip → edit → done → title persists
8. **Test viewer:** still works with new MixViewModel — paging, playback, scrub, delete, tags
9. **Visual comparison:** committed canvas should match viewer canvas for same content
