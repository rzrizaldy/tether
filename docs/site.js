// Tether's landing page: a deck you scroll, one idea per screen.
// The hero replays what the app does: cable in, iPad lights up, lid closes.
(() => {
  // ?still freezes every animation in its end state (used for README screenshots).
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches || /[?&]still\b/.test(location.search);
  if (/[?&]still\b/.test(location.search)) document.documentElement.classList.add("still");

  // ───────────────────────── Deck ─────────────────────────
  const deck = document.getElementById("deck");
  const slides = [...deck.querySelectorAll(".slide")];
  const rail = document.getElementById("rail");
  const next = document.getElementById("next");
  const navLinks = [...document.querySelectorAll(".nav nav a")];
  const scenes = new Map();
  let current = -1;

  const dots = slides.map((slide, i) => {
    const b = rail.appendChild(document.createElement("button"));
    b.setAttribute("aria-label", `${i + 1}. ${slide.dataset.title}`);
    b.title = slide.dataset.title;
    b.addEventListener("click", () => go(i));
    return b;
  });

  function go(i) {
    const target = slides[Math.max(0, Math.min(slides.length - 1, i))];
    deck.scrollTo({ top: target.offsetTop, behavior: reduce ? "auto" : "smooth" });
  }

  function activate(i) {
    if (i === current) return;
    if (current >= 0) { slides[current].classList.remove("active"); scenes.get(slides[current])?.leave(); }
    current = i;
    const slide = slides[i];
    slide.classList.add("active");
    dots.forEach((d, k) => d.classList.toggle("on", k === i));
    next.classList.toggle("end", i === slides.length - 1);
    next.setAttribute("aria-label", i === slides.length - 1 ? "Back to the top" : "Next slide");
    navLinks.forEach((a) => a.classList.toggle("on", a.getAttribute("href") === `#${slide.id}`));
    if (location.hash !== `#${slide.id}`) history.replaceState(null, "", location.pathname + location.search + (i === 0 ? "" : `#${slide.id}`));
    scenes.get(slide)?.enter();
  }

  const watcher = new IntersectionObserver((entries) => {
    for (const e of entries) {
      const screen = e.rootBounds?.height || innerHeight;
      if (e.isIntersecting && e.intersectionRect.height >= screen * 0.5) activate(slides.indexOf(e.target));
    }
  }, { root: deck, threshold: Array.from({ length: 21 }, (_, i) => i / 20) });
  slides.forEach((s) => watcher.observe(s));

  next.addEventListener("click", () => go(current === slides.length - 1 ? 0 : current + 1));
  document.querySelectorAll('a[href^="#"]').forEach((a) => a.addEventListener("click", (e) => {
    const i = slides.findIndex((s) => `#${s.id}` === a.getAttribute("href"));
    if (i >= 0) { e.preventDefault(); go(i); }
  }));
  addEventListener("keydown", (e) => {
    if (e.metaKey || e.ctrlKey || e.altKey || /INPUT|TEXTAREA|BUTTON/.test(document.activeElement?.tagName)) return;
    if (["ArrowDown", "PageDown", " "].includes(e.key)) { e.preventDefault(); go(current + 1); }
    if (["ArrowUp", "PageUp"].includes(e.key)) { e.preventDefault(); go(current - 1); }
    if (e.key === "Home") go(0);
    if (e.key === "End") go(slides.length - 1);
  });

  // ───────────────────────── Hero: plug, light, close ─────────────────────────
  const demo = document.getElementById("demo");
  const status = document.getElementById("status");
  const say = (text) => {
    if (status.textContent === text) return;
    status.textContent = text;
    status.classList.remove("swap"); void status.offsetWidth; status.classList.add("swap");
  };
  const STEPS = [
    [0, "", "The Mac's screen is broken"],
    [1400, "plug", "Plug in the cable"],
    [2500, "plug on", "Tether turns on Sidecar"],
    [4600, "plug on shut", "Close the lid. Still awake."],
    [8200, "", "Unplugged. The Mac sleeps."],
  ];
  const LOOP = 10200;

  // The cable runs from the Mac's port, under the desk, up into the iPad.
  const desk = demo.querySelector(".desk");
  const cable = document.getElementById("cable");
  const ledDot = document.getElementById("ledDot");
  function layoutCable() {
    const d = desk.getBoundingClientRect(), port = demo.querySelector(".port").getBoundingClientRect(), pad = demo.querySelector(".pad").getBoundingClientRect();
    if (!d.width) return;
    const px = port.left + port.width / 2 - d.left, py = port.bottom - d.top - 1;
    const qx = pad.left + pad.width * 0.5 - d.left, qy = pad.bottom - d.top - 2;
    const dip = Math.max(26, d.height * 0.16);
    cable.setAttribute("viewBox", `0 0 ${d.width} ${d.height}`);
    cable.firstElementChild.setAttribute("d", `M${px} ${py} C${px + 6} ${py + dip}, ${qx} ${qy + dip}, ${qx} ${qy}`);
    ledDot.style.transform = "";
    ledDot.style.left = `${qx}px`; ledDot.style.top = `${qy + 1}px`;
  }
  layoutCable();
  addEventListener("resize", layoutCable);
  new ResizeObserver(layoutCable).observe(desk);
  let timers = [];
  const stop = () => { timers.forEach(clearTimeout); timers = []; };
  function play() {
    stop();
    for (const [at, cls, text] of STEPS) timers.push(setTimeout(() => { if (!cls) layoutCable(); demo.className = `demo r ${cls}`; say(text); }, at));
    timers.push(setTimeout(play, LOOP));
  }
  scenes.set(slides[0], {
    enter() {
      if (reduce) { demo.className = "demo r plug on"; say("iPad is your screen"); return; }
      play();
    },
    leave: stop,
  });

  // ───────────────────────── The menu: tick and untick ─────────────────────────
  document.querySelectorAll('.menu [role="menuitemcheckbox"]').forEach((b) => b.addEventListener("click", () => {
    const on = b.getAttribute("aria-checked") !== "true";
    b.setAttribute("aria-checked", String(on));
  }));

  // ───────────────────────── Copy ─────────────────────────
  document.querySelectorAll(".copy").forEach((b) => b.addEventListener("click", async () => {
    try { await navigator.clipboard.writeText(b.dataset.copy); b.textContent = "Copied"; }
    catch { b.textContent = "Select and copy"; }
    setTimeout(() => (b.textContent = "Copy"), 1600);
  }));

  // ───────────────────────── Theme ─────────────────────────
  const themeColors = { light: "#e7eef1", dark: "#0d1317", colorful: "#e8e3f4" };
  const themeButtons = [...document.querySelectorAll(".themes button")];
  function setTheme(theme, save) {
    document.documentElement.dataset.theme = theme;
    themeButtons.forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.theme === theme)));
    document.querySelector('meta[name="theme-color"]')?.setAttribute("content", themeColors[theme]);
    if (save) try { localStorage.setItem("tether-theme", theme); } catch {}
  }
  themeButtons.forEach((b) => b.addEventListener("click", () => setTheme(b.dataset.theme, true)));
  setTheme(document.documentElement.dataset.theme || "light", false);

  // ───────────────────────── The logo hops when you touch it ─────────────────────────
  if (!reduce) {
    const logos = [...document.querySelectorAll(".logo")];
    const hop = (logo) => { logo.classList.remove("hop"); void logo.offsetWidth; logo.classList.add("hop"); };
    logos.forEach((logo) => logo.addEventListener("pointerenter", () => hop(logo)));
    setTimeout(() => logos.forEach(hop), 600);
  }
})();
