"""Voice adapter: Windows' own voices (free, offline), through PowerShell's System.Speech.

    python radio_calls/windows_voice.py --list
    python radio_calls/windows_voice.py "Darkstar, picture, clean." out.wav [--voice "Microsoft David Desktop"]

speak(text, voice, rate) returns the bytes of a WAV file. Two Windows engines, both free
and offline: System.Speech ("Microsoft David Desktop", "Microsoft Zira Desktop") and the
newer Windows.Media.SpeechSynthesis ("OneCore": "Microsoft Mark", "Microsoft David", and
language voices added in Settings, Speech, Add voices); a voice is spoken by whichever
engine lists it (--list shows both, with the engine last). Windows' "natural" voices
(Ryan, Andrew, Sonia, Guy, ...) are Narrator's only: neither engine offers them. rate is
-10 (slow) to 10 (fast), 0 is normal. "{pause}" in the text is a longer gap than a full
stop gives (PAUSE_MS).
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
$voice.GetInstalledVoices() | ForEach-Object { $_.VoiceInfo.Name + ' | ' + $_.VoiceInfo.Gender + ' | ' + $_.VoiceInfo.Culture + ' | desktop' }
$voice.Dispose()
[Windows.Media.SpeechSynthesis.SpeechSynthesizer,Windows.Media.SpeechSynthesis,ContentType=WindowsRuntime] | Out-Null
[Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices | ForEach-Object { $_.DisplayName + ' | ' + $_.Gender + ' | ' + $_.Language + ' | onecore' }
"""

# Windows' newer speech engine (Windows.Media.SpeechSynthesis, "OneCore"): Mark and the
# voices added from Settings that it lists. Rate as SpeakingRate (1 = normal).
SPEAK_ONECORE_SCRIPT = r"""
Add-Type -AssemblyName System.Runtime.WindowsRuntime
[Windows.Media.SpeechSynthesis.SpeechSynthesizer,Windows.Media.SpeechSynthesis,ContentType=WindowsRuntime] | Out-Null
[Windows.Storage.Streams.DataReader,Windows.Storage.Streams,ContentType=WindowsRuntime] | Out-Null
$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($op, [Type]$type) {
    $task = $asTask.MakeGenericMethod($type).Invoke($null, @($op))
    $task.Wait(-1) | Out-Null
    $task.Result
}
$s = New-Object Windows.Media.SpeechSynthesis.SpeechSynthesizer
$s.Voice = [Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices | Where-Object { $_.DisplayName -eq $env:RADIO_VOICE } | Select-Object -First 1
$s.Options.SpeakingRate = [double]$env:RADIO_SPEED
$stream = Await ($s.SynthesizeSsmlToStreamAsync($env:RADIO_SSML)) ([Windows.Media.SpeechSynthesis.SpeechSynthesisStream])
$reader = New-Object Windows.Storage.Streams.DataReader($stream.GetInputStreamAt(0))
$size = [uint32]$stream.Size
Await ($reader.LoadAsync($size)) ([uint32]) | Out-Null
$bytes = New-Object byte[] $size
$reader.ReadBytes($bytes)
[IO.File]::WriteAllBytes($env:RADIO_WAV, $bytes)
"""

_engines = None   # voice name -> "desktop" | "onecore", read once


def voice_engines():
    """Every voice either engine has: name -> "desktop" (System.Speech) or "onecore"."""
    global _engines
    if _engines is None:
        _engines = {}
        for line in list_voices():
            parts = [p.strip() for p in line.split("|")]
            if len(parts) == 4:
                _engines.setdefault(parts[0], parts[3])
    return _engines


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
    """Text -> the bytes of a WAV file in a Windows voice, through whichever engine has it."""
    handle, path = tempfile.mkstemp(suffix=".wav", prefix="radio_call_")
    os.close(handle)
    try:
        if voice and voice_engines().get(voice) == "onecore":
            speed = max(0.5, min(3.0, 1.0 + rate * 0.1))   # rate -10..10 as System.Speech's
            run_powershell(SPEAK_ONECORE_SCRIPT, {"RADIO_SSML": ssml(text), "RADIO_VOICE": voice,
                                                  "RADIO_SPEED": str(speed), "RADIO_WAV": path})
        else:
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
