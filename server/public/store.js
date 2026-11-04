// Dot-matrix meter for the recording panel, and the hero's hold, talk, let go loop.
(() => {
  const still = matchMedia("(prefers-reduced-motion: reduce)").matches;

  // Each .meter becomes columns of five dots, lit from the bottom.
  const meters = [...document.querySelectorAll(".meter")].map((el) => {
    const cols = Number(el.dataset.cols) || 16;
    const dots = [];
    for (let c = 0; c < cols; c++) {
      const col = [];
      for (let r = 0; r < 5; r++) col.push(document.createElement("i"));
      col.slice().reverse().forEach((d) => el.appendChild(d));
      dots.push(col);
    }
    return { el, cols, dots, levels: new Array(cols).fill(0) };
  });

  const level = (mode, x, t) => {
    if (mode === "talk") {
      const wave = Math.sin(x * 9 + t * 7) * 0.5 + Math.sin(x * 4 - t * 5) * 0.35;
      return Math.max(0.2, Math.min(1, 0.55 + wave * 0.45 * Math.sin(x * Math.PI)));
    }
    if (mode === "process") return (Math.sin(x * 10 - t * 9) + 1) / 2 > 0.82 ? 0.6 : 0.1;
    if (mode === "done") return 0.22 + 0.18 * Math.sin(x * Math.PI);
    return 0.1;
  };

  const paint = (m, mode, t) => {
    for (let c = 0; c < m.cols; c++) {
      const goal = level(mode, c / (m.cols - 1), t);
      m.levels[c] += (goal - m.levels[c]) * (still ? 1 : 0.35);
      const lit = Math.round(m.levels[c] * 5);
      m.dots[c].forEach((d, r) => {
        d.classList.toggle("on", r < lit);
        d.classList.toggle("hi", r >= 3 && r < lit);
      });
    }
  };

  const modeOf = (m) => m.el.closest(".hud")?.dataset.state ?? "idle";
  if (still) {
    meters.forEach((m) => paint(m, modeOf(m) === "idle" ? "talk" : modeOf(m), 0.6));
  } else {
    const tick = (now) => {
      meters.forEach((m) => paint(m, modeOf(m), now / 1000));
      requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  }

  // Buy buttons: a ring of dots around the pill. Hovering sends a waveform
  // around it, the dots stepping outward like the meter's columns.
  const GAP = 7; // ring distance from the button edge, to the dot centers
  const SPACING = 7;
  const ring = (button) => {
    const box = document.createElement("span");
    box.className = "ring";
    box.setAttribute("aria-hidden", "true");
    button.appendChild(box);
    button.classList.add("ringed");
    let dots = [];

    // Evenly spaced points on the pill, each with its outward direction.
    const layout = () => {
      const w = button.offsetWidth, h = button.offsetHeight, r = h / 2;
      const R = r + GAP, L = w - h, P = 2 * L + 2 * Math.PI * R;
      const count = Math.round(P / SPACING);
      box.replaceChildren();
      dots = [];
      for (let i = 0; i < count; i++) {
        const s = (i * P) / count;
        let x, y, nx, ny;
        if (s < L) { x = r + s; y = r - R; nx = 0; ny = -1; }
        else if (s < L + Math.PI * R) {
          const a = -Math.PI / 2 + (s - L) / R;
          nx = Math.cos(a); ny = Math.sin(a); x = w - r + R * nx; y = r + R * ny;
        } else if (s < 2 * L + Math.PI * R) { x = w - r - (s - L - Math.PI * R); y = r + R; nx = 0; ny = 1; }
        else {
          const a = Math.PI / 2 + (s - 2 * L - Math.PI * R) / R;
          nx = Math.cos(a); ny = Math.sin(a); x = r + R * nx; y = r + R * ny;
        }
        const el = document.createElement("i");
        box.appendChild(el);
        dots.push({ el, x, y, nx, ny, u: s / P });
      }
      draw(amp, 0);
    };

    const draw = (amp, t) => {
      for (const d of dots) {
        // Two waves travelling around the ring, folded into 0 to 3 steps.
        const wave = Math.max(0, Math.sin(d.u * Math.PI * 6 - t * 7)) * 0.65 +
          Math.abs(Math.sin(d.u * Math.PI * 14 + t * 11)) * 0.35;
        const step = Math.round(wave * amp * 3);
        const out = step * 2.5;
        d.el.style.transform = `translate(${d.x + d.nx * out}px, ${d.y + d.ny * out}px)`;
        d.el.classList.toggle("hi", step >= 2);
      }
    };

    // data-ring="live" keeps a small ripple going, for a page's one main action.
    const rest = button.dataset.ring === "live" && !still ? 0.35 : 0;
    let amp = rest, goal = rest, frame = 0;
    const tick = (now) => {
      amp += (goal - amp) * 0.12;
      if (goal === 0 && amp < 0.02) { amp = 0; draw(0, 0); frame = 0; return; }
      draw(amp, now / 1000);
      frame = requestAnimationFrame(tick);
    };
    const set = (on) => {
      if (still) return;
      goal = on ? 1 : rest;
      if (!frame) frame = requestAnimationFrame(tick);
    };
    if (rest) frame = requestAnimationFrame(tick);
    button.addEventListener("pointerenter", () => set(true));
    button.addEventListener("pointerleave", () => set(false));
    button.addEventListener("focus", () => set(true));
    button.addEventListener("blur", () => set(false));
    new ResizeObserver(layout).observe(button);
  };
  document.querySelectorAll(".button.primary").forEach(ring);

  // Hero: hold the key, talk, let go, the sentence is typed.
  const stage = document.querySelector("[data-demo]");
  if (!stage) return;
  const hud = stage.querySelector(".hud");
  const label = stage.querySelector(".hud-label");
  const key = stage.querySelector(".key-cmd");
  const typed = stage.querySelector(".typed");
  const sentence = typed.dataset.text;
  const steps = [
    ["idle", "Hold ⌘ to dictate", 1200],
    ["talk", "Listening", 2600],
    ["process", "Processing", 900],
    ["done", "Inserted", 2600],
  ];
  if (still) {
    hud.dataset.state = "done";
    label.textContent = "Inserted";
    typed.textContent = sentence;
    return;
  }
  let i = 0;
  const run = () => {
    const [state, text, ms] = steps[i];
    hud.dataset.state = state;
    label.textContent = text;
    key.classList.toggle("down", state === "talk");
    if (state === "idle") typed.textContent = "";
    if (state === "done") {
      let n = 0;
      const type = () => {
        n += 3;
        typed.textContent = sentence.slice(0, n);
        if (n < sentence.length) setTimeout(type, 18);
      };
      type();
    }
    i = (i + 1) % steps.length;
    setTimeout(run, ms);
  };
  run();
})();
