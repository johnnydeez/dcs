# Kola F-16 Randomized Mission Generator — Planning Doc

> **Status:** v0 — initial planning, 2026-09-21. No code yet.
> Companion to the Syria project (`notes/notes.md`). Open questions are marked **[Q]** — answer them inline and the doc becomes the spec.
>
> **Layout:** *Last session* (pick up here) → *Plan* (§1–10, concept and research) → *Architecture* (§11, code structure decisions).

---

## Last session — where we left off  *(2026-09-21)*

**Done this session:** §11.1–11.5 — separate from Syria; one plain-data plan table built by the 7 stages, nothing spawns until it's finished, immutable after build; startup sequence (load → wait → gather inputs → stages → dump → hand off); consumer list; consumers build DCS formats on the fly, no separate spawn/mission tables.

**Moving to the Windows dev box to start writing.** Still to decide, in the order we'll hit it:

*Needed before the first file:*
1. **Kola script directory layout and load order** — what `init.lua` loads and in what order (data files, stages, consumers). Install path and the ME trigger line, since it's separate from Syria.
2. **Naming / id convention** — group names, mission numbers, target ids, ME late-activation group names. Planner assigns them, tracker matches DCS events back to them, so it has to be settled before stage 1 is written.

*Needed by the time we reach the executor:*
3. **Runtime state table shape** — what spawner/scheduler/tracker record and how it's keyed to the plan.
4. **ATO scheduler + scramble loop** — tick rates, alive-cap policy (defer vs drop a line), how the landing-despawn handler feeds the count.
5. **Success model** — binary per line vs score (§9 item 9).

*Can wait for their phases:*
6. Skynet (phase 3), pydcs (phase 8), naval research (phase 2).

*Phase 0 prerequisites on the Windows box (§8):* Kola `.miz` with dynamic-spawn F-16 slots, de-sanitize check, `dumpAirbases()` to confirm base name strings, runway lengths.

**Suggested start for the next session:** items 1 and 2, then write `init.lua`, the input-gather step, and stage 1 — enough to get a plan dump on screen and prove the pipeline before any spawning exists.

---

## 1. Concept  *(decided 2026-09-21)*

A mission generator for the **F-16C Block 50** on the **Kola map**. When the `.miz` loads, the script:

1. **Rolls the battlefield** — Syria-style cluster assignment: some clusters always Red, some always Blue, contested clusters randomized. Airbase ownership, F10 territory circles, dynamic-spawn slots all follow.
2. **Generates an ATO for a ~6-hour window** — a coherent set of Blue flights (CAP rotations, tanker tracks, AWACS, strike packages, SEAD, escort, CAS) *and* a Red ATO opposing it. **One Blue line is the player's flight**; every other line is flown by AI. The player does not know whether tonight is SEAD, CAS, airfield strike, CAP, etc. until the frag arrives. Everything must be *consistent with the roll*: targets in Red territory, launch bases Blue and in range, threats in between, TOTs deconflicted.
3. **Delivers the intel** — the player's frag with essentials on screen, the full ATO and intel sections in F10.
4. **Executes the ATO** — spawns AI flights on schedule, keeps the alive-aircraft count under a performance cap.
5. **Tracks the outcome** — knows when the player's objective is met or failed, reports it, feeds the cost tracker. Later: lets the player pick another ATO line after landing.

All F-16 role types in §4 are in scope. The Syria sandbox stays as-is; this is a sibling project, not a replacement.

See §1.9 for the ATO model — it's the organizing idea for the whole project.

Where the Syria project is a *sandbox* (everything spawns at T+0, players pick what to hit), this project is a *tasking generator*: the player gets a mission card, flies it, and the mission knows whether it succeeded.

**Players:** 1 for now, 2 F-16 slots (friend later). No AI in the player's flight.

### 1.1 The build order  *(decided 2026-09-21)*

The key architectural idea: **separate the plan from its execution.** `Planner.build()` is a pure function of (RNG, content catalog, config) that returns a plain Lua table. `Executor.run(plan)` spawns things. `Briefing.deliver(plan)` talks to the player. This lets us log the whole plan to a file, replay it, or dry-run the planner without spawning a single unit.

The plan is built in **stages**, each consuming the outputs of every stage before it and never reaching backward. Later stages can be *intelligent* because earlier stages have already fixed the facts they need.

```
 ┌────────────────────────────────┐
 │ 1. Base coalitions             │  cluster roll → base ownership
 │    + front geometry            │  + distance matrix, frontline bases,
 │                                │    cluster adjacency across the line
 └───────────────┬────────────────┘
                 ▼
 ┌────────────────────────────────┐
 │ 2. Base defenses (Red & Blue)  │  AAA / MANPADS / SHORAD at every base,
 │                                │  heavier at frontline bases
 └───────────────┬────────────────┘
                 ▼
 ┌────────────────────────────────┐
 │ 3. Fixed ground units          │  strategic IADS (ME late-activation),
 │    (Red & Blue)                │  strike targets (statics, depots, ships),
 │                                │  garrisons + Blue positions in ME zones
 │                                │  → THREAT MAP (SAM rings)
 │                                │  → TARGET CATALOG (what really exists)
 └───────────────┬────────────────┘
                 ▼
 ┌────────────────────────────────┐
 │ 4. Ground scheme of maneuver   │  moving units: Red pushes zone→zone,
 │    ("ground ATO", Red & Blue)  │  Blue reinforcements, convoys, TEL
 │                                │  deployments, recon targets
 │                                │  → CONTACTS (where/when sides meet)
 │                                │  → interdiction candidates
 └───────────────┬────────────────┘
                 ▼
 ┌────────────────────────────────┐
 │ 5. Red air ATO                 │  from stages 1–4 only. Clocked: CAP
 │                                │  stations/rotations, strike packages
 │                                │  vs Blue bases / ground units.
 │                                │  Standing posture: QRA per fighter base
 └───────────────┬────────────────┘
                 ▼
 ┌────────────────────────────────┐
 │ 6. Blue air ATO                │  from stages 1–4 only — does NOT read
 │    (AI + player)               │  the Red ATO. Support first (AWACS,
 │                                │  tankers); player line (type roll,
 │                                │  target, launch base, TOT T+60–90);
 │                                │  package by static rules (§1.10);
 │                                │  CAP rotations over the front; fill
 │                                │  under aircraft budget; routes + TOT
 │                                │  deconfliction; alert-CAP posture
 └───────────────┬────────────────┘
                 ▼
 ┌────────────────────────────────┐
 │ 7. Brief                       │  EOB from 3, GOB from 4, AOB from Red
 │                                │  standing posture (stations, base
 │                                │  types, QRA — no times), fidelity
 │                                │  rule applied; F10 tree; marks
 └───────────────┬────────────────┘
                 ▼
     plan table  →  Executor.run(plan)  →  Briefing.deliver(plan)
                →  Objectives.track(plan) → end state
```

#### Stage inputs → outputs

| Stage | Consumes | Produces |
|---|---|---|
| 1 Base coalitions | cluster table, RNG | `territory` (base → side), `clusterSides`, `front` (distances, frontline bases, adjacency) |
| 2 Base defenses | territory, front | defense groups per base (heavier on the front) |
| 3 Fixed ground | territory, front, content catalog (§1.2), ME zones | `threatMap` (SAM sites + rings), `targets` (instantiated catalog entries), garrisons/positions |
| 4 Ground maneuver | territory, front, zones, garrisons | `contacts` (Red/Blue meeting points + ETA), moving groups, interdiction candidates |
| 5 Red air ATO | stages 1–4 (territory, front, Red fighter bases, Blue-side targets) | Red ATO lines, Red standing posture (CAP stations, QRA per base) |
| 6 Blue air ATO | stages 1–4 + history file — **not** stage 5 | Blue ATO lines incl. the player's, routes, packages, Blue alert posture |
| 7 Brief | threatMap (3), contacts (4), Red standing posture (5), player line (6), fidelity rule | brief text, F10 menu tree, map marks |

