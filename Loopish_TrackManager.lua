local r = reaper
local State = require("Loopish_State")

local TrackManager = {}

-- =========================================================
-- PRIVATE HELPERS
-- =========================================================

-- Parses "Loopish_Track001_Layer001" -> 1, 1
local function parse_name(name)
    local t_id, l_id = name:match("Loopish_Track(%d+)_Layer(%d+)")
    if t_id and l_id then
        return tonumber(t_id), tonumber(l_id)
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
        
        if t_num and l_num then
            -- Find or Create Model
            local model = find_track_model(t_num)
            if not model then
                model = {
                    number = t_num,
                    layers = {},
                    currentLayer = 0,
                    active = true 
                }
                table.insert(State.tracks, model)
            end
            
            -- Add Layer info
            table.insert(model.layers, { id = l_num, ptr = reaper_track })
            
            -- Update Max Layer
            if l_num > model.currentLayer then
                model.currentLayer = l_num
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
-- COMMANDS (Called by GUI)
-- =========================================================

function TrackManager.cmd_play_start()
    r.OnPlayButton()
end

function TrackManager.register_new_inputs()
    local track_count = r.CountTracks(0)
    
    -- Find next ID
    local highest_num = 0
    for _, tr in ipairs(State.tracks) do
        if tr.number > highest_num then highest_num = tr.number end
    end
    
    local updates = false
    
    for i = 0, track_count - 1 do
        local track = r.GetTrack(0, i)
        local _, name = r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
        local t_num, _ = parse_name(name)
        local is_armed = r.GetMediaTrackInfo_Value(track, "I_RECARM") == 1
        
        if is_armed and not t_num then
            highest_num = highest_num + 1
            local new_name = string.format("Loopish_Track%03d_Layer%03d", highest_num, 1)
            r.GetSetMediaTrackInfo_String(track, "P_NAME", new_name, true)
            updates = true
        end
    end
    
    if updates then
        TrackManager.rebuild_state()
        TrackManager.force_sync_active_state() -- Ensure new ones are handled correctly
    end
end

function TrackManager.cmd_move_window(direction)
    local start_time, end_time = r.GetSet_LoopTimeRange(false, true, 0, 0, false)
    local current_len = end_time - start_time
    
    -- Fallback if no loop exists
    if current_len <= 0.001 then
        local bpm = r.Master_GetTempo()
        current_len = State.settings.window_length_q * (60 / bpm)
        start_time = r.GetCursorPosition()
    end

    local shift = current_len * direction
    local new_start = math.max(0, start_time + shift)
    local new_end = new_start + current_len

    r.GetSet_LoopTimeRange(true, true, new_start, new_end, false)
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

return TrackManager