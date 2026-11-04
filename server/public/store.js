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
