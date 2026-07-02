// =============================================
// DUSTFALL — AUDIO ENGINE (Pass 13+14, v1.1)
// Fully synthesized: SFX + a sparse generative western ambient layer.
// Zero assets, zero network — WebAudio oscillators and filtered noise only.
// Classic script (no modules), safe under file:// and Electron.
// Mute: press M anywhere; persisted via DF.storage ("audio").
// =============================================
(function () {
  "use strict";
  const DF = (window.DF = window.DF || {});

  let ctx = null,
    master = null,
    sfxGain = null,
    musicGain = null;
  let muted = false;
  let mood = null, // current music mood id
    droneNodes = [],
    motifTimer = null;

  // ---- persisted settings ----
  function loadPrefs() {
    const s = DF.storage && DF.storage.load ? DF.storage.load("audio") : null;
    muted = !!(s && s.muted);
  }
  function savePrefs() {
    if (DF.storage && DF.storage.save) DF.storage.save("audio", { muted });
  }

  function ensure() {
    if (ctx) return true;
    try {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return false;
      ctx = new AC();
      master = ctx.createGain();
      master.gain.value = muted ? 0 : 1;
      master.connect(ctx.destination);
      sfxGain = ctx.createGain();
      sfxGain.gain.value = 0.5;
      sfxGain.connect(master);
      musicGain = ctx.createGain();
      musicGain.gain.value = 0.14;
      musicGain.connect(master);
    } catch (e) {
      return false;
    }
    return true;
  }
  // browsers gate audio behind a user gesture — unlock on the first one
  function unlock() {
    if (!ensure()) return;
    if (ctx.state === "suspended") ctx.resume();
    if (mood && !droneNodes.length) startMood(mood); // deferred music start
  }
  window.addEventListener("pointerdown", unlock, { passive: true });
  window.addEventListener("keydown", (e) => {
    unlock();
    if ((e.key === "m" || e.key === "M") && !e.repeat) DF.audio.toggleMute();
  });

  // ---- tiny synth toolkit ----
  function noiseBuffer(seconds) {
    const len = Math.max(1, Math.floor(ctx.sampleRate * seconds));
    const buf = ctx.createBuffer(1, len, ctx.sampleRate);
    const d = buf.getChannelData(0);
    for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
    return buf;
  }
  // filtered noise burst: the backbone of shots/blasts/whiffs
  function burst(dur, filterType, freq, gain, sweepTo) {
    const src = ctx.createBufferSource();
    src.buffer = noiseBuffer(dur);
    const f = ctx.createBiquadFilter();
    f.type = filterType;
    f.frequency.value = freq;
    if (sweepTo)
      f.frequency.exponentialRampToValueAtTime(sweepTo, ctx.currentTime + dur);
    const g = ctx.createGain();
    g.gain.setValueAtTime(gain, ctx.currentTime);
    g.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + dur);
    src.connect(f);
    f.connect(g);
    g.connect(sfxGain);
    src.start();
    src.stop(ctx.currentTime + dur);
  }
  // one decaying tone
  function tone(type, freq, dur, gain, endFreq, dest, when) {
    const t0 = ctx.currentTime + (when || 0);
    const o = ctx.createOscillator();
    o.type = type;
    o.frequency.setValueAtTime(freq, t0);
    if (endFreq) o.frequency.exponentialRampToValueAtTime(endFreq, t0 + dur);
    const g = ctx.createGain();
    g.gain.setValueAtTime(0.0001, t0);
    g.gain.exponentialRampToValueAtTime(gain, t0 + 0.015);
    g.gain.exponentialRampToValueAtTime(0.001, t0 + dur);
    o.connect(g);
    g.connect(dest || sfxGain);
    o.start(t0);
    o.stop(t0 + dur + 0.05);
  }

  const ready = () => !muted && ensure() && ctx.state === "running";

  // ---- SFX ----
  DF.sfx = {
    shot() {
      if (!ready()) return;
      burst(0.14, "lowpass", 900, 0.7, 200); // powder crack
      burst(0.05, "highpass", 2500, 0.25); // muzzle snap
    },
    hit() {
      if (!ready()) return;
      tone("square", 220, 0.1, 0.25, 90);
      burst(0.08, "bandpass", 500, 0.3);
    },
    miss() {
      if (!ready()) return;
      burst(0.18, "bandpass", 1800, 0.12, 3200); // whiff past the ear
    },
    blast() {
      if (!ready()) return;
      burst(0.5, "lowpass", 500, 0.9, 60); // boom
      tone("sine", 70, 0.45, 0.5, 40); // ground thump
    },
    divine() {
      if (!ready()) return;
      // a chord out of the sky
      [220, 277, 330, 440].forEach((f, i) =>
        tone("sawtooth", f, 0.7, 0.12, f * 1.5, sfxGain, i * 0.05),
      );
      burst(0.6, "highpass", 4000, 0.1);
    },
    heal() {
      if (!ready()) return;
      tone("sine", 392, 0.16, 0.2, null, sfxGain, 0);
      tone("sine", 523, 0.28, 0.2, null, sfxGain, 0.1);
    },
    stun() {
      if (!ready()) return;
      tone("square", 660, 0.08, 0.15, 660, sfxGain, 0);
      tone("square", 660, 0.08, 0.12, 660, sfxGain, 0.12);
    },
    click() {
      if (!ready()) return;
      tone("square", 900, 0.03, 0.08, 500);
    },
    win() {
      if (!ready()) return;
      [262, 330, 392, 523].forEach((f, i) =>
        tone("triangle", f, 0.35, 0.22, null, sfxGain, i * 0.13),
      );
    },
    lose() {
      if (!ready()) return;
      [330, 294, 262, 196].forEach((f, i) =>
        tone("sawtooth", f, 0.5, 0.16, f * 0.97, sfxGain, i * 0.22),
      );
    },
  };

  // ---- generative ambient (Pass 14) ----
  // A mood = a low drone + sparse pentatonic plucks. Sparse on purpose: this
  // is desert wind with a memory of a guitar, not a soundtrack.
  const MOODS = {
    // root (Hz), drone type, pluck scale (semitone offsets), pluck pace (ms)
    title: { root: 55, scale: [0, 3, 5, 7, 10], pace: [4000, 9000], vol: 0.14 },
    map: {
      root: 65.4,
      scale: [0, 3, 5, 7, 10],
      pace: [5000, 11000],
      vol: 0.12,
    },
    town: { root: 82.4, scale: [0, 2, 5, 7, 9], pace: [4500, 9000], vol: 0.1 },
    battle: {
      root: 49,
      scale: [0, 3, 6, 7, 10],
      pace: [2500, 6000],
      vol: 0.16,
    },
    boss: { root: 41.2, scale: [0, 1, 3, 6, 7], pace: [1800, 4200], vol: 0.2 },
  };
  function stopMusic() {
    droneNodes.forEach((n) => {
      try {
        n.stop ? n.stop() : n.disconnect();
      } catch (e) {}
    });
    droneNodes = [];
    if (motifTimer) {
      clearTimeout(motifTimer);
      motifTimer = null;
    }
  }
  function startMood(id) {
    if (!ensure() || ctx.state !== "running") {
      mood = id; // start when the first gesture unlocks audio
      return;
    }
    stopMusic();
    mood = id;
    const m = MOODS[id] || MOODS.title;
    musicGain.gain.setTargetAtTime(m.vol, ctx.currentTime, 1.2);
    // two detuned saws through a dark lowpass = desert wind organ
    const lp = ctx.createBiquadFilter();
    lp.type = "lowpass";
    lp.frequency.value = 220;
    lp.connect(musicGain);
    [0, 0.7].forEach((det) => {
      const o = ctx.createOscillator();
      o.type = "sawtooth";
      o.frequency.value = m.root + det;
      const g = ctx.createGain();
      g.gain.value = 0.5;
      o.connect(g);
      g.connect(lp);
      o.start();
      droneNodes.push(o, g);
    });
    droneNodes.push(lp);
    // sparse plucked motif, 1-3 notes from the mood scale
    const pluck = () => {
      if (mood !== id || !ctx) return;
      const notes = 1 + Math.floor(Math.random() * 3);
      for (let i = 0; i < notes; i++) {
        const semi = m.scale[Math.floor(Math.random() * m.scale.length)];
        const oct = 2 + Math.floor(Math.random() * 2); // 2-3 octaves up
        const f = m.root * Math.pow(2, oct + semi / 12);
        tone("triangle", f, 0.9, 0.1, f * 0.995, musicGain, i * 0.28);
      }
      motifTimer = setTimeout(
        pluck,
        m.pace[0] + Math.random() * (m.pace[1] - m.pace[0]),
      );
    };
    motifTimer = setTimeout(pluck, 1200);
  }
  DF.music = {
    play(id) {
      if (mood === id && droneNodes.length) return;
      startMood(id);
    },
    stop() {
      mood = null;
      stopMusic();
    },
    // engine hook: called by DF.go on every scene switch
    onScene(name) {
      if (name === "title" || name === "creator") this.play("title");
      else if (name === "worldmap") this.play("map");
      else if (name === "town") this.play("town");
      else if (name === "results" || name === "ending") this.play("map");
      // battle picks its own mood (boss-aware) in scene_battle enter()
    },
  };

  DF.audio = {
    get muted() {
      return muted;
    },
    toggleMute() {
      muted = !muted;
      savePrefs();
      if (ctx && master)
        master.gain.setTargetAtTime(muted ? 0 : 1, ctx.currentTime, 0.05);
      return muted;
    },
  };

  loadPrefs();
})();
