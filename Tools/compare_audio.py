"""Compare a sound recording of the port against MAME's.

Usage: Tools/compare_audio.py [--all] [--true-rate] <mame.wav> <godot.wav>

mame.wav is MAME's own recording (-wavwrite, 48 kHz). godot.wav comes from
Project/tools/synth_replay.gd or sound_replay.gd, at the sound chip's own
rate; it is resampled here to MAME's. synth_replay.gd places MAME's writes
on MAME's sample grid (55555 samples a second); for sound_replay.gd, which
runs at the chip's true rate (55555.56), pass --true-rate. Only the seconds
with a residual above -35 dB are listed unless --all is given. The two are lined up (MAME's resampler
delays its output slightly) and smoothed, and for every second the script prints both
levels, the gain that fits the port to MAME best (1.00 = same loudness) and
how much of MAME's signal is left after subtracting the port's, in dB (the
more negative the closer).
"""
import array
import math
import sys
import wave

# MAME runs the chip's sound stream at a whole number of samples per second
CHIP_RATE = 8000000 // 144


def load(path):
    with wave.open(path) as w:
        data = array.array("h", w.readframes(w.getnframes()))
        return w.getframerate(), [data[0::2], data[1::2]]


def resample(samples, rate_in, rate_out, count, delay):
    """Linear resampling; `delay` (in output samples, may be fractional) shifts the result later."""
    out = array.array("d", bytes(8 * count))
    step = rate_in / rate_out
    limit = len(samples) - 1
    for n in range(count):
        position = (n - delay) * step
        index = int(position)
        if position < 0 or index >= limit:
            continue
        fraction = position - index
        out[n] = samples[index] * (1 - fraction) + samples[index + 1] * fraction
    return out


def smooth(samples, width=6):
    """Two passes of a moving average: keeps roughly the lowest 4 kHz, where
    the two resamplers agree."""
    for _ in range(2):
        out = array.array("d", bytes(8 * len(samples)))
        total = 0.0
        for n, value in enumerate(samples):
            total += value
            if n >= width:
                total -= samples[n - width]
            out[n] = total / width
        samples = out
    return samples


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def best_delay(mame, port_raw, rate):
    """Delay of the port, in fractions of a sample, that matches MAME best:
    the median over five of the louder seconds, spread over the recording."""
    seconds = min(len(mame) // rate, int(len(port_raw) / CHIP_RATE))
    power = {s: dot(mame[s * rate:(s + 1) * rate], mame[s * rate:(s + 1) * rate]) for s in range(1, seconds - 1)}
    ranked = sorted(power, key=power.get)
    chosen = sorted(ranked[len(ranked) // 2:])
    chosen = chosen[::max(len(chosen) // 5, 1)][:5]
    delays = []
    for second in chosen:
        a = smooth(mame[(second - 1) * rate:(second + 1) * rate])[rate:]
        first = int((second - 1) * CHIP_RATE)
        piece = port_raw[first:first + int(2.1 * CHIP_RATE)]
        offset = (second - 1) * rate - first * rate / CHIP_RATE

        def score(delay):
            b = smooth(resample(piece, CHIP_RATE, rate, 2 * rate, delay - offset))[rate:]
            return dot(a, b) / math.sqrt(dot(b, b) or 1)
        coarse = max(range(-8, 9), key=score)
        delays.append(max((coarse + f / 8 for f in range(-8, 9)), key=score))
    return sorted(delays)[len(delays) // 2]


def db(x):
    return 10 * math.log10(x) if x > 0 else -99.0


def main():
    global CHIP_RATE
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    show_all = "--all" in sys.argv
    if "--true-rate" in sys.argv:
        CHIP_RATE = 8000000 / 144
    rate, mame = load(args[0])
    _, port_raw = load(args[1])
    seconds = min(len(mame[0]) // rate, int(len(port_raw[0]) / CHIP_RATE))
    first, last = 0, seconds
    delay = best_delay(mame[0], port_raw[0], rate)
    port = [smooth(resample(side, CHIP_RATE, rate, seconds * rate, delay)) for side in port_raw]
    mame = [smooth(side) for side in mame]
    print("port delayed %.3f samples; columns per side: mame dB, port dB, gain, residual dB" % delay)
    worst = -99.0
    compared = 0
    for second in range(max(first, 1), last - 1):
        line = "%4d s" % second
        here = -99.0
        for side in range(2):
            a = mame[side][second * rate:(second + 1) * rate]
            b = port[side][second * rate:(second + 1) * rate]
            aa, bb, ab = dot(a, a), dot(b, b), dot(a, b)
            if aa < rate and bb < rate:
                line += "   (silent)                    "
                continue
            gain = ab / bb if bb else 0.0
            residual = (aa - 2 * gain * ab + gain * gain * bb) / aa if aa else 1.0
            here = max(here, db(residual))
            compared += 1
            line += "   %6.1f %6.1f  %5.2f %6.1f" % (db(aa / rate), db(bb / rate), gain, db(residual))
        worst = max(worst, here)
        if show_all or here > -35:
            print(line)
    print("%d seconds with sound compared; worst residual %.1f dB" % (compared // 2, worst))


if __name__ == "__main__":
    main()
