// Soft two-note notification tones for peer join/leave — synthesized via
// Web Audio API rather than shipping audio files, so there's nothing to
// load and no asset to keep in sync. Sine waves + a short linear
// attack/decay envelope keep it gentle instead of a harsh beep/click.
let audioContext = null;

function getAudioContext() {
  if (!audioContext) {
    audioContext = new (window.AudioContext || window.webkitAudioContext)();
  }
  return audioContext;
}

function playTone(frequencies, { gain = 0.12, noteDuration = 0.14 } = {}) {
  try {
    const ctx = getAudioContext();
    if (ctx.state === 'suspended') ctx.resume();

    frequencies.forEach((freq, i) => {
      const oscillator = ctx.createOscillator();
      const gainNode = ctx.createGain();
      oscillator.type = 'sine';
      oscillator.frequency.value = freq;

      const startTime = ctx.currentTime + i * noteDuration;
      gainNode.gain.setValueAtTime(0, startTime);
      gainNode.gain.linearRampToValueAtTime(gain, startTime + 0.02);
      gainNode.gain.linearRampToValueAtTime(0, startTime + noteDuration);

      oscillator.connect(gainNode).connect(ctx.destination);
      oscillator.start(startTime);
      oscillator.stop(startTime + noteDuration + 0.02);
    });
  } catch {
    // A notification chime is a nicety — never let it break the call.
  }
}

// Rising major third — the other person joined/rejoined.
export function playJoinChime() {
  playTone([523.25, 659.25]); // C5, E5
}

// Falling minor third — the other person left.
export function playLeaveChime() {
  playTone([440, 349.23]); // A4, F4
}
