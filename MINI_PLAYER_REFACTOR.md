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

MixViewerView has **no internal `.position()`** (except for top chrome), **no `.ignoresSafeArea()`**, **no layout opinions**. HomeView gives it a frame, clips it, scales it, offsets it, and positions it.

### 5. Independent layers are siblings, not children

Tag bar is NOT inside a VStack with the canvas. It's an independent floating element:
- **Tag bar** (`ViewerTagBar`): sibling in HomeView ZStack, positioned at `screenHeight - safeAreaBottom - 22`

### 6. One view for both states (no if/else branches)

Fullscreen and mini are the same `MixViewerView` instance with conditional modifiers. SwiftUI can animate between states because the view identity doesn't change.

---

## Mini Card Cropping

Only `previewScaleY` drives the mini card height (`previewScaleX` is not used for cropping):

```swift
let sy = max(mix.previewScaleY ?? 1.0, 1.2) // floor of 1.2 ensures some crop
let aspectRatio = 390.0 / (844.0 / sy)
currentMiniCardHeight = miniCardWidth / aspectRatio
```

In HomeView, a second `.frame(height:)` with `.clipped()` (center alignment) crops equally from top and bottom when mini. The full canvas stays the same size — only the visible portion changes.

**Gotcha**: use `max()` not `min()` for the floor — `min()` caps values *down*, throwing away real crop data like `1.62`.

---

## Mini Drag & Hit Testing

### The scaleEffect hit area problem

`.scaleEffect()` visually shrinks the viewer but the hit area stays at the original full-canvas size. This means:
- Attaching `.gesture()` directly to the scaled viewer either catches the whole screen or nothing
- Internal buttons inside MixViewerView (mini controls) can eat touches meant for the drag

### Solution: separate mini hit target (zIndex 12)

A `Color.clear` sibling in the HomeView ZStack, sized to the **actual mini card dimensions** (not the pre-scale canvas), positioned at the same `miniTargetPosition`:

```swift
Color.clear
    .frame(width: miniCardWidth, height: max(currentMiniCardHeight - inset * 2, 20))
    .contentShape(.rect)
    .offset(miniDragOffset)
    .position(x: miniTargetPosition.x, y: miniTargetPosition.y)
    .gesture(miniCornerDragGesture)
    .onTapGesture { expandFromMini() }
    .zIndex(12)
```

The `inset` (38pt) leaves room at top and bottom for the mini control buttons (dismiss X, playback controls) to remain tappable. The middle area handles drag-to-reposition and tap-to-expand.

### Mini controls hit testing

- `pagingCanvas`: `.allowsHitTesting(!isMinimized)` — disabled when mini
- `topChrome`: `.allowsHitTesting(!isMinimized)` — disabled when mini
- `miniControls`: `.allowsHitTesting(isMinimized)` — enabled when mini
- The viewer itself: `.allowsHitTesting(true)` always, but internal views control their own hit testing

### Corner snapping

On drag release, the card snaps to the nearest corner based on which screen quadrant the predicted landing position falls in:

```swift
let midX = screen.width / 2
let midY = screen.height / 2
let isRight = landing.x > midX
let isDown = landing.y > midY
// (isRight, isDown) → corner enum
```

### Corner positions

- **Bottom corners**: `screen.height - padding - bottomBarClearance - cardH/2`
- **Top corners**: `safeAreaTop - 8 + cardH/2` (sits 8pt above the safe area edge)

---

## Top Chrome Layout

- **Left**: ellipsis menu (auto-scroll toggle, delete)
- **Center**: title chip (tap to edit via sheet)
- **Right**: X button (minimize/dismiss)
- Positioned at `y: safeAreaTop + 36` (14pt breathing room below safe area)
- All buttons have `.glassEffect(in: .circle)`, title has `.glassEffect(in: .capsule)`
- **Fade with drag**: `opacity = max(1 - dragProgress * 3, 0)` — disappears in first third of drag
- **Pause/mute overlay** in MixCanvasView also fades with the same formula via passed `dragProgress`

---

## Canvas Background

Each mix has `gradientTop` and `gradientBottom` hex color strings (stored in Supabase). MixCanvasView renders a `LinearGradient` from top to bottom as the canvas background, with content (images, video, embeds, text) layered on top.

Default fallback: `#1a1a2e` → `#16213e` (dark blue).

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
  │     ├── pagingCanvas — fixed size, gradient background, hitTesting off when mini
  │     ├── topChrome — .position(y: safeAreaTop + 36), hitTesting off when mini
  │     └── miniControls — sized to miniVisibleCanvasHeight, hitTesting on when mini
  │
  │   HomeView applies to MixViewerView:
  │     .frame(width:height:) → .frame(height: clip) → .clipped()
  │     .clipShape(.rect(cornerRadius: 16))
  │     .scaleEffect() → .offset() → .position()
  │     .allowsHitTesting(true)
  │
  ├── Mini drag target (zIndex 12, Color.clear, actual mini size minus inset)
  │     — handles drag-to-corner and tap-to-expand
  │     — inset 38pt top/bottom so mini control buttons remain tappable
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
