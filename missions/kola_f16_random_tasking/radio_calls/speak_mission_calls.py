"""The radio helper: speaks the mission's radio calls through the radio player.

    python radio_calls/speak_mission_calls.py [--exit-with-dcs]

The mission (kola_f16/consumers/send_radio_calls.lua) writes each call's facts as one JSON
line to mission_calls.jsonl in this folder, emptying it at mission start. This reads new
lines as they come (every 0.2 s), words each call, speaks it in a Windows voice
(windows_voice.py) and sends it to the radio player (radio_player.py), which plays it. The
mission starts both with start_radio_calls.cmd; either can also be started by hand. One
copy runs at a time.

Who says it:
  Darkstar's calls (picture, picture_clean, no_coverage, threat): phrase_bank_wording.py and
      awacs_phrases.json, in the controller's voice (Zira);
  Darkstar's orders to AI flights (engage, resume, return_to_base, land_at, scramble_vector):
      flight_phrase_wording.py and awacs_order_phrases.json, in the controller's voice too;
  the AI pilots' mission calls (airborne, pushing, fox, splash, ...): flight_phrase_wording.py
      and pilot_phrases.json; airfield traffic calls (taxi, departing, inbound, final,
      clear): the same with airfield_phrases.json. A pilot's voice comes from
      pilot_phrases.json's list, picked by its flight's callsign, so a flight always sounds
      the same; never Zira.
To the player, from the mission's facts: the call's frequency and channel, its priority and
how long it may wait (expires_s); its age counts from when this helper read it (event_at),
so a backlog here counts too. A picture replaces an older one for the same player not
played yet.
Each call is logged here and in speak_mission_calls.log (emptied at each start): the words,
and how long the wording and the voice took.
"""

import argparse
import json
import os
import socket
import sys
import time
import zlib

import flight_phrase_wording
import phrase_bank_wording
import radio_player
import send_radio_call
import windows_voice

HERE = os.path.dirname(os.path.abspath(__file__))
CALLS_FILE = os.path.join(HERE, "mission_calls.jsonl")
LOG_FILE = os.path.join(HERE, "speak_mission_calls.log")
LOCK_PORT = 47111            # held while running, so a second copy exits
READ_EVERY_S = 0.2
DCS_CHECK_EVERY_S = 30
OLD_FILE_S = 60              # a calls file untouched this long at start is a past mission's
AWACS_CALLS = {"picture", "picture_clean", "no_coverage", "threat"}
# when the mission's call doesn't say (an older mission file)
DEFAULT_EXPIRES_S = {"threat": 30}
DEFAULT_PICTURE_EXPIRES_S = 90

_log_file = None


def log(text):
    line = "%s %s" % (time.strftime("%H:%M:%S"), text)
    print(line, flush=True)
    if _log_file:
        _log_file.write(line + "\n")
        _log_file.flush()


class CallsFile:
    """New complete lines of the calls file; starts over when the mission empties it."""

    def __init__(self, path):
        self.path = path
        self.position = 0
        self.partial = b""
        try:
            if time.time() - os.path.getmtime(path) > OLD_FILE_S:
                self.position = os.path.getsize(path)   # a past mission's calls: skip them
        except OSError:
            pass

    def new_lines(self):
        try:
            size = os.path.getsize(self.path)
        except OSError:
            return []
        if size < self.position:            # emptied: a new mission
            self.position, self.partial = 0, b""
            log("a new mission started")
        if size == self.position:
            return []
        with open(self.path, "rb") as f:
            f.seek(self.position)
            data = f.read(size - self.position)
        self.position += len(data)
        data = self.partial + data
        lines = data.split(b"\n")
        self.partial = lines.pop()
        return [line.decode("utf-8") for line in lines if line.strip()]


