"""The radio sound: turns a clean voice recording into a call heard over a military radio.

    python radio_calls/radio_sound.py <clean .wav> <radio .wav>

The steps, each tuned in radio_sound_settings.json (read again for every call, so a change
is heard on the next call without restarting the radio player):
  1. mono, at the radio's sample rate (sample_rate_hz; a real radio's audio is narrow anyway);
  2. band-pass: high_pass_hz to low_pass_hz, filter_stages steep, with a presence peak
     (presence_hz, presence_gain_db) for the radio's "honk";
  3. drive: soft clipping, louder and grittier as it goes up (1 = clean);
  4. hiss under the voice (hiss_level), band-passed like the voice;
  5. squelch: a click and a short burst of hiss as the transmitter keys up (key_up_ms,
     click_level), and the squelch tail as it lets go (squelch_tail_ms, squelch_tail_level);
  6. volume (times the cockpit radio's own volume knob, when the radio player knows it),
     then 16-bit mono WAV.
A speaker's pitch (a little faster and higher, or slower and lower) is applied in step 1.

Levels are fractions of full scale (1.0 = the loudest a WAV can hold).
"""

import array
import audioop
import io
import json
import math
import os
import random
import sys
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
SETTINGS_PATH = os.path.join(HERE, "radio_sound_settings.json")


def load_settings(path=SETTINGS_PATH):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def read_wav(wav_bytes):
    """A WAV file's bytes -> (16-bit mono samples as an array, sample rate)."""
    with wave.open(io.BytesIO(wav_bytes), "rb") as w:
        channels, width, rate = w.getnchannels(), w.getsampwidth(), w.getframerate()
        frames = w.readframes(w.getnframes())
    if width == 1:
        frames = audioop.bias(frames, 1, -128)   # 8-bit WAV is unsigned
    if width != 2:
        frames = audioop.lin2lin(frames, width, 2)
    if channels == 2:
        frames = audioop.tomono(frames, 2, 0.5, 0.5)
    elif channels != 1:
        raise ValueError("WAV with %d channels: only mono and stereo are read" % channels)
    return frames, rate


def write_wav(samples, rate):
    """Float samples (-1..1) -> the bytes of a 16-bit mono WAV file."""
    pcm = array.array("h", (int(max(-1.0, min(1.0, s)) * 32767) for s in samples))
    if sys.byteorder == "big":
        pcm.byteswap()
    out = io.BytesIO()
    with wave.open(out, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm.tobytes())
    return out.getvalue()


def biquad(kind, rate, frequency_hz, q=0.7071, gain_db=0.0):
    """Filter coefficients (b0, b1, b2, a1, a2), normalised; Robert Bristow-Johnson's cookbook."""
    w0 = 2 * math.pi * frequency_hz / rate
    cos_w0, alpha = math.cos(w0), math.sin(w0) / (2 * q)
    if kind == "low_pass":
        b0, b1, b2 = (1 - cos_w0) / 2, 1 - cos_w0, (1 - cos_w0) / 2
        a0, a1, a2 = 1 + alpha, -2 * cos_w0, 1 - alpha
    elif kind == "high_pass":
        b0, b1, b2 = (1 + cos_w0) / 2, -(1 + cos_w0), (1 + cos_w0) / 2
        a0, a1, a2 = 1 + alpha, -2 * cos_w0, 1 - alpha
    elif kind == "peak":
        a = 10 ** (gain_db / 40)
        b0, b1, b2 = 1 + alpha * a, -2 * cos_w0, 1 - alpha * a
        a0, a1, a2 = 1 + alpha / a, -2 * cos_w0, 1 - alpha / a
    else:
        raise ValueError(kind)
    return b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0


def apply_filter(samples, coefficients):
    b0, b1, b2, a1, a2 = coefficients
    x1 = x2 = y1 = y2 = 0.0
    out = [0.0] * len(samples)
    for i, x in enumerate(samples):
        y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, x, y1, y
        out[i] = y
    return out


