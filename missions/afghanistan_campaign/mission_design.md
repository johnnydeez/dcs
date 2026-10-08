# Afghanistan Campaign — Plan

> **What this is:** the design of a persistent DCS campaign on the Afghanistan map. Two coalitions fight a conventional war, in the air and on the ground, over a few hours of play at a time. When the mission is shut down the campaign's state is saved, and the next session picks up from that state. Each side is led by an AI Joint Force Commander (strategy) that hands directives down to an air tasking planner and a Mission Operations Controller (execution). Logistics feed the whole war. Much of the code comes from the Kola mission (`missions/kola_f16_random_tasking/`), and the parts both missions use move into a shared library.
>
> **State:** design (started 2026-10-03); **map creation under way since 2026-10-07:** the spawn site survey is built and tested on three areas (Bagram / Kabul, Kandahar, Jalalabad); **John approved its site finding 2026-10-08** after reviewing them in the viewer with trucks and SA-10s. Its tools, how they work and what's next are under *Map data: the site survey*. **The whole map was surveyed 2026-10-08: 249,458 spawn sites, split by tile in `shared_mission_framework\map_data\afghanistan\`.** Next: a look at the sites, then the grid assignment and off-road routing. Nothing of the campaign itself is built. Still open from earlier: *Next discussion: the ground war* and *Open*.
>
> **Paths** are relative to this mission folder (`missions/afghanistan_campaign/`) unless they say otherwise.
>
> **Working rules** (carried over from Kola):
> - Commits are always done by John, on his own schedule; never ask about or perform a commit.
> - Name things by what they are or do, in full words, folders included; no abbreviations in code names. Prose may use common terms (JFC, MOC, ATO, SEAD).
> - Judge every rule by what real forces would do.
> - Decide with John step by step; present proposals before building.
> - No wildcard deletes.

---

## Decided

### Scenario (2026-10-03)

- **A fictional modern conventional war.** Exotic minerals have been found in Afghanistan, and two coalitions fight for control of them.
  - **Blue:** a NATO-style coalition.
  - **Red:** a Russian / Chinese / Pakistani coalition.
- **Not hyper-realistic on purpose** (John): the scenario is there to use everything DCS offers. Some equipment crosses sides to even things out, as in Kola, where Blue fields Soviet-made SAMs. Coverage and fun beat an exact order of battle.
- **Both sides have air forces, SAM networks and ground forces.** Most of Kola's air war carries over: SEAD, scrambles, CAP, AWACS and the radar picture.
- **The minerals are backstory** (John, 2026-10-03): they explain the war but earn nothing, and may not be modelled on the map at all. **Not an RTS:** nothing on the map produces supply for whoever holds it.

### Sessions and saved state (2026-10-03)

- **How it's played** (John): load the mission for a few hours, fly with a friend, shut it down; the state is saved and the next session picks up from it. No server running around the clock.
- **The world freezes between sessions, and the clock carries on where it stopped.** Quit at 15:40 on day 3, and the next session starts at 15:40 on day 3. Nothing happens while nobody is playing.
- **Night flying is part of the campaign.** A session can start at dusk or at night, and both the AI and the planners must work at night.
- **Weather changes slowly over time.** A campaign weather model moves on with the clock. A running mission can't change its own weather or start time, so a **launcher** (a `.cmd` / Python step run before DCS loads the mission) writes the next start time, date and weather into the `.miz`. Weather changes between sessions, not during one.
- **Saving** (proposed 2026-10-03, not reviewed in detail): every few minutes while running, at mission end, and from a server hook (`Saved Games\DCS\Scripts\Hooks`) when the simulation stops. Each save goes to a temporary file that is then swapped in, and the last few saves are kept as backups.
- **In motion at shutdown** (proposed): aircraft in the air are resolved on paper (on the way home → landed; inbound → aborted, back at base); convoys and ground units keep their position and route.
- **Destroyed scenery** (buildings, bridges) is recorded and destroyed again at load, before anyone sees it.

### Players (2026-10-03)

- **Usually both players fly Blue together.** A session where one flies Red and the other Blue must also work.
- **So the same mission design works for both coalitions:** every player-facing feature (slots, brief, comms menu, steerpoints, air picture calls, datalink) exists per coalition, and nothing in the shared library knows which side the players are on. This is the biggest structural change from Kola, which assumes Blue is "own" in many places.
- **Aircraft:** see *Aircraft*.

### Aircraft (2026-10-03)

- **Starting list, agreed in general** (John: "pretty good"), helicopters included:
  - **Red:** Su-25T, Su-27, Su-33, MiG-29, MiG-21bis, Ka-50, Mi-24P, Mi-8;
  - **Blue:** F/A-18C, A-10C II, F-15E, AV-8B, AH-64D, F-14, Mirage 2000C, UH-1H, CH-47F.
