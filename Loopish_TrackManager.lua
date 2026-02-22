local r = reaper
local State = require("Loopish_State")

local TrackManager = {}

-- =========================================================
-- PRIVATE HELPERS
-- =========================================================

-- Parses "Loopish_Track001_Layer001" -> 1, 1
-- Parses "Loopish_Track001_BUS" -> 1, "BUS"
local function parse_name(name)
    local t_id, l_id = name:match("Loopish_Track(%d+)_Layer(%d+)")
    if t_id and l_id then
        return tonumber(t_id), tonumber(l_id)
    end
    
    local b_id = name:match("Loopish_Track(%d+)_BUS")
    if b_id then
        return tonumber(b_id), "BUS"
    end
    
    return nil, nil
end

-- Finds a track model in State by number
local function find_track_model(number)
    for _, tr in ipairs(State.tracks) do
        if tr.number == number then return tr end
    end
    return nil
end

-- =========================================================
-- STATE MANAGEMENT
-- =========================================================

-- Scans project and populates State.tracks
function TrackManager.rebuild_state()
    State.tracks = {} -- Reset state
    local track_count = r.CountTracks(0)
    
    -- 1. Scan Project
    for i = 0, track_count - 1 do
        local reaper_track = r.GetTrack(0, i)
        local _, name = r.GetSetMediaTrackInfo_String(reaper_track, "P_NAME", "", false)
        local t_num, l_num = parse_name(name)
        
        if t_num then
            -- Find or Create Model
            local model = find_track_model(t_num)
            if not model then
                model = {
                    number = t_num,
                    bus = nil,
                    layers = {},
                    currentLayer = 0,
                    active = true 
                }
                table.insert(State.tracks, model)
            end
            
            if l_num == "BUS" then
                model.bus = reaper_track
            elseif type(l_num) == "number" then
                -- Add Layer info
                table.insert(model.layers, { id = l_num, ptr = reaper_track })
                
                -- Update Max Layer
                if l_num > model.currentLayer then
                    model.currentLayer = l_num
                end
            end
        end
    end

    -- 2. Sort Tracks
    table.sort(State.tracks, function(a,b) return a.number < b.number end)

    -- 3. Sort Layers
    for _, tr in ipairs(State.tracks) do
        table.sort(tr.layers, function(a,b) return a.id < b.id end)
    end
end

-- Force Reaper tracks (Arm/Monitor) to match our State active flags
function TrackManager.force_sync_active_state()
    for _, track_model in ipairs(State.tracks) do
        TrackManager.sync_track_active_state(track_model)
    end
    r.UpdateArrange()
end

-- Syncs a SINGLE track model to Reaper (used by Checkbox)
function TrackManager.sync_track_active_state(track_model)
    local active = track_model.active
    
    for _, layer in ipairs(track_model.layers) do
        -- Only touch the current layer
        if layer.id == track_model.currentLayer then
            -- Arm/Disarm
            r.SetMediaTrackInfo_Value(layer.ptr, "I_RECARM", active and 1 or 0)
            
            -- If active, force monitoring ON
            if active then
                r.SetMediaTrackInfo_Value(layer.ptr, "I_RECMON", 1)
            end
        end
    end
end

-- =========================================================
-- WINDOW MANAGEMENT
-- =========================================================

function TrackManager.get_actual_window()
    local start_time, end_time = r.GetSet_LoopTimeRange(false, true, 0, 0, false)
    local bpm = r.Master_GetTempo()
    local actual_len = State.settings.window_length_q * (60 / bpm)
    
    if end_time - start_time <= 0.001 then
        return r.GetCursorPosition(), actual_len
    end
    
    -- The end_time is always the true end of the window.
    local actual_start = end_time - actual_len
    return actual_start, actual_len
end

