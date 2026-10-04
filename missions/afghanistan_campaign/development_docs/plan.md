# Afghanistan Campaign — Plan

> **What this is:** the design of a persistent DCS campaign on the Afghanistan map. Two coalitions fight a conventional war, in the air and on the ground, over a few hours of play at a time. When the mission is shut down the campaign's state is saved, and the next session picks up from that state. Each side is led by an AI Joint Force Commander (strategy) that hands directives down to an air tasking planner and a Mission Operations Controller (execution). Logistics feed the whole war. Much of the code comes from the Kola mission (`missions/kola_f16_random_tasking/`), and the parts both missions use move into a shared library.
>
> **State:** planning only (started 2026-10-03, session 1). Nothing built. Decisions so far are under *Decided*; **next session starts with *Next discussion: the ground war***; everything else still open is under *Open*.
>
> **Paths** are relative to this mission folder (`missions/afghanistan_campaign/`, one up from `development_docs/`) unless they say otherwise.
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
- **Movement: mostly by road, plus drawn off-road routes** (John, 2026-10-04): roads don't cover every tactical route, so John draws zones that say where companies can move off road, with terrain facts measured by a survey like Kola's zones. The mountains matter: valleys and passes are what both sides fight over.
- **DCS's AI fights; the MOC gives broad orders** (John, 2026-10-04), in the same shape as the air controller (situation → directive → intent → orders).
- **New units are bought with logistics units,** spawned in an own base's grid zones and driven to the front (John, 2026-10-04).
- **Unit volume starts from Syria's** (John, 2026-10-04: Syria runs fine with lots of moving ground units): see the numbers under *Next discussion*.
- **The territory grid follows the bases held, not the ground forces** (John, 2026-10-04: ground forces move and spawn constantly, so a grid drawn from them would churn). Own / contested / enemy cells change only when a base changes hands. The ground forces' positions still reach the JFC and the MOC through each side's intelligence picture, so a push up a valley is seen and answered without redrawing the map.
- **The moving cap starts at Syria's maximum load** (John, 2026-10-04): up to **~310 ground units moving or attacking at once** (~133 of them vehicles), about 15 companies plus infantry, both sides together; companies beyond it wait or sleep. Syria's top end is only what we know runs well, not the true upper bound, which nobody has measured. It's a starting point, raised or lowered from frame rates in runs.

### Map and opening (2026-10-03)

- **Bases start with fixed owners, set by John;** no random territory roll at the start (unlike Kola).
- **Spawn zones are drawn by John** in advance, as in Kola's zone survey.
- **A grid like Kola's airspace grid** (`divide_airspace.lua`, 10 km cells: own / contested / enemy, regions and pockets).

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
9. **The shared library:** what moves out of Kola, where it lives, what it's called (no generic folder name), and how Kola keeps working while code moves (Kola is still in active development; its plan says no shared code with Syria, which stays true). Whether Kola's controller is renamed the Mission Operations Controller too.
10. **The launcher:** what it does before each session (weather, time, the JFC's model call, a backup of the save), how it's run.
