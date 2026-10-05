"""Wording adapter, phrase bank, for pilots: turns a flight's or an airfield call's facts into
what the pilot says.

    python radio_calls/flight_phrase_wording.py      checks pilot_phrases.json and airfield_phrases.json, prints samples

Darkstar's calls have their own wording (phrase_bank_wording.py, awacs_phrases.json); this one
is for the AI pilots: their mission calls ("Viper two one, Fox three") and their airfield
traffic calls ("Kallax traffic, Viper two one, final, runway three one, Kallax").

Each call kind in a phrase file is a list of parts, said in order, joined with commas. Each
part is a list of alternatives: a plain string, or {text, weight, when}. weight (default 1)
makes an alternative more or less common; an empty text leaves the part out; when names a
condition the call's facts must have (CALLS below). Placeholders in {braces} are the call's
facts, said the radio way (FACT_WORDS). Recently used alternatives are made less likely, never
ruled out (as Darkstar's). Every placeholder and condition is checked when a file is loaded,
so a typo stops the helper at start, not in the middle of a mission.

A call's facts (one dict, as the mission sends them):
    {"call": "fox", "callsign": "Viper 2-1", "fox": 3, "target_type": "Su-27", "flags": ["target_known"]}
"""

import json
import os
import random
import re

import phrase_bank_wording as words

HERE = os.path.dirname(os.path.abspath(__file__))
PILOT_PHRASES_PATH = os.path.join(HERE, "pilot_phrases.json")
AIRFIELD_PHRASES_PATH = os.path.join(HERE, "airfield_phrases.json")

PLACEHOLDER = re.compile(r"\{(\w+)\}")
RECENT_WEIGHT = [0.25, 0.5]

# Every call kind: the facts it carries (its placeholders) and the conditions it may set.
# "awacs" (the controller's callsign) and "pause" can be used in any call.
COMMON = {"callsign", "flight", "awacs", "pause"}
CALLS = {
    # mission calls (the mission and AWACS channels)
    "airborne":    ({"base", "count", "mission", "target"}, {"patrol", "attack", "sead", "single", "two_ship", "has_target"}),
    "on_station":  ({"station"}, set()),
    "pushing":     ({"target"}, {"sead", "has_target"}),
    "fox":         ({"fox", "target_type"}, {"target_known", "fox_one", "fox_two", "fox_three"}),
    "magnum":      ({"target"}, {"has_target"}),
    "rifle":       ({"target"}, {"has_target"}),
    "bombs":       ({"target"}, {"has_target"}),
    "splash":      ({"kill_type"}, {"type_known"}),
    "defending":   ({"threat"}, {"sam", "air"}),
    "jet_down":    ({"down"}, {"ejected"}),
    "winchester":  (set(), set()),
    "bingo":       ({"base"}, set()),
    "off_target":  ({"base"}, {"sead", "attack", "patrol"}),
    "check_out":   ({"base"}, {"patrol", "attack", "sead"}),
    # airfield traffic calls (each field's own frequency)
    "taxi":        ({"field", "runway"}, {"runway_known", "single", "two_ship"}),
    "departing":   ({"field", "runway", "direction"}, {"single", "two_ship"}),
    "inbound":     ({"field", "runway", "distance", "direction"}, {"runway_known"}),
    "final":       ({"field", "runway"}, set()),
    "clear":       ({"field", "runway"}, {"runway_known"}),
}

FOX_WORDS = {1: "one", 2: "two", 3: "three"}


def alternatives(raw):
    out = []
    for item in raw:
        if isinstance(item, str):
            item = {"text": item}
        out.append({"text": item["text"], "weight": item.get("weight", 1), "when": item.get("when")})
    return out


def spoken_callsign(text):
    """ "Weasel 3-1" -> "Weasel three one", "Weasel 3" -> "Weasel three" (digits one by one). """
    def digits(m):
        return " ".join(words.DIGITS[int(d)] if d != "9" else "niner" for d in m.group(0) if d.isdigit())
    return re.sub(r"\d+(-\d+)?", digits, text or "")


def spoken_system(text):
    """SAM names as said: "the Sodankyla SA-10" -> "the Sodankyla S A ten"."""
    return re.sub(r"\bSA-(\d+)", lambda m: "S A " + words.number_words(int(m.group(1))), text or "")


def spoken_place(name):
    """A DCS airbase name as said: "Kemi_Tornio" -> "Kemi Tornio"."""
    return re.sub(r"[_-]+", " ", name or "").strip()


