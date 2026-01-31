-- =========================================================
-- Loopish_Main.lua (ENTRY POINT)
-- =========================================================
local r = reaper

-- 1. SETUP PATHS
local info = debug.getinfo(1, 'S');
local script_path = info.source:match([[^@?(.*[\/])[^\/]-$]])
package.path = package.path .. ";" .. script_path .. "?.lua"

-- 2. DEV RELOAD (Optional: Remove in production)
-- Forces Lua to reload the modules every time you run the script action
package.loaded["Loopish_State"] = nil
package.loaded["Loopish_TrackManager"] = nil
package.loaded["Loopish_GUI"] = nil

-- 3. IMPORTS
local State = require("Loopish_State")
local TM = require("Loopish_TrackManager")
local GUI = require("Loopish_GUI")

-- 4. CONTEXT
local ctx = r.ImGui_CreateContext('Loopish')

-- 5. INITIALIZATION
local function OnInitialize()
    if not r.APIExists('ImGui_GetVersion') then 
        r.ShowConsoleMsg("Error: ReaImGui extension not found.\n")
        return false 
    end
    
    -- Build state and sync hardware (Rec Arm)
    TM.rebuild_state()
    TM.force_sync_active_state()
    
    return true
end

-- 6. LOOP
local function Main()
    local visible, open = r.ImGui_Begin(ctx, 'Loopish', true)
    
    if visible then
        GUI.draw(ctx)
        r.ImGui_End(ctx)
    end
    
    if open then
        r.defer(Main)
    end
end

-- 7. EXECUTE
if OnInitialize() then
    r.defer(Main)
end