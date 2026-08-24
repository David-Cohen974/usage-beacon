async function loadLatestRelease() {
  try {
    const metadataPath = document.body.dataset.page === "home" ? "latest.json" : "../latest.json";
    const metadataURL = new URL(metadataPath, document.baseURI);
    const response = await fetch(metadataURL, { cache: "no-cache" });
    if (!response.ok) throw new Error(`latest.json returned ${response.status}`);
    const latest = await response.json();

    if (latest.version) {
      document.querySelectorAll("[data-latest-version]").forEach((element) => {
        element.textContent = `Version ${latest.version}`;
      });
    }
    if (latest.minimumMacOS) {
      document.querySelectorAll("[data-minimum-macos]").forEach((element) => {
        element.textContent = `macOS ${latest.minimumMacOS.replace(/\.0$/, "")}+`;
      });
    }
    if (latest.downloadUrl) {
      document.querySelectorAll(".download-link").forEach((link) => {
        link.href = latest.downloadUrl;
      });
    }
  } catch (error) {
    console.warn("Could not load latest release metadata", error);
  }
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
    list.querySelector(".empty-state").textContent = "The changelog could not be loaded right now.";
    console.warn("Could not load changelog", error);
  }
}

function initHomeDemo() {
  const demo = document.querySelector(".product-demo");
  if (!demo) return;

  const shortcut = demo.querySelector(".shortcut-control");
  const surfaces = [...document.querySelectorAll("[data-surface]")];
  const animatedLayers = [
    demo.querySelector(".notification-center"),
    demo.querySelector(".menu-popover"),
    demo.querySelector(".extracted-widget"),
    demo.querySelector(".hud-preview"),
  ].filter(Boolean);

  function setHudVisible(visible) {
    demo.dataset.demoState = visible ? "open" : "closed";
    shortcut?.setAttribute("aria-pressed", String(visible));
  }

  function toggleHud() {
    setHudVisible(demo.dataset.demoState !== "open");
  }

  function replayLayerMotion() {
    animatedLayers.forEach((layer) => {
      layer.getAnimations().forEach((animation) => {
        animation.cancel();
        animation.play();
      });
    });
  }

  shortcut?.addEventListener("click", toggleHud);

  document.addEventListener("keydown", (event) => {
    const target = event.target;
    const isEditable = target instanceof HTMLElement && (target.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName));
    if (isEditable) return;
    if (event.shiftKey && event.metaKey && event.key.toLowerCase() === "u") {
      event.preventDefault();
      toggleHud();
    }
  });

  surfaces.forEach((surface) => {
    surface.addEventListener("click", () => {
      surfaces.forEach((item) => {
        const active = item === surface;
        item.classList.toggle("is-active", active);
        item.setAttribute("aria-pressed", String(active));
      });
      demo.dataset.activeSurface = surface.dataset.surface;
      if (surface.dataset.surface === "hud") setHudVisible(true);
      replayLayerMotion();
      demo.scrollIntoView({ behavior: "smooth", block: "center" });
    });
  });
}

loadLatestRelease();
loadChangelog();
initHomeDemo();