function TrackManager.sync_window(actual_start)
    local bpm = r.Master_GetTempo()
    local actual_len = State.settings.window_length_q * (60 / bpm)
    local pre_roll_sec = State.settings.pre_roll_q * (60 / bpm)
    
    local loop_start = actual_start
    local loop_end = actual_start + actual_len
    
    if State.is_recording and State.settings.include_preroll_in_loop and pre_roll_sec > 0 then
        loop_start = math.max(0, actual_start - pre_roll_sec)
    end
    
    r.GetSet_LoopTimeRange(true, true, loop_start, loop_end, false)
    return loop_start, loop_end
end

-- =========================================================
-- COMMANDS (Called by GUI)
-- =========================================================

function TrackManager.cmd_record()
    local actual_start, actual_len = TrackManager.get_actual_window()
    local bpm = r.Master_GetTempo()
    local pre_roll_sec = State.settings.pre_roll_q * (60 / bpm)
    
    State.is_recording = true
    local loop_start, loop_end = TrackManager.sync_window(actual_start)
    
    if State.settings.include_preroll_in_loop and pre_roll_sec > 0 then
        r.SetEditCurPos(loop_start, true, false)
        
        -- Turn OFF REAPER's built-in pre-roll
        if r.GetToggleCommandState(41745) == 1 then
            r.Main_OnCommand(41745, 0)
        end
    else
        -- Standard behavior: pre-roll is outside the loop window
        if actual_start >= pre_roll_sec and pre_roll_sec > 0 then
            -- We have enough space on the timeline for a manual pre-roll
            r.SetEditCurPos(actual_start - pre_roll_sec, true, false)
            
            -- Turn OFF REAPER's built-in pre-roll so they don't stack
            if r.GetToggleCommandState(41745) == 1 then
                r.Main_OnCommand(41745, 0)
            end
        else
            -- Not enough space (e.g., at the very beginning of the project)
            r.SetEditCurPos(actual_start, true, false)
            
            -- Turn ON REAPER's built-in pre-roll if pre_roll_q > 0
            if pre_roll_sec > 0 then
                if r.GetToggleCommandState(41745) == 0 then
                    r.Main_OnCommand(41745, 0)
                end
            else
                -- If pre-roll is 0, ensure REAPER's pre-roll is OFF
                if r.GetToggleCommandState(41745) == 1 then
                    r.Main_OnCommand(41745, 0)
                end
            end
        end
    end
    
    -- Turn on looping
    r.GetSetRepeat(1)
    
    -- Initialize recording history
    State.recording_windows = {
        { start_time = actual_start, end_time = actual_start + actual_len }
    }
    
    -- Start recording (Command ID 1013 is Transport: Record)
    r.Main_OnCommand(1013, 0)
end

function TrackManager.cmd_stop()
    if State.settings.stop_immediately then
        -- Stop immediately (Command ID 1016 is Transport: Stop)
        r.Main_OnCommand(1016, 0)
        -- The actual trimming and window restoration will happen on the next defer tick
        -- when it detects that play_state is no longer recording.
    else
        -- Schedule a stop for the end of the current loop
        State.scheduled_action = { type = "stop" }
    end
end