class Speakers:
    """Wording and voice for every kind of call."""

    def __init__(self):
        self.awacs = phrase_bank_wording.PhraseBank()
        types = self.awacs.data["types"]
        self.pilot = flight_phrase_wording.FlightPhraseBank(flight_phrase_wording.PILOT_PHRASES_PATH, types)
        self.airfield = flight_phrase_wording.FlightPhraseBank(flight_phrase_wording.AIRFIELD_PHRASES_PATH, types)
        self.orders = flight_phrase_wording.FlightPhraseBank(flight_phrase_wording.ORDER_PHRASES_PATH, types)
        installed = set()
        try:
            installed = {line.split(" | ")[0] for line in windows_voice.list_voices()}
        except Exception as error:
            log("couldn't list the Windows voices (%s)" % error)
        controller_voice = self.awacs.data["controller"]["voice"]
        listed = self.pilot.data["voices"]["list"]
        self.pilot_voices = [v for v in listed if v["voice"] in installed and v["voice"] != controller_voice]
        if not self.pilot_voices:
            self.pilot_voices = [{"voice": None, "rate": 1, "pitch": 1.0}]
        log("pilot voices: %s" % ", ".join(sorted({v["voice"] or "Windows default" for v in self.pilot_voices})))

    def pilot_voice(self, key):
        return self.pilot_voices[zlib.crc32((key or "").encode("utf-8")) % len(self.pilot_voices)]

    def speak(self, call):
        """(text, wav bytes, header fields) for one call."""
        kind = call["call"]
        if kind in AWACS_CALLS:
            controller = self.awacs.data["controller"]
            text = self.awacs.word(call)
            wav = windows_voice.speak(text, controller["voice"], controller["rate"])
            fields = {"speaker": controller["callsign"],
                      "priority": call.get("priority", 1 if kind == "threat" else 3),
                      "expires_s": call.get("expires_s", DEFAULT_EXPIRES_S.get(kind, DEFAULT_PICTURE_EXPIRES_S))}
            if kind != "threat":
                fields["replaces"] = "picture:" + call.get("to", "")
            return text, wav, fields
        if kind in self.orders.kinds():
            controller = self.awacs.data["controller"]
            text = self.orders.word(call)
            wav = windows_voice.speak(text, controller["voice"], controller["rate"])
            fields = {"speaker": controller["callsign"], "priority": call.get("priority", 2),
                      "expires_s": call.get("expires_s", 20)}
            return text, wav, fields
        bank = self.pilot if kind in self.pilot.kinds() else self.airfield
        if kind not in bank.kinds():
            raise ValueError("no phrases for call '%s'" % kind)
        text = bank.word(call)
        voice = self.pilot_voice(call.get("voice_key") or call.get("flight"))
        wav = windows_voice.speak(text, voice["voice"], voice["rate"])
        fields = {"speaker": call.get("callsign", "?"), "pitch": voice.get("pitch", 1.0),
                  "priority": call.get("priority", 2), "expires_s": call.get("expires_s", 20)}
        return text, wav, fields


def speak_call(speakers, call, read_at):
    started = time.time()
    text, wav, fields = speakers.speak(call)
    spoken = time.time()
    fields.update(event_at=read_at, channel=call.get("channel"))
    frequency = call.get("frequency_mhz")
    try:
        send_radio_call.send_call(wav, fields.pop("speaker"), frequency, **fields)
        sent = "sent"
    except OSError:
        sent = "NOT SENT: no radio player running"
    log("%s (mission %s s, %s %s): %s  [words + voice %.2f s, %s]" % (
        call["call"], call.get("mission_time_s", "?"), call.get("channel", "?"),
        "%.3f" % frequency if isinstance(frequency, (int, float)) else "-", text, spoken - started, sent))


def main():
    global _log_file
    parser = argparse.ArgumentParser(description="Speaks the mission's radio calls.")
    parser.add_argument("--exit-with-dcs", action="store_true", help="close once DCS isn't running")
    args = parser.parse_args()

    lock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        lock.bind(("127.0.0.1", LOCK_PORT))
    except OSError:
        sys.exit("the radio helper is already running")
    _log_file = open(LOG_FILE, "w", encoding="utf-8")

    speakers = Speakers()
    calls = CallsFile(CALLS_FILE)
    log("radio helper reading %s%s" % (CALLS_FILE, "; closes with DCS" if args.exit_with_dcs else ""))
    next_dcs_check = time.time() + DCS_CHECK_EVERY_S
    try:
        while True:
            lines = calls.new_lines()
            read_at = time.time()
            # the most urgent first when several came at once
            parsed = []
            for line in lines:
                try:
                    parsed.append(json.loads(line))
                except ValueError as error:
                    log("call not read: %s: %s" % (error, line[:200]))
            parsed.sort(key=lambda c: c.get("priority", 3 if c.get("call") != "threat" else 1))
            for call in parsed:
                try:
                    speak_call(speakers, call, read_at)
                except Exception as error:   # one bad call never stops the helper
                    log("call not spoken: %s: %s" % (error, json.dumps(call)[:200]))
            if args.exit_with_dcs and time.time() >= next_dcs_check:
                next_dcs_check = time.time() + DCS_CHECK_EVERY_S
                if not radio_player.dcs_running():
                    log("DCS isn't running: radio helper closing")
                    break
            time.sleep(READ_EVERY_S)
    except KeyboardInterrupt:
        log("radio helper stopped")
    finally:
        lock.close()


if __name__ == "__main__":
    main()
