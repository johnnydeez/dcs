"""Wording adapter, phrase bank: turns an AWACS call's facts into what the controller says.

    python radio_calls/phrase_bank_wording.py          checks awacs_phrases.json and prints sample calls

The phrases are in awacs_phrases.json (see its "_about"); this file holds the brevity rules
that never vary: the order of a group's facts, bearings digit by digit ("zero niner zero"),
which aspect word goes with which angle (the mission decides that), "angels" never used for
an enemy's altitude. Randomness only picks the words, never whether a fact is said.

A call's facts (one dict, as the mission will send them):
    {"call": "picture" | "picture_clean" | "no_coverage" | "threat",
     "to": "Snake one one",                       the player's callsign, as spoken
     "groups": [                                  picture: highest threat first; threat: the one group
        {"type": "Su-27",                         DCS type name, "unknown" if not identified
         "bearing": 135,                          magnetic, from the player
         "range_nm": 42.3, "range_known": true,
         "altitude_ft": 25000,
         "aspect": "hot" | "flank" | "beam" | "drag" | "slow",
         "track": "SW",                           the group's direction of travel, 8 points
         "age_s": 5}]}                            seconds since a radar last saw it
The result is the spoken text, with {pause} where the voice should stop a moment longer.
"""

import json
import math
import os
import random
import re

HERE = os.path.dirname(os.path.abspath(__file__))
PHRASES_PATH = os.path.join(HERE, "awacs_phrases.json")

PLACEHOLDER = re.compile(r"\{(\w+)\}")

# A phrase used last time keeps a quarter of its weight, the time before half.
RECENT_WEIGHT = [0.25, 0.5]

CONDITIONS = {"one_group", "several_groups", "busy", "close_hot", "type_known", "type_unknown",
              "stale", "scattered"}

# The placeholders each kind of phrase may use (checked when the file is loaded).
CALL_PLACEHOLDERS = {"to", "me", "pause"}
PLACEHOLDERS = {
    "opening": CALL_PLACEHOLDERS,
    "count": CALL_PLACEHOLDERS | {"group_count"},
    "label": CALL_PLACEHOLDERS | {"direction", "number", "ordinal"},
    "braa": CALL_PLACEHOLDERS | {"bearing", "range", "altitude", "aspect"},
    "braa_no_range": CALL_PLACEHOLDERS | {"bearing", "altitude", "aspect"},
    "aspect": {"track"},
    "declare": CALL_PLACEHOLDERS | {"type"},
    "stale": CALL_PLACEHOLDERS | {"age_minutes"},
    "low_altitude": set(),
    "more_groups": CALL_PLACEHOLDERS | {"more_groups", "more_direction", "more_range"},
    "closing": CALL_PLACEHOLDERS | {"first_direction"},
    "picture_clean": CALL_PLACEHOLDERS,
    "no_coverage": CALL_PLACEHOLDERS,
    "threat_opening": CALL_PLACEHOLDERS | {"direction"},
    "threat_closing": CALL_PLACEHOLDERS | {"direction"},
}

ONES = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen",
        "nineteen"]
TENS = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
DIGITS = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "niner"]
ORDINALS = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth",
            "tenth"]
COMPASS = {"N": "north", "NE": "northeast", "E": "east", "SE": "southeast", "S": "south",
           "SW": "southwest", "W": "west", "NW": "northwest"}
COMPASS_POINTS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]


# ── numbers, as said on the radio ──────────────────────────────────

