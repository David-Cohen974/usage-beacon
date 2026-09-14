// Firebase web configuration is public. No Analytics SDK is loaded on this website.
const firebaseConfig = {
  apiKey: "AIzaSyAl2WI3iWpv1RbANhP5xZGuDg90g6GH-tc",
  appId: "1:577080900099:web:af7b57e4941ff0ba83ec36",
  projectId: "usagebeacon-telemetry",
};
const SUPPORT_KEY = "website_show_buy_me_a_coffee";

function setSupportVisible(visible) {
  document.querySelectorAll("[data-support-link]").forEach((link) => { link.hidden = !visible; });
}

async function initRemoteConfig() {
  try {
    const [{ initializeApp }, remote] = await Promise.all([
      import("https://www.gstatic.com/firebasejs/12.19.0/firebase-app.js"),
      import("https://www.gstatic.com/firebasejs/12.19.0/firebase-remote-config.js"),
    ]);
    if (!(await remote.isSupported())) return;
    const config = remote.getRemoteConfig(initializeApp(firebaseConfig));
    config.defaultConfig = { [SUPPORT_KEY]: false };
    config.settings = { minimumFetchIntervalMillis: 60_000, fetchTimeoutMillis: 8_000 };
    const apply = () => setSupportVisible(remote.getBoolean(config, SUPPORT_KEY));
    const refresh = async () => {
      try {
        await remote.fetchAndActivate(config);
        apply();
      } catch (error) {
        setSupportVisible(true);
        console.warn("Support link kept visible: remote configuration unavailable", error);
      }
    };
    await refresh();
    remote.onConfigUpdate(config, {
      next: async () => {
        try { await remote.activate(config); apply(); }
        catch { setSupportVisible(true); }
      },
      error: (error) => console.warn("Remote Config live updates unavailable; periodic refresh remains active", error),
    });
    setInterval(() => { if (!document.hidden) refresh(); }, 60_000);
    document.addEventListener("visibilitychange", () => { if (!document.hidden) refresh(); });
  } catch (error) {
    setSupportVisible(true);
    console.warn("Support link kept visible: Firebase could not initialize", error);
  }
}

initRemoteConfig();
