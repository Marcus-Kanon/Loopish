local State = {
    -- Persistent Settings (could be saved/loaded to disk later)
    settings = {
        window_length_q = 4,
        pre_roll_q = 1
    },

    -- Runtime Data Model
    -- Structure: { number=int, layers={ {id=int, ptr=MediaTrack} }, currentLayer=int, active=bool }
    tracks = {} 
}

return State