#### Why this order
- **Defenses before fixed units:** fixed targets sit inside base defense umbrellas; the planner needs to know what's already there.
- **Fixed before moving:** moving units start from and go to fixed positions (garrisons, zones); contacts are only meaningful once both ends exist.
- **Ground before air:** CAS lines target *real* contacts with ETAs; interdiction lines target real convoys; the threat map is complete before any corridor is drawn.
- **Red air and Blue air are independent:** both are planned from stages 1–4 only. **No side reads the other side's plan.** Blue's packaging decisions are static lookups (SAM ring? fighter base nearby?), not predictions of Red's schedule. The order 5 → 6 is just so the brief can include Red's standing posture; nothing in 6 depends on 5. See §1.10.
- **Brief last, and derived:** generated from what was actually planned/spawned, so it can't lie; fidelity degradation is the only distortion. Red's *timeline* is never disclosed — only station areas and base posture.

#### Execution timing
Planning is pure data and fast. **Spawning** is the cost. Stages 1–4 spawn at T+0 (Syria does this in one frame; if the Kola ground layer is much bigger, spread spawns over a few seconds with `timer.scheduleFunction`). Stages 5–6 spawn on the ATO clock via the Executor's scheduler, under the alive-aircraft budget (§1.9).

### 1.2 Content catalog and the side-condition

Every piece of content declares where it lives and when it's valid:

```lua
{
    id        = "SAM_OLENYA_SA10",
    kind      = "sam_site",                 -- feeds mission types: sead, dead
    cluster   = "KOLA_CORE",
    valid_if  = "red",                      -- cluster must be Red
    me_groups = { "TGT_Olenya_SA10_SR", "TGT_Olenya_SA10_TR", "TGT_Olenya_SA10_LN" },
    pos       = ll(68.15, 33.46),
    success   = { kind = "destroy_any", of = { "TGT_Olenya_SA10_SR", "TGT_Olenya_SA10_TR" } },
    point_def = "by_threat",                -- spawn Syria-style tiered defenses
}
```

Contested clusters need **both** Red-side and Blue-side content pre-placed, because only one set gets activated:

| Content | Lives in | Valid when cluster is |
|---|---|---|
| SAM batteries, airfield statics, radar sites, depots | any Red-capable cluster | Red |
| "Attack X" CAS garrisons | contested / Red | Red |
| "Defend X" CAS positions (Blue ME groups) | contested | Blue — *and* an adjacent cluster is Red (attackers need somewhere to come from) |
| Ships in Kola Bay | KOLA_CORE | always Red |
| Dynamic templates (TEL hunt, convoy, recon box) | none — anchored on any Red base at runtime | — |

Rough ME content budget: **2–4 hand-placed target sites per Red-capable cluster**, plus one Defend + one Attack CAS site per contested cluster. Everything late-activation, named `TGT_<Base>_<Type>_<Part>` so the catalog and the ME stay in sync (same discipline as `RED_<Site>_SA2`).

### 1.3 Feasibility matrix — what can be rolled given the territory

| Mission type | Needs | Guaranteed? |
|---|---|---|
| SEAD / DEAD | ≥1 `sam_site` in Red cluster within range | Yes — KOLA_CORE always Red and has several |
| Airfield strike | Red airfield with static templates | Yes |
| Infrastructure | `fixed_target` in Red cluster | Yes if KOLA_CORE has a few |
| Naval | Kola Bay ships | Yes |
| CAP / Sweep | Red fighter base within range | Yes |
| Escort | any strike target for the AI package | Yes |
| CAS Defend | contested cluster rolled Blue with a Red neighbor | **Not guaranteed** — skip type if none |
| CAS Attack | contested cluster rolled Red, or Red site | Usually |
| Recon | any Red base to anchor on | Yes |

Type weights are applied *after* filtering to feasible types, so a session never dead-ends. Recommend a **session history file** (we have `io`/`lfs` — de-sanitized) recording the last N mission types so the roller can down-weight repeats. Cheap, and it's the seed of campaign-style progression later.

### 1.4 Launch base  *(decided)*

The planner **picks the launch base** and builds the whole flight plan from it (steerpoints, IP, TOT, fuel). The player reads the frag and spawns there via dynamic spawn. No enforcement, no personalized re-brief needed — the frag is the plan. Every Blue F-16-capable base needs dynamic spawn enabled in the ME since any of them can be chosen.

### 1.5 Briefing  *(decided: essentials on screen at start, everything else in F10)*

One `outText` at T+0 with the **essentials only** — no chained/timed messages. F10 **Briefing** submenu holds the full sections for reading in the cockpit. Map marks carry the geometry.

**Essential (on-screen brief):**
- Tasking type, target name, target coords (DMS + MGRS + elev), desired effect
- TOT window
- Launch base, recovery base
- Steerpoints — coords only, one line each
- Tanker + AWACS: callsign, freq, TACAN
- Threats: CONFIRMED sites one line each; PROBABLE/POSSIBLE summarized as one line ("mobile SA-11 assessed vic. Kandalaksha; possible SA-15 at core bases")
- Recommended load

**Submenu only (F10 > Briefing >):**
- `ATO` — every line in the window (§1.9), player's line highlighted
- `Package` — who's flying with/ahead of the player, their TOTs and callsigns
- `Threats` — full EOB/AOB with confidence, rings, AOB per base
- `Target` — full description, composition, success criteria, attack axis
- `Support` — tanker track details, offload, AWACS, divert fields
- `Fuel & Times` — joker/bingo estimate, sunrise/sunset, TOT math
- `ROE / SPINS`
- `Re-show brief` — the essentials again

#### What's realistic for the pilot to know

Real-world briefing layers and what they'd contain here:

| Layer | Real-world content | Generator equivalent |
|---|---|---|
| **Frag** (from the ATO) | Mission #, callsign, # aircraft, mission type, target ID + DMPI coords + elevation, TOT, package (escort/SEAD/tanker), controlling agency | Mission type, target name/ID, exact coords (DMS + MGRS 10-digit + elev ft), TOT window, AI package callsigns, AWACS callsign |
| **SPINS / comm-nav** | ROE, IFF, tanker track/alt/TACAN/freq/offload, AWACS freq, divert fields, code words, sunrise/sunset | Tanker + AWACS data, divert = nearest 2 Blue bases, sunrise/sunset from mission time |
| **Mission data card** | Steerpoints w/ coords, altitudes, times; joker/bingo; freq presets | Steerpoints: launch base → (tanker) → push point → IP → target → egress → recovery. Coords for each. Estimated joker/bingo from distance. |
| **Intel — EOB** (electronic order of battle) | Fixed strategic SAMs: exact location, type, status. Mobile SAMs: "assessed" type + operating area, confidence probable/possible. AAA/MANPADS: generic warning only. | See fidelity rule below |
| **Intel — AOB** (air order of battle) | Types and numbers per base, CAP normally on station?, QRA reaction time | "Monchegorsk: Su-27/MiG-31 regiment. 2-ship CAP assessed on station vicinity X. QRA reaction ~10 min." |
| **Intel — GOB** (ground, for CAS) | FLOT, friendly unit + position, enemy unit type + axis, commander's intent, JTAC contact | Friendly group + smoke marker, enemy composition + attack radials (Syria CAS already does this), JTAC freq if using AI FAC |
| **Target materials** | Imagery, description, DMPI, desired effect, collateral limits, weaponeering, attack axis restrictions | Target description + composition, success criterion phrased as desired effect ("destroy the SA-10 engagement radar"), recommended loadout, attack axis suggestion from the IP geometry |

