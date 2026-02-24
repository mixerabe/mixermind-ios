# Home

Lists all mixes sorted by recency. Entry point after Supabase setup.

## Components

- **HomeView** — NavigationStack with mix list, empty state, + button to create, disconnect button.
- **HomeViewModel** — Loads mixes from MixRepository, manages loading state.
- **MixRow** — Private component showing mix type icon, text preview, and relative timestamp.

## Flow

1. On appear, loads all mixes from Supabase.
2. Shows ContentUnavailableView if empty.
3. Tap + opens CreateMixView as sheet.
4. On sheet dismiss, reloads mixes.
5. Disconnect clears Supabase config and returns to SetupView.

## API

- `MixRepository.listMixes()` — fetches all mixes ordered by created_at desc
