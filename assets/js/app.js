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

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "../vendor/topbar"
import { Terminal } from "./xterm/xterm"
import * as echarts from "./echarts/echarts.min"

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

let hooks = {}
hooks.Terminal = {
  mounted() {
    let cols = this.el.dataset.cols ?? 100;
    let rows = this.el.dataset.rows ?? 24;

    let term = new Terminal({
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
};

hooks.ScrollBottom = {
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
};

hooks.EChart = {
  mounted() {
      var callback = (args) => {
        return args.data.info
      }

      selector = "#" + this.el.id
      this.chart = echarts.init(this.el.querySelector(selector + "-chart"))
      option = JSON.parse(this.el.querySelector(selector + "-data").textContent)
      // Set the callback in the tooltip formatter (or any other part of the option)
      option.tooltip = {
        formatter: callback  // Set the callback function here
      };

      this.chart.setOption(option)
  },
  updated() {
      selector = "#" + this.el.id
      option = JSON.parse(this.el.querySelector(selector + "-data").textContent)
      this.chart.setOption(option)
  }
}

let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks
})

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

