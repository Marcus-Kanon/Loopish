local State = {
    -- Persistent Settings (could be saved/loaded to disk later)
    settings = {
        window_length_q = 8,
        pre_roll_q = 1,
        stop_immediately = true,
        include_preroll_in_loop = false
    },

    -- Runtime Data Model
    -- Structure: { number=int, bus=MediaTrack, layers={ {id=int, ptr=MediaTrack} }, currentLayer=int, active=bool }
    tracks = {},
    
    -- Recording State
    is_recording = false,
    scheduled_action = nil,
    recording_windows = {}
}

return State