#### Threat-intel fidelity rule  *(replaces the "difficulty knob" idea)*

Fidelity follows the threat's real-world nature, not a difficulty setting:

| Threat class | In brief as | Map |
|---|---|---|
| Fixed strategic SAM (SA-2/3/5/10) | **CONFIRMED** — type, exact coords, status, engagement ring | Ring drawn |
| Mobile SAM (SA-6/8/11/15/19) | **PROBABLE** — type + "operating vicinity <area>", or **POSSIBLE** — type only, region only; a fraction are **unlisted** | Area circle (±5–10 nm) or nothing |
| Point defense (AAA, MANPADS, ZSU) | Generic: "expect AAA/MANPADS in target area" | None |
| Air | Per-base type/number, CAP assessment, QRA timing | CAP station circle |
| Target itself | Exact — unless mission is CAS (JTAC-provided) or Recon (search box only) | Mark |

The per-session roll: for each mobile SAM the planner spawns, roll confirmed / probable / possible / unlisted with weights that can shift by mission "threat tier." Fixed sites are always confirmed. This gives surprise threats a realistic justification — the RWR is the last line of intel.

#### Brief template (draft)

```
=== FRAG ORDER — MSN 2041 — VIPER 1 (2x F-16CM) ===
TASKING:   SEAD / DEAD
TARGET:    SA-10 site OLENYA-SW  (TGT-KL-017)
           N68°07'12" E033°21'40"   35VNK 42815 61240   ELEV 610 ft
           Engagement radar (30N6) + 4 TELs. DESIRED EFFECT: radar destroyed.
TOT:       14:40–14:55Z
LAUNCH:    Rovaniemi (EFRO)  — 212 nm to target, bearing 041°
RECOVERY:  Rovaniemi. DIVERT: Ivalo, Kemi Tornio.

STEERPOINTS
 1 EFRO         N66°33'  E025°49'
 2 PUSH         N67°20'  E029°10'   FL250
 3 IP  "HAMMER" N67°58'  E032°40'   FL220  (18 nm SW of tgt)
 4 TGT          N68°07'  E033°21'
 5 EGRESS       N67°45'  E031°30'
 6 EFRO
FUEL:      JOKER 4.5  BINGO 3.2  (est., 2 bags)

PACKAGE / SUPPORT
 TEXACO 1   KC-135 MPRS  Track ALPHA  N67°00' E027°30'  FL220  251.0  TCN 51Y
 MAGIC      E-3A         264.0
 (no escort assigned)

THREATS — EOB
 CONFIRMED  SA-10  Olenya-SW      N68°07' E033°21'  (target)   ring 40 nm
 CONFIRMED  SA-3   Monchegorsk    N67°58' E032°52'             ring 13 nm
 PROBABLE   SA-11  battery operating vic. Kandalaksha–Alakurtti road
 POSSIBLE   SA-15  point defense reported Kola core bases
 Expect AAA / MANPADS at target.
THREATS — AOB
 Monchegorsk: Su-27 / MiG-31. 2-ship CAP assessed vic. N68°20' E032°00'. QRA ~10 min.

RECOMMENDED LOAD:  2x AGM-88C, 2x GBU-12, HTS, 2x AIM-120C, 2x AIM-9M, 2 bags, TGP
ROE:       Weapons free in Red territory east of the 029°E line. No strikes on civil airfields.
SUNSET:    15:12Z
=== F10 > Briefing to re-read any section ===
```

Sections map 1:1 to F10 **Briefing >** `Frag` / `Steerpoints` / `Support` / `Threats` / `Target` / `Full Brief`.

**Delivery caveats (DCS limits, to verify):**
- Script cannot push steerpoints into the player's jet; the pilot hand-jams from the brief or reads coords off the F10 marks. Realistic enough (pilots hand-jam all the time). DTC via ME is per-group and probably doesn't apply to dynamic-spawn slots — **[TODO test]**.
- Kneeboard pages are images and can't be generated by Lua at runtime. If we ever want a printable card, that's the pydcs/Python route (§7).
- `outText` has practical length limits and no scrolling; the full brief may need to be 2–3 chained messages or rely on the F10 sections for the long parts. **[TODO test]** the max readable length.

#### In-flight updates
Event-driven `outText`: "MAGIC: bandits airborne Monchegorsk, 2-ship, heading 270", "TEXACO on station", "Secondary: convoy sighted moving S on E105", objective met/failed, score delta. Result + "Roll next tasking" (phase 7) via F10 **Briefing > Status**.

### 1.6 Spawn timing  *(decided)*
Target, point defense, and ambient Red base defenses spawn at T+0 (Syria pattern — proven). Red CAP and QRA are **event-driven** (timer after player takeoff, or player crossing the front line) so they aren't bingo before the player arrives.

### 1.7 Ground layer at T+0  *(decided — a full layer, not an afterthought)*

The ATO (§1.9) covers the **air** picture. The **ground** picture is spawned at mission start, Syria-style, and is a first-class part of the battlefield:

1. **Airfield coalitions** — every base set per the cluster roll (`setCoalition`, `autoCapture(false)`, F10 circles, dynamic-spawn slots follow).
2. **Airfield defenses** — randomized ground defenses at every Red base (Syria `defense_setup` pattern; Kola unit pools).
3. **ME-defined ground zones** — trigger zones placed by hand in the ME, each tagged with a side condition and a role, e.g. `ZONE_RED_ARMOR_Pechenga`, `ZONE_BLUE_MECH_Ivalo`, `ZONE_RED_SAM_Kandalaksha`. At T+0 the script spawns Red and Blue ground units *inside their zones* according to the cluster roll — Red zones in Red-owned clusters activate, Blue zones in Blue-owned clusters activate, contested clusters get whichever side won the roll. Zones can also be **movement corridors**: a unit group spawns in one zone and routes to another, giving Red armor pushing toward a Blue border town, Blue reinforcing a defensive line, convoys on real roads.

Why zones instead of Syria's ring-around-the-airbase random offsets: Kola is lakes, marsh, and forest the API can't see. Hand-placed zones in known clearings/along roads sidestep the whole terrain-validation problem (§6) and give the planner a real **GOB** to brief — "Red mechanized battalion assessed vic. Pechenga moving W" is true because a zone spawned it.

How the ground layer feeds the ATO:
- CAS lines (player or AI) target ground zones where opposing units are in contact.
- Strike/SEAD targets are still catalog entries (§1.2) — zones and targets share the same `cluster` + `valid_if` tagging.
- Secondaries (TEL hunt, convoy, recon box) are drawn from zone spawns.
- Rule of thumb still applies: nothing in the ground layer may be a juicier target than the player's frag, and roaming units stay clear of planned IPs/corridors.

Details to design later: zone naming convention, per-zone unit templates by side and role, force-level scaling (Syria `FORCE_LEVELS` pattern), how many zones per cluster, whether Blue and Red zones can be paired into "fronts" that fight each other without the player. **[LATER — own design pass]**

