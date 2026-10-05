"""Plays sample Darkstar calls through the radio player (radio_player.py must be running).

    python play_sample_awacs_calls.py                 the sample calls below, in order
    python play_sample_awacs_calls.py --repeat 4      each sample call 4 times (hear the variety)
    python play_sample_awacs_calls.py --only 3        just sample call 3 (numbers as printed)
    python play_sample_awacs_calls.py --text-only     print the words, send nothing

The facts are made up, shaped the way the mission will send them (phrase_bank_wording.py).
The words come from awacs_phrases.json, the voice from its "controller" block (Zira), and
the radio player queues the calls and plays them one after another.
"""

import argparse
import time

import phrase_bank_wording
import send_radio_call
import windows_voice

TO = "Snake one one"

SAMPLE_CALLS = [
    # 1. nothing on the scope
    {"call": "picture", "to": TO, "groups": []},
    # 2. one Flanker patrol far off, flanking
    {"call": "picture", "to": TO, "groups": [
        {"type": "Su-27", "bearing": 47, "range_nm": 118, "range_known": True,
         "altitude_ft": 31000, "aspect": "flank", "track": "SE", "age_s": 4}]},
    # 3. two groups: a Foxhound high and hot, a Fullback low and beaming
    {"call": "picture", "to": TO, "groups": [
        {"type": "MiG-31", "bearing": 62, "range_nm": 84, "range_known": True,
         "altitude_ft": 38000, "aspect": "hot", "track": "SW", "age_s": 3},
        {"type": "Su-34", "bearing": 95, "range_nm": 61, "range_known": True,
         "altitude_ft": 800, "aspect": "beam", "track": "N", "age_s": 9}]},
    # 4. a close, hot Flanker and a Fulcrum going away
    {"call": "picture", "to": TO, "groups": [
        {"type": "Su-30", "bearing": 12, "range_nm": 31, "range_known": True,
         "altitude_ft": 22000, "aspect": "hot", "track": "S", "age_s": 2},
        {"type": "MiG-29S", "bearing": 340, "range_nm": 55, "range_known": True,
         "altitude_ft": 15000, "aspect": "drag", "track": "NE", "age_s": 6}]},
    # 5. busy: six groups, one unidentified, one with no range, one stale
    {"call": "picture", "to": TO, "groups": [
        {"type": "Su-27", "bearing": 75, "range_nm": 45, "range_known": True,
         "altitude_ft": 27000, "aspect": "hot", "track": "W", "age_s": 3},
        {"type": "unknown", "bearing": 110, "range_nm": 70, "range_known": True,
         "altitude_ft": 9000, "aspect": "flank", "track": "NW", "age_s": 12},
        {"type": "Su-24M", "bearing": 150, "range_nm": 0, "range_known": False,
         "altitude_ft": 2500, "aspect": "beam", "track": "E", "age_s": 20},
        {"type": "Tu-22M3", "bearing": 30, "range_nm": 140, "range_known": True,
         "altitude_ft": 33000, "aspect": "drag", "track": "N", "age_s": 95},
        {"type": "A-50", "bearing": 60, "range_nm": 190, "range_known": True,
         "altitude_ft": 30000, "aspect": "beam", "track": "S", "age_s": 30},
        {"type": "Mi-8MT", "bearing": 100, "range_nm": 105, "range_known": True,
         "altitude_ft": 400, "aspect": "slow", "track": "N", "age_s": 40}]},
    # 6. out of the AWACS's reach
    {"call": "no_coverage", "to": TO},
    # 7. threat: a Flanker hot at 28 miles
    {"call": "threat", "to": TO, "groups": [
        {"type": "Su-27", "bearing": 38, "range_nm": 28, "range_known": True,
         "altitude_ft": 24000, "aspect": "hot", "track": "SW", "age_s": 2}]},
]


def main():
    parser = argparse.ArgumentParser(description="Plays sample Darkstar calls.")
    parser.add_argument("--repeat", type=int, default=1, help="each call this many times")
    parser.add_argument("--only", type=int, help="just this sample call (1 to %d)" % len(SAMPLE_CALLS))
    parser.add_argument("--text-only", action="store_true", help="print the words, send nothing")
    args = parser.parse_args()

    bank = phrase_bank_wording.PhraseBank()
    controller = bank.data["controller"]
    numbered = list(enumerate(SAMPLE_CALLS, 1))
    if args.only:
        numbered = [numbered[args.only - 1]]
    for number, call in numbered:
        for _ in range(args.repeat):
            text = bank.word(call)
            print("%d. %s" % (number, text))
            if args.text_only:
                continue
            started = time.time()
            wav = windows_voice.speak(text, controller["voice"], controller["rate"])
            voice_s = time.time() - started
            try:
                send_radio_call.send_call(wav, controller["callsign"], "251.000")
            except ConnectionRefusedError:
                raise SystemExit("no radio player running: start start_radio_player.cmd first")
            print("   (voice %.1f s, sent)" % voice_s)


if __name__ == "__main__":
    main()
