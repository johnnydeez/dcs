"""The radio player: plays AI radio calls to Windows' default sound output, as heard over a radio.

    python radio_calls/radio_player.py [--port 47110] [--exit-with-dcs]

It listens on a local port (127.0.0.1 only) for calls, puts the radio sound on each one
(radio_sound.py, tuned in radio_sound_settings.json) and plays them one at a time. Stop it
with Ctrl+C. A second copy can't start while one is running (the port is taken), so
starting it twice is harmless. With --exit-with-dcs (as the mission starts it) it closes
itself once DCS is no longer running.

A call is one TCP connection carrying one line of JSON, then the audio:
    {"speaker": "Darkstar", "frequency": "251.000", "audio_bytes": 123456, ...}\\n
    <audio_bytes bytes of a WAV file: the clean voice>
Header fields, all but audio_bytes optional:
    speaker, frequency  for the log (one frequency for now)
    sent_at             seconds since 1970: how long the call waited before it played
    urgent              true: played before every call waiting that isn't urgent (threat calls)
    replaces            a key ("picture:Snake one one"): a call waiting with the same key is
                        dropped, so a newer picture replaces an older one not yet played
    expires_s           not played if it waited longer than this since sent_at
send_radio_call.py sends test calls; speak_mission_calls.py sends the mission's.
"""

import argparse
import json
import socket
import subprocess
import sys
import threading
import time
import winsound

import radio_sound

DEFAULT_PORT = 47110
MAX_HEADER_BYTES = 4096
MAX_AUDIO_BYTES = 50 * 1024 * 1024
DCS_CHECK_EVERY_S = 30


def log(text):
    print(time.strftime("%H:%M:%S"), text, flush=True)


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
    return "%s on %s" % (header.get("speaker", "?"), header.get("frequency", "?"))


class CallsWaiting:
    """The calls not played yet: urgent ones first, then in the order they came."""

    def __init__(self):
        self.calls = []
        self.ready = threading.Condition()

    def add(self, header, audio):
        with self.ready:
            key = header.get("replaces")
            if key:
                for old in [c for c in self.calls if c[0].get("replaces") == key]:
                    self.calls.remove(old)
                    log("%s: replaced by a newer call before it played (%s)" % (describe(old[0]), key))
            call = (header, audio, time.time())
            if header.get("urgent"):
                at = sum(1 for c in self.calls if c[0].get("urgent"))
                self.calls.insert(at, call)
            else:
                self.calls.append(call)
            self.ready.notify()

    def next(self):
        with self.ready:
            while not self.calls:
                self.ready.wait()
            return self.calls.pop(0)


def play_calls(waiting):
    """The player thread: one call at a time."""
    while True:
        header, audio, received_at = waiting.next()
        try:
            waited = time.time() - header.get("sent_at", received_at)
            if header.get("expires_s") is not None and waited > header["expires_s"]:
                log("%s: dropped, %.0f s old (expires after %s s)" % (describe(header), waited, header["expires_s"]))
                continue
            started = time.time()
            radio = radio_sound.make_radio_call(audio)
            sound_s = time.time() - started
            seconds = (len(radio) - 44) / 2.0 / radio_sound.load_settings()["sample_rate_hz"]
            log("%s: %.1f s of audio%s (radio sound %.2f s, %.1f s since sent)"
                % (describe(header), seconds, ", urgent" if header.get("urgent") else "", sound_s, waited))
            winsound.PlaySound(radio, winsound.SND_MEMORY)
        except Exception as error:   # one bad call never stops the player
            log("%s: not played: %s" % (describe(header), error))


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
    args = parser.parse_args()

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        server.bind(("127.0.0.1", args.port))
    except OSError:
        sys.exit("port %d is taken: is the radio player already running?" % args.port)
    server.listen(8)
    server.settimeout(1.0)   # wakes up each second so Ctrl+C works

    waiting = CallsWaiting()
    threading.Thread(target=play_calls, args=(waiting,), daemon=True).start()
    log("radio player listening on 127.0.0.1:%d (Ctrl+C to stop)%s"
        % (args.port, "; closes with DCS" if args.exit_with_dcs else ""))
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