### 1.8 Session history  *(decided)*
Write `Saved Games\DCS\kola_f16_history.lua` (or JSON-ish) after each plan: date, mission type, target id, launch base, outcome. Roller down-weights recent types. Controlled by a config flag: `HISTORY_ENABLED = true/false`, plus `FORCE_MISSION_TYPE = "sead"` / `FORCE_TARGET = "SAM_OLENYA_SA10"` overrides for testing.

### 1.9 The ATO model  *(decided in principle 2026-09-21 — the organizing idea)*

Instead of planning one mission, the generator plans an **Air Tasking Order for a ~6-hour window** starting at mission time. Every line is a flight with a callsign, aircraft, mission type, target or station, and times. One Blue line is the player's; AI flies the rest. Red gets its own ATO.

#### ATO line structure
```lua
{
    msn       = "2041",              -- mission number
    side      = "blue",
    callsign  = "VIPER 1",
    ac_type   = "F-16C_50", count = 2,
    role      = "sead",              -- cap | sead | dead | strike | escort | cas | tanker | awacs | recce | airlift
    player    = true,                -- exactly one Blue line
    base      = "Rovaniemi",
    target    = "SAM_OLENYA_SA10",   -- catalog id, or station id for cap/tanker/awacs
    package   = "PKG-A",             -- lines sharing a package share a TOT window
    t_start   = 3600,                -- mission-relative seconds: spawn/startup time
    t_tot     = 5400,                -- time on target / on station
    t_end     = 7200,                -- off station / expected recovery
    tanker    = "TEXACO 1",
    control   = "MAGIC",
    route     = { ... },             -- steerpoints from §1.1 step 10
}
```

#### Coherence rules (what makes it feel like an ATO and not a spawn list)
1. **Support up first.** AWACS and tanker lines start before any package and stay up across the window (rotate tankers if > 3 h on station).
2. **CAP covers packages.** At least one Blue CAP line is on station over the corridor while any strike/SEAD package is inside Red territory. CAP rotations overlap by ~10 min.
3. **SEAD precedes strike.** If a package strikes a target inside a CONFIRMED SAM ring, a SEAD line has a TOT 3–5 min earlier on that ring's site.
4. **Escort by proximity.** If the target is within ~80 nm of a Red fighter base, the package gets an escort line (static rule — §1.10).
5. **TOT deconfliction.** No two packages have TOTs within 10 min of each other on targets < 30 nm apart; tanker rendezvous slots don't overlap.
6. **Reaction is one loop, not many triggers.** Red QRA and Blue alert CAP are spawned by the per-base scramble loop (§1.10), not by the ATO. CAP rotations and strikes are on the clock.
7. **Player's line lands at T+60–90 min TOT** so there's time to read the brief, plan, start up, and take off; earlier ATO lines are already airborne (CAP on station, tanker orbiting) when the player launches — the world is already in motion.

#### The player's place in it
- The player's role is rolled like before (§1.3 feasibility, history weighting); the ATO is built *around* that line, then filled out.
- Package missions (escort, SEAD-for-a-strike, strike-with-SEAD) fall out naturally: the player is one line, AI flies the others, the brief lists them under `Package`.
- After recovery, **F10 > Briefing > ATO** can offer "take line 2087" — the player picks another *not-yet-started* line in the window and gets a new brief. This replaces the "roll next tasking" idea and is how a session chains 2–3 sorties.

#### Red ATO
Mirror structure, smaller: CAP rotations from Monchegorsk / Severomorsk-3 / Kilpyavr, QRA posture per base, 0–2 Red strike packages (Su-24/Su-34) against Blue border bases during the window. The intel **AOB** in the brief is derived from Red's *standing posture* (station areas, base types, QRA), degraded by the fidelity rule — never from Red's timeline. This also gives CAP/sweep player missions real customers.

#### Performance budget
DCS AI aircraft aren't free. Syria caps at 12 alive; here the target is **≤ ~20 alive at once** (tune by testing on the server box). The Executor enforces it: lines are spawned at `t_start`, despawned on RTB (Syria `S_EVENT_LAND` pattern), and the filler in step 8 of the pipeline is budget-aware — it only adds lines whose time windows fit under the cap. Rough shape of a 6-hour window: 1 AWACS, 1–2 tankers, 2 CAP rotations (2-ship each, 90-min cycles), 3–5 packages of 2–4 aircraft, plus Red's 2 CAP rotations + QRA + 1–2 packages ≈ 25–35 lines, 12–20 alive at any time.

#### Scope note — build it in layers
This is a big step up from "one tasking." Plan to build the *data model* fully from day one (an ATO is just a table, cheap) but execute it incrementally:
1. Player line + AWACS + tanker only.
2. + Blue CAP rotations (reuse `blue_air_support` pattern).
3. + Package lines around the player (SEAD/escort/second element).
4. + Red ATO (CAP, QRA, strikes).
5. + Filler packages, airlift/recce, "take another line" after landing.
At every layer the F10 `ATO` view shows only lines that actually execute — never fake lines.

### 1.10 Reaction model — keep it simple  *(decided 2026-09-21)*

**Hard rule: no side reads the other side's plan.** Neither planner predicts the other's behavior. Each side has objectives and planned missions built from the static picture; responsiveness comes from *one* cheap reaction loop per side plus DCS's native AI.

#### Plan-time: static facts only
Both ATOs are built from stages 1–4: territory, the front, the fixed ground picture (SAM sites, garrisons, bases), and each side's own assets. These are things both sides plausibly know — Red knows its own SAMs; Blue has imagery of fixed sites. Nobody knows the other side's schedule. Blue packaging is therefore a short table of **static lookups**, not a model of Red intent:

| Static fact | Blue packaging rule |
|---|---|
| Target inside a CONFIRMED fixed SAM ring | Add a SEAD line, TOT 3–5 min ahead of the strike |
| Target within ~80 nm of a Red fighter base | Add an escort line |
| Corridor crosses an assessed mobile-SAM *area* | Route around it, or HARMs on call |
| Distance to target > threshold | Assign a tanker line |
| Red fighter base within ~100 nm of a Blue base | Blue CAP rotation covers that sector |

Red uses the mirror of the same table for its own packages (Blue SHORAD at the target base → Red SEAD element, etc.), and places its CAP stations over its high-value areas.

#### What the brief says about Red air
Derived from Red's **standing posture** only — never its timeline: base → fighter types, assessed CAP station *area*, QRA reaction time. "Monchegorsk: Su-27/MiG-31. CAP station assessed vic. N68°20' E032°00' — expect contact if you enter that area. QRA ~10 min." That is the most Blue knows, and it's true because the same posture generated Red's actual CAP line. Fidelity rule applies (a station may be listed as POSSIBLE with a wider area, or omitted).

#### Execution-time: one reaction loop per side
One periodic check (every 30–60 s), one rule, mirrored for both sides:

```
for each fighter base of side S with alert fighters available and cooldown elapsed:
    if any enemy aircraft is within R nm of that base:
        scramble a 2-ship with an intercept task on the nearest enemy group
        decrement alert availability; start cooldown
```

- **Red:** this *is* QRA. Cheap to spawn, DCS AI intercepts well, no scripting of the fight itself.
- **Blue:** alert CAP scrambles the same way, plus an AWACS-style `outText` to the player ("MAGIC: bandits bullseye 045/60, 2-ship, hot").
- Caps and cooldowns per base keep it from spiraling and keep it under the aircraft budget (§1.9).
- Detection starts dumb (distance check over `coalition.getGroups`); can later be driven by a real Red EW radar's `getDetectedTargets()` without changing the shape.

