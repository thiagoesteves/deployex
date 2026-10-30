// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "../vendor/topbar"

import { Terminal } from "./xterm/xterm"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const hooks = {
  ScrollBottom: {
    mounted() {
      this.el.scrollTo(0, this.el.scrollHeight);
    },

    updated() {
      const pixelsBelowBottom =
        this.el.scrollHeight - this.el.clientHeight - this.el.scrollTop;

      if (pixelsBelowBottom < this.el.clientHeight * 0.3) {
        this.el.scrollTo(0, this.el.scrollHeight);
      }
    },
  },

  // Mirrors the theme and sidebar state, which root.html.heex keeps on <html>, into the aria
  // state of a shell control. data-state names the state, data-state-attr the attribute to set.
  ShellState: {
    mounted() {
      this.sync = () => {
        const html = document.documentElement;
        const states = {
          "theme-dark": html.dataset.theme === "dark",
          "sidebar-expanded": html.dataset.sidebar !== "collapsed",
        };
        this.el.setAttribute(this.el.dataset.stateAttr, String(states[this.el.dataset.state]));
      };
      this.sync();
      window.addEventListener("dx:shell-state", this.sync);
    },

    updated() {
      this.sync();
    },

    destroyed() {
      window.removeEventListener("dx:shell-state", this.sync);
    }
  },

  // Runs the data-escape command of a UI.Menu when Escape is pressed inside it. A phx-keydown
  // binding fires only on the focused element itself, not on its parents.
  Menu: {
    mounted() {
      this.el.addEventListener("keydown", (e) => {
        if (e.key === "Escape") this.liveSocket.execJS(this.el, this.el.dataset.escape);
      });
    }
  },

  // The bell's read state is per browser: the newest read item id stays in localStorage. Sets the
  // badge, bolds the unread items, and shows each time in the browser's time zone.
  Bell: {
    mounted() {
      this.el.addEventListener("click", (e) => {
        if (e.target.closest("[data-bell-clear]")) this.clear();
      });
      this.sync();
    },

    updated() {
      this.sync();
    },

    cleared() {
      try {
        return Number(localStorage.getItem("dx:bell-read")) || 0;
      } catch (_e) {
        return 0;
      }
    },

    // Hides every item there now. A newer event shows, and the footer link keeps them all
    clear() {
      const ids = [...this.el.querySelectorAll("[data-bell-item]")].map((el) => Number(el.dataset.bellItem));
      try {
        if (ids.length) localStorage.setItem("dx:bell-read", String(Math.max(...ids)));
      } catch (_e) {}
      this.sync();
    },

    sync() {
      const cleared = this.cleared();
      let shown = 0;
      this.el.querySelectorAll("[data-bell-item]").forEach((el) => {
        el.hidden = Number(el.dataset.bellItem) <= cleared;
        if (!el.hidden) shown++;
      });
      const badge = this.el.querySelector("[data-bell-badge]");
      badge.textContent = shown;
      badge.classList.toggle("hidden", shown === 0);
      this.el.querySelector("[data-bell-clear]").classList.toggle("hidden", shown === 0);
      this.el.querySelector("[data-bell-empty]").classList.toggle("hidden", shown > 0);
      this.el.querySelector("button[aria-controls]")
        .setAttribute("aria-label", shown ? `Notifications, ${shown} new` : "Notifications");
    }
  },

  // The search combobox: the arrow keys move through the results, Enter opens one, Escape clears the
  // field, then leaves it
  Search: {
    mounted() {
      this.input = this.el.querySelector("input[role=combobox]");
      this.active = -1;
      this.input.addEventListener("keydown", (e) => this.onKey(e));
      this.input.addEventListener("focus", () => this.input.setAttribute("aria-expanded", "true"));
      this.input.addEventListener("blur", () => this.input.setAttribute("aria-expanded", "false"));
      // Keep the focus in the field when a result is pressed, so the list stays open until the click
      this.el.querySelector("[role=listbox]").addEventListener("mousedown", (e) => e.preventDefault());
    },

    updated() {
      this.active = -1;
      this.highlight();
      // A picked result clears the search, and the focused field keeps its text unless told
      if (this.el.dataset.query === "") this.input.value = "";
    },

    options() {
      return [...this.el.querySelectorAll("[role=option]")];
    },

    highlight() {
      this.options().forEach((el, i) => el.setAttribute("aria-selected", String(i === this.active)));
      const current = this.options()[this.active];
      if (current) {
        this.input.setAttribute("aria-activedescendant", current.id);
        current.scrollIntoView({ block: "nearest" });
      } else {
        this.input.removeAttribute("aria-activedescendant");
      }
    },

    onKey(e) {
      const options = this.options();
      if (e.key === "ArrowDown" || e.key === "ArrowUp") {
        if (!options.length) return;
        e.preventDefault();
        const step = e.key === "ArrowDown" ? 1 : -1;
        this.active = (this.active + step + options.length) % options.length;
        this.highlight();
      } else if (e.key === "Backspace" && this.input.value === "") {
        const tags = this.el.querySelectorAll("[data-tag-remove]");
        if (tags.length) {
          e.preventDefault();
          tags[tags.length - 1].click();
        }
      } else if (e.key === "Enter") {
        e.preventDefault();
        const choice = options[this.active] || options[0];
        if (choice) choice.click();
      } else if (e.key === "Escape") {
        e.preventDefault();
        if (this.input.value) {
          this.input.value = "";
          this.input.dispatchEvent(new Event("input", { bubbles: true }));
        } else {
          this.input.blur();
        }
      }
    }
  },

  // A shell session in xterm.js, sized to its panel. Keys and the size go to the LiveView, the output
  // comes back as shell-output events for this target, and shell-reset replays what the session printed.
  // Pushed events reach every hook on the page, so the dock and the Terminal page each use their scope
  XTerm: {
    mounted() {
      const target = this.el.dataset.target;
      const scope = this.el.dataset.scope;
      this.term = new Terminal({
        // 13 px at the browser's default font size, larger when the user sets a larger one
        fontSize: Math.round(13 * parseFloat(getComputedStyle(document.documentElement).fontSize) / 16),
        cursorBlink: true,
        fontFamily: "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace",
        theme: { background: "#0d1117", foreground: "#c9d1d9", cursor: "#7ee787", selectionBackground: "#264f78" }
      });
      this.term.open(this.el);
      this.term.onData((keys) => this.pushEventTo(this.el, "shell-keys", { target, keys }));
      this.handleEvent(`shell-output-${scope}-${target}`, ({ data }) => this.term.write(data));
      this.handleEvent(`shell-reset-${scope}-${target}`, ({ data }) => {
        this.term.reset();
        this.term.write(data);
      });
      this.fit = () => {
        // A hidden terminal, like one in a collapsed dock, keeps its size, so the shell does not rewrap to it
        if (!this.el.clientWidth || !this.el.clientHeight) return;
        const cell = this.term._core._renderService.dimensions.css.cell;
        if (!cell.width || !cell.height) return;
        const cols = Math.max(20, Math.floor(this.el.clientWidth / cell.width));
        const rows = Math.max(5, Math.floor(this.el.clientHeight / cell.height));
        if (cols !== this.term.cols || rows !== this.term.rows) {
          this.term.resize(cols, rows);
          this.pushEventTo(this.el, "shell-resize", { target, rows, cols });
        }
      };
      this.observer = new ResizeObserver(() => this.fit());
      this.observer.observe(this.el);
      requestAnimationFrame(() => {
        this.fit();
        if (this.el.dataset.focus !== undefined) this.term.focus();
      });
    },

    destroyed() {
      this.observer && this.observer.disconnect();
      this.term && this.term.dispose();
    }
  },

  // A click on an app row opens or closes the app, like its chevron, unless it selects text or hits a
  // control in the row. The chevron stays the keyboard control
  RowToggle: {
    mounted() {
      this.el.addEventListener("click", (e) => {
        if (e.target.closest("button, a, [role=button]") || String(window.getSelection())) return;
        this.pushEvent("toggle-app", { name: this.el.dataset.name });
      });
    }
  },

  // The time left of a session, from data-expires (an ISO 8601 time)
  Countdown: {
    mounted() {
      this.tick = () => {
        const left = Math.max(0, Math.floor((new Date(this.el.dataset.expires) - new Date()) / 1000));
        this.el.textContent = `${Math.floor(left / 60)}:${String(left % 60).padStart(2, "0")}`;
      };
      this.tick();
      this.timer = setInterval(this.tick, 1000);
    },

    updated() {
      this.tick();
    },

    destroyed() {
      clearInterval(this.timer);
    }
  },

  // A tooltip in the top layer (its [popover] child), so no scroll box clips it. It shows on hover and on
  // keyboard focus, stays while the pointer is on it, and Escape or a scroll hides it
  Tip: {
    mounted() {
      this.show = () => {
        this.open = true;
        this.place();
        document.addEventListener("keydown", this.onKey);
        window.addEventListener("scroll", this.hide, { capture: true, passive: true });
      };
      this.hide = () => {
        this.open = false;
        const tip = this.tip();
        if (tip && tip.matches(":popover-open")) tip.hidePopover();
        document.removeEventListener("keydown", this.onKey);
        window.removeEventListener("scroll", this.hide, { capture: true });
      };
      this.onKey = (e) => e.key === "Escape" && this.hide();
      this.el.addEventListener("pointerenter", this.show);
      this.el.addEventListener("pointerleave", this.hide);
      this.el.addEventListener("focusin", (e) => e.target.matches(":focus-visible") && this.show());
      this.el.addEventListener("focusout", this.hide);
    },

    updated() {
      if (this.open) this.place();
    },

    destroyed() {
      this.hide();
    },

    tip() {
      return this.el.querySelector("[popover]");
    },

    // Below the trigger, or above it when the window has no room, and inside the window
    place() {
      const tip = this.tip();
      if (!tip) return;
      if (!tip.matches(":popover-open")) tip.showPopover();
      const r = this.el.getBoundingClientRect();
      const t = tip.getBoundingClientRect();
      const below = r.bottom + 8 + t.height <= window.innerHeight;
      tip.dataset.side = below ? "below" : "above";
      tip.style.top = `${below ? r.bottom + 8 : r.top - 8 - t.height}px`;
      tip.style.left = `${Math.max(8, Math.min(r.left + r.width / 2 - t.width / 2, window.innerWidth - t.width - 8))}px`;
    }
  },

  // The dock: passes the dx:dock-open window events to the dock LiveView, and keeps its height (resize by
  // the grip, the arrow keys, or Taller and Shorter), minimized and full size in localStorage while it is open
  Dock: {
    mounted() {
      this.min = 160;
      this.step = 40;
      this.onOpen = (e) => this.pushEventTo(this.el, "open", e.detail);
      window.addEventListener("dx:dock-open", this.onOpen);
      this.el.addEventListener("click", (e) => {
        const action = e.target.closest("[data-dock]");
        if (action) this.act(action.dataset.dock);
      });
      this.el.addEventListener("keydown", (e) => {
        if (!e.target.closest("[data-dock-grip]")) return;
        if (e.key === "ArrowUp") { e.preventDefault(); this.act("taller"); }
        if (e.key === "ArrowDown") { e.preventDefault(); this.act("shorter"); }
      });
      this.el.addEventListener("mousedown", (e) => {
        if (!e.target.closest("[data-dock-grip]")) return;
        e.preventDefault();
        const startY = e.clientY;
        const startHeight = this.panel() ? this.panel().getBoundingClientRect().height : this.height();
        // Near the top bar the dock snaps to full size, like Expand. Restore then gives back the height it
        // had before the drag
        const bar = document.getElementById("shell-top-bar");
        const snapAt = (bar ? bar.getBoundingClientRect().bottom : 56) + 40;
        const before = this.load().state === "max" ? this.height() : this.clamp(startHeight);
        const move = (ev) =>
          ev.clientY <= snapAt
            ? this.save({ height: before, state: "max" })
            : this.save({ height: this.clamp(startHeight + startY - ev.clientY), state: "normal" });
        const up = () => {
          window.removeEventListener("mousemove", move);
          window.removeEventListener("mouseup", up);
        };
        window.addEventListener("mousemove", move);
        window.addEventListener("mouseup", up);
      });
      this.apply();
    },

    updated() {
      this.apply();
    },

    destroyed() {
      window.removeEventListener("dx:dock-open", this.onOpen);
      document.documentElement.style.removeProperty("--dx-dock-space");
    },

    panel() {
      return this.el.querySelector("[data-dock-panel]");
    },

    load() {
      try {
        return JSON.parse(localStorage.getItem("dx:dock")) || {};
      } catch (_e) {
        return {};
      }
    },

    save(patch) {
      try {
        localStorage.setItem("dx:dock", JSON.stringify(Object.assign(this.load(), patch)));
      } catch (_e) {}
      this.apply();
    },

    height() {
      return this.clamp(this.load().height || 320);
    },

    // Full size reaches up to just below the top bar, so the grip stays clear of it
    fullTop() {
      const bar = document.getElementById("shell-top-bar");
      return (bar ? bar.getBoundingClientRect().bottom : 56) + 8;
    },

    clamp(height) {
      return Math.max(this.min, Math.min(window.innerHeight - 120, height));
    },

    act(action) {
      const state = this.load().state || "normal";
      if (action === "taller") this.save({ height: this.clamp(this.height() + this.step), state: "normal" });
      if (action === "shorter") this.save({ height: this.clamp(this.height() - this.step), state: "normal" });
      if (action === "minimize") this.save({ state: state === "min" ? "normal" : "min" });
      if (action === "maximize") this.save({ state: state === "max" ? "normal" : "max" });
    },

    apply() {
      const panel = this.panel();
      const root = document.documentElement;
      // A closed dock forgets its size, so the next one opens at the default height
      if (!panel) {
        root.style.removeProperty("--dx-dock-space");
        try {
          localStorage.removeItem("dx:dock");
        } catch (_e) {}
        return;
      }
      const state = this.load().state || "normal";
      const height = state === "min" ? 42 : state === "max" ? window.innerHeight - this.fullTop() : this.height();
      panel.style.height = `${height}px`;
      panel.classList.toggle("dx-dock-min", state === "min");
      panel.dataset.state = state;
      this.el.querySelectorAll("[data-dock=minimize]").forEach((b) => {
        b.setAttribute("aria-label", state === "min" ? "Restore the dock" : "Minimize the dock");
        b.querySelector("svg").style.transform = state === "min" ? "rotate(180deg)" : "none";
      });
      this.el.querySelectorAll("[data-dock=maximize]").forEach((b) => {
        b.setAttribute("aria-pressed", String(state === "max"));
        b.setAttribute("aria-label", state === "max" ? "Restore the dock size" : "Expand the dock");
      });
      root.style.setProperty("--dx-dock-space", `${state === "min" ? 56 : height + 24}px`);
    }
  },

  // Clear Flash message automatically after 3,5 seconds
  AutoDismissFlash: {
    mounted() {
      setTimeout(() => {
        this.el.style.transition = "opacity 0.5s";
        this.el.style.opacity = "0";
        setTimeout(() => this.el.remove(), 500);
      }, 3500);
    },
  },
};

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks
})

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

