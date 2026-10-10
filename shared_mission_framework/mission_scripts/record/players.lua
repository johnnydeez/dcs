-- The record of the players now: unit, group, player name, the jet's callsign, type,
-- position, in the air or not. One writer: watch\players.lua, worked out when read
-- (rule 11).

RecordPlayers = {}

-- The players of coalition `side` (coalition.side), in DCS's order (watch\players.lua
-- says what each holds).
function RecordPlayers.list(side)
    return WatchPlayers.list(side)
end
