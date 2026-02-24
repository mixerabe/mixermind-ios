# Planning Rules -- Presentation

Rules that affect planning for views, view models, and UI components.

## Architecture

Organized by **feature**. Each feature owns its ViewModel and View.

App-wide UI things go in the root `Presentation/` layer, not Core:

```
Presentation/
├── extensions/    # UI type extensions (Color+Extensions, View+Extensions, Font+Extensions)
├── components/    # Shared UI components (AvatarView, LoadingView, ErrorView)
├── modifiers/     # Shared view modifiers (ShimmerModifier, CardStyle)
├── styles/        # Design tokens, themes (AppColors, AppFonts, AppSpacing)
├── utils/         # UI helpers, formatters
├── models/        # Shared UI models
└── [feature]/     # Feature folders...
```

## Feature Structure

**Hard rule:** Every feature has exactly:
- `[Feature]ViewModel.swift` - at feature root
- `[Feature]View.swift` - at feature root

**Optional folders:**
- `components/` - Additional components for this feature
- `models/` - UI models consumed by views
- `modifiers/` - SwiftUI view modifiers
- `utils/` - Helpers, formatters, extensions
- `features/` - Nested child features

## Feature Inheritance

Features form a tree. Children inherit from parents.

If `search/` needs a model, it looks in:
1. `search/models/` - local
2. `home/models/` - from parent
3. `Presentation/models/` - from grandparent (app-level)
4. etc...

If two sibling features need the same thing, it **moves up** to the parent. Code never moves sideways between siblings.

## When Does Something Become a Feature?

A piece of UI becomes its own feature when it needs a ViewModel.

**The Decision Test** - Ask in order, stop at first "yes":

| Question | If YES |
|----------|--------|
| Does it manage loading/error/retry states? | Needs a ViewModel → Feature |
| Does its state need to survive navigation or persist across renders? | Needs a ViewModel → Feature |
| Does it coordinate multiple async operations? | Needs a ViewModel → Feature |

If all answers are "no," it's just a **component** in the parent's `components/` folder.

## Feature Patterns
- ViewModels: `@Observable` classes with injected repositories
- Views: Structs with `@State var viewModel`
- Feature minimum: ViewModel + View + FEATURE_OVERVIEW.md
- Subfolders: `components/`, `models/`, `modifiers/`, `utils/`, `features/`

## State Management
```swift
@State private var localState = ""                 // View-local only
@Observable @MainActor final class VM { }          // Shared state
@State private var viewModel = ViewModel()         // In parent view
@Bindable var viewModel: ViewModel                 // Passed to child
```

## Navigation
```swift
NavigationStack {
    List(items) { item in
        NavigationLink(value: item) { Row(item: item) }
    }
    .navigationDestination(for: Item.self) { DetailView(item: $0) }
}
```

## Async in Views
```swift
.task { await loadData() }                         // Lifecycle-aware
```

## Layout

### Prefer (in order)
1. `containerRelativeFrame` - for sizing relative to container
2. `ViewThatFits` - for adaptive content
3. `GeometryReader` - only for coordinate spaces or child measurement

### Avoid
```swift
UIScreen.main.bounds                               // Use layout APIs
.frame(width: 300)                                 // Use relative sizing
```

## Performance
- Use `LazyVStack`/`LazyHStack` for large lists
- Keep `body` property lightweight (no heavy computation)
- Use stable identifiers for list items
- Don't filter/sort data in `body`
- Don't make network calls in `body`




# Code Rules -- Presentation

Rules applied automatically when writing views, view models, and UI components.

## Modern SwiftUI APIs

```swift
.foregroundStyle(.primary)                         // NOT foregroundColor()
.clipShape(.rect(cornerRadius: 12))                // NOT cornerRadius()
.onChange(of: value) { old, new in }               // NOT single-param
.containerRelativeFrame(.horizontal)               // For relative sizing
.sensoryFeedback(.success, trigger: value)         // For haptics
ContentUnavailableView("Empty", systemImage: "")   // For empty states
Tab("Home", systemImage: "house") { }              // NOT tabItem()
```

## Previews
```swift
#Preview {
    @Previewable @State var text = ""
    TextField("Name", text: $text)
}
```

## Environment (@Entry macro)
```swift
extension EnvironmentValues {
    @Entry var customValue: String = "default"
}
```

## Accessibility
- Use semantic fonts (`.body`, `.headline`) - respect Dynamic Type
- Use `Button`, not `onTapGesture` - proper accessibility
- Add accessibility labels to custom controls

## Things to Avoid

| Don't | Do Instead | Why |
|-------|------------|-----|
| `ObservableObject` | `@Observable` | Performance, cleaner |
| `AnyView` (in animations) | `@ViewBuilder`, generics | Animation identity |
| `GeometryReader` (for sizing) | `containerRelativeFrame` | Cleaner, performant |
| `.font(.system(size: 16))` | `.font(.body)` | Dynamic Type |
| `onTapGesture` (for buttons) | `Button { } label: { }` | Accessibility |
| `PreviewProvider` | `#Preview { }` | Modern syntax |
| `Color(UIColor.systemBackground)` | `Color(.systemBackground)` | Cleaner |
