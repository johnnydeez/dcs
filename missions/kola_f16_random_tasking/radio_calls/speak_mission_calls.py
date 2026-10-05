"""The radio helper: speaks the mission's AWACS calls through the radio player.

    python radio_calls/speak_mission_calls.py [--exit-with-dcs]

The mission (kola_f16/consumers/send_radio_calls.lua) writes each call's facts as one JSON
line to mission_calls.jsonl in this folder, emptying it at mission start. This reads new
lines as they come (every 0.2 s), words each call (phrase_bank_wording.py, awacs_phrases.json),
speaks it in the controller's Windows voice (windows_voice.py) and sends it to the radio
player (radio_player.py), which plays it. The mission starts both with start_radio_calls.cmd;
either can also be started by hand. One copy runs at a time.

To the player: threat calls are urgent (played before anything waiting); a picture replaces
an older one for the same player not played yet; a picture not played within
PICTURE_EXPIRES_S, a threat within THREAT_EXPIRES_S, is dropped (old news).
Each call is logged here and in speak_mission_calls.log (emptied at each start): the
words, and how long the wording and the voice took.
"""

import argparse
import json
import os
import socket
import sys
import time

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
PICTURE_EXPIRES_S = 90
THREAT_EXPIRES_S = 30
FREQUENCY = "251.000"        # one frequency for now

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


def speak_call(bank, call):
    started = time.time()
    text = bank.word(call)
    worded = time.time()
    controller = bank.data["controller"]
    wav = windows_voice.speak(text, controller["voice"], controller["rate"])
    spoken = time.time()
    kind = call["call"]
    extra = {"urgent": kind == "threat",
             "expires_s": THREAT_EXPIRES_S if kind == "threat" else PICTURE_EXPIRES_S}
    if kind != "threat":
        extra["replaces"] = "picture:" + call.get("to", "")
    try:
        send_radio_call.send_call(wav, controller["callsign"], FREQUENCY, **extra)
        sent = "sent"
    except OSError:
        sent = "NOT SENT: no radio player running"
    log("%s (mission %s s): %s  [wording %.2f s, voice %.2f s, %s]" % (
        kind, call.get("mission_time_s", "?"), text, worded - started, spoken - worded, sent))


def main():
    global _log_file
    parser = argparse.ArgumentParser(description="Speaks the mission's AWACS calls.")
    parser.add_argument("--exit-with-dcs", action="store_true", help="close once DCS isn't running")
    args = parser.parse_args()

    lock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        lock.bind(("127.0.0.1", LOCK_PORT))
    except OSError:
        sys.exit("the radio helper is already running")
    _log_file = open(LOG_FILE, "w", encoding="utf-8")

    bank = phrase_bank_wording.PhraseBank()
    calls = CallsFile(CALLS_FILE)
    log("radio helper reading %s%s" % (CALLS_FILE, "; closes with DCS" if args.exit_with_dcs else ""))
    next_dcs_check = time.time() + DCS_CHECK_EVERY_S
    try:
        while True:
            for line in calls.new_lines():
                try:
                    speak_call(bank, json.loads(line))
                except Exception as error:   # one bad call never stops the helper
                    log("call not spoken: %s: %s" % (error, line[:200]))
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
