# Viewer Feature

Full-screen mix viewer with TikTok-style vertical swipe navigation.

## Files
- `MixView.swift` — Full-screen view with vertical TabView paging
- `MixViewModel.swift` — URL-based playback (video + audio from Supabase Storage)

## Behavior
- Opens from HomeView grid cell tap at the tapped mix's position
- Vertical swipe to navigate between mixes
- Tap canvas to pause/resume (when playback exists)
- Horizontal drag to scrub through video/audio
- Top bar: close (left), audio pill (center), controls (right)
- Delete mix via trash button with confirmation alert

## Shared Components
- `LoopingVideoView` — in `Presentation/Components/`, shared with Create feature

## Key Difference from Create
- Create plays from local `Data` (temp files written to disk)
- Viewer plays from remote URLs (Supabase Storage public URLs)
- No editing state, no pickers, no upload logic
