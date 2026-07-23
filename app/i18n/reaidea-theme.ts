export type Theme = "light" | "dark";

/** 与 reaidea.com 主站一致，子域共享 .reaidea.com Cookie */
export const THEME_COOKIE_KEY = "reaidea_theme";
export const THEME_STORAGE_KEY = "theme";

export const REAIDEA_THEME_BOOT_SCRIPT = `(() => {
  const THEME_COOKIE_KEY = 'reaidea_theme';
  const THEME_STORAGE_KEY = 'theme';
  const readCookie = (key) => {
    const cookie = '; ' + document.cookie;
    const parts = cookie.split('; ' + key + '=');
    if (parts.length !== 2) return null;
    return decodeURIComponent(parts.pop().split(';').shift());
  };
  try {
    const c = readCookie(THEME_COOKIE_KEY);
    const s = c || localStorage.getItem(THEME_STORAGE_KEY);
    const d =
      s === 'light' || s === 'dark'
        ? s
        : window.matchMedia('(prefers-color-scheme: dark)').matches
          ? 'dark'
          : 'light';
    document.documentElement.setAttribute('data-theme', d);
  } catch {
    document.documentElement.setAttribute('data-theme', 'light');
  }
})();`;

export function readThemeCookie(key: string): string | null {
  if (typeof document === "undefined") return null;
  const cookie = `; ${document.cookie}`;
  const parts = cookie.split(`; ${key}=`);
  if (parts.length !== 2) return null;
  return decodeURIComponent(parts.pop()!.split(";").shift()!);
}

export function themeCookieAttrs(): string {
  const attrs = ["path=/", "max-age=31536000", "SameSite=Lax"];
  if (typeof location !== "undefined") {
    const host = location.hostname;
    if (host === "reaidea.com" || host.endsWith(".reaidea.com")) {
      attrs.push("Domain=.reaidea.com");
    }
  }
  return attrs.join("; ");
}

export function resolveTheme(): Theme {
  if (typeof window === "undefined") return "light";
  try {
    const fromCookie = readThemeCookie(THEME_COOKIE_KEY);
    const stored = fromCookie || window.localStorage.getItem(THEME_STORAGE_KEY);
    if (stored === "light" || stored === "dark") return stored;
  } catch {
    /* ignore */
  }
  return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

export function saveTheme(theme: Theme) {
  document.cookie = `${THEME_COOKIE_KEY}=${encodeURIComponent(theme)}; ${themeCookieAttrs()}`;
  try {
    window.localStorage.setItem(THEME_STORAGE_KEY, theme);
  } catch {
    /* ignore */
  }
}

export function applyTheme(theme: Theme) {
  document.documentElement.setAttribute("data-theme", theme);
  const meta = document.querySelector('meta[name="theme-color"]');
  if (meta) meta.setAttribute("content", theme === "dark" ? "#121212" : "#f7f7f2");
}