function TrackManager.register_new_inputs()
    local track_count = r.CountTracks(0)
    
    -- Find next ID
    local highest_num = 0
    for _, tr in ipairs(State.tracks) do
        if tr.number > highest_num then highest_num = tr.number end
    end
    
    local updates = false
    
    -- 1. Collect all armed tracks that need registration first
    local tracks_to_register = {}
    for i = 0, track_count - 1 do
        local track = r.GetTrack(0, i)
        local _, name = r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
        local t_num, _ = parse_name(name)
        local is_armed = r.GetMediaTrackInfo_Value(track, "I_RECARM") == 1
        
        if is_armed and not t_num then
            table.insert(tracks_to_register, track)
        end
    end
    
    -- 2. Process them in order
    for _, track in ipairs(tracks_to_register) do
        highest_num = highest_num + 1
        
        -- 1. The original track becomes the BUS
        local bus_track = track
        local bus_name = string.format("Loopish_Track%03d_BUS", highest_num)
        r.GetSetMediaTrackInfo_String(bus_track, "P_NAME", bus_name, true)
        
        -- Save input settings before disarming
        local rec_input = r.GetMediaTrackInfo_Value(bus_track, "I_RECINPUT")
        local rec_mode = r.GetMediaTrackInfo_Value(bus_track, "I_RECMODE")
        
        -- Disarm the BUS track
        r.SetMediaTrackInfo_Value(bus_track, "I_RECARM", 0)
        r.SetMediaTrackInfo_Value(bus_track, "I_RECMON", 0)
        
        -- 2. Create the new Layer 1 track at the end of the project
        local new_track_idx = r.CountTracks(0)
        r.InsertTrackAtIndex(new_track_idx, true)
        local layer_track = r.GetTrack(0, new_track_idx)
        
        local layer_name = string.format("Loopish_Track%03d_Layer%03d", highest_num, 1)
        r.GetSetMediaTrackInfo_String(layer_track, "P_NAME", layer_name, true)
        
        -- Copy input settings to the new layer
        r.SetMediaTrackInfo_Value(layer_track, "I_RECINPUT", rec_input)
        r.SetMediaTrackInfo_Value(layer_track, "I_RECMODE", rec_mode)
        
        -- 3. Route Layer 1 to BUS
        -- Disable master/parent send on the layer
        r.SetMediaTrackInfo_Value(layer_track, "B_MAINSEND", 0)
        -- Create send from layer to bus
        local send_idx = r.CreateTrackSend(layer_track, bus_track)
        -- Set send volume to 0dB (1.0)
        r.SetTrackSendInfo_Value(layer_track, 0, send_idx, "D_VOL", 1.0)
        
        updates = true
    end
    
    if updates then
        TrackManager.rebuild_state()
        TrackManager.force_sync_active_state() -- Ensure new ones are handled correctly
    end
end

function TrackManager.cmd_move_window(direction)
    if State.is_recording then
        -- Schedule the move for the end of the current loop
        State.scheduled_action = { type = "move_window", direction = direction }
        return
    end

    local actual_start, actual_len = TrackManager.get_actual_window()
    local shift = actual_len * direction
    local new_start = math.max(0, actual_start + shift)

    TrackManager.sync_window(new_start)
    r.SetEditCurPos(new_start, true, false)
    r.UpdateArrange()
end

function TrackManager.goto_latest_time()
    local max_time = 0
    for _, tr in ipairs(State.tracks) do
        for _, layer in ipairs(tr.layers) do
             if layer.id == tr.currentLayer then
                 local item_count = r.CountTrackMediaItems(layer.ptr)
                 for i = 0, item_count - 1 do
                     local item = r.GetTrackMediaItem(layer.ptr, i)
                     local end_pos = r.GetMediaItemInfo_Value(item, "D_POSITION") + r.GetMediaItemInfo_Value(item, "D_LENGTH")
                     if end_pos > max_time then max_time = end_pos end
                 end
             end
        end
    end
    
    if max_time > 0 then
        r.SetEditCurPos(max_time, true, false)
    end
end

-- =========================================================
-- RUNTIME LOOP (Called by Main defer)
-- =========================================================