class FlightPhraseBank:
    def __init__(self, path, types=None, rng=None):
        with open(path, encoding="utf-8") as f:
            self.data = json.load(f)
        self.path = path
        self.types = types or {}           # DCS type -> {"nato": ..., "designation": ...}
        self.rng = rng or random.Random()
        self.recent = {}
        self.check()

    def check(self):
        problems = []
        for kind, parts in self.data["calls"].items():
            if kind not in CALLS:
                problems.append("calls.%s: not a call kind the mission sends (%s)" % (kind, ", ".join(sorted(CALLS))))
                continue
            facts, conditions = CALLS[kind]
            allowed = facts | COMMON
            for i, part in enumerate(parts):
                for item in alternatives(part):
                    for name in PLACEHOLDER.findall(item["text"]):
                        if name not in allowed:
                            problems.append("calls.%s part %d: {%s} can't be filled there (\"%s\")"
                                            % (kind, i + 1, name, item["text"]))
                    if item["when"] and item["when"] not in conditions:
                        problems.append("calls.%s part %d: unknown condition '%s'" % (kind, i + 1, item["when"]))
        if problems:
            raise ValueError("%s:\n  %s" % (os.path.basename(self.path), "\n  ".join(problems)))

    def kinds(self):
        return set(self.data["calls"])

    def pick(self, key, raw, conditions):
        items = [a for a in alternatives(raw) if not a["when"] or a["when"] in conditions]
        if not items:
            return ""
        recent = self.recent.setdefault(key, [])
        weights = []
        for a in items:
            weight = a["weight"]
            if a["text"]:
                for age, text in enumerate(reversed(recent)):
                    if text == a["text"]:
                        weight *= RECENT_WEIGHT[age]
                        break
            weights.append(weight)
        roll = self.rng.uniform(0, sum(weights))
        chosen = items[-1]
        for a, weight in zip(items, weights):
            roll -= weight
            if roll <= 0:
                chosen = a
                break
        recent.append(chosen["text"])
        del recent[:-len(RECENT_WEIGHT)]
        return chosen["text"]

    def type_words(self, type_name):
        entry = self.types.get(type_name)
        if entry:
            return entry["nato"] if self.rng.random() < 0.7 else entry["designation"]
        return words.spoken_type_name(type_name)

    def values(self, call):
        """The call's facts, said the radio way."""
        v = {"awacs": call.get("awacs", "Darkstar"), "pause": "{pause}",
             "callsign": spoken_callsign(call.get("callsign")), "flight": spoken_callsign(call.get("flight"))}
        if "base" in call:
            v["base"] = spoken_place(call["base"])
        if "field" in call:
            v["field"] = spoken_place(call["field"])
        if "count" in call:
            v["count"] = words.number_words(call["count"])
        if "mission" in call:
            v["mission"] = call["mission"]
        if "target" in call:
            v["target"] = spoken_system(call["target"])
        if "station" in call:
            v["station"] = call["station"] or ""
        if "fox" in call:
            v["fox"] = FOX_WORDS.get(int(call["fox"]), str(call["fox"]))
        for key in ("target_type", "kill_type"):
            if call.get(key):
                v[key] = self.type_words(call[key])
        if "threat" in call:
            v["threat"] = call["threat"]
        if "down" in call:
            v["down"] = spoken_callsign(call["down"])
        if call.get("runway"):
            v["runway"] = words.digit_words(int(call["runway"]), 2)
        if "distance_nm" in call:
            v["distance"] = words.number_words(max(1, int(round(call["distance_nm"]))))
        if call.get("direction"):
            v["direction"] = words.COMPASS.get(call["direction"], call["direction"])
        return v

    def word(self, call):
        kind = call["call"]
        parts = self.data["calls"][kind]
        conditions = set(call.get("flags") or [])
        values = self.values(call)
        said = [words.fill(self.pick("%s.%d" % (kind, i), part, conditions), values) for i, part in enumerate(parts)]
        text = ", ".join(s.strip() for s in said if s.strip())
        for written, spoken in self.data.get("pronounce", {}).items():
            text = re.sub(r"\b%s\b" % re.escape(written), spoken, text)
        return words.tidy(text)


SAMPLES = [
    {"call": "airborne", "callsign": "Weasel 3-1", "flight": "Weasel 3", "base": "Rovaniemi", "count": 2,
     "mission": "SEAD", "target": "the Sodankyla SA-10", "flags": ["sead", "two_ship", "has_target"]},
    {"call": "pushing", "callsign": "Viper 2-1", "flight": "Viper 2", "target": "", "flags": []},
    {"call": "fox", "callsign": "Eagle 1-1", "flight": "Eagle 1", "fox": 3, "target_type": "Su-27",
     "flags": ["target_known", "fox_three"]},
    {"call": "magnum", "callsign": "Weasel 3-2", "flight": "Weasel 3", "target": "SA-10", "flags": ["has_target"]},
    {"call": "splash", "callsign": "Hornet 2-1", "flight": "Hornet 2", "kill_type": "MiG-31", "flags": ["type_known"]},
    {"call": "defending", "callsign": "Viper 4-2", "flight": "Viper 4", "threat": "SAM", "flags": ["sam"]},
    {"call": "jet_down", "callsign": "Hornet 2-1", "flight": "Hornet 2", "down": "Hornet 2-2", "flags": ["ejected"]},
    {"call": "off_target", "callsign": "Weasel 3-1", "flight": "Weasel 3", "base": "Rovaniemi", "flags": ["sead"]},
    {"call": "taxi", "callsign": "Viper 1-1", "flight": "Viper 1", "field": "Kallax", "runway": 32,
     "flags": ["runway_known", "two_ship"]},
    {"call": "departing", "callsign": "Viper 1-1", "flight": "Viper 1", "field": "Kallax", "runway": 32,
     "direction": "NE", "flags": ["two_ship"]},
    {"call": "inbound", "callsign": "Hornet 2-1", "flight": "Hornet 2", "field": "Kemi_Tornio", "runway": 18,
     "distance_nm": 10, "direction": "N", "flags": ["runway_known"]},
    {"call": "final", "callsign": "Hornet 2-1", "flight": "Hornet 2", "field": "Kemi_Tornio", "runway": 18, "flags": []},
]


def main():
    awacs = json.load(open(words.PHRASES_PATH, encoding="utf-8"))
    pilot = FlightPhraseBank(PILOT_PHRASES_PATH, awacs["types"])
    airfield = FlightPhraseBank(AIRFIELD_PHRASES_PATH, awacs["types"])
    print("pilot_phrases.json and airfield_phrases.json are fine.\n")
    for call in SAMPLES:
        bank = pilot if call["call"] in pilot.kinds() else airfield
        for _ in range(2):
            print("- %-10s %s" % (call["call"], bank.word(call)))


if __name__ == "__main__":
    main()
