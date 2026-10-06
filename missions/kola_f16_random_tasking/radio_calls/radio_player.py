"""The radio player: plays AI radio calls to Windows' default sound output, as heard over a radio.

    python radio_calls/radio_player.py [--port 47110] [--exit-with-dcs]

It listens on a local port (127.0.0.1 only) for calls, puts the radio sound on each one
(radio_sound.py, tuned in radio_sound_settings.json) and plays them one at a time: calls
never overlap, whichever radio they are on. Stop it with Ctrl+C. A second copy can't start
while one is running (the port is taken), so starting it twice is harmless. With
--exit-with-dcs (as the mission starts it) it closes itself once DCS is no longer running.

The jet's radios: our export script (export_cockpit_radios.lua, run by DCS's export system)
sends the player's radios (frequency, on / off, volume knob) here about twice a second, over
UDP on 127.0.0.1:RADIOS_PORT. While it does, a call is played only when one of the jet's
radios is on and tuned to the call's frequency, at that radio's volume; with no word from it
(DCS not running the script, a spectator slot, a type it can't read) every call is played.
At start this player makes sure DCS's Export.lua loads that script (one line, added if
missing; nothing else in the file is touched); DCS reads Export.lua when it starts, so the
first time it needs one DCS restart. README.md, "Kola radio calls", has the details.

A call is one TCP connection carrying one line of JSON, then the audio:
    {"speaker": "Darkstar", "frequency": 262.0, "audio_bytes": 123456, ...}\\n
    <audio_bytes bytes of a WAV file: the clean voice>
Header fields, all but audio_bytes optional:
    speaker             for the log
    frequency           MHz the call is on; only played when a radio is tuned to it (above)
    channel             for the log ("awacs", "mission", "airfield")
    priority            1 (combat, threat) to 3 (routine); waiting calls play in this order,
                        then in the order they came. urgent: true is priority 1 (older senders)
    event_at            seconds since 1970 when it happened in the mission; its age counts
                        from here (sent_at when missing)
    sent_at             seconds since 1970 when it was sent
    expires_s           not played if older than this when its turn comes
    replaces            a key ("picture:Snake one one"): a call waiting with the same key is
                        dropped, so a newer picture replaces an older one not yet played
    pitch               the voice played this much faster and higher (1.05) or slower (0.95)
When more than MAX_BACKLOG_S of audio is waiting, the lowest-priority calls go first
(the oldest of them), so a busy fight never leaves the radio minutes behind.
send_radio_call.py sends test calls; speak_mission_calls.py sends the mission's.
"""

import argparse
import io
import json
import os
import socket
import subprocess
import sys
import threading
import time
import wave
import winsound

import radio_sound

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_PORT = 47110
RADIOS_PORT = 47112             # UDP, from export_cockpit_radios.lua
MAX_HEADER_BYTES = 4096
MAX_AUDIO_BYTES = 50 * 1024 * 1024
DCS_CHECK_EVERY_S = 30
MAX_BACKLOG_S = 20.0            # audio waiting before the lowest-priority calls are dropped
RADIOS_FRESH_S = 3.0            # the jet's radios as last reported count this long
TUNED_WITHIN_MHZ = 0.01
EXPORT_SCRIPT = os.path.join(HERE, "export_cockpit_radios.lua")
# everything the window shows, also kept in a file, rewritten at each start (git-ignored), so
# a run can be read afterwards: the jet's radios as they changed, and each call heard, not
# heard (and why) or dropped (2026-10-06: the volume knobs did nothing in the 00:16 run, and
# nothing was left to show whether the radios ever reached the player)
LOG_PATH = os.path.join(HERE, "radio_player.log")
_log_file = None


def log(text):
    line = "%s %s" % (time.strftime("%H:%M:%S"), text)
    print(line, flush=True)
    if _log_file:
        try:
            _log_file.write(line + "\n")
            _log_file.flush()
        except OSError:
            pass


def read_call(connection):
    """One call off a connection: (header, the voice's WAV bytes)."""
    data = b""
    while b"\n" not in data:
        chunk = connection.recv(4096)
        if not chunk:
            raise ValueError("connection closed before the call's header ended")
        data += chunk
        if len(data) > MAX_HEADER_BYTES and b"\n" not in data:
            raise ValueError("no header line in the first %d bytes" % MAX_HEADER_BYTES)
    line, audio = data.split(b"\n", 1)
    header = json.loads(line.decode("utf-8"))
    size = int(header["audio_bytes"])
    if not 0 < size <= MAX_AUDIO_BYTES:
        raise ValueError("audio_bytes %d out of range" % size)
    while len(audio) < size:
        chunk = connection.recv(min(65536, size - len(audio)))
        if not chunk:
            raise ValueError("connection closed after %d of %d audio bytes" % (len(audio), size))
        audio += chunk
    return header, audio[:size]