window.addEventListener("phx:copy_to_clipboard", event => {
  if ("clipboard" in navigator) {
    const text = event.detail.text;
    navigator.clipboard.writeText(text);
  } else {
    alert("Sorry, your browser does not support clipboard copy.");
  }

  const defaultMessage = document.getElementById("c2c-default-message-" + event.detail.id);
  if (defaultMessage) {
    defaultMessage.setAttribute("hidden", "");
  }

  const successMessage = document.getElementById("c2c-success-message-" + event.detail.id);
  if (successMessage) {
    successMessage.removeAttribute("hidden");
  }

  setTimeout(() => {
    const successMessage = document.getElementById("c2c-success-message-" + event.detail.id);
    if (successMessage) {
      successMessage.setAttribute("hidden", "");
    }

    const defaultMessage = document.getElementById("c2c-default-message-" + event.detail.id);
    if (defaultMessage) {
      defaultMessage.removeAttribute("hidden");
    }
  }, 1000);
});

// Puts text on the clipboard. The clipboard API needs a secure page, so a plain HTTP host falls back to a
// hidden text area
const copyText = (text) => {
  const fallback = () => {
    const area = document.createElement("textarea");
    area.value = text;
    area.setAttribute("readonly", "");
    area.style.cssText = "position: fixed; opacity: 0";
    document.body.appendChild(area);
    area.select();
    document.execCommand("copy");
    area.remove();
  };
  return navigator.clipboard ? navigator.clipboard.writeText(text).catch(fallback) : Promise.resolve(fallback());
};

