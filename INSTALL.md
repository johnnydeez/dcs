# Install

## 1. De-sanitize MissionScripting.lua

Edit `C:\Program Files\Eagle Dynamics\DCS World\Scripts\MissionScripting.lua`.
Comment out the 6 lines inside the `do...end` sanitize block (lines 16–21):

Use -- for comments

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

Requires a full DCS restart. Must be redone after every DCS update.

## 2. Copy scripts

Copy the `scripts/` folder from this repo to:

```
C:\Users\<you>\Saved Games\DCS\Scripts\a2g_dynamic_syria\
```


## 3. Starting Server

- Make sure to un-pause the server before anything tlse, that kicks off all the random spawning.
- Select Blue coalition and DYNAMIC slots only
- Spawn where you see fit