def describe(header):
    frequency = header.get("frequency")
    on = ("%.3f" % float(frequency)) if isinstance(frequency, (int, float)) else (frequency or "?")
    return "%s on %s%s" % (header.get("speaker", "?"), on,
                           " (%s)" % header["channel"] if header.get("channel") else "")


def priority_of(header):
    if header.get("urgent"):
        return 1
    return int(header.get("priority", 2))


def audio_seconds(audio):
    try:
        with wave.open(io.BytesIO(audio), "rb") as w:
            return w.getnframes() / float(w.getframerate())
    except Exception:
        return 0.0


def age_of(header, received_at):
    return time.time() - header.get("event_at", header.get("sent_at", received_at))


class CallsWaiting:
    """The calls not played yet: by priority, then in the order they came."""

    def __init__(self):
        self.calls = []        # (header, audio, received_at, seconds)
        self.ready = threading.Condition()

    def add(self, header, audio):
        with self.ready:
            key = header.get("replaces")
            if key:
                for old in [c for c in self.calls if c[0].get("replaces") == key]:
                    self.calls.remove(old)
                    log("%s: replaced by a newer call before it played (%s)" % (describe(old[0]), key))
            call = (header, audio, time.time(), audio_seconds(audio))
            priority = priority_of(header)
            at = sum(1 for c in self.calls if priority_of(c[0]) <= priority)
            self.calls.insert(at, call)
            self.trim()
            self.ready.notify()

    def trim(self):
        """Over MAX_BACKLOG_S of audio waiting: drop the lowest priority, oldest first; never
        the last call left."""
        while len(self.calls) > 1 and sum(c[3] for c in self.calls) > MAX_BACKLOG_S:
            lowest = max(priority_of(c[0]) for c in self.calls)
            victim = next(c for c in self.calls if priority_of(c[0]) == lowest)
            self.calls.remove(victim)
            log("%s: dropped, the radio is %.0f s behind (priority %d)"
                % (describe(victim[0]), sum(c[3] for c in self.calls) + victim[3], lowest))

    def next(self):
        with self.ready:
            while not self.calls:
                self.ready.wait()
            return self.calls.pop(0)


class JetRadios:
    """The player's radios as export_cockpit_radios.lua last reported them."""

    def __init__(self):
        self.report = None
        self.received_at = 0.0
        self.stale_said = False
        self.lock = threading.Lock()

    def listen(self, port=RADIOS_PORT):
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            sock.bind(("127.0.0.1", port))
        except OSError as error:
            log("can't listen for the jet's radios on UDP %d (%s): every call is played" % (port, error))
            return
        first, said = True, None
        while True:
            try:
                data, _ = sock.recvfrom(8192)
                report = json.loads(data.decode("utf-8"))
            except Exception as error:
                log("a report from the jet's radios couldn't be read: %s" % error)
                continue
            with self.lock:
                self.report, self.received_at = report, time.time()
                self.stale_said = False
            # every change of the radios (a volume knob counted in steps of 0.05), so the
            # log shows what the jet was tuned to and how loud when each call played
            text = self.text(report, volume_step=0.05)
            if first:
                first = False
                log("hearing the jet's radios from DCS: %s" % text)
            elif text != said:
                log("the jet's radios: %s" % text)
            said = text

    @staticmethod
    def text(report, volume_step=0.01):
        radios = report.get("radios") or []
        if not radios:
            return "%s, no radios read (every call is played)" % report.get("type", "no aircraft")
        return "%s, " % report.get("type", "?") + ", ".join(
            "%s %.3f %s vol %.2f" % (r.get("name", "?"), r.get("mhz", 0), "on" if r.get("on") else "off",
                                     round(float(r.get("volume", 1)) / volume_step) * volume_step) for r in radios)

    def tuned(self, frequency):
        """(play?, volume, why) for a call on `frequency` MHz."""
        with self.lock:
            report, age = self.report, time.time() - self.received_at
            fresh = age <= RADIOS_FRESH_S
            if report and not fresh and not self.stale_said:
                self.stale_said = True
                log("no word from the jet's radios for %.0f s: every call plays at full volume" % age)
        if frequency is None or not fresh or not report or not report.get("radios"):
            return True, 1.0, "" if report else "no word from the jet's radios yet, played at full volume"
        try:
            frequency = float(frequency)
        except (TypeError, ValueError):
            return True, 1.0, ""
        for r in report["radios"]:
            if r.get("on") and abs(float(r.get("mhz", 0)) - frequency) <= TUNED_WITHIN_MHZ:
                return True, float(r.get("volume", 1.0)), r.get("name", "")
        return False, 0.0, "no radio tuned to %.3f" % frequency


