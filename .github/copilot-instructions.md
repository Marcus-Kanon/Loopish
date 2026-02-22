# Loopish: AI Coding Agent Instructions

## Architecture Overview
Loopish is a modular REAPER script for live looping using `ReaImGui`.
- **[Loopish_State.lua](Loopish_State.lua)**: The Data Model. All variables that drive the UI or track logic must reside here.
- **[Loopish_TrackManager.lua](Loopish_TrackManager.lua)**: The Logic/Command layer. Handles all direct REAPER API calls (`reaper.*`).
- **[Loopish_GUI.lua](Loopish_GUI.lua)**: The Presentation layer. Uses the `State` to draw the interface and calls `TM` (TrackManager) functions for actions.
- **[Loopish_Main.lua](Loopish_Main.lua)**: Entry point. Handles module loading, the `defer` loop, and dev-time hot reloading.

## Key Patterns and Conventions

### 1. Data Flow (MVVM-like)
- UI (GUI) → Command (TrackManager) → State (State) → UI Update.
- Always prefer updating the `State` and letting the UI react.
- Example: `GUI` calls `TM.sync_track_active_state(model)` which then modifies REAPER state based on `model.active`.

### 2. REAPER Track Identification & Routing
- Tracks are managed by a custom naming pattern: `Loopish_Track%03d_Layer%03d` and `Loopish_Track%03d_BUS`.
- **BUS Routing**: When a new input is registered, the original armed track becomes the BUS (disarmed, moved to top). A new empty track is created as Layer 1 and routed to the BUS.
- Use `TrackManager.rebuild_state()` to synchronize the project's actual tracks with the internal `State`.

### 3. Window Management & Pre-roll
- **Single Source of Truth**: Always use `TrackManager.get_actual_window()` to derive the true grid-aligned window from the `end_time`.
- **Syncing**: Use `TrackManager.sync_window(actual_start)` to dynamically apply pre-roll expansion to the `start_time` when `include_preroll_in_loop` is active.
- **Timing**: Use quarter-note units (`_q`) for loop lengths (synced to project BPM). Convert to seconds using `quarters * (60 / bpm)`.

### 4. Live Recording Workflow
- **Continuous Recording**: Do not switch armed tracks or modify items while REAPER is actively recording.
- **Queued Actions**: Actions like "Next Window" or "Stop" during recording are queued in `State.scheduled_action` and executed by `TrackManager.on_defer_tick()` when within 200ms of the loop end.
- **Post-Processing**: `TrackManager.process_recorded_items()` handles chopping continuous takes into window-sized items and trimming pre-roll audio *only after* the transport has fully stopped.

### 5. ReaImGui Context
- The ImGui context (`ctx`) is created in `Main` and passed into `GUI.draw(ctx)`.
- Use `r.ImGui_*` functions consistently for UI elements.

### 6. Development Workflow
- **Hot Reloading**: `Loopish_Main.lua` resets `package.loaded` for modules. When editing logic, simply re-run the script in REAPER to see changes without restarting.

## API Usage Guidelines
- **Track Metadata**: Use `r.GetSetMediaTrackInfo_String(track, "P_NAME", ...)` for reading/writing the `Loopish` names.
- **Record States**: Control arming via `I_RECARM` and monitoring via `I_RECMON`.
- **Routing**: Use `CreateTrackSend` and disable master send (`B_MAINSEND = 0`) for Layer -> BUS routing.

## Critical Implementation Details
- Never hardcode track indices; always use the `Loopish_TrackX_LayerY` names to find managed tracks.
- Never modify media items (`SplitMediaItem`, `SetMediaItemInfo_Value`) while `r.GetPlayState() & 4` (recording) is true.
- When adding new functionality, check if it belongs in `TrackManager` (logic) or `GUI` (presentation).
