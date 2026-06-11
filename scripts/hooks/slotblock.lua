-- Slot blocker: prevents Blue players from taking client slots at Red-owned bases.
-- Lives in: Saved Games\DCS\Scripts\Hooks\slotblock.lua
--
-- coalition_setup.lua sets a DCS user flag per group name (1=Red/blocked, 0=Blue/open).
-- This script reads those flags via net.dostring_in and blocks the slot if flag == 1.

local slotblock = {}

function slotblock.onPlayerTryChangeSlot(playerId, side, slotId)
    local gname = DCS.getUnitProperty(slotId, DCS.UNIT_GROUPNAME)

    net.log("[SLOTBLOCK] onPlayerTryChangeSlot: playerId=" .. tostring(playerId)
        .. "  side=" .. tostring(side)
        .. "  slotId=" .. tostring(slotId)
        .. "  gname=" .. tostring(gname))

    if not gname or gname == "" then return end

    local flagVal, err = net.dostring_in('server',
        'return trigger.misc.getUserFlag("' .. gname .. '")')

    net.log("[SLOTBLOCK] flag('" .. gname .. "') = " .. tostring(flagVal))

    if flagVal and tonumber(flagVal) == 1 then
        net.send_chat_to("[SLOTBLOCK] " .. gname .. " is at a Red base — choose a Blue base.", playerId)
        net.force_player_slot(playerId, 0, "")
        return false
    end
end

DCS.setUserCallbacks(slotblock)
