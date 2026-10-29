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
  Terminal: {
    mounted() {
      const cols = this.el.dataset.cols ?? 100;
      const rows = this.el.dataset.rows ?? 24;

      const term = new Terminal({
        fontSize: 14,
        cols: cols,
        rows: rows,
        cursorBlink: true,
        fontFamily: 'Monospace'
      });
      term.open(this.el.querySelector(".xtermjs_container"));
      term.onKey(key => {
        this.pushEventTo(this.el, "key", key);
      });

      term.attachCustomKeyEventHandler(event => {
        // From: https://stackoverflow.com/questions/2903991/how-to-detect-ctrlv-ctrlc-using-javascript
        // Ctrl+V or Cmd+V pressed?
        if ((event.ctrlKey || event.metaKey) && event.keyCode == 86) {
          // xterm calls this handler for keyup too, so paste only once, on keydown
          if (event.type === "keydown") {
            navigator.clipboard.readText()
              .then(text => {
                this.pushEventTo(this.el, "key", { key: text });
              })
          }
          return false;
        }
        return true;
      });

      this.handleEvent("print-" + this.el.id, e => {
        term.write(e.data);
      });
    }
  },

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
          "theme-system": html.dataset.themePref === "system",
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
        if (e.target.closest("[data-bell-mark-read]")) this.markRead();
      });
      this.sync();
    },

    updated() {
      this.sync();
    },

    lastRead() {
      try {
        return Number(localStorage.getItem("dx:bell-read")) || 0;
      } catch (_e) {
        return 0;
      }
    },

    markRead() {
      const ids = [...this.el.querySelectorAll("[data-bell-item]")].map((el) => Number(el.dataset.bellItem));
      try {
        if (ids.length) localStorage.setItem("dx:bell-read", String(Math.max(...ids)));
      } catch (_e) {}
      this.sync();
    },

    sync() {
      const last = this.lastRead();
      let unread = 0;
      this.el.querySelectorAll("[data-bell-item]").forEach((el) => {
        const isNew = Number(el.dataset.bellItem) > last;
        if (isNew) unread++;
        el.querySelector("[data-bell-title]").style.fontWeight = isNew ? "700" : "500";
      });
      const badge = this.el.querySelector("[data-bell-badge]");
      badge.textContent = unread;
      badge.classList.toggle("hidden", unread === 0);
      this.el.querySelector("[data-bell-mark-read]").classList.toggle("hidden", unread === 0);
      this.el.querySelector("button[aria-controls]")
        .setAttribute("aria-label", unread ? `Notifications, ${unread} unread` : "Notifications");
      this.el.querySelectorAll("time[datetime]").forEach((t) => {
        const at = new Date(t.getAttribute("datetime"));
        t.textContent = at.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", hour12: false });
      });
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
