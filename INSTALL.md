# Install

## 1. De-sanitize MissionScripting.lua

Run the included script to do this automatically:

1. Open a terminal as Administrator (right-click → "Run as administrator")
2. Run: `python desanitize_dcs.py`
3. Fully restart DCS (not just the mission)

**Re-run after every DCS update** — updates reset MissionScripting.lua, which breaks script loading with `attempt to index global 'lfs' (a nil value)`.

### Manual alternative

Edit `C:\Program Files\Eagle Dynamics\DCS World\Scripts\MissionScripting.lua` and comment out the 6 lines inside the `do...end` sanitize block:

```lua
do
    -- sanitizeModule('os')
    -- sanitizeModule('io')
    -- sanitizeModule('lfs')
    -- _G['require'] = nil
    -- _G['loadlib'] = nil
    -- _G['package'] = nil
end
```

## 2. Copy scripts

Copy the `scripts/` folder from this repo to:

```
C:\Users\<you>\Saved Games\DCS\Scripts\a2g_dynamic_syria\
```


## 3. Starting Server

- Make sure to un-pause the server before anything tlse, that kicks off all the random spawning.
- Select Blue coalition and DYNAMIC slots only
- Spawn where you see fit