def band_filters(settings, rate):
    """The radio's band-pass and presence peak, as a list of filters."""
    nyquist_margin = rate * 0.45
    filters = []
    for _ in range(int(settings["filter_stages"])):
        filters.append(biquad("high_pass", rate, settings["high_pass_hz"]))
        filters.append(biquad("low_pass", rate, min(settings["low_pass_hz"], nyquist_margin)))
    if settings["presence_gain_db"]:
        filters.append(biquad("peak", rate, min(settings["presence_hz"], nyquist_margin),
                              q=1.0, gain_db=settings["presence_gain_db"]))
    return filters


def band_pass(samples, filters):
    for f in filters:
        samples = apply_filter(samples, f)
    return samples


def normalise(samples, peak_level):
    peak = max((abs(s) for s in samples), default=0.0)
    if peak == 0:
        return samples
    scale = peak_level / peak
    return [s * scale for s in samples]


def noise(count, level, filters):
    """Band-passed hiss at about `level` (its peaks), the same band as the voice."""
    if count <= 0 or level <= 0:
        return [0.0] * max(count, 0)
    raw = [random.uniform(-1.0, 1.0) for _ in range(count)]
    return normalise(band_pass(raw, filters), level)


def fade(samples, fade_in, fade_out):
    n = len(samples)
    for i in range(min(fade_in, n)):
        samples[i] *= i / fade_in
    for i in range(min(fade_out, n)):
        samples[n - 1 - i] *= i / fade_out
    return samples


def make_radio_call(wav_bytes, settings=None, pitch=1.0, radio_volume=1.0):
    """A clean voice WAV's bytes -> the radio version's WAV bytes.
    pitch: the voice played this much faster and higher (1.05) or slower and lower (0.95), so
    flights sharing one Windows voice sound like different people (System.Speech ignores SSML
    pitch); radio_volume: the cockpit radio's volume knob, 0..1, on top of the settings' volume."""
    settings = settings or load_settings()
    frames, rate = read_wav(wav_bytes)
    radio_rate = int(settings["sample_rate_hz"])
    rate = int(round(rate * pitch))
    if rate != radio_rate:
        frames, _ = audioop.ratecv(frames, 2, 1, rate, radio_rate, None)
    pcm = array.array("h")
    pcm.frombytes(frames)
    if sys.byteorder == "big":
        pcm.byteswap()
    voice = [s / 32768.0 for s in pcm]

    filters = band_filters(settings, radio_rate)
    voice = normalise(band_pass(voice, filters), 1.0)
    drive = float(settings["drive"])
    if drive > 1:
        voice = [math.tanh(s * drive) for s in voice]
    voice = normalise(voice, 0.9)

    per_ms = radio_rate / 1000.0
    key_up = int(settings["key_up_ms"] * per_ms)
    tail = int(settings["squelch_tail_ms"] * per_ms)
    hiss_level = settings["hiss_level"]

    # Key up: a click, then hiss alone until the voice starts.
    click = int(8 * per_ms)
    opening = noise(click, settings["click_level"], filters)
    opening += noise(max(key_up - click, 0), hiss_level, filters)
    # The voice with hiss under it.
    hiss = noise(len(voice), hiss_level, filters)
    body = [v + h for v, h in zip(voice, hiss)]
    # Let go: the squelch tail, falling away fast.
    closing = fade(noise(tail, settings["squelch_tail_level"], filters), int(3 * per_ms), tail // 2)

    volume = float(settings["volume"]) * max(0.0, min(1.0, radio_volume))
    call =[s * volume for s in fade(opening, int(2 * per_ms), 0) + body + closing]
    return write_wav(call, radio_rate)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    with open(sys.argv[1], "rb") as f:
        clean = f.read()
    with open(sys.argv[2], "wb") as f:
        f.write(make_radio_call(clean))
    print("wrote", sys.argv[2])


if __name__ == "__main__":
    main()