- **F-16C on both sides,** so a human can fly the F-16 for Red (John). Like Kola's cross-side equipment.
- **C-130 on both sides, flying logistics** (John): the transport that carries logistics units (see *Logistics*).
- **No JF-17 for players:** neither John nor his friend owns it.
- **Player aircraft** (2026-10-03): each player flies a module they own. John owns the C-130, AH-64D, F-16C and F/A-18C; his friend the F/A-18C and C-130. Flying the same type together: the F/A-18C or the C-130.
- **Who flies which side** (John): together, both fly Blue; against each other, John flies Red and his friend Blue.
- **Player slots:** Blue F-16C, F/A-18C, AH-64D, C-130; Red F-16C, C-130 (and the AH-64D? open). **No F/A-18C on Red** (John: feels off on the Red side).
- **Players fly logistics too:** a player C-130 carries logistics units like an AI one, so airlift is a player tasking (its own brief, load and delivery).
- **The AI flies logistics** in the C-130 and helicopters (Mi-8, CH-47F, …) on both sides (John).
- **The C-130 can land off runway at some places** (John): players only. The AI C-130 lands at airfields; no need to make it land anywhere else.
- AI aircraft from modules nobody owns may not be installed at all, so the AI rosters are checked against what's installed, as Kola's `unit_pool.lua` is generated from the DCS install.

### Logistics: logistics units (2026-10-03)

John: the entire war runs on **logistics units**, and they are its only currency.

**One thing only.** No fuel, missiles, crates or other kinds of supply tracked; everything is counted in logistics units. They pay mainly for **spawning**: a player who lands at an own base finds the weapons and fuel there, and nothing is rationed per weapon.

**Where they come from: a fixed supply, injected at rear bases**
- Each coalition gets a fixed influx at its rear bases about every campaign hour (numbers to tune in runs).
- **Not an RTS:** holding ground or sites earns nothing; nobody can gain more than their fixed supply. What a side can do is **deny the enemy theirs**: take bases, cut routes, destroy stores and transports.
- Logistics units are useless at a rear base until they are **physically moved** to where they're spent.
- **Primary receiving bases:** the bases that get the influx, picked by John when he builds the opening (two or three per side, likely). **Losing one cuts its supply:** its share of the influx stops and isn't sent anywhere else, and the new owner doesn't receive it either. It's the only way to truly cut a side's supply, so these are the war's biggest objectives.

**Captured stock** (John, 2026-10-03): when a base changes hands, its stock is lost to the side that held it; the side that takes it gets **15 % of what was there** (equipment found on the base, and a way to defend it at once). The rest is gone.

**Where they're held: stores**
- A base's logistics units sit in its **stores**, static objects of two kinds (John, 2026-10-03): **buildings** (warehouses, fuel and ammunition stores) and the **parked aircraft** on its ramp. Each store holds an equal share of the base's stock; destroying one destroys its share, so an airfield strike on the ramp has a real effect. Rebuilding a store costs logistics units and takes time. The stores make up a base's capacity, so piling everything into one hub is a risk a JFC weighs.

**How they move: between airbases, by air and by road**
- **Airbase to airbase only, to begin with;** no FARPs.
- **Airlift:** C-130s (AI and players) and helicopters. A transport shot down loses its whole load.
- **Convoys on the roads** (John: they work well and don't cost much performance; Kola has a convoy planner). A destroyed truck loses its share.
- **Our own carrying and transfer, not the module's cargo:** the load is counted by our script (load at one own base, deliver on landing or arrival at another), not read from the C-130's real cargo system, so a DCS update can't break the logistics.

**Where they're spent: the grid**
- Every airbase owns the grid zones around it (the campaign's grid, like Kola's). Anything spawned in a zone is paid from the stock of the base that owns it.

**What they buy: everything that spawns**
- **Aircraft aren't tracked; they are logistics units** (John, 2026-10-03): no squadrons, no airframe counts per base. A base flies any aircraft its runway fits (Kola's rule).
- **Aircraft, as loan and return** (John agreed): a flight's aircraft are paid for at spawn; when it lands and is removed, most of their value comes back, the difference being the sortie's cost. A lost aircraft loses its full value. So a sortie costs a little and a loss costs a lot.
- **Where the refund goes** (John agreed): to the base the flight took off from; if that base is contested or lost when the flight lands, to the base where it lands. So a flight airborne when its base falls saves its value, an evacuation flight carries value out (see *Bases changing hands*), and fighters can't be used as cargo planes to move supply forward.
- **Ground units:** reinforcements spawned in a base's zones. Units already on the map are saved with the campaign and not paid for again.
- **SAM sites:** a new site, or a destroyed radar or launcher replaced.
- **Repairs:** stores, SAM sites. **No runway repairs:** runway damage doesn't really work in DCS, so it isn't modelled.
- **A base without enough stock can't spawn;** the JFC has to move supply there first.

**Players**
- **A player's spawn costs logistics units, and a base without enough stock blocks it** (John: experiment with how that works).
- **No loss for a dropped player:** a player who disconnects or crashes out of the game isn't charged the loss of their aircraft. Proposed: automatic when the aircraft leaves the world with no hit on it in the last minute or so, plus an admin "cheat" command in the comms menu to refund a loss by hand.

**DCS's built-in warehouses if they fit, else our own** (John: prefer existing systems, but not if they cause problems or don't support the design). Research: whether one of the warehouse's numbers can hold the logistics units and do everything above; otherwise the count lives in our script and the save, and DCS's warehouses stay unlimited.

### Command layers (2026-10-03)

John: the JFC runs the strategy and passes directives to the controller; the controller is responsible for individual commands and decisions.

