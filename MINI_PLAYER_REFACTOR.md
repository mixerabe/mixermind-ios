# Mini Player & Viewer — Architecture Rules

## Golden Rule: Position-Based Floating Layout

Every view is a **known-size rectangle** placed at an **absolute screen position** using `.position(x:y:)`. No alignment, no padding for positioning, no safe area tricks. You know the size, you do the math, you place it.

```
Fullscreen: .position(x: canvasW/2, y: canvasH/2)     — top edge at y=0
Mini:       .position(x: miniTargetPosition.x/y)       — corner position
Dragging:   .scaleEffect(dragScale) + .offset(dragOffset) on top of position
```

---

## How It Works

### Canvas Sizing
- **Width** = screen width (edge to edge)
- **Height** = width * (17/9) aspect ratio
- These are exact pixel dimensions, computed once

### Placement
- `.frame(width:height:)` gives the view its fixed size
- `.position(x:y:)` places its center at absolute coordinates
- To pin top edge to screen top: `position(y: height / 2)`
- Safe area insets come from `UIApplication.shared.connectedScenes` window, passed as parameters

### State Transitions
- **Drag**: only `scaleEffect` and `offset` change — no frame changes mid-gesture
- **Commit to mini**: `isViewerExpanded = false` triggers animated snap to mini position/scale
- **Frame clip height** changes at the same moment as state transition (not during drag)

---

## Rules That Prevent Flickering

### 1. NEVER change `.frame()` during a drag

During a drag, only change `scaleEffect` and `offset`. Frame changes cause layout thrashing and scroll position jumps.

### 2. NEVER use `.containerRelativeFrame` on scaled content

It sizes to the container. Container changes cause cascading relayout. Use explicit fixed sizes.

### 3. Use `.position()` not `.offset()` for resting positions

`.offset()` is reserved for the drag system only. Resting positions use `.position(x:y:)` with absolute coordinates. This prevents jump-on-drag-start bugs.

### 4. MixViewerView is a dumb box

MixViewerView has **no internal `.position()`**, **no `.ignoresSafeArea()`**, **no layout opinions**. HomeView gives it a frame, clips it, scales it, offsets it, and positions it. Like a yellow rectangle.

### 5. Independent layers are siblings, not children

Tag bar and mini controls are NOT inside a VStack with the canvas. They're independent floating elements:
- **Tag bar** (`ViewerTagBar`): sibling in HomeView ZStack, positioned at `screenHeight - safeAreaBottom - 22`
- **Mini controls**: inside MixViewerView but sized to `miniVisibleCanvasHeight`, not the full canvas

### 6. One view for both states (no if/else branches)

Fullscreen and mini are the same `MixViewerView` instance with conditional modifiers. SwiftUI can animate between states because the view identity doesn't change.

---

## Mini Controls Strategy

Mini controls (dismiss, play/pause, prev/next) live **inside** MixViewerView as big buttons:
- ~70-80pt frames in canvas coordinates
- At mini scale (~0.35x), they become ~24-28pt — proper mini size
- **Invisible** in fullscreen (`opacity: 0` when `!isMinimized`)
- **Visible** in mini (`opacity: 1` when `isMinimized`)
- Sized to `miniVisibleCanvasHeight` (not full canvas) so they respect the crop clip
- Bottom padding is proportional (`miniVisibleCanvasHeight * 0.05`) so spacing looks the same regardless of crop

No counter-scaling needed. They just naturally shrink with the viewer.

---

## Mini Card Cropping

Each mix has `previewScaleX` / `previewScaleY` crop values. The mini card height varies per mix:

```swift
let sx = mix.previewScaleX ?? 1.0
let sy = mix.previewScaleY ?? 1.0
let aspectRatio = (390.0 / sx) / (844.0 / sy)
currentMiniCardHeight = miniCardWidth / aspectRatio
```

In HomeView, a second `.frame(height:)` with `.clipped()` (center alignment) crops equally from top and bottom when mini. The full canvas stays the same size — only the visible portion changes.

---

## Chrome Behavior

- **Top chrome** (minimize, title, menu): positioned at `y: safeAreaTop + 22` inside MixViewerView
- **Buttons have `.glassEffect(in: .circle)`** for proper glass design
- **Fade with drag**: `opacity = max(1 - dragProgress * 3, 0)` — disappears in first third of drag
- **Pause/mute overlay** in MixCanvasView also fades with the same formula via passed `dragProgress`

---

## Black Backdrop

`Color.black` between NavigationStack and viewer:
- `opacity = viewerDragScale` when expanded (fades with drag)
- `opacity = 0` when mini (fully transparent)
- zIndex 9 (below viewer at 10)

---

## Architecture

```
HomeView ZStack:
  ├── NavigationStack (home grid + bottom bar)
  ├── Color.black backdrop (zIndex 9, fades with drag)
  ├── MixViewerView (zIndex 10)
  │     ├── pagingCanvas — fixed size, no internal positioning
  │     ├── topChrome — .position(y: safeAreaTop + 22)
  │     └── miniControls — sized to miniVisibleCanvasHeight, opacity toggles
  │
  │   HomeView applies to MixViewerView:
  │     .frame(width:height:) → .frame(height: clip) → .clipped()
  │     .clipShape(.rect(cornerRadius: 16))
  │     .scaleEffect() → .offset() → .position()
  │
  ├── ViewerTagBar (zIndex 11, sibling, position at bottom safe area)
  └── Yellow test rect (zIndex 20, toggle from menu)
```

---

## Wrong Mix Opening on Tap

Never use `enumerated()` index with `ForEach` in masonry layouts. Look up by ID at tap time:

```swift
ForEach(mixes) { mix in
    Card(mix: mix).onTapGesture {
        let index = mixes.firstIndex(where: { $0.id == mix.id }) ?? 0
        open(startIndex: index)
    }
}
```

---

## Key Debugging Pattern: Yellow Rectangle Test

To verify positioning logic, add a `Color.yellow` rectangle with known dimensions and `.position()`. If the yellow rect works but the real view doesn't, the problem is inside the real view (internal layout fighting external control). Strip the real view's internals until it behaves like the yellow rect.