// Says a short message to screen readers, from a live region outside the LiveViews
const announce = (message) => {
  let live = document.getElementById("dx-announce");
  if (!live) {
    live = document.createElement("div");
    live.id = "dx-announce";
    live.className = "sr-only";
    live.setAttribute("aria-live", "polite");
    document.body.appendChild(live);
  }
  live.textContent = message;
};

// Copies the data-copy text of the clicked button. Its tooltip says Copied for a moment
window.addEventListener("dx:copy", (e) => {
  const button = e.target;
  copyText(button.dataset.copy).then(() => {
    const wrap = button.closest("[phx-hook=Tip]");
    const tip = wrap && wrap.querySelector("[popover]");
    if (tip) tip.textContent = "Copied";
    announce("Copied");
    setTimeout(() => {
      if (tip) tip.textContent = tip.dataset.text;
    }, 1500);
  });
});

// Copies the log rows shown in detail.from, one row a line, and the button says how many it copied. The
// label sits in a phx-update="ignore" element, so a page update does not reset it early
window.addEventListener("dx:copy-lines", (e) => {
  const button = e.target;
  const rows = [...document.querySelectorAll(`${e.detail.from} > *`)];
  const text = rows
    .map((row) => [...row.children].map((cell) => cell.textContent.trim()).filter(Boolean).join(" "))
    .join("\n");
  copyText(text).then(() => {
    const label = button.querySelector("[data-label]") || button;
    const done = rows.length === 1 ? "Copied 1 line" : `Copied ${rows.length} lines`;
    label.textContent = done;
    announce(done);
    clearTimeout(button.copyTimer);
    button.copyTimer = setTimeout(() => (label.textContent = label.dataset.label), 2000);
  });
});

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({ detail: reloader }) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", () => keyDown = null)
    window.addEventListener("click", e => {
      if (keyDown === "c") {
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if (keyDown === "d") {
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