1. **Joint Force Commander (JFC):** strategy, one per coalition. Reads its own coalition's intelligence picture, never the truth (Kola's rule: no side reads the other side's plan). Writes **directives**: objectives and their priority, how the air effort is split, what to defend, where the ground forces push, how much risk to accept, where supply goes.
2. **Air tasking planner** (proposed, Kola's `PlanAirTasking`): turns the directives into an air tasking order: flights, targets, times, routes. Today Kola's planner sets its own priorities; here it takes them from the JFC. In a real air force this is the air operations center.
3. **Mission Operations Controller (MOC):** real-time execution, the Kola controller (`control_air_flights/`) grown up: scrambles, the bandit call, go cold, retries, the leash, and later the ground forces' moment-to-moment orders.

### Rules and text, side by side (2026-10-03)

John: the design must work without an LLM and be better with one. The JFC may become an LLM first (2–3 text-heavy calls per session, cheap), and later possibly the air tasking planner and the MOC too. So every decision layer is designed to be run by rules **or** by a language model.

How (proposed 2026-10-03, to review):
- **Every decision point has two plain-data tables with a fixed shape:** the *situation* (what the decider knows) and the *decision* (what it orders). Everything below a decider reads only the decision table, never who made it.
- **Two renderings of the same situation:** the rules engine reads the table; the language model gets it written out as a briefing in plain text and must answer in the decision's fixed shape (JSON). Kola already keeps facts and text apart in the air picture calls (`describe` vs the text functions); this makes it the rule everywhere.
- **Every decision is checked by the same validator,** whoever made it: units that exist, within fuel and range, supply that is there. A model's decision that fails the check, times out or can't be reached falls back to the rules engine's, and the log says so.
- **The middle road, likely the best one:** the model sets the *intent* (priorities, weights, risk, a written commander's intent), and the rules engine does the arithmetic (which flight, which base, which route). The model is where judgement adds the most, and the rules engine is where it can't go wrong.
- **Both explain themselves in text:** the rules engine writes a reason with each decision (as Kola's `CONTROL` lines do), the model writes its rationale. Both go in the log and the saved state.
- **Replays stay reproducible:** a model's decisions are saved with the state, so a harness replays them without calling the model.
- **Where calls happen:** DCS's Lua can't easily make web calls. The JFC's calls fit the launcher (before the session, Python) or a helper process next to DCS during the session, exchanging files with the mission. The MOC decides every few seconds, far too often for a model; a model there would only take the slow calls (retargeting, whether a mission still makes sense), never the bandit call.

### Bases changing hands (2026-10-03)

- **Our own capture rule, not DCS's** (John agreed after the research): auto-capture off at every base (`autoCapture(false)`), and the script calls `setCoalition` when our rule says so. Why: the save is the only truth about who holds a base (DCS can't flip one at load), the logic doesn't depend on undocumented DCS behaviour that an update could change, and every rule (zone, timing, which units count) is ours to set and log.
- **What DCS does, for reference** (research, 2026-10-03): a zone about 2 km around the airfield's centre (undocumented; reports differ); only live ground units count (not aircraft, statics or wrecks); both sides present → contested; one side left → it owns the base, at once; an undocumented "strength" rule (a truck or infantry entering against an enemy IFV doesn't contest it); `S_EVENT_BASE_CAPTURED`; no settings. Liberation wrote its own trigger-zone check after capture bugs (parked aircraft blocking captures).
- **Only ground forces capture;** air power clears a base but can't take it.
- **No hunting the last defender** (John): a MANPADS team hidden in the trees doesn't hold a base against six tanks next to the runway. The rule weighs the forces on each side, not whether every enemy unit is dead.
- **Combat value** (agreed 2026-10-03; numbers to tune): each ground unit counts by its role (unit pool roles): tank 10, IFV 6, APC / armed scout car 3, SHORAD / AAA / SAM launcher 2, infantry squad / MANPADS team 1, trucks and support vehicles 0. A damaged unit may count in proportion to its life left.
- **Capture zone:** a circle around the airfield, half its longest runway + ~2 km; forces fighting outside it don't count.
- **States** (agreed), checked every 15–30 s for bases with enemy ground forces near:
  1. **Held:** the owner's forces only, or the enemy below the contest minimum (a truck or scout car passing doesn't shut a base).
  2. **Threatened:** enemy ground forces within ~15 km. The base works normally; the JFC is told and decides: evacuate, reinforce or hold.
  3. **Contested:** the enemy has at least the contest minimum (combat value ~6, an IFV) in the zone. **The base spawns nothing** (John): no launches, no ground spawns.
  4. **Capturing:** the attacker has at least **3×** the defender's combat value in the zone and at least the capture minimum (~10); a hold timer runs. Below 3:1 the timer resets and the base is only contested.
  5. **Captured:** after **10 min** of capturing. The base flips; **defenders still in the zone surrender** (removed, logged), so a hidden team can't contest it straight back.
  6. **Setup** (John agreed), then held by the new owner: aircraft launch from it only after a setup period (30–60 min of campaign time proposed) and a minimum stock delivered.