local function process_recorded_items()
    if not State.recording_windows or #State.recording_windows == 0 then return end
    
    local bpm = r.Master_GetTempo()
    local pre_roll_sec = State.settings.pre_roll_q * (60 / bpm)
    local include_preroll = State.settings.include_preroll_in_loop and pre_roll_sec > 0
    
    for _, track_model in ipairs(State.tracks) do
        for _, layer in ipairs(track_model.layers) do
            if layer.id == track_model.currentLayer then
                -- 1. Chop the continuous item at window boundaries
                for i = 1, #State.recording_windows - 1 do
                    local split_pos = State.recording_windows[i].end_time
                    
                    -- We must re-count items each time because splitting adds new items
                    local item_count = r.CountTrackMediaItems(layer.ptr)
                    local items_to_split = {}
                    
                    for j = 0, item_count - 1 do
                        local item = r.GetTrackMediaItem(layer.ptr, j)
                        local item_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
                        local item_len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
                        
                        -- If the item crosses the boundary, mark it for splitting
                        -- We use a small epsilon (0.001) to avoid floating point precision issues
                        if split_pos > (item_pos + 0.001) and split_pos < (item_pos + item_len - 0.001) then
                            table.insert(items_to_split, item)
                        end
                    end
                    
                    for _, item in ipairs(items_to_split) do
                        r.SplitMediaItem(item, split_pos)
                    end
                end
                
                -- 2. Trim the pre-roll from the VERY FIRST window
                if include_preroll then
                    local first_window = State.recording_windows[1]
                    local target_start = first_window.start_time
                    local preroll_start = target_start - pre_roll_sec
                    
                    -- Re-fetch items since we split them
                    item_count = r.CountTrackMediaItems(layer.ptr)
                    local items_to_delete = {}
                    
                    for i = 0, item_count - 1 do
                        local item = r.GetTrackMediaItem(layer.ptr, i)
                        local item_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
                        local item_len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
                        
                        -- If the item is entirely within the pre-roll zone, mark for deletion
                        if item_pos >= (preroll_start - 0.001) and (item_pos + item_len) <= (target_start + 0.001) then
                            table.insert(items_to_delete, item)
                        -- If the item starts in the pre-roll zone but crosses into the target window, trim it
                        elseif item_pos < target_start and (item_pos + item_len) > target_start then
                            local diff = target_start - item_pos
                            
                            r.SetMediaItemInfo_Value(item, "D_POSITION", target_start)
                            r.SetMediaItemInfo_Value(item, "D_LENGTH", item_len - diff)
                            
                            local take = r.GetActiveTake(item)
                            if take then
                                local take_offset = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
                                r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", take_offset + diff)
                            end
                        end
                    end
                    
                    -- Delete the isolated pre-roll items
                    for _, item in ipairs(items_to_delete) do
                        r.DeleteTrackMediaItem(layer.ptr, item)
                    end
                end
            end
        end
    end
    
    r.UpdateArrange()
    State.recording_windows = {} -- Clear history
end

function TrackManager.on_defer_tick()
    -- Check if we are still recording
    local play_state = r.GetPlayState()
    if (play_state & 4) == 0 then
        if State.is_recording then
            -- We just stopped recording. If we had a scheduled stop, or if we stopped manually,
            -- we should process the items now that REAPER has finished writing them to disk.
            process_recorded_items()
            
            State.is_recording = false
            
            -- Restore the loop window to its actual size
            local actual_start, _ = TrackManager.get_actual_window()
            TrackManager.sync_window(actual_start)
        end
        
        State.is_recording = false
        State.scheduled_action = nil
        return
    end
    
    -- If recording and we have a scheduled action, check if we are near the loop end
    if State.is_recording and State.scheduled_action then
        local start_time, end_time = r.GetSet_LoopTimeRange(false, true, 0, 0, false)
        local play_pos = r.GetPlayPosition()
        
        -- If we are within 200ms of the loop end, execute the scheduled action
        -- We do this early enough so REAPER doesn't loop back
        if end_time - play_pos < 0.2 then
            
            local actual_start, actual_len = TrackManager.get_actual_window()
            
            if State.scheduled_action.type == "move_window" then
                -- Move the window
                local shift = actual_len * State.scheduled_action.direction
                local new_start = math.max(0, actual_start + shift)
                
                TrackManager.sync_window(new_start)
                
                -- Record the new window in our history
                if State.recording_windows then
                    table.insert(State.recording_windows, {
                        start_time = new_start,
                        end_time = new_start + actual_len
                    })
                end
                
                -- Clear the action so it doesn't fire again
                State.scheduled_action = nil
            elseif State.scheduled_action.type == "stop" then
                -- Stop immediately (Command ID 1016 is Transport: Stop)
                r.Main_OnCommand(1016, 0)
                -- The actual trimming and window restoration will happen on the next defer tick
                -- when it detects that play_state is no longer recording.
            end
        end
    end
end

return TrackManager