#### Everything else is native DCS AI
- CAP flights on station with `EngageTargets` engage what enters their zone.
- SAMs engage on their own (Skynet, if adopted, adds HARM-aware behavior — §5.3).
- An AWACS unit in the mission feeds AI datalink awareness automatically.
- Strike packages with `REACTION_ON_THREAT` evade/abort on their own.

#### Why this feels authentic
The player gets what a pilot gets: fixed threats known, a CAP *area* to expect trouble in, a QRA warning. Push into the CAP area → the planned CAP is there. Get close to Monchegorsk → jets scramble. Cross a SAM ring → it shoots. No prediction on either side — posture plus a tripwire.

#### Red is not tuned to the player
Red defends what Red values, with no knowledge of which target is the player's. CAP stations and SAM density weight toward Red's high-value areas (Olenya, Severomorsk, the core) — which is where the good targets are, so coverage emerges without special-casing. Variance is accepted; the history-weighted type roll, per-target threat tiers, and "take another line" after landing handle quiet nights.

---

## 2. Why the F-16 changes the design

The A-10/F-16/F-18 Syria mission is really an A-10 mission with other slots. The F-16C Block 50 is a different animal and the generator should be built around what it's actually for:

| F-16 role | DCS loadout | Generator implication |
|---|---|---|
| **SEAD / DEAD** | AGM-88C HARM + HTS pod, GBU-12/38 for the kill | The Block 50's signature job. Needs a real, randomized IADS with emitting radars — not scattered SA-9s. |
| **Precision strike** | GBU-31/38 JDAM, GBU-12/10 LGB, AGM-65D/G/H, CBU-97/105 | Needs fixed, hard targets: bunkers, radars, fuel farms, parked aircraft, bridges, moored ships. JDAM on statics = coordinates matter → mission card must give precise DMS/MGRS. |
| **CAP / Sweep / Escort** | AIM-120C, AIM-9M/X | Needs Red AI fighters that actually launch: MiG-29/31, Su-27/33/34 from Kola bases. Syria has no air threat at all. |
| **CAS** | Maverick, GBU-12, CBU | Direct reuse of Syria `cas_mission.lua`. |
| **Anti-ship** | JDAM / LGB against moored ships, Maverick vs small craft (no Harpoon on DCS F-16) | Northern Fleet in Severomorsk / Polyarny / Kola Bay — moored statics are viable JDAM targets. |
| **Recon** | TGP, eyes | "Find and report" — locate a mobile target in a search box, confirm via F10. Cheap to build, good filler. |

**Range is the real constraint.** Bodø → Murmansk is ~700 km. Rovaniemi → Olenya ~450 km. The F-16 with 2 bags and a strike load is tight past ~300 nm radius. Every mission needs either a forward base or an AI tanker on station — the generator should pick the launch base *based on* target distance, or spawn a tanker track when it can't.

---

## 3. Kola map facts

