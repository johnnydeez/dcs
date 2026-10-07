# Hearing the radio calls when John hosts

Darkstar, the AI pilots and the airfields talk on your jet's radios (F-16C or F/A-18C). John's PC does the voices; yours only plays them, through your own radios: tune a radio to a frequency to hear it, turn its volume knob to make it louder or quieter.

## QUICK START

1. unzip /radio_calls folder anywhere
2. Double click start_radio_player_client.cmd
3. Get John's Zero Tier address - enter it in the prompt



## Once

1. **Get this folder** (`radio_calls`): clone the repository (`git clone git@github.com:johnnydeez/dcs.git`, the folder is `dcs\shared_mission_framework\radio_calls`), or unzip the copy John sends you anywhere you like. Python 3.7 or newer must be installed.
2. **Join John's ZeroTier network** and ask him for his ZeroTier address (looks like `10.147.17.1`).

## Every time you fly

1. **Double-click `start_radio_player_client.cmd`** in this folder, before or after starting DCS. The first time it asks for John's ZeroTier address and remembers it.
2. Keep its window open while you fly (minimise it if you like). It should say `connected to the host's radio helper` once John's mission is running; until then it says `waiting for the host's radio helper` and keeps trying by itself.
3. Close the window when you're done.

**The very first time only:** the radio player adds one line to `Saved Games\DCS\Scripts\Export.lua` (so it can read your jet's radios; its window says so). **Restart DCS once** after that. Until you do, you hear every call whatever your radios are tuned to.

## If it doesn't work

- **The window says `waiting for the host's radio helper`** the whole time John's mission is running: check you're both on ZeroTier and the address is right. To type a new address, delete `host_zerotier_address.txt` in this folder and start again.
- **You hear calls but they ignore your radios:** restart DCS once (see above). John's server must have "Allow player export" on.
- **The window says `another version`:** get this folder again, so it matches John's.
- Send John the file `radio_player.log` from this folder; it shows everything the player heard and why.
