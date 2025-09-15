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
          navigator.clipboard.readText()
            .then(text => {
              this.pushEventTo(this.el, "key", { key: text });
            })
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

  // Theme management is handled in root.html.heex
  // This hook can be used for theme-aware components if needed
  ThemeAware: {
    mounted() {
      this.updateTheme();

      // Listen for theme changes
      window.addEventListener('phx:set-theme', () => {
        setTimeout(() => this.updateTheme(), 10);
      });
    },

    updateTheme() {
      const theme = document.documentElement.getAttribute('data-theme');
      this.el.setAttribute('data-current-theme', theme);
    }
  }
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
