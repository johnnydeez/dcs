"""Sends a test call to the radio player (radio_player.py must be running).

    python radio_calls/send_radio_call.py                         Darkstar's sample picture, Windows voice
    python radio_calls/send_radio_call.py --say "Darkstar, picture, clean."
    python radio_calls/send_radio_call.py --voice "Microsoft Zira Desktop" --rate 1
    python radio_calls/send_radio_call.py --wav some_voice.wav     any WAV file instead of a Windows voice

To tune the sound: change radio_sound_settings.json, save, and send again; the player reads
the settings fresh for every call.
"""

import argparse
import json
import socket
import time

import radio_player
import windows_voice

SAMPLE_PICTURE = ("Viper one one, Darkstar, picture, two groups. "
                  "Group one, MiG twenty-nine, bearing one one zero, one two zero miles, "
                  "twenty thousand, hot. "
                  "Group two, Sukhoi thirty-four, bearing zero niner zero, eight five miles, "
                  "low, flanking.")


def send_call(wav_bytes, speaker, frequency, port=radio_player.DEFAULT_PORT, host="127.0.0.1", **extra):
    """One call to a radio player; extra header fields (urgent, replaces, expires_s) as given."""
    header = dict(extra, speaker=speaker, frequency=frequency,
                  audio_bytes=len(wav_bytes), sent_at=time.time())
    with socket.create_connection((host, port), timeout=5) as connection:
        connection.sendall(json.dumps(header).encode("utf-8") + b"\n" + wav_bytes)


def main():
    parser = argparse.ArgumentParser(description="Sends a test call to the radio player.")
    parser.add_argument("--say", default=SAMPLE_PICTURE, help="text for a Windows voice")
    parser.add_argument("--voice", help="Windows voice name (windows_voice.py --list)")
    parser.add_argument("--rate", type=int, default=0, help="Windows voice speed, -10 to 10")
    parser.add_argument("--wav", help="send this WAV file instead of a Windows voice")
    parser.add_argument("--speaker", default="Darkstar")
    parser.add_argument("--frequency", default="251.000")
    parser.add_argument("--port", type=int, default=radio_player.DEFAULT_PORT)
    args = parser.parse_args()

    started = time.time()
    if args.wav:
        with open(args.wav, "rb") as f:
            wav_bytes = f.read()
    else:
        wav_bytes = windows_voice.speak(args.say, args.voice, args.rate)
    voice_s = time.time() - started
    try:
        send_call(wav_bytes, args.speaker, args.frequency, args.port)
    except ConnectionRefusedError:
        raise SystemExit("no radio player on port %d: start radio_player.py first" % args.port)
    print("sent %d bytes (voice took %.1f s)" % (len(wav_bytes), voice_s))


if __name__ == "__main__":
    main()
