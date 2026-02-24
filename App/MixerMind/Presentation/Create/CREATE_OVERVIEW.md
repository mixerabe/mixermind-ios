# Create Mix

Create a new mix with optional text and/or media (image, video, audio).

## Components

- **CreateMixView** — Single-screen canvas with center action buttons (Add Text / Upload), media preview, text overlay, pill indicators for media and text state, and a Create button.
- **CreateMixViewModel** — Manages media selection (PhotosPicker for images/videos, fileImporter for audio), text input, Supabase upload, and mix creation.
- **TextInputSheet** — Modal sheet with a TextEditor for entering/editing text content.

## Flow

1. Canvas starts empty with "Add Text" and "Upload" buttons centered.
2. User adds text via sheet and/or uploads media via picker.
3. Canvas previews the content (image thumbnail, video thumbnail, audio waveform icon, text overlay).
4. Two pills at bottom show current media and text state. Tapping opens picker/sheet. Long-press on text pill to remove.
5. "Create" uploads media to Supabase Storage, creates the mix row, and dismisses.
6. Empty creation is allowed (no validation).

## API

- `MixRepository.uploadMedia(data:fileName:contentType:)` — uploads to `mix-media` bucket
- `MixRepository.createMix(_:)` — inserts into `mixes` table
