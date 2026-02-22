local r = reaper

-- Retrieve dependencies
-- We assume these are loaded in Main, but we require them here for IntelliSense/Scope
local State = require("Loopish_State")
local TM = require("Loopish_TrackManager")

local GUI = {}

-- Main Draw Function
function GUI.draw(ctx)
    
    local w, h = r.ImGui_GetWindowSize(ctx)
    
    -- =========================================================
    -- SECTION 1: SETTINGS
    -- =========================================================
    if r.ImGui_CollapsingHeader(ctx, 'Settings', r.ImGui_TreeNodeFlags_DefaultOpen()) then
        
        -- Window Length
        local changed_len, new_len = r.ImGui_InputInt(ctx, 'Window (Qtrs)', State.settings.window_length_q)
        if changed_len then State.settings.window_length_q = new_len end

        -- Pre-Roll
        local changed_roll, new_roll = r.ImGui_InputInt(ctx, 'Pre-Roll (Qtrs)', State.settings.pre_roll_q)
        if changed_roll then State.settings.pre_roll_q = new_roll end
        
        -- Stop Immediately
        local changed_stop, new_stop = r.ImGui_Checkbox(ctx, 'Stop Immediately', State.settings.stop_immediately)
        if changed_stop then State.settings.stop_immediately = new_stop end
        
        -- Include Pre-roll in Loop
        local changed_inc, new_inc = r.ImGui_Checkbox(ctx, 'Include Pre-roll in Loop', State.settings.include_preroll_in_loop)
        if changed_inc then State.settings.include_preroll_in_loop = new_inc end
        
        r.ImGui_Separator(ctx)
    end

    -- =========================================================
    -- SECTION 2: TRANSPORT & COMMANDS
    -- =========================================================
    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, "Transport Controls")
    
    -- Play / New Take
    local btn_label = "RECORD"
    if State.is_recording then
        if State.scheduled_action and State.scheduled_action.type == "stop" then
            btn_label = "STOPPING..."
        else
            btn_label = "STOP RECORDING"
        end
    end
    
    if r.ImGui_Button(ctx, btn_label, -1, 40) then
        if State.is_recording then
            TM.cmd_stop()
        else
            TM.cmd_record()
        end
    end

    r.ImGui_Spacing(ctx)
    
    -- Window Navigation Grid
    local btn_width = (w / 2) - 15
    
    local prev_label = "< Prev Window"
    if State.scheduled_action and State.scheduled_action.direction == -1 then
        prev_label = "[QUEUED] < Prev Window"
    end
    
    if r.ImGui_Button(ctx, prev_label, btn_width) then
        TM.cmd_move_window(-1)
    end
    
    r.ImGui_SameLine(ctx) 
    
    local next_label = "Next Window >"
    if State.scheduled_action and State.scheduled_action.direction == 1 then
        next_label = "Next Window > [QUEUED]"
    end
    
    if r.ImGui_Button(ctx, next_label, btn_width) then
        TM.cmd_move_window(1)
    end

    -- =========================================================
    -- SECTION 3: TRACK CONFIGURATION
    -- =========================================================
    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, "Input Configuration")

    -- Register Button
    if r.ImGui_Button(ctx, "Register New Armed Inputs", -1) then
        TM.register_new_inputs()
    end
    
    r.ImGui_Spacing(ctx)

    -- Track List
    if #State.tracks == 0 then
        r.ImGui_TextDisabled(ctx, "(No tracks configured)")
    else
        r.ImGui_Text(ctx, "Tracks to Record:")
        
        -- Iterate the State (View binding)
        for _, track_model in ipairs(State.tracks) do
            
            local bus_status = track_model.bus and " (BUS OK)" or " (NO BUS)"
            local label = string.format("Track %d (Layer %d)%s", track_model.number, track_model.currentLayer, bus_status)
            
            -- Checkbox
            local changed, new_val = r.ImGui_Checkbox(ctx, label, track_model.active)
            
            -- If user clicks checkbox, update model AND notify Manager to update Reaper
            if changed then
                track_model.active = new_val
                TM.sync_track_active_state(track_model)
            end
        end
    end

    -- =========================================================
    -- SECTION 4: ACTIONS
    -- =========================================================
    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)

    if r.ImGui_Button(ctx, "Go to Latest End", -1) then
        TM.goto_latest_time()
    end
end

return GUI