### Size & geography
- ~1,400 km E-W × ~1,000 km N-S ([ED product page](https://www.digitalcombatsimulator.com/en/products/terrains/kola_terrain/)). Covers northern Norway, Sweden, Finland, and the Kola Peninsula / Murmansk oblast.
- Russian side: Northern Fleet home — Murmansk, Severomorsk, Polyarny sub bases; dense cluster of airfields and installations in the Kola–Karelia corridor.
- Terrain: taiga/tundra, huge numbers of lakes and marsh, sparse roads, fjords on the Norwegian coast. Deep snow much of the year. **Off-road ground spawning will be harder than Syria** — lakes read as `WATER`, forest is invisible to the API, and roads are few.
- Lighting: high latitude. Polar night in winter, midnight sun in summer. Time-of-day randomization matters more here than on Syria (see §7 — can't be done in Lua at runtime).

### Airbases — exact DCS name strings
Source: MOOSE `AIRBASE.Kola` enumeration ([Airbase.lua](https://github.com/FlightControl-Master/MOOSE/blob/master/Moose%20Development/Moose/Wrapper/Airbase.lua)). **Verify in-game with `Log.dumpAirbases()` before relying on these** — the Syria project caught several mismatches.

| Country | Bases (DCS string) | Notes |
|---|---|---|
| **Norway** | `Bodo`, `Bardufoss`, `Evenes`, `Andoya`, `Banak`, `Alta`, `Kirkenes` | Bodø = premier Blue hub (long runway, far from threat). Banak/Kirkenes are right on the Russian border. |
| **Sweden** | `Kallax`, `Vidsel`, `Kiruna`, `Jokkmokk`, `Kalixfors`, `Arvidsjaur`, `Hemavan`, `Boden Heli Base` | Kallax (Luleå) = second Blue hub. Vidsel = test range. Jokkmokk/Kalixfors are Swedish dispersal strips — check runway length. |
| **Finland** | `Rovaniemi`, `Kemi Tornio`, `Kuusamo`, `Ivalo`, `Kittila`, `Enontekio`, `Sodankyla`, `Hosio`, `Vuojarvi` | Rovaniemi = Finnish AF fighter base, closest big Blue base to Kola. Ivalo/Sodankylä are within ~200 km of the border. |
| **Russia** | `Murmansk International`, `Severomorsk-1`, `Severomorsk-3`, `Olenya`, `Monchegorsk`, `Afrikanda`, `Kilpyavr`, `Koshka Yavr`, `Luostari Pechenga`, `Alakurtti`, `Kalevala`, `Poduzhemye` | Olenya = long-range aviation (Tu-22M/Tu-95 statics = great strike targets). Monchegorsk = fighters. Severomorsk-3 = naval aviation. Kalevala/Poduzhemye are far south in Karelia. |

High-detail airports per Orbx: Rovaniemi, Kemi-Tornio, Kuusamo, Ivalo, Severomorsk-1/-3, Murmansk, Bodø, Kirkenes, Banak, Kiruna, Jokkmokk, Luleå, Vidsel, Kalixfors ([Threshold preview](https://www.thresholdx.net/news/tekola)).

**[TODO research]** Runway lengths for the F-16 viability table (Syria has `research_runway_lengths.md`; need a Kola equivalent). Known/likely: Bodø ~3,400m, Kallax ~3,350m, Rovaniemi ~3,000m, Evenes ~2,800m, Banak ~2,800m; suspect short: Jokkmokk, Kalixfors, Hemavan, Hosio, Enontekiö.

### Proposed clusters (Syria-style, for `coalition_setup`)

Finland and Sweden are NATO members as of 2023/2024, so "all Nordic = Blue" is the realistic baseline. The interesting contested zones are the border regions.

| Cluster | Type | Bases |
|---|---|---|
| **NORWAY_REAR** | Always Blue | Bodø, Evenes, Andøya, Bardufoss |
| **SWEDEN** | Always Blue | Kallax, Vidsel, Kiruna, Jokkmokk, Kalixfors, Arvidsjaur, Hemavan, Boden |
| **FINLAND_SOUTH** | Always Blue | Rovaniemi, Kemi Tornio, Kuusamo, Hosio, Vuojärvi |
| **FINNMARK** | Contested | Banak, Alta, Kirkenes |
| **LAPLAND_NORTH** | Contested | Ivalo, Kittilä, Sodankylä, Enontekiö |
| **KOLA_CORE** | Always Red | Murmansk Intl, Severomorsk-1, Severomorsk-3, Olenya, Monchegorsk, Kilpyavr, Koshka Yavr, Luostari Pechenga |
| **KOLA_SOUTH** | Contested (lean Red) | Afrikanda, Alakurtti |
| **KARELIA** | Always Red | Kalevala, Poduzhemye |

Contested-cluster randomization gives the "Russia pushed into Finnmark" vs "NATO holds the border" variation. **Decided:** Syria-style dynamic assignment with fixed + contested clusters. Consequence: contested clusters need both Red-side and Blue-side content pre-placed (§1.2), and the IADS in KOLA_CORE can still be hand-placed with real-world fidelity since that cluster is always Red.

**[Q]** Exact cluster membership above is a first guess — worth a pass together on the map. In particular: is KOLA_SOUTH (Afrikanda, Alakurtti) worth being contested, or should it just be Red so the front is always the Finnish/Norwegian border?

---

## 4. Mission catalog (draft)

Each session rolls one **primary** from the weighted pool, then 0–2 **secondaries**. Every mission carries `{ type, target, threat_level, launch_base, support }`.

### 4.1 Primary mission types

| # | Type | Target | What gets spawned | Success condition |
|---|---|---|---|---|
| P1 | **SEAD** | One SAM battery (SA-2/3/6/11/10) | Late-activation ME battery + dynamic point defense (SA-15/Shilka/MANPADS) + optional decoy emitter | Search/track radar dead |
| P2 | **DEAD strike** | Full SAM site incl. launchers | As P1, plus ammo trucks/statics | ≥ N% of battery destroyed |
| P3 | **Airfield strike** | Parked aircraft / fuel farm / HAS at a Red base | Static aircraft (Tu-22M3, Su-24, MiG-31), fuel tanks, dynamic AAA | ≥ N statics destroyed |
| P4 | **Infrastructure strike** | Radar site / comms / bridge / depot | Statics + light defenses; bridge = map object (scenery destruction works via `destroy` on scenery? — **verify**) | Target destroyed |
| P5 | **Naval strike** | Moored ships in Kola Bay / Severomorsk | Ship units (stationary) + SA-N point defense; or statics | Ship(s) sunk |
| P6 | **CAP / Sweep** | Red air activity | Red fighter groups launched on a schedule toward Blue airspace | Survive N minutes / kill N bandits |
| P7 | **Escort** | Blue AI strike package | Blue AI F-16/F-18 strike + Red fighters vectored to intercept | Package survives to target |
| P8 | **CAS** | Ground battle | Direct port of Syria `cas_mission.lua` | Red attackers reduced below threshold |
| P9 | **Recon / Find** | Mobile target in a 20×20 km box (SS-26 TEL, S-300 relocation, convoy) | Dynamic ground group, no marker | Player confirms via F10 "Target sighted" within N km |

### 4.2 Secondary objectives (small, 1–3 units)
- Scud/Iskander TEL hunt (Syria S&D port)
- Convoy interdiction (Syria convoy port)
- EW radar site (single emitter, MANPADS)
- Helicopter FARP

### 4.3 Threat layers (independent rolls)
- **Air threat:** none / CAP on station / QRA scramble on detection / both. Red fighter pool: MiG-29A/S, MiG-31, Su-27, Su-33 (from Severomorsk-3), Su-34.
- **IADS density:** low / med / high — controls how many *extra* SAMs spawn along the ingress corridor beyond the target's own defenses.
- **Point defense:** as Syria threat tiers, plus SA-15 Tor and SA-19 Tunguska at high.

### 4.4 Support layers
- **Tanker:** KC-135 MPRS / KC-130 on a track ~150 nm behind the front. Spawn when target distance from launch base > X nm. Give freq/TACAN in the card.
- **AWACS:** E-3A on a racetrack over Norway/Sweden. Always-on is fine (cheap).
- **Blue CAP:** 2-ship AI F-16/F-18 for the CAP/Escort missions and as a comfort layer at low threat.
- **Blue SEAD escort:** optional AI 2-ship with HARMs when the primary is a strike into a high-IADS zone.

---

## 5. Architecture

### 5.1 Relationship to the Syria code **[Q — biggest decision]**

Three options:

| Option | Description | Pros | Cons |
|---|---|---|---|
| **A. Fork** | Copy `scripts/` to `scripts_kola/` (or new repo), edit freely | Fastest start, zero risk to Syria | Two copies of spawner/logger/cost tracker drift apart |
| **B. Shared lib + per-map config** | Refactor to `scripts/lib/` (shared) + `scripts/maps/syria/` + `scripts/maps/kola/`; `init.lua` takes a map param | One codebase, bug fixes land everywhere | Refactor work up front; Syria regression risk |
| **C. Shared lib, separate mission dirs** | `lib/` shared; `a2g_dynamic_syria/` and `kola_f16/` each have own `init.lua` + modules, both `dofile` the shared lib | Cheap refactor (just move 2 files), no Syria logic touched | Modules like `sam_setup`/`cas_mission` still get copied if reused |

**Recommendation: C.** Move `logger.lua`, `spawner.lua`, and the `cost_*` trio to a shared `lib/`; leave Syria modules alone. Kola gets its own module set. Promote things to `lib/` only once both maps actually use them identically.

Runtime layout would become:
```
Saved Games\DCS\Scripts\
    lib\                      ← shared: logger, spawner, cost_config/logic/ui
    a2g_dynamic_syria\        ← unchanged
    kola_f16\                 ← new
        init.lua
        modules\...
```

### 5.2 What ports over cleanly
- `spawner.lua` — as-is (ring spawn, flatness, land check, routes, fireGroups). Add an MGRS formatter for the F-16 (`coord.LLtoMGRS`).
- `logger.lua` — as-is.
- `cost_*` — as-is; F-16C_50 cost already present. Add HARM (`AGM_88C` already there), add Red fighter kill values (mostly there).
- `coalition_setup.lua` pattern — new cluster table, same logic.
- `sam_setup.lua` pattern — new site table; extend for SA-3/SA-10/SA-11/SA-15.
- `blue_air_support.lua` — becomes the template for **all** AI air spawning (tanker, AWACS, CAP, strike package, Red fighters). Its Orbit + EngageTargets + WEAPON_FREE lessons are the hard-won part.
- `cas_mission.lua`, `convoy_setup.lua`, `sd_mission.lua` — port as P8 / secondaries, with Kola unit pools and terrain checks tightened.

### 5.3 New plumbing needed

1. **Mission catalog + roller** — weighted random selection, mutual-exclusion rules (no Escort + CAP together), secondary picker.
2. **Target templates** — a data-driven way to describe a target: `{ statics = {...}, units = {...}, defenses_by_threat = {...}, success = { kind="destroy_pct", pct=0.6 } }`. Hand-placed ME late-activation groups for real-world fidelity (SAM sites, airfield statics) + dynamic fill.
3. **Objective tracking** — a per-mission event handler counting kills against the target set → success/fail state, on-screen result, cost-tracker bonus. This is the one thing Syria genuinely lacks.
4. **Red air AI** — spawn-on-schedule and spawn-on-trigger (player crosses a line / a radar detects). Needs a decision on GCI logic: hand-rolled `EngageTargets` vectors vs. **Skynet IADS** for the SAM side (no dependencies, fits the no-MOOSE stance — [Skynet](https://github.com/walder/Skynet-IADS)). **[Q]** Willing to take Skynet as the one external dependency? It gives SAMs that go dark when HARMs fly, EW-radar-cued launches, and coordinated sectors — a big step up for SEAD gameplay.
5. **Launch base selection** — pick the Blue base by target distance and runway length; the whole flight plan is built from it and the player spawns there (§1.4). Requires F-16 dynamic spawn enabled at every candidate Blue base in the ME.
6. **Support package** — tanker/AWACS spawn helper with TACAN/freq via `ActivateBeacon` + `SetFrequency` commands; string these into the card.
7. **Mission card** — one `outText` + F10 "Briefing" entry + map marks. Contents: task, target desc, coordinates (DMS + MGRS), threat summary, recommended loadout, launch base, tanker/AWACS freqs, TOT window if any.
8. **Mission end** — success/fail detection → summary → optional "roll next mission" F10 command so a session can chain 2–3 taskings without a mission restart.

---

## 6. Kola-specific technical risks

| Risk | Why it matters | Mitigation |
|---|---|---|
| Ground spawns in lakes/marsh | Thousands of lakes; `nearPos` will hit water constantly | Keep `isOnLand` + retry; raise retry count; prefer road-snap and ME-placed anchors for anything that must be flat |
| Forest (invisible to API) | Vehicles spawn in trees, can't move, can't be seen | Prefer hand-placed anchor zones (trigger zones in ME at known clearings) for CAS/S&D; dynamic offsets only within those zones |
| Ground AI movement | Sparse roads, long distances → convoys stall | Shorter routes (cap ~100 km), on-road only, test early |
| Range / fuel | F-16 bingo on long legs | Tanker always available when distance > threshold; launch-base selection |
| Runway lengths | Several Nordic strips may be too short for a loaded F-16 | Research table (TODO above); exclude from launch-base pool |
| Airbase name strings | Same trap as Syria | `Log.dumpAirbases()` on a timer (the T+0 empty-table issue) |
| Red air AI competence | Su-27s with `EngageTargets` can be either lethal or useless | Start with ME-defined CAP templates activated by script; tune skill per threat level |
| Skynet + no-MOOSE stance | Skynet is standalone but ~200 KB and has its own conventions | Prototype it on one SA-6 site before committing |
| Polar night | Dark missions need TGP/NVG; players may not want them every time | Can't fix in Lua — see §7 |

---

## 7. Out-of-sim randomization (weather / time / statics) — decision point

Lua at runtime **cannot** change weather, time of day, or date. On Kola that's a real loss (polar night vs midnight sun, snowstorms). Options:

1. **Live with it** — fixed ME weather/time, all randomness in-sim. Simplest; what Syria does.
2. **Multiple `.miz` files** — 3–4 hand-made variants (summer day / winter twilight / storm), pick one at server start. Cheap, coarse.
3. **pydcs pre-generation** — a Python step (you already source CLSIDs from [pydcs](https://github.com/pydcs/dcs)) writes the `.miz` before launch: random weather, time, date, and can also place statics/SAM sites programmatically with validated type names. In-sim Lua then handles the dynamic parts. **Big upside:** pydcs knows every unit type string, so the Leopard-2 silent-replacement bug class goes away for anything it places.

**[Q]** Appetite for a Python pre-gen step? It's the most powerful path and the tooling (`desanitize_dcs.py`) already runs Python on the server box. Recommendation: plan for **option 3 as a later phase**; start with option 1 so the Lua side gets built first.

---

## 8. Phased plan (proposal)

| Phase | Deliverable | Reuses | New |
|---|---|---|---|
| **0** | Kola `.miz` with dynamic-spawn F-16 slots at Blue bases, de-sanitize check, `dumpAirbases()` confirming all names, runway table | Install flow | Runway research |
| **1** | `lib/` split (§5.1 option C); Kola `init.lua` + `coalition_setup` with clusters; F10 skeleton | logger, spawner, cost_* | cluster table |
| **2** | **Strike primary (P3/P4)** against ME-placed statics at Red airfields + point defense; objective tracking; mission card | sam threat tiers | catalog roller, objective tracker, card |
| **3** | **SEAD/DEAD (P1/P2)** with 3–4 hand-placed batteries; Skynet prototype on one site | sam_setup pattern | Skynet integration, HARM scoring |
| **4** | Support package: tanker + AWACS with TACAN/freqs in the card | blue_air_support | beacon/freq commands |
| **5** | **Red air**: QRA scramble + CAP on station; P6/P7 missions | blue_air_support | Red fighter templates, trigger-on-detection |
| **6** | Ports: CAS (P8), convoy/TEL secondaries, Recon (P9) | cas/convoy/sd modules | Kola anchor zones |
| **7** | Mission chaining ("next tasking" without restart), session summary | cost_ui | end-state machine |
| **8** | (optional) pydcs pre-gen for weather/time | — | Python |

---

## 9. Open questions summary

**Decided 2026-09-21**
- ~~One primary tasking vs. board~~ → **one mission planned at load time**, player learns the type from intel. All F-16 role types in scope.
- ~~Contested clusters vs. fixed front~~ → **Syria-style dynamic assignment** (fixed Red, fixed Blue, contested).

- ~~Launch base~~ → **planner picks it**, player spawns there. No enforcement. *(§1.4)*
- ~~Briefing delivery~~ → **one full brief at start**, F10 sections for drill-down, ATO/SPINS/intel-brief realism. *(§1.5)*
- ~~Intel-quality knob~~ → replaced by the **fidelity rule**: fixed SAMs confirmed, mobile SAMs probable/possible/unlisted, AAA generic. *(§1.5)*
- ~~Session history~~ → **yes**, with `HISTORY_ENABLED` flag and `FORCE_MISSION_TYPE` / `FORCE_TARGET` test overrides. *(§1.8)*
- ~~Spawn timing~~ → T+0 for target/defenses, event-driven for Red air. *(§1.6)*
- ~~Single tasking~~ → **full ATO for a ~6 h window**, one Blue line is the player's, AI flies the rest, Red has its own ATO. Built in layers. *(§1.9)*
- ~~Briefing length~~ → essentials in one `outText`, no timed chaining; everything else in F10 submenus. *(§1.5)*
- ~~Ambient layer~~ → air side is the ATO; **ground side is a full T+0 layer**: airfield coalitions, airfield defenses, and ME-defined Red/Blue ground zones. Zone details are their own later design pass. *(§1.7)*
- ~~Player count~~ → **1 player for now, 2 F-16 slots** (friend later). **No AI in the player's flight.**
- ~~Build order~~ → **7 stages**: base coalitions + front geometry → base defenses → fixed ground units (IADS, targets, garrisons) → ground scheme of maneuver → Red air ATO → Blue air ATO (AI + player) → intel/brief. Each stage consumes the previous ones' outputs only. *(§1.1)*
- ~~AI JTAC~~ → works in-game already, trivially added later. Not a design question.
- ~~How sides react to each other~~ → **No side reads the other's plan.** Both ATOs from static facts (stages 1–4); Blue packaging = static lookup table; brief's AOB = Red standing posture, no times. Execution: **one scramble loop per side** (per-fighter-base QRA/alert with cooldown + cap), native DCS AI for everything else. Red not tuned to the player. *(§1.10)*

**Open — concept level**
1. Cluster membership review, esp. KOLA_SOUTH contested vs. Red *(§3)*
2. ATO window: 6 h from mission start — should mission start time itself vary (dawn/dusk/night) per session? Only possible via the pydcs route (§7).
3. `outText` length limits and DTC-on-dynamic-spawn behavior — test items, not decisions *(§1.5 caveats)*

**Deferred — own design pass later**
- Ground zones: naming, per-zone templates, force scaling, zones-per-cluster, paired Red/Blue fronts *(§1.7)*
- Ground ambient beyond zones: roaming SAMs, convoys, ship traffic, keep-clear rules around planned corridors *(§1.7)*

**Open — architecture level**
5. Code structure: fork / full refactor / shared-lib (recommended C)?
6. Skynet IADS as a dependency for SEAD?
7. Python (pydcs) pre-generation for weather/time — now, later, never?
8. Naval strike — worth the ship-spawn research?
9. Success criteria — binary pass/fail, or a score (ties into cost tracker)?

---

## 10. Sources

- [DCS: Kola Map — ED product page](https://www.digitalcombatsimulator.com/en/products/terrains/kola_terrain/)
- [Kola Map announcement — ED news 2022-07-29](https://www.digitalcombatsimulator.com/en/news/2022-07-29/)
- [Threshold: Orbx Kola previews (high-detail airport list)](https://www.thresholdx.net/news/tekola)
- [Orbx Kola FAQ](https://orbxstudios.com/dcs-kola-map-faqs/)
- [MOOSE Wrapper.Airbase — `AIRBASE.Kola` string enumeration](https://flightcontrol-master.github.io/MOOSE_DOCS/Documentation/Wrapper.Airbase.html)
- [Skynet IADS](https://github.com/walder/Skynet-IADS)
- [pydcs](https://github.com/pydcs/dcs)

---

## 11. Architecture  *(started 2026-09-21 — in discussion)*

### 11.1 Relationship to the Syria code  *(decided 2026-09-21)*

**Completely separate.** No shared `lib/`, no refactor of the Syria scripts, nothing in the Syria tree is touched. Kola is its own script directory with its own copies of whatever it borrows (logger, spawner, cost tracker patterns). The Syria mission must keep working exactly as it does today, and sharing code would put that at risk. This supersedes §5.1 (option C is dropped).

### 11.2 The plan is one table  *(decided 2026-09-21)*

The 7 stages of §1.1 build **one accumulating Lua table**. Stage 1 writes `plan.territory`; stage 2 reads it and writes `plan.defenses`; and so on. Each stage is one module that takes the table, reads the keys of earlier stages, and adds its own key. "Stage N only reads earlier stages" is a convention, not enforced.

- **Nothing spawns until all 7 stages are done.** Unlike Syria, where each module decides and spawns in the same function, here the stages only produce data. This is a much larger setup; deciding everything first and spawning afterwards is the only way the later stages (ATOs, brief) can see the complete picture.
- **Plain data only.** Strings, numbers, nested tables. No DCS object handles, no functions. Anything needed from the sim (airbase positions, ME zone positions, late-activation group names) is read into plain values as part of building the plan. Consequence: the plan can be written to a file (`Saved Games\DCS\kola_last_plan.lua`, behind a config flag) and read when debugging, instead of reconstructing what was planned from `dcs.log`.
- **Each entry carries everything its consumer needs.** Since spawning happens later, a defense entry holds unit types, positions, headings; an ATO line holds its route; an ME-placed target holds its late-activation group names. In Syria these live in locals right before the spawn call — here they go in the table.
- **Immutable once built** (not enforced). Consumers — spawner, mission reporter/briefing, ATO scheduler, objective tracker — all read the plan; none write to it.
- **Runtime state lives elsewhere.** What has launched, what's dead, objective status, scramble cooldowns: separate tracking structures owned by the executor/trackers, keyed by the same IDs the plan uses (mission number, target id, group name) so the two can always be joined.

### 11.3 From mission start to a finished plan  *(decided 2026-09-21)*

1. **ME trigger fires `init.lua`** at mission start. Loads the script files, nothing else.
2. **Wait a few seconds** (`timer.scheduleFunction`) — airbase queries return empty at T+0 (the Syria issue noted in §6).
3. **Gather inputs — one step, up front.** All DCS reads happen here and are converted to plain values: airbase list with positions and current coalition, trigger zones, late-activation group names and positions, mission time/date. Plus the static data files (cluster table, content catalog, unit pools) and the session history file. Every stage then works from the same snapshot; the stages never see a DCS object. Cost: what the stages need has to be known ahead of time — for airbases/zones/groups that's clear enough.
4. **Stages 1–7 run back-to-back** in one call. All data, milliseconds.
5. **Plan dump** to file if the config flag is set.
6. **Hand off** to spawner, briefing, ATO scheduler, objective tracker.

Open: whether the gathered inputs are stored on the plan itself (e.g. `plan.world`) so the dump file is self-contained, or kept separate. Leaning on the plan — it costs nothing and makes the dump complete.

### 11.4 Consumers of the plan  *(decided 2026-09-21)*

Who reads the plan and what they pull from it:

| Consumer | When | Reads | Needs per entry |
|---|---|---|---|
| **Ground spawner** | T+0 | `defenses`, `fixed` (targets, garrisons, IADS), `ground` (moving units) | ME late-activation group name to activate, *or* country + unit types + positions + headings (+ route if it moves). Doesn't care why anything is there. |
| **ATO scheduler** | on the clock | `red.ato`, `blue.ato` (skips the player's line) | `t_start`, aircraft type + count, base, loadout, steerpoints, role → DCS task (CAP orbit / SEAD / bombing target / escort target / tanker track + TACAN + freq / AWACS orbit + freq), callsign. Alive-aircraft cap from config. |
| **Scramble loop** (per side) | periodic | posture: alert bases, fighter count/type, cooldown, detection radius | everything else is runtime state |
| **Briefing** | T+0, F10 on demand | player's line, support lines, `fixed.threat_map` + fidelity, `ground.contacts`, Red posture (AOB), full ATO for the F10 view | coordinates in DMS + MGRS — stored in the plan or converted on the way out |
| **Objective tracker** | event-driven | player's line → target → `success` criterion (group/unit names, fraction) | later: AI lines' success too, for the F10 ATO view |
| **History writer** | plan time + end | mission type, target id, launch base; outcome from the tracker | |
| **F10 ATO / "take another line"** (later) | after landing | full Blue ATO with times | not-yet-started lines only |

Two kinds of need show up: spawner and scheduler need **spawn-ready detail** (unit types, exact positions, routes); briefing/tracker/history need **mission-level meaning** (target name, TOT, threat type + confidence). Both are in the one table. Group names, mission numbers, and target ids are **assigned by the planner**, not invented at spawn time — the tracker has to match DCS event names back to plan entries.

### 11.5 One table — what's in it and what isn't  *(decided 2026-09-21)*

**The plan holds every decision, in our own vocabulary.** What, where, who, when, how it's named, what counts as success. Example, a stage-2 defense entry:

```lua
{
    id     = "DEF_Olenya_SA15",
    base   = "Olenya",
    side   = "red",
    kind   = "shorad",
    pos    = { x = 123456, z = 654321, lat = 68.15, lon = 33.46 },
    units  = { { type = "Tor 9A331", heading = 90 }, { type = "Ural-375", heading = 90 } },
    spread = 60,
}
```

**Consumers own the DCS formats.** The `coalition.addGroup` table, waypoint + task tables, `outText` strings, F10 menu structures, map-mark calls — all built on the fly from plan entries at the moment they're used, and thrown away afterwards. Going from the entry above to an `addGroup` table is a *translation*, not a decision; nothing new is chosen, so nothing new is stored. There is no separate "spawn table" or "mission table" — the ATO lines and targets *are* the mission data, the defense and ground entries *are* the battlefield data; they're different keys of the same table, and the briefing can walk `plan.blue.ato[msn].target → plan.fixed.targets[id] → plan.fixed.threat_map` without crossing structures.

**State holds what happened.** Spawned group → plan id, alive/dead, launched, objective status, cooldowns. Written by consumers at runtime (§11.2).

Net effect: all the planning is pure logic over plain data — fast, and segmented from the sim. The spawner then reads the plan and creates units that already fit the missions the plan built.
