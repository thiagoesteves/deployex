defmodule DeployexWeb.ObserverLive do
  use DeployexWeb, :live_view

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(mermaid_links: Deployex.Observer.generate())

    ~H"""
    <div>
      <%!-- <script src="https://cdn.jsdelivr.net/npm/mermaid@11.4.0/dist/mermaid.min.js">
      </script> --%>

      <script type="module">
  import mermaid from './mermaid/mermaid';
  let config = { startOnLoad: true, flowchart: { useMaxWidth: false, htmlLabels: true } };
  mermaid.initialize(config);
</script>

      <div >
        <script>
          function testClick(nodeId) {
            console.log("clicked", nodeId)
            var originalBgColor = document.querySelector('body').style.backgroundColor
            document.querySelector('body').style.backgroundColor = 'yellow'
            setTimeout(function() {
              document.querySelector('body').style.backgroundColor = originalBgColor
            }, 500)
          }
        </script>

        <div class="mermaid" phx-hook="Mermaid" id="mermaid-container">
---
title: Node with text
---
flowchart LR
<%= @mermaid_links %>
       </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end
end
