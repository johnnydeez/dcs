"""Voice adapter: Windows' own voices (free, offline), through PowerShell's System.Speech.

    python radio_calls/windows_voice.py --list
    python radio_calls/windows_voice.py "Darkstar, picture, clean." out.wav [--voice "Microsoft David Desktop"]

speak(text, voice, rate) returns the bytes of a WAV file. Voices: David (male) and
Zira (female); Mark is a OneCore voice System.Speech can't use. More accents are free in Windows Settings (Speech, Add
voices). rate is -10 (slow) to 10 (fast), 0 is normal. "{pause}" in the text is a longer
gap than a full stop gives (PAUSE_MS).
"""

import os
import subprocess
import sys
import tempfile
from xml.sax.saxutils import escape

PAUSE_MS = 400

SPEAK_SCRIPT = r"""
Add-Type -AssemblyName System.Speech
$voice = New-Object System.Speech.Synthesis.SpeechSynthesizer
if ($env:RADIO_VOICE) { $voice.SelectVoice($env:RADIO_VOICE) }
$voice.Rate = [int]$env:RADIO_RATE
$voice.SetOutputToWaveFile($env:RADIO_WAV)
$voice.SpeakSsml($env:RADIO_SSML)
$voice.Dispose()
"""

LIST_SCRIPT = r"""
Add-Type -AssemblyName System.Speech
$voice = New-Object System.Speech.Synthesis.SpeechSynthesizer
$voice.GetInstalledVoices() | ForEach-Object { $_.VoiceInfo.Name + ' | ' + $_.VoiceInfo.Gender + ' | ' + $_.VoiceInfo.Culture }
$voice.Dispose()
"""


def run_powershell(script, environment=None):
    env = dict(os.environ)
    env.update(environment or {})
    result = subprocess.run(["powershell", "-NoProfile", "-NonInteractive", "-Command", script],
                            env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            universal_newlines=True, creationflags=0x08000000)  # no window
    if result.returncode != 0:
        raise RuntimeError("PowerShell: " + result.stderr.strip())
    return result.stdout


def list_voices():
    return [line.strip() for line in run_powershell(LIST_SCRIPT).splitlines() if line.strip()]


def ssml(text):
    pause = '<break time="%dms"/>' % PAUSE_MS
    body = escape(text).replace("{pause}", pause)
    return ('<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="en-US">'
            + body + "</speak>")


def speak(text, voice=None, rate=0):
    """Text -> the bytes of a WAV file in a Windows voice."""
    handle, path = tempfile.mkstemp(suffix=".wav", prefix="radio_call_")
    os.close(handle)
    try:
        run_powershell(SPEAK_SCRIPT, {"RADIO_SSML": ssml(text), "RADIO_VOICE": voice or "",
                                      "RADIO_RATE": str(rate), "RADIO_WAV": path})
        with open(path, "rb") as f:
            return f.read()
    finally:
        os.remove(path)


def main():
    if sys.argv[1:] == ["--list"]:
        print("\n".join(list_voices()))
        return
    if len(sys.argv) not in (3, 5) or (len(sys.argv) == 5 and sys.argv[3] != "--voice"):
        sys.exit(__doc__)
    voice = sys.argv[4] if len(sys.argv) == 5 else None
    with open(sys.argv[2], "wb") as f:
        f.write(speak(sys.argv[1], voice))
    print("wrote", sys.argv[2])


if __name__ == "__main__":
    main()
