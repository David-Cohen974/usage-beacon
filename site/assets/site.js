const RELEASES_URL = "https://github.com/David-Cohen974/usage-beacon/releases/latest";
const RELEASE_API = "https://api.github.com/repos/David-Cohen974/usage-beacon/releases/latest";
let releaseRequest = null;

async function loadLatestRelease() {
  if (releaseRequest) return releaseRequest;
  releaseRequest = (async () => {
    // Keep downloads on GitHub's moving latest URL until a fresh API response is verified.
    document.querySelectorAll(".download-link").forEach((link) => { link.href = RELEASES_URL; });
    document.querySelectorAll("[data-latest-version]").forEach((el) => { el.textContent = "Latest release"; });
    try {
      const response = await fetch(RELEASE_API, { cache: "no-store", signal: AbortSignal.timeout(8000) });
      if (!response.ok) throw new Error(`Release API returned ${response.status}`);
      const release = await response.json();
      if (release.draft || release.prerelease || !/^v?\d+\.\d+\.\d+$/.test(release.tag_name)) throw new Error("Invalid stable release");
      const asset = release.assets?.find((item) => /^UsageBeacon-.*\.dmg$/.test(item.name));
      const url = new URL(asset?.browser_download_url || RELEASES_URL);
      if (url.origin !== "https://github.com" || !url.pathname.startsWith("/David-Cohen974/usage-beacon/releases/")) throw new Error("Invalid download URL");
      document.querySelectorAll("[data-latest-version]").forEach((el) => { el.textContent = `Version ${release.tag_name.replace(/^v/, "")}`; });
      document.querySelectorAll(".download-link").forEach((link) => { link.href = url.href; });
    } catch (error) {
      // An old local JSON file must never pin visitors to an obsolete download.
      console.warn("Using GitHub latest-release fallback", error);
    }
  })();
  try { await releaseRequest; } finally { releaseRequest = null; }
}

function renderNotes(container, notes) {
  const lines = String(notes).split("\n");
  let list = null;
  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line) {
      list = null;
      continue;
    }
    if (line.startsWith("- ") || line.startsWith("* ")) {
      if (!list) {
        list = document.createElement("ul");
        container.append(list);
      }
      const item = document.createElement("li");
      item.textContent = line.slice(2);
      list.append(item);
      continue;
    }
    if (line.startsWith("## ") || line.startsWith("### ")) {
      const heading = document.createElement("h3");
      heading.textContent = line.replace(/^#{2,3}\s+/, "");
      container.append(heading);
      list = null;
      continue;
    }
    const paragraph = document.createElement("p");
    paragraph.textContent = line.replace(/^#\s+/, "");
    container.append(paragraph);
    list = null;
  }
}

async function loadChangelog() {
  const list = document.querySelector("#changelog-list");
  if (!list) return;

  try {
    const response = await fetch(new URL("../releases.json", document.baseURI), { cache: "no-cache" });
    if (!response.ok) throw new Error(`releases.json returned ${response.status}`);
    const releases = await response.json();
    if (!releases.length) return;

    list.replaceChildren();
    const dateFormatter = new Intl.DateTimeFormat(undefined, { dateStyle: "long" });
    releases.forEach((release) => {
      const article = document.createElement("article");
      const header = document.createElement("header");
      const title = document.createElement("h2");
      title.textContent = release.version;
      const meta = document.createElement("div");
      meta.className = "change-meta";
      const date = release.releaseDate ? dateFormatter.format(new Date(release.releaseDate)) : "Unpublished";
      meta.textContent = release.prerelease ? `${date} · Beta` : date;
      header.append(title, meta);

      const body = document.createElement("div");
      body.className = "change-notes";
      renderNotes(body, release.notes);

      if (release.url) {
        const source = document.createElement("a");
        source.href = release.url;
        source.textContent = "View release on GitHub →";
        source.className = "text-link";
        body.append(source);
      }

      article.append(header, body);
      list.append(article);
    });
  } catch (error) {
    const message = document.createElement("p");
    message.className = "empty-state";
    message.textContent = "The changelog could not be loaded right now. View releases on GitHub using the link below.";
    list.replaceChildren(message);
    console.warn("Could not load changelog", error);
  }
}