def play_calls(waiting, radios):
    """The player thread: one call at a time."""
    while True:
        header, audio, received_at, _ = waiting.next()
        try:
            age = age_of(header, received_at)
            if header.get("expires_s") is not None and age > header["expires_s"]:
                log("%s: dropped, %.0f s old (expires after %s s)" % (describe(header), age, header["expires_s"]))
                continue
            play, volume, why = radios.tuned(header.get("frequency"))
            if not play:
                log("%s: not heard, %s" % (describe(header), why))
                continue
            started = time.time()
            radio = radio_sound.make_radio_call(audio, pitch=float(header.get("pitch", 1.0)), radio_volume=volume)
            sound_s = time.time() - started
            seconds = (len(radio) - 44) / 2.0 / radio_sound.load_settings()["sample_rate_hz"]
            log("%s: %.1f s of audio, priority %d, %s at volume %.2f (radio sound %.2f s, %.1f s after the event)"
                % (describe(header), seconds, priority_of(header), ("on " + why) if why else "every call played",
                   volume, sound_s, age))
            winsound.PlaySound(radio, winsound.SND_MEMORY)
        except Exception as error:   # one bad call never stops the player
            log("%s: not played: %s" % (describe(header), error))


# ── DCS's Export.lua: the one line that loads our export script ──────────

def saved_games_dcs_folders():
    """The DCS folders under Saved Games that exist (DCS, DCS.openbeta)."""
    home = os.path.join(os.path.expanduser("~"), "Saved Games")
    return [os.path.join(home, name) for name in ("DCS", "DCS.openbeta") if os.path.isdir(os.path.join(home, name))]


def export_line():
    return ("pcall(function() dofile([[%s]]) end, nil) -- Kola radio calls: the jet's radios for "
            "radio_player.py (see the repo's README, Kola radio calls)" % EXPORT_SCRIPT)


def install_export_line():
    """Adds our line to each Saved Games DCS folder's Scripts\\Export.lua if it isn't there,
    or corrects its path if the folder moved. Never touches any other line."""
    for folder in saved_games_dcs_folders():
        path = os.path.join(folder, "Scripts", "Export.lua")
        try:
            text = open(path, encoding="utf-8", errors="replace").read() if os.path.exists(path) else ""
        except OSError as error:
            log("can't read %s (%s): the jet's radios won't be heard" % (path, error))
            continue
        lines = text.splitlines()
        ours = [i for i, l in enumerate(lines) if "export_cockpit_radios.lua" in l]
        line = export_line()
        if ours and lines[ours[0]].strip() == line:
            continue
        if ours:
            lines[ours[0]] = line
            what = "corrected the path in"
        else:
            lines.append(line)
            what = "added a line to"
        try:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8", newline="\n") as f:
                f.write("\n".join(lines) + "\n")
        except OSError as error:
            log("can't write %s (%s): the jet's radios won't be heard" % (path, error))
            continue
        log("%s %s: restart DCS once so it loads the jet's radios (until then every call is played)"
            % (what, path))


def dcs_running():
    try:
        out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq DCS.exe", "/NH"], stdout=subprocess.PIPE,
                             universal_newlines=True, creationflags=0x08000000).stdout
    except OSError:
        return True
    return "DCS.exe" in out


def main():
    parser = argparse.ArgumentParser(description="Plays AI radio calls with a radio sound.")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--exit-with-dcs", action="store_true", help="close once DCS isn't running")
    parser.add_argument("--no-export-line", action="store_true", help="don't check DCS's Export.lua")
    args = parser.parse_args()

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        server.bind(("127.0.0.1", args.port))
    except OSError:
        sys.exit("port %d is taken: is the radio player already running?" % args.port)
    global _log_file   # opened only by the copy that runs, so a second start doesn't wipe its log
    try:
        _log_file = open(LOG_PATH, "w", encoding="utf-8")
    except OSError as error:
        print("can't write %s (%s): the log is in this window only" % (LOG_PATH, error), flush=True)
    server.listen(8)
    server.settimeout(1.0)   # wakes up each second so Ctrl+C works

    if not args.no_export_line:
        install_export_line()
    waiting, radios = CallsWaiting(), JetRadios()
    threading.Thread(target=radios.listen, daemon=True).start()
    threading.Thread(target=play_calls, args=(waiting, radios), daemon=True).start()
    log("radio player listening on 127.0.0.1:%d, the jet's radios on UDP %d (Ctrl+C to stop)%s"
        % (args.port, RADIOS_PORT, "; closes with DCS" if args.exit_with_dcs else ""))
    next_dcs_check = time.time() + DCS_CHECK_EVERY_S
    try:
        while True:
            if args.exit_with_dcs and time.time() >= next_dcs_check:
                next_dcs_check = time.time() + DCS_CHECK_EVERY_S
                if not dcs_running():
                    log("DCS isn't running: radio player closing")
                    break
            try:
                connection, _ = server.accept()
            except socket.timeout:
                continue
            with connection:
                connection.settimeout(10)
                try:
                    header, audio = read_call(connection)
                except Exception as error:
                    log("bad call: %s" % error)
                    continue
            waiting.add(header, audio)
    except KeyboardInterrupt:
        log("radio player stopped")
    finally:
        server.close()


if __name__ == "__main__":
    main()