- **Logged** under `CAPTURE`: threatened, contested, capturing (each side's combat value and the ratio), timer reset, captured, surrendered units, setup done. A base's state and timers are saved, so a capture in progress at shutdown carries on.
- **The base fights to the end on the ground** (John): no retreat orders for ground units (too complicated, unlikely to work in DCS).
- **Evacuation by air** (John agreed): the JFC of a threatened base may order **evacuation flights**: jets with no mission flown to a safe base, carrying their value out (see the refund rule under *Logistics*), and C-130s / helicopters carrying stock out. Evacuate too early and a base that could have held is given up; too late and it's contested and nothing gets out: a real commander's call.
- **Captured stock:** 15 % to the new owner (see *Logistics*); a primary receiving base's influx stops.
- **Store buildings still standing** become the new owner's capacity; destroyed ones stay destroyed (proposed). The loser's parked aircraft are removed (next line), so their share is part of the stock lost.
- **The loser's parked aircraft are removed** when the base flips (John).
- **Player slots follow the base** (John tested it in the Syria mission): DCS dynamic slots become available to the base's new coalition by themselves; nothing to script.

### Ground war (2026-10-03)

- **A real ground war, fought in DCS** (John): ground forces move and fight, and the front moves because of it. Making it run well is a design problem to solve, not a reason to put it on paper.
- **The unit is a company** (John agreed, 2026-10-04): one DCS group of 4–12 vehicles, the piece the campaign saves and the MOC orders. The JFC plans in battalion task forces of 3–4 companies.
- **Movement: mostly by road, plus off-road routes** (John, 2026-10-04): roads don't cover every tactical route, and the mountains matter: valleys and passes are what both sides fight over. **The off-road routes come from the site survey's slope data, nothing hand-drawn** (John, 2026-10-07: hand-drawn routes dropped; everything is built by code into data files consumed later; *Map data: the site survey*).
- **DCS's AI fights; the MOC gives broad orders** (John, 2026-10-04), in the same shape as the air controller (situation → directive → intent → orders).
- **New units are bought with logistics units,** spawned in an own base's grid zones and driven to the front (John, 2026-10-04).
- **Unit volume starts from Syria's** (John, 2026-10-04: Syria runs fine with lots of moving ground units): see the numbers under *Next discussion*.
- **The territory grid follows the bases held, not the ground forces** (John, 2026-10-04: ground forces move and spawn constantly, so a grid drawn from them would churn). Own / contested / enemy cells change only when a base changes hands. The ground forces' positions still reach the JFC and the MOC through each side's intelligence picture, so a push up a valley is seen and answered without redrawing the map.
- **The moving cap starts at Syria's maximum load** (John, 2026-10-04): up to **~310 ground units moving or attacking at once** (~133 of them vehicles), about 15 companies plus infantry, both sides together; companies beyond it wait or sleep. Syria's top end is only what we know runs well, not the true upper bound, which nobody has measured. It's a starting point, raised or lowered from frame rates in runs.

### Map and opening (2026-10-03)

- **Bases start with fixed owners, set by John;** no random territory roll at the start (unlike Kola).
- ~~Spawn zones are drawn by John in advance, as in Kola's zone survey.~~ Replaced 2026-10-07: the site survey finds them (*Map data: the site survey*).
- **A grid like Kola's airspace grid** (`divide_airspace.lua`, 10 km cells: own / contested / enemy, regions and pockets).
- **The theatre is the whole map** (John, 2026-10-07).
- **Base owners come from the scenario story,** decided together (John, 2026-10-07). Airbase data (codes, classes, tower frequencies) and the player slots (dynamic slots, now for both coalitions) work as in Kola and Caucasus.

### Map data: the site survey, not drawn zones (2026-10-07)

John: drawing zones by hand is time-consuming and limiting, so on this map nobody draws them. A survey finds the places instead.

#### Decided

- **Nothing on this map is drawn by hand** (John): sites, routes and every other map fact are built by code into data files that the missions consume. Hand-drawn off-road routes are dropped too (*Ground war*).
- **One kind of site:** a clear, flat, dry area where anything fits: a group of ground units, a large SAM site, a target. Nothing more granular (John: the map is big and mostly open). What goes in a site is decided as things spawn.
- **A survey mission of its own, started by hand,** never part of a flyable mission or its start. Its result serves **any mission on the Afghanistan map**. Run again only after a DCS map update or a change to what it measures.
- **The map's data lives in the framework, per map** (John: it is mission-agnostic): `shared_mission_framework\map_data\afghanistan\` (not created yet), read by any Afghanistan mission. This is roadmap item 18 arriving early.
- **Where the pieces live** (John: tools and generators, not mission scripts): the Lua that runs in the survey missions in `shared_mission_framework\map_surveys\` (copied to `Saved Games\DCS\Scripts\map_surveys\`); the Python that decides in `shared_mission_framework\map_data_tools\`; raw survey output in `Saved Games\DCS\map_surveys\<map>\`.
- **In passes, coarse to fine** (John agreed; resolutions to adjust if they don't work): pass 1 the whole map on a 1 km lattice (cheap: most of the mountains drop out), pass 2 the flat and dry cells at 100 m, then map objects; resumable batches on a timer, so DCS never freezes for long.
- **Raw measurements in DCS, the judgement in Python,** so the site rules are tuned without flying the survey again.
- **Test in small areas first, then survey the whole map once** (John: the whole survey takes over an hour, so not more than once). Several test areas, each looked at in a viewer mission with units spawned in the sites to check by eye.
- **Hands-off** (John: "I just want you to populate the map … I don't want to select zones and run surveys"): one flight of the survey mission surveys, finds the sites and shows them.
- **Units never stand in water: each unit's own spot is checked at spawn** (John, 2026-10-07, after trucks stood in rivers; option 2 of three): a spot on water moves to the nearest dry ground in the site. The survey's water check stays at 100 m (a 50 m check would add ~50 min to the whole-map survey; John: too long), so a narrow river can still cross a site; the spawner keeps units out of it. The real missions' ground spawner must do the same.
- **Each vehicle's own spot must also be flat** (John, 2026-10-08: every site suits trucks off road, but parts of a site wouldn't take an SA-10; "require a more stringent flat area for the vehicles within the zone"): the ground at the spot and 8 points 8 m around it within 0.8 m (a 16 m footprint, ~3°); else the nearest dry, flat spot in the site, or the vehicle is left out. Built in the viewer (`show_spawn_sites.lua`, `goodSpot`), and in the framework's placement for every mission (`Placement.unevenGround` in `isClear` / `isClearRoad`, 2026-10-08; John: "working exceptionally well"). The site rules themselves are unchanged.
- **SA-10s to judge the sites by** (John, 2026-10-08): the viewer lays out 50 SA-10s (the framework's own recipe, `sam_site_recipes.lua`, read from the repository) in sites picked evenly across the shown areas, red circles on the F10 map; the rest of the sites keep their trucks.
- **Unit routing from pass 1** (John: "a very good idea"; not built): the lattice's slope data is also a map of where vehicles can drive, so the ground planner can find off-road routes and give companies waypoints (DCS ground units don't find their own way off road).
- **Grid assignment comes later, on top** (not built): each campaign grid cell gets the sites inside it; when a base changes hands its cells' sites go with them, nothing surveyed again.
- **Trees are invisible to every DCS API:** a site in a green zone may hold orchards.

#### How it works (built 2026-10-07)

**The missions** (in `Saved Games\DCS\Missions\`, written by `find_spawn_sites.py make-missions` from John's empty `Afghanistan_survey_1.miz`; each is one trigger, ONCE → TIME MORE 1 → DO SCRIPT, running one `map_surveys` script; both need the de-sanitized `MissionScripting.lua`):
- **`afghanistan_spawn_site_survey.miz`:** the survey. With no trigger zone in it (as now): the whole-map survey (below). With trigger zones: test areas around them; wait for "SURVEY DONE" (~1–2 min per area), look at the F10 map.
- **`afghanistan_spawn_sites_shown.miz`:** shows the test areas' sites, without surveying.

**The whole-map survey** (built 2026-10-08, offline-tested, not flown; decided with John the same day):
- **The area:** `shared_mission_framework\map_data\afghanistan\survey_area.lua`, the four GPS corners John read off the F10 map. The survey converts them with DCS's own `coord.LLtoLO` (exact, unlike the fit below) and measures the smallest x / z box around them, widened to the 1 km lattice. **Another map** (Kola, Caucasus, … later): draw its rectangle, read the corners, add `map_data\<map>\survey_area.lua` (the map's name in lower case); nothing else is map-specific. **Forests:** trees are invisible to DCS's API, so on forested maps sites may land in woods; noted in the script, to deal with when porting (John).
- **100 km tiles** on a lattice from x = 0, z = 0, cut to the box (Afghanistan: 88), south to north. Each tile measured as a test area is (pass 1, pass 2, map objects; below), then written to a `.tmp` and renamed, so a tile file is whole or not there. **A crash loses one tile at most:** flying the survey mission again carries on with the first missing tile.
- **Each run its own dated folder,** `map_data\afghanistan\survey_measurements\<date>_<time>\` (in the repository, git-ignored; John backs it up to his own cloud): `run.lua` (box, corners, settings, DCS version if DCS gives it), `latitude_longitude_grid.txt` (`coord.LOtoLL` every 10 km, for the sites' GPS), the `tile_*.txt` files (a line per cell, heights packed: pass 2's as metres above the cell's lowest point; one surface letter when they're all the same; object squares only where there are any), `survey_complete.lua` at the end.
- **On screen every 10 s, by the wall clock,** for 5 s and replacing the last line (John: lines stacked up unreadably): the tile (of 96, its x / z range), what it is doing (cells measured and through to pass 2, or the 5 km object square), the whole map's %, the time this session, **the time left from this session's finished tiles** (their seconds per cell × the cells left; John: the first estimate, from cells measured so far, climbed to 22 h), and the share of DCS's time the survey gets. Each finished tile in `dcs.log` with its timing: slices, % of the time, and **the time per kind of DCS call** (heights, surfaces, object searches).
- **Pacing** (first flights, 2026-10-08): 0.2 s of work per frame woke DCS's anti-freeze (mission time held still, the escape menu wouldn't open); 0.05 s per tick of mission time still did, and crawled. Now a 0.05 s slice of work, then a rest as long, by the wall clock. Tile 5 still took 802 s (528 s of work, 65 % of the time, slices averaging 0.16 s) where tiles 1–4 took 2–15 s: one DCS call far over the slice. **Suspect: the nearest-road lookup** (one per pass 2 cell, can't be split; tile 5's cells are a median 26 km from a road), so:
- **Road distances: looked up in the mission, if and when needed** (John, 2026-10-08, after the first full run): the whole map has ~250,000 sites, too many to look up (hours at the remote-desert speed), so the sites files carry no road distance; **a mission that needs one calls `land.getClosestPointOnRoads` for the few sites it actually uses** (one call each; fast near roads, can be 0.1 s or more far from any). The tiles don't look up roads either (`?` in their road field; tiles 1–5 of the first run have the cell centre's, unused). A per-site road pass at the end of the survey was built and taken out the same day (it hung DCS loading the then one 39 MB sites file before its first lookup).
- **At the end** it starts `find_spawn_sites.cmd map-survey afghanistan <run>` on its own (DCS isn't frozen while it works, minutes on the whole map), shows its progress lines, then the summary: sites found, why points were rejected, and against the last sites file: how many are the same (within 100 m), new and gone. Nothing is drawn (John: the data file is the point; drawing and test spawns later).
- **The result, split by tile** (John, 2026-10-08: keep every site, but split the data for size and so a mission loads only what it queries), replaced only by a finished run:
  - **`map_data\afghanistan\spawn_sites_index.lua`, the index** (John: named as one; `SPAWN_SITES`): the map, the run, when found, `tile_m`, `folder`, `site_fields`, the rules (every site is a disc of `rules.site_radius_m`, 275 m), the counts, and `tiles`: per tile its `name`, `file`, `x_min` / `x_max` / `z_min` / `z_max` (its 100 km lattice square), `sites` and `first_number`.
  - **`map_data\afghanistan\spawn_sites\tile_<x km>_<z km>.lua`, one per tile with sites** (`SPAWN_SITES_TILE`: `tile`, its bounds, `sites`): one short line per site, `{ number, x, z, latitude, longitude, height_m, rise_m }` (the order in `site_fields`). Numbers run across the whole map, south-west to north-east, so a site keeps one id.
  - **How a mission reads it:** `dofile` the index, pick the tiles whose square overlaps the area it needs, `dofile` those (`SPAWN_SITES_TILE` each); never the whole map at once. No shared loader yet; it comes with the first mission that uses the sites.
  - Written to `spawn_sites.tmp\` first and swapped in, the old tile files removed one by one.
- **Flown again after a finished run,** it says so and offers, under *Spawn site survey* in the comms menu: **"Survey the map again"** (after a DCS map update: a new run folder, the old one kept) and **"Find the sites again"** (after a change to the site rules: no flying, minutes).
- **The same sites a test area would give:** a site near a tile's edge is judged with the neighbouring tile's points, and the spacing is chosen across the whole map at once (checked offline: identical to the test-area finder on the same points).

**One flight of the survey mission with trigger zones (test areas):**
1. **`map_surveys\survey_spawn_sites.lua`** surveys a 30 × 30 km square around each trigger zone (its name names the area), snapped to the 1 km lattice. An area whose file already exists is skipped (delete its `area_<name>.lua` to survey it again). (Until 2026-10-08 it surveyed squares around a list of airbases, `TEST_AREAS_AROUND`, when there was no zone; removed with the whole-map survey.) Per area:
   - pass 1: every 1 km cell, 3 × 3 heights and surface types (L land, R road, W water, S shallow water, U runway);
   - pass 2: the cells with ≤ 60 m between their highest and lowest pass-1 point and no water (loose on purpose): 11 × 11 heights and surface types every 100 m, edges included, and the distance from the cell's centre to the nearest road;
   - map objects (buildings, walls, rubbish, containers …): one `world.searchObjects` per 5 km tile; per cell the count, and on pass-2 cells the count in each 100 m square and a tally by type;
   - written to `Saved Games\DCS\map_surveys\Afghanistan\area_<name>.lua` (`SURVEYED_AREA`).
2. Then it runs **`map_data_tools\find_spawn_sites.cmd`** (Python 3.10 if installed, else `python`), which runs **`find_spawn_sites.py`** on every `area_*.lua` and logs to `find_spawn_sites.log` beside them. The repository's place on this PC comes from **`Saved Games\DCS\Scripts\map_surveys\local_paths.lua`** (`MAP_SURVEY_PATHS.repository_folder`), which lives only there, never in the repository (bug 76); copying the scripts leaves it alone. Without it the run ends with the command to type.
3. Then it runs **`map_surveys\show_spawn_sites.lua`**, the viewer.

**The site rules** (`find_spawn_sites.py`, at the top of the file): every 100 m survey point is tried as a centre:
- a disc of **275 m radius** (550 m across; Kola's zones were 274 m circles, which every SAM site and target fit);
- every survey point in it surveyed in pass 2 (else "steep or wet nearby"), on land or road (no water, shallow water or runway);
- **no map object** in any 100 m square that reaches within the disc + 50 m;
- **≤ 15 m** between its highest and lowest point, and **≤ 10 m** between any two neighbouring points (a 10 % slope);
- then the flattest first, **≥ 1 km between centres**.

It writes `spawn_sites_<name>.lua` (`SPAWN_SITES`: the area, the rules, the counts and why points were rejected, each site's number, x / z, radius, height, rise, and road distance from its cell; and the "near misses", flat and dry cells with no site) and prints a summary per area.

**The viewer** (`show_spawn_sites.lua`) reads every `spawn_sites_*.lua` and draws, on the F10 map for everyone: each area's outline and name (yellow), each site as a green circle with its number, each near miss as an orange square. On the ground: one **Red ground group per site** (CJTF Red, AI off, so F7 cycles through them; John asked for units, not statics), 19 Ural-375 trucks: one at the centre, 6 at 45 % of the radius, 12 at 90 %. **Each truck's spot is checked:** on water it moves to the nearest dry spot (land or road) in the site, looked for on rings 10 m apart, 16 directions each; with none it is left out. The screen and `dcs.log` (`[SPAWN SITES SHOWN]`) say how many moved or were left out.

**The probe** (`map_surveys\probe_terrain_survey_costs.lua`, the first step, flown once): times every DCS call the survey uses, writes every airbase (`airbases.lua`: name, id, callsign, category, coalition, position, runways, parking) and surveyed 60 × 60 km around Bagram and Kabul. Its findings shaped the survey; they are in `dcs_scripting_gotchas.md` (call costs, Afghanistan's map) and below.

#### What has been run

- **The probe, 2026-10-07** (~8 min): height ~65 µs, surface ~24 µs, nearest road ~0.16 ms, **nearest railway ~0.2 s** (no railways on the map: never asked), ~6 µs per map object found. 26 real airbases; heliports report as airdromes; FOB Camp Dubs, Clark and Thunder are placeholders far off the map with no runways. Around Bagram / Kabul 38 % of the 1 km cells were flat and dry, but there are 1.5 million map objects (Afghan compound pieces, `PARTHOUSEAFGHANISTAN_*`), so in the built-up valleys the objects decide more than the slope. A whole-map survey: estimated ~1½–2 h of running.
- **Bagram / Kabul, from the probe's data** (converted into the survey's format, `area_Bagram_Kabul_probe.lua`, because the probe kept every object): **214 sites** in 60 × 60 km, median 331 m from a road. Points rejected as centres: map objects 91,515, steep or wet nearby 17,247, rise 12,208, water or runway 11,149, slope 44. **John's review in the viewer, 2026-10-07: "That looks pretty good honestly"**; the one problem, trucks in rivers, led to the spawn-time water check (above; built after that review, not seen in DCS yet).
- **Kandahar and Jalalabad, 2026-10-08** (30 × 30 km each, surveyed 10:59, sites found 11:13; `find_spawn_sites.log`):
  - **Kandahar** (open desert and dunes): 815 of 900 cells flat and dry enough for pass 2, **276 sites**, median 251 m from a road. Points rejected as centres: map objects 51,251, steep or wet nearby 6,368, water or runway 5,829, rise 1,310, slope 81 (the desert's slope barely rules anything out).
  - **Jalalabad** (a narrow green river valley between mountains): 570 of 900 cells, **117 sites**, median 328 m from a road. Rejected: map objects 33,878, steep or wet nearby 8,966, rise 8,618, water or runway 4,492, slope 32.
  - Bagram / Kabul's sites found again in the same run, unchanged (214).
- **The review in the viewer, 2026-10-08:** all three areas in `afghanistan_spawn_sites_shown.miz`, trucks in every site, the 50 SA-10s, the per-vehicle water and flatness checks at spawn. **John: everything is working right in terms of finding correct zones; approved for the whole map.** Camp Bastion, Herat and Maymana weren't needed as test areas.

- **The whole map, run 2026-10-08_1301** (finished 2026-10-08 13:56 after three sessions: the anti-freeze and road-lookup fixes above): 96 tiles, 781,044 cells, 383,875 through to pass 2, 27 min of measuring once the road lookups were gone; raw data 172 MB. `find_spawn_sites.py` (818 s): 39.1 M points looked at, 26.3 M could centre a site, **249,458 sites** (my estimate had been "several thousand": the test areas' 0.1–0.3 sites per km² over 780,000 km² was always ~250,000). Rejected: rise 7.0 M, map objects 2.8 M, steep or wet nearby 2.6 M, water or runway 0.3 M, slope 44 K. That one `spawn_sites.lua` was **39.4 MB**, too big for the repository and for a mission to load in one go (DCS sat 13+ min in the road pass's `dofile` of it), so (John: keep every site) the sites were written again split by tile, from the same run (1,068 s): all 249,458 the same, an 18 KB index and 94 tile files (2 tiles have no site), 16 MB in all, the biggest 574 KB (8,781 sites). DCS's own Lua (`luae.exe`) loads the index in under a millisecond and the biggest tile in 0.012 s.

#### Next

1. ~~**Two more small test areas**~~ (Kandahar and Jalalabad, done and approved 2026-10-08, above).
2. **The whole-map survey**, once the rules hold. **The theatre to survey is a rectangle John drew on the F10 map** (2026-10-08, `C:\Users\johnk\Desktop\afghanistan_survey_area.jpg`; easier than exclusion zones). It covers Afghanistan from Herat / Zaranj to Jalalabad / Khost, with edges of Turkmenistan, Iran and Pakistan inside it. John's corners read off the F10 map with the mouse (degrees, decimal minutes): NW N37 02.256 E60 37.425, NE N36 39.763 E72 30.615, SW N30 28.647 E60 47.370, SE N30 10.378 E71 51.097. Roughly, in DCS coordinates (a transverse Mercator fitted to 19 airfields' real coordinates against `airbases.lua`: central meridian ~63° E, ~1.3 km accuracy): **x −389,000 to +342,000 (731 km south to north), z −513,000 to +555,000 (1,068 km west to east)**, about 780,000 km², 88 tiles; the survey itself converts the corners exactly with DCS's `coord.LLtoLO`. The F10 map is north-up in DCS's own frame, so the rectangle is a plain x / z box. It lies inside the map, so finding the map's edges is no longer needed. **Built and run 2026-10-08** (*How it works*, *The whole-map survey*; *What has been run*): 96 tiles, 249,458 sites, split by tile.
3. **Next session:** a look at the sites (drawing them or test spawns in a chosen tile, from the split files), then the grid assignment and the off-road routing from pass 1. A shared loader for the sites comes with the first mission that uses them.

---

## Next discussion: the ground war

Session 2 (2026-10-04): questions 1, 2, 4, 5, 6 and 7 answered (under *Decided*, Ground war). Still open:
- **Performance (3):** the claim that moving ground units cost the most was a rule of thumb in Kola's plan, never measured; John's Syria runs fine with dozens of moving vehicles. Proposed: everything in DCS, Kola's sleeping for idle companies far from any fight, and measure before adding anything else (no movement on paper unless runs show the need).
- **Scale (7):** from Syria (`a2g_dynamic_syria/modules/convoy_setup.lua`, `cas_mission.lua`), which runs well, at once:
  - 3 convoys: 24–68 vehicles, moving;
  - Attack HS02: Blue attackers 18–32 (12–20 infantry, 6–12 vehicles), moving, against a Red garrison of 39 (28 infantry, 11 vehicles);
  - Defend Kovanli: Red attackers ~38–210 in 1–3 groups (infantry 31–157, 7–53 vehicles, by force level), moving, against 40 Blue defenders (30 infantry, 10 vehicles);
  - so ~80–310 moving units (37–133 of them vehicles), ~80 more fighting in place, plus base defenses and SAMs standing. In companies of 4–12 vehicles: roughly 8–15 companies moving or fighting at once, both sides together, plus infantry.
- **The MOC's ground orders:** the DCS commands available (see the session 2 answer): routes on or off road with formations, hold, stop / resume, fire at a point (artillery), ROE, alarm state, disperse under fire, embark / disembark; no "attack that group" task for ground units, they fight what they find on their way.

## Open

To settle with John, roughly in this order:

1. **Aircraft:** the AI rosters per coalition and role, checked against what's installed; whether Red gets an AH-64D slot for John.
2. **Bases changing hands, what's left** (designed under *Decided*): the setup period's length; tuning the combat values and thresholds in runs; the JFC's evacuation rule.
3. **The ground war's design:** how it moves (roads, the mountains, DCS ground pathing in this terrain), how much of it is active at once for performance (Kola's sleeping units, an active budget, battle areas near players), how fights are started and ended, reinforcements.
4. **Logistics, what's left** (the design is under *Decided*): the influx per base (numbers); costs of each kind of spawn; transport loads; how the JFC directs supply and who plans the transport flights and convoys (agreed in outline: the JFC says where supply goes, a logistics planner builds the flights and convoys around the threats, the MOC runs them, player C-130 runs offered as taskings, escorts or CAP cover on risky routes); how logistics is shown (comms menu, map, `LOGISTICS` event word); the warehouse research; the dropped-player refund.
5. **What the save holds,** in detail: units and their damage, each base's stock and stores, base states and capture timers, scenery destroyed, the JFCs' orders, the weather model.
6. **The JFC's directives:** their exact shape (the table everything below reads), how often the JFC decides (session start, every campaign hour, on events), its rules engine.
7. **Victory and defeat:** territory (bases held), a side's supply cut off, attrition, or none (an open-ended war). Not mineral sites: they're backstory.
8. **The weather model:** seasons, fronts, Afghanistan's dust, snow in the passes, valley fog; how fast it changes per campaign hour.
9. **The shared library:** what moves out of Kola, where it lives, what it's called (no generic folder name), and how Kola keeps working while code moves (Kola is still in active development; its plan says no shared code with Syria, which stays true). Whether Kola's controller is renamed the Mission Operations Controller too. **Answered 2026-10-06 except the last question:** it is `shared_mission_framework\` (the Lua in `mission_scripts\`, the radio in `radio_calls\`, the map tools in `map_data_tools\`, the offline test harness), split out of Kola step by step with Kola tested and flown after each step: the root `plan.md` (status and build log) and `shared_mission_framework\framework_design.md` (how a mission sits on it, its `mission_settings.lua` and map and scenario data, and how the code works); overrides were retired 2026-10-06 (each mission's settings live only in its own data). Syria stays separate. Still open: the controller's name, and making every player feature per coalition (the framework plan, *Later*).
10. **The launcher:** what it does before each session (weather, time, the JFC's model call, a backup of the save), how it's run.
