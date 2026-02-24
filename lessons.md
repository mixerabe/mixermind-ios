# Lessons Learned

## SwiftUI: fullScreenCover dismisses when child sheet closes
**Problem:** A `fileImporter` (or `sheet`) inside a `fullScreenCover` causes the parent to dismiss when the child sheet closes.
**Root cause:** The child sheet dismissal triggers an interactive dismiss gesture on the parent `fullScreenCover`.
**Fix:** Add `.interactiveDismissDisabled()` to the `fullScreenCover` content view. One line, no structural changes.
**Wrong approaches tried:**
- Wrapping in `NavigationStack` to isolate dismiss scope — unnecessary overhead
- Switching from `@Environment(\.dismiss)` to `@Binding var isPresented` — couples the view to its presentation context, less reusable
- Moving closure logic to ViewModel to avoid capturing `dismiss` — wasn't the issue

**Takeaway:** When a `fullScreenCover` unexpectedly closes, check interactive dismiss first. The simplest fix is usually the right one.