def number_words(n):
    """0..999 in words: 42 -> "forty-two", 120 -> "one hundred twenty"."""
    n = int(n)
    if n < 20:
        return ONES[n]
    if n < 100:
        return TENS[n // 10] + ("-" + ONES[n % 10] if n % 10 else "")
    rest = n % 100
    return ONES[n // 100] + " hundred" + (" " + number_words(rest) if rest else "")


def digit_words(n, width=0):
    """Each digit on its own: 90 -> "niner zero", width 3 -> "zero niner zero"."""
    return " ".join(DIGITS[int(d)] for d in str(int(n)).zfill(width))


def bearing_words(bearing):
    bearing = int(round(bearing)) % 360
    return digit_words(bearing or 360, 3)


def range_words(range_nm, style):
    n = int(round(range_nm))
    if n >= 100:
        n = int(round(n / 5.0) * 5)
    if style == "digits" and n >= 10:
        return digit_words(n)
    if n < 100:
        return number_words(n)
    if style == "hundred":
        rest = n % 100
        head = "a hundred" if n < 200 else ONES[n // 100] + " hundred"
        return head + (" " + number_words(rest) if rest else "")
    hundreds, rest = n // 100, n % 100        # "plain": the way pilots say it
    if rest == 0:
        return ONES[hundreds] + " hundred"
    if rest < 10:
        return ONES[hundreds] + " oh " + ONES[rest]
    return ONES[hundreds] + " " + number_words(rest)


def altitude_words(altitude_ft, style, low_words):
    if altitude_ft < 1000:
        return low_words
    thousands = int(round(altitude_ft / 1000.0))
    if style == "digits" and thousands >= 10:
        return digit_words(thousands) + " thousand"
    return number_words(thousands) + " thousand"


def minutes_words(seconds):
    minutes = max(1, int(round(seconds / 60.0)))
    return "a minute" if minutes == 1 else number_words(minutes) + " minutes"


def compass_point(bearing):
    return COMPASS_POINTS[int(math.floor((bearing % 360) / 45.0 + 0.5)) % 8]


def mean_bearing(bearings):
    x = sum(math.cos(math.radians(b)) for b in bearings)
    y = sum(math.sin(math.radians(b)) for b in bearings)
    return math.degrees(math.atan2(y, x)) % 360


def angle_between(a, b):
    d = abs(a - b) % 360
    return min(d, 360 - d)


# ── the phrase bank ────────────────────────────────────────────────

def alternatives(raw):
    """A list of strings / {text, weight, when} -> a list of {text, weight, when}."""
    out = []
    for item in raw:
        if isinstance(item, str):
            item = {"text": item}
        out.append({"text": item["text"], "weight": item.get("weight", 1), "when": item.get("when")})
    return out


class PhraseBank:
    def __init__(self, path=PHRASES_PATH, rng=None):
        with open(path, encoding="utf-8") as f:
            self.data = json.load(f)
        self.rng = rng or random.Random()
        self.recent = {}      # list key -> the texts last chosen from it, newest last
        self.check()

    # every alternative uses only placeholders its kind can fill, and only known conditions
    def check(self):
        problems = []
        for key, kind, items in self.phrase_lists():
            allowed = PLACEHOLDERS[kind]
            for item in items:
                for name in PLACEHOLDER.findall(item["text"]):
                    if name not in allowed:
                        problems.append("%s: {%s} can't be filled there (\"%s\")" % (key, name, item["text"]))
                if item["when"] and item["when"] not in CONDITIONS:
                    problems.append("%s: unknown condition '%s'" % (key, item["when"]))
        for kind in ("range", "altitude", "type", "label"):
            if kind not in self.data["styles"]:
                problems.append("styles: no '%s'" % kind)
        if problems:
            raise ValueError("awacs_phrases.json:\n  " + "\n  ".join(problems))

    def phrase_lists(self):
        """(key, kind, alternatives) for every list of phrases in the file."""
        picture = self.data["picture"]
        for name, raw in picture.items():
            if name in ("label", "aspect"):
                for sub, sub_raw in raw.items():
                    if not sub.startswith("_"):
                        yield "picture.%s.%s" % (name, sub), name, alternatives(sub_raw)
            else:
                yield "picture." + name, name, alternatives(raw)
        for name in ("opening", "closing"):
            yield "threat." + name, "threat_" + name, alternatives(self.data["threat"][name])
        yield "picture_clean", "picture_clean", alternatives(self.data["picture_clean"])
        yield "no_coverage", "no_coverage", alternatives(self.data["no_coverage"])

    def pick(self, key, raw, conditions=()):
        """One alternative's text: weighted, `when` honoured. A recently used phrase is
        made less likely (RECENT_WEIGHT), never ruled out, so the file's weights still hold;
        saying nothing (an empty text) is never held back."""
        items = [a for a in alternatives(raw) if not a["when"] or a["when"] in conditions]
        if not items:
            return ""
        recent = self.recent.setdefault(key, [])   # newest last
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

    def pick_style(self, kind):
        weights = {k: v for k, v in self.data["styles"][kind].items() if not k.startswith("_")}
        names = sorted(weights)
        return self.rng.choices(names, [weights[n] for n in names])[0]

    def type_words(self, type_name, style):
        entry = self.data["types"].get(type_name)
        if entry:
            return entry[style]
        return spoken_type_name(type_name)

    def pronounce(self, text):
        for written, spoken in self.data.get("pronounce", {}).items():
            text = re.sub(r"\b%s\b" % re.escape(written), spoken, text)
        return text

    # ── calls ──────────────────────────────────────────────────────

    def word(self, call):
        """A call's facts -> the spoken text."""
        values = {"to": call.get("to", ""), "me": self.data["controller"]["callsign"], "pause": "{pause}"}
        kind = call["call"]
        if kind == "picture" and not call.get("groups"):
            kind = "picture_clean"
        if kind in ("picture_clean", "no_coverage"):
            text = fill(self.pick(kind, self.data[kind]), values)
        elif kind == "picture":
            text = self.word_picture(call["groups"], values)
        elif kind == "threat":
            text = self.word_threat(call["groups"][0], values)
        else:
            raise ValueError("unknown call '%s'" % kind)
        return self.pronounce(tidy(text))

    def word_picture(self, groups, values):
        p = self.data["picture"]
        in_full = groups[:self.data["groups_in_full"]]
        rest = groups[len(in_full):]
        first = groups[0]
        conditions = set()
        conditions.add("one_group" if len(groups) == 1 else "several_groups")
        if len(groups) >= 4:
            conditions.add("busy")
        if (first["aspect"] == "hot" and first.get("range_known", True)
                and first["range_nm"] <= self.data["close_hot_nm"]):
            conditions.add("close_hot")
        style = {kind: self.pick_style(kind) for kind in ("range", "altitude", "type", "label")}
        directions = [compass_point(g["bearing"]) for g in in_full]
        if len(set(directions)) < len(directions):
            style["label"] = "number"
        label_form = self.pick("picture.label." + style["label"], p["label"][style["label"]])

        values = dict(values, group_count=number_words(len(groups)),
                      first_direction=COMPASS[compass_point(first["bearing"])])
        sentences = [join(fill(self.pick("picture.opening", p["opening"], conditions), values),
                          fill(self.pick("picture.count", p["count"], conditions), values))]
        for i, g in enumerate(in_full):
            sentences.append(self.word_group(g, i, len(groups), label_form, style, values))
        if rest:
            sentences.append(self.word_more_groups(rest, values))
        sentences.append(fill(self.pick("picture.closing", p["closing"], conditions), values))
        return ". ".join(s for s in sentences if s)

    def word_threat(self, g, values):
        """One hot group close in: who it's for, "threat", then the group as in a picture."""
        t = self.data["threat"]
        style = {kind: self.pick_style(kind) for kind in ("range", "altitude", "type")}
        values = dict(values, direction=COMPASS[compass_point(g["bearing"])])
        return ". ".join(s for s in [
            fill(self.pick("threat.opening", t["opening"]), values),
            self.word_group(g, 0, 1, "", style, values),
            fill(self.pick("threat.closing", t["closing"]), values)] if s)

    def word_group(self, g, index, group_count, label_form, style, values):
        p = self.data["picture"]
        type_known = g.get("type") and not g["type"].startswith("unknown") or g.get("type") in self.data["types"]
        stale = g.get("age_s", 0) >= self.data["stale_s"]
        conditions = {"type_known" if type_known else "type_unknown"}
        if stale:
            conditions.add("stale")
        aspect_key = "picture.aspect." + g["aspect"]
        aspect = fill(self.pick(aspect_key, p["aspect"][g["aspect"]]),
                      {"track": COMPASS.get(g.get("track", ""), "")})
        facts = dict(values,
                     direction=COMPASS[compass_point(g["bearing"])], number=number_words(index + 1),
                     ordinal=ORDINALS[index] if index < len(ORDINALS) else number_words(index + 1),
                     bearing=bearing_words(g["bearing"]),
                     range=range_words(g["range_nm"], style["range"]),
                     altitude=altitude_words(g["altitude_ft"], style["altitude"],
                                             self.pick("picture.low_altitude", p["low_altitude"])),
                     aspect=aspect,
                     type=self.type_words(g["type"], style["type"]) if type_known else "",
                     age_minutes=minutes_words(g.get("age_s", 0)))
        parts = []
        if group_count > 1:
            parts.append(fill(label_form, facts))
        if g.get("range_known", True):
            parts.append(fill(self.pick("picture.braa", p["braa"]), facts))
        else:
            parts.append(fill(self.pick("picture.braa_no_range", p["braa_no_range"]), facts))
        parts.append(fill(self.pick("picture.declare", p["declare"], conditions), facts))
        if stale:
            parts.append(fill(self.pick("picture.stale", p["stale"]), facts))
        return ", ".join(x for x in parts if x)

    def word_more_groups(self, rest, values):
        bearings = [g["bearing"] for g in rest]
        centre = mean_bearing(bearings)
        conditions = set()
        if len(rest) > 1 and max(angle_between(b, centre) for b in bearings) > 60:
            conditions.add("scattered")
        nearest = min(g["range_nm"] for g in rest if g.get("range_known", True)) if any(
            g.get("range_known", True) for g in rest) else 0
        facts = dict(values,
                     more_groups=("one more group" if len(rest) == 1
                                  else number_words(len(rest)) + " more groups"),
                     more_direction=COMPASS[compass_point(centre)],
                     more_range=range_words(max(10, int(nearest // 10) * 10), "plain"))
        p = self.data["picture"]
        return fill(self.pick("picture.more_groups", p["more_groups"], conditions), facts)


def spoken_type_name(type_name):
    """A type not in the table: "Su-27" -> "Sukhoi twenty-seven"."""
    prefixes = {"Su": "Sukhoi", "MiG": "MiG", "Tu": "Tupolev", "Mi": "Mil", "Ka": "Kamov",
                "Yak": "Yak", "IL": "Ilyushin", "Il": "Ilyushin"}
    m = re.match(r"([A-Za-z]+)-?(\d+)", type_name)
    if not m or int(m.group(2)) > 999:
        return type_name.replace("_", " ")
    return prefixes.get(m.group(1), m.group(1)) + " " + number_words(int(m.group(2)))


def fill(template, values):
    return PLACEHOLDER.sub(lambda m: str(values.get(m.group(1), "")), template)


def join(*fragments):
    return ", ".join(f for f in fragments if f)


def tidy(text):
    text = re.sub(r"\s+", " ", text).strip().lstrip(",. ")
    text = re.sub(r"\s+([,.])", r"\1", text)
    text = re.sub(r",\s*,", ",", text)
    text = re.sub(r"\.\s*\.", ".", text)
    text = text[0].upper() + text[1:] if text else text
    return text if text.endswith(".") else text + "."


def main():
    import play_sample_awacs_calls as sample_awacs_calls
    bank = PhraseBank()
    print("awacs_phrases.json is fine.\n")
    for call in sample_awacs_calls.SAMPLE_CALLS:
        print("-", bank.word(call))


if __name__ == "__main__":
    main()