function initHomeDemo() {
  const demo = document.querySelector(".product-demo");
  if (!demo) return;
  const panel = demo.querySelector(".demo-panel");
  const hud = demo.querySelector(".hud-preview");
  const shortcut = demo.querySelector(".shortcut-control");
  const labels = {
    menu: ["Menu bar overview", "Click the menu bar icon for the full picture."],
    notification: ["Notification Center widget", "Add a widget to Notification Center or your desktop."],
    hud: ["Floating HUD", "Keep your budget above your work. Toggle it with ⇧⌘U."],
  };
  const toggleHud = () => {
    hud.hidden = !hud.hidden;
    shortcut.setAttribute("aria-pressed", String(!hud.hidden));
  };
  shortcut.addEventListener("click", toggleHud);
  document.querySelectorAll("[data-surface]").forEach((surface) => {
    surface.setAttribute("aria-controls", "surface-preview");
    surface.addEventListener("click", () => {
      document.querySelectorAll("[data-surface]").forEach((item) => {
        item.classList.toggle("is-active", item === surface);
        item.setAttribute("aria-pressed", String(item === surface));
      });
      demo.dispatchEvent(new Event("show-static-demo"));
      const mode = surface.dataset.surface;
      demo.dataset.activeSurface = mode;
      panel.hidden = mode === "hud";
      hud.hidden = mode !== "hud";
      shortcut.hidden = mode !== "hud";
      shortcut.setAttribute("aria-pressed", String(!hud.hidden));
      panel.setAttribute("aria-label", labels[mode][0]);
      demo.querySelector("[data-preview-title]").textContent = labels[mode][0];
      demo.querySelector("[data-preview-description]").textContent = labels[mode][1];
      demo.scrollIntoView({ behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth", block: "center" });
    });
  });
  document.addEventListener("keydown", (event) => {
    if (event.target instanceof HTMLElement && (event.target.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(event.target.tagName))) return;
    if (demo.dataset.activeSurface === "hud" && event.shiftKey && event.metaKey && event.key.toLowerCase() === "u") {
      event.preventDefault();
      toggleHud();
    }
  });
}

loadLatestRelease();
loadChangelog();
initHomeDemo();
// Refresh tabs left open across a release, including back/forward cache restores.
setInterval(() => { if (!document.hidden) loadLatestRelease(); }, 5 * 60 * 1000);
document.addEventListener("visibilitychange", () => { if (!document.hidden) loadLatestRelease(); });
window.addEventListener("pageshow", (event) => { if (event.persisted) loadLatestRelease(); });


function initDemoVideo() {
  const demo = document.querySelector(".product-demo");
  const video = demo?.querySelector(".demo-video");
  const fallback = demo?.querySelector(".demo-fallback");
  const source = video?.querySelector("source[data-src]");
  if (!video || !fallback || !source || matchMedia("(prefers-reduced-motion: reduce)").matches) return;

  let enabled = true;
  const restoreFallback = () => {
    demo.classList.remove("video-is-playing");
    fallback.inert = false;
    fallback.removeAttribute("aria-hidden");
    video.setAttribute("aria-hidden", "true");
    video.tabIndex = -1;
  };
  video.addEventListener("playing", () => {
    if (!enabled) return;
    demo.classList.add("video-is-playing");
    fallback.inert = true;
    fallback.setAttribute("aria-hidden", "true");
    video.removeAttribute("aria-hidden");
    video.tabIndex = 0;
  });
  video.addEventListener("canplay", () => {
    if (enabled) video.play().catch(restoreFallback);
  }, { once: true });
  video.addEventListener("error", restoreFallback);
  source.addEventListener("error", restoreFallback);
  demo.addEventListener("show-static-demo", () => {
    enabled = false;
    video.pause();
    restoreFallback();
  });
  video.muted = true;
  source.src = source.dataset.src;
  video.load();
}
initDemoVideo();
