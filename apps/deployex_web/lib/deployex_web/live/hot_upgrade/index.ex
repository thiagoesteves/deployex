defmodule DeployexWeb.HotUpgradeLive do
  use DeployexWeb, :live_view

  alias Deployer.HotUpgrade
  alias DeployexWeb.Cache.UiSettings
  alias DeployexWeb.Components.Confirm
  alias DeployexWeb.Components.Progress
  alias DeployexWeb.Components.SystemBar
  alias DeployexWeb.Helper
  alias DeployexWeb.HotUpgrade.Data

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} ui_settings={@ui_settings} current_path={@current_path}>
      <div class="min-h-screen bg-base-300">
        <SystemBar.content info={@host_info} />
        <!-- Main Content -->
        <div class="p-5">
          <!-- Breadcrumb -->
          <div class="breadcrumbs text-sm mb-6">
            <ul>
              <li><a href="/applications" class="text-base-content/60">Applications</a></li>
              <li class="text-base-content font-medium">Hot Upgrade</li>
            </ul>
          </div>
          <!-- Page Header -->
          <div class="mb-8">
            <h1 class="text-3xl font-bold text-base-content mb-2">Hot Upgrade Manager</h1>
            <p class="text-base-content/60">Upload and apply hot upgrades without downtime</p>
          </div>
          <!-- Upload Section -->
          <div class="card bg-base-100 shadow-sm mb-6">
            <div class="card-body">
              <h2 class="card-title text-xl mb-4">
                <svg
                  class="w-6 h-6 text-primary"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12"
                  >
                  </path>
                </svg>
                Upload Hot Upgrade Release
              </h2>

              <form id="upload-form" phx-submit="validate-upload" phx-change="validate-upload">
                <div
                  class="border-2 border-dashed border-base-300 rounded-lg p-8 hover:border-primary/50 transition-colors duration-200"
                  phx-drop-target={@uploads.hotupgrade.ref}
                >
                  <.live_file_input upload={@uploads.hotupgrade} class="hidden" />

                  <div class="text-center">
                    <svg
                      class="w-16 h-16 mx-auto text-base-content/40 mb-4"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M9 13h6m-3-3v6m5 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
                      >
                      </path>
                    </svg>

                    <label for={@uploads.hotupgrade.ref} class="cursor-pointer">
                      <span class="text-lg font-medium text-base-content">
                        Drop your .tar.gz file here or
                        <span class="text-primary hover:text-primary-focus">browse</span>
                      </span>
                    </label>

                    <p class="text-sm text-base-content/60 mt-2">
                      Maximum file size: {trunc(@uploads.hotupgrade.max_file_size / 1_000_000)}MB
                    </p>
                  </div>
                </div>
                <!-- Upload Progress -->
                <%= for entry <- @uploads.hotupgrade.entries do %>
                  <div class="mt-4 p-4 bg-base-200 rounded-lg">
                    <div class="flex items-center justify-between mb-2">
                      <div class="flex items-center gap-3">
                        <svg
                          class="w-5 h-5 text-info"
                          fill="none"
                          stroke="currentColor"
                          viewBox="0 0 24 24"
                        >
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z"
                          >
                          </path>
                        </svg>
                        <div>
                          <p class="font-medium text-base-content">{entry.client_name}</p>
                          <p class="text-sm text-base-content/60">
                            {format_bytes(entry.client_size)}
                          </p>
                        </div>
                      </div>

                      <button
                        type="button"
                        phx-click="cancel-upload"
                        phx-value-ref={entry.ref}
                        class="btn btn-sm btn-circle btn-ghost text-error"
                      >
                        ✕
                      </button>
                    </div>
                    <!-- Progress Bar -->
                    <div class="w-full bg-base-300 rounded-full h-2">
                      <div
                        class="bg-primary h-2 rounded-full transition-all duration-300"
                        style={"width: #{entry.progress}%"}
                      >
                      </div>
                    </div>
                    <p class="text-xs text-base-content/60 mt-1">{entry.progress}% uploaded</p>
                    <!-- Validation Errors -->
                    <%= for err <- upload_errors(@uploads.hotupgrade, entry) do %>
                      <div class="alert alert-error mt-2">
                        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                          >
                          </path>
                        </svg>
                        <span>{error_to_string(err)}</span>
                      </div>
                    <% end %>
                  </div>
                <% end %>
                <!-- General Upload Errors -->
                <%= for err <- upload_errors(@uploads.hotupgrade) do %>
                  <div class="alert alert-error mt-4">
                    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                      >
                      </path>
                    </svg>
                    <span>{error_to_string(err)}</span>
                  </div>
                <% end %>
              </form>
            </div>
          </div>
          <!-- Validated Release Section -->
          <%= if @downloaded_release do %>
            <div
              class="card bg-base-100 shadow-sm mb-6"
              phx-mounted={
                JS.transition(
                  {"ease-in duration-300", "opacity-0 scale-95", "opacity-100 scale-100"},
                  time: 300
                )
              }
            >
              <div class="card-body">
                <h2 class="card-title text-xl mb-4">
                  <svg
                    class="w-6 h-6 text-success"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
                    >
                    </path>
                  </svg>
                  Uploaded release
                </h2>

                <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
                  <!-- Release Info -->
                  <div class="bg-base-200 border border-base-300 rounded-lg p-4">
                    <div class="flex items-center gap-2 mb-3">
                      <svg
                        class="w-5 h-5 text-primary"
                        fill="none"
                        stroke="currentColor"
                        viewBox="0 0 24 24"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                        >
                        </path>
                      </svg>
                      <h3 class="font-semibold text-base-content">Release Information</h3>
                    </div>

                    <dl class="space-y-2">
                      <div>
                        <dt class="text-xs text-base-content/60">Application</dt>
                        <dd class="font-mono text-sm font-medium text-base-content">
                          {@downloaded_release.name}
                        </dd>
                      </div>
                      <div :if={!@downloaded_release.error}>
                        <dt class="text-xs text-base-content/60">Version</dt>
                        <dd class="font-mono text-sm font-medium text-primary">
                          {@downloaded_release.to_version}
                        </dd>
                      </div>
                      <div>
                        <dt class="text-xs text-base-content/60">Filename</dt>
                        <dd class="font-mono text-xs text-base-content/80 truncate">
                          {@downloaded_release.filename}
                        </dd>
                      </div>
                      <div>
                        <dt class="text-xs text-base-content/60">Size</dt>
                        <dd class="text-sm text-base-content">
                          {format_bytes(@downloaded_release.size)}
                        </dd>
                      </div>
                    </dl>
                  </div>
                  <!-- Upgrade Details -->
                  <div class="bg-base-200 border border-base-300 rounded-lg p-4">
                    <div class="flex items-center gap-2 mb-3">
                      <svg
                        class="w-5 h-5 text-info"
                        fill="none"
                        stroke="currentColor"
                        viewBox="0 0 24 24"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
                        >
                        </path>
                      </svg>
                      <h3 class="font-semibold text-base-content">Upgrade Details</h3>
                    </div>

                    <dl class="space-y-2">
                      <div>
                        <dt class="text-xs text-base-content/60">Current Version</dt>
                        <dd class="font-mono text-sm font-medium text-base-content">
                          {@downloaded_release.from_version || "N/A"}
                        </dd>
                      </div>
                      <div :if={!@downloaded_release.error}>
                        <dt class="text-xs text-base-content/60">Target Version</dt>
                        <dd class="font-mono text-sm font-medium text-success">
                          {@downloaded_release.to_version}
                        </dd>
                      </div>
                      <div :if={!@downloaded_release.error}>
                        <dt class="text-xs text-base-content/60">Upgrade Type</dt>
                        <dd class="inline-flex items-center px-2 py-1 rounded-full text-xs font-semibold bg-warning/10 text-warning">
                          Hot Upgrade
                        </dd>
                      </div>
                      <div :if={@downloaded_release.error}>
                        <dt class="text-xs text-base-content/60">Error</dt>
                        <dd class="inline-flex items-center px-2 py-1 rounded-full text-xs font-semibold bg-error/10 text-error">
                          {@downloaded_release.error}
                        </dd>
                      </div>
                    </dl>
                  </div>
                </div>
                <!-- Warning Banner -->
                <div
                  :if={!@downloaded_release.error}
                  class="bg-warning/10 border border-warning/20 rounded-lg p-4 mb-6"
                >
                  <div class="flex gap-3">
                    <svg
                      class="w-5 h-5 text-warning flex-shrink-0 mt-0.5"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L4.082 16.5c-.77.833.192 2.5 1.732 2.5z"
                      >
                      </path>
                    </svg>
                    <div>
                      <p class="font-semibold text-warning mb-1">Important Notice</p>
                      <ul class="text-sm text-base-content/80 space-y-1 list-disc list-inside">
                        <li>This will perform a hot upgrade without restarting the application</li>
                        <li>Ensure the release is compatible with the current version</li>
                        <li>This operation cannot be easily undone</li>
                        <li>Consider backing up current state before proceeding</li>
                      </ul>
                    </div>
                  </div>
                </div>
                <!-- Action Buttons -->
                <div class="flex gap-3 justify-end">
                  <button type="button" phx-click="remove-release" class="btn btn-ghost">
                    Remove
                  </button>
                  <.link
                    :if={!@downloaded_release.error}
                    id={Helper.normalize_id("hotupgrade-#{@downloaded_release.name}")}
                    patch={~p"/hotupgrade/apply"}
                  >
                    <button type="button" class="btn btn-primary">
                      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M5 13l4 4L19 7"
                        >
                        </path>
                      </svg>
                      Apply Hot Upgrade
                    </button>
                  </.link>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>

    <%= cond do %>
      <% @live_action == :apply and @upgrade_state != :init -> %>
        <Progress.content id={"hotupgrade-progress-modal-#{@downloaded_release.name}"}>
          <:header>Hot Upgrade Progress</:header>

          <div id="upgrade-progress" class="mt-6 space-y-4">
            <!-- Progress Header -->
            <div class="flex items-center justify-between px-4">
              <h3 class="text-base-content font-semibold">Upgrade Progress</h3>
              <%= if @upgrade_state == :running do %>
                <span class="text-sm text-base-content/60">
                  Step {length(@upgrade_progress)} of {@total_upgrade_steps}
                </span>
              <% end %>
            </div>
            <!-- Progress Log -->
            <div class="bg-base-200 rounded-lg p-4">
              <div
                id="upgrade-progress-log"
                phx-hook="AutoScroll"
                class="space-y-2 max-h-48 overflow-y-auto text-sm font-mono"
              >
                <%= for line <- @upgrade_progress do %>
                  <div class="flex items-start gap-2 text-base-content/80">
                    <span class="text-success mt-0.5 flex-shrink-0">✓</span>
                    <span class="flex-1">{line}</span>
                  </div>
                <% end %>

                <%= if @upgrade_state == :running and length(@upgrade_progress) > 0 do %>
                  <div class="flex items-center gap-2 text-primary/80">
                    <span class="loading loading-spinner loading-xs"></span>
                    <span class="italic">Processing...</span>
                  </div>
                <% end %>
              </div>
            </div>
            <!-- Status Message -->
            <div :if={@upgrade_state not in [:success, :error]} class="px-4 flex items-center gap-2">
              <span class="loading loading-spinner loading-sm text-primary"></span>
              <span class="text-sm text-base-content/60">Applying hot upgrade…</span>
            </div>
            <!-- Completion Status -->
            <div :if={@upgrade_state == :success} class="px-4">
              <div class="alert alert-success">
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
                  />
                </svg>
                <span>Hot upgrade completed successfully!</span>
              </div>
            </div>

            <div :if={@upgrade_state == :error} class="px-4">
              <div class="alert alert-error">
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
                  />
                </svg>
                <span>Hot upgrade failed!</span>
              </div>
            </div>
          </div>

          <:footer :if={@upgrade_state != :running}>
            <Progress.done_button
              id="hotupgrade-progress-done"
              event="hotupgrade-progress-done"
              value={@downloaded_release.name}
            >
              Done
            </Progress.done_button>
          </:footer>
        </Progress.content>
      <% @live_action == :apply and @downloaded_release != nil and @downloaded_release.error == nil -> %>
        <Confirm.content id={"hotupgrade-modal-#{@downloaded_release.name}"}>
          <:header>Hot upgrade</:header>

          <div class="space-y-4">
            <p class="text-base-content/90">
              You are about to perform a <span class="font-bold text-error">hot upgrade</span> for:
            </p>
            <div class="bg-base-200 border border-base-300 rounded-lg p-4">
              <div class="flex items-center gap-3">
                <div class="w-10 h-10 bg-primary/10 border border-primary/20 rounded-lg flex items-center justify-center">
                  <span class="text-base font-mono font-bold text-primary">
                    {String.first(@downloaded_release.name)}
                  </span>
                </div>
                <div>
                  <p class="text-sm text-base-content/60">
                    {@downloaded_release.name}
                  </p>
                </div>
              </div>
            </div>

            <div class="bg-error/10 border border-error/20 rounded-lg p-4">
              <div class="flex gap-3">
                <svg
                  class="w-5 h-5 text-error flex-shrink-0 mt-0.5"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L4.082 16.5c-.77.833.192 2.5 1.732 2.5z"
                  >
                  </path>
                </svg>
                <div class="space-y-2">
                  <p class="font-semibold text-error">Warning: Destructive Operation</p>
                  <ul class="text-sm text-base-content/80 space-y-1 list-disc list-inside">
                    <li>All running application instances will be terminated</li>
                    <li>Deployments will restart sequentially</li>
                    <li>This may cause temporary service interruption</li>
                    <li>This action cannot be undone</li>
                  </ul>
                </div>
              </div>
            </div>
          </div>

          <:footer>
            <Confirm.cancel_button id="hotupgrade-cancel">
              Cancel
            </Confirm.cancel_button>
            <Confirm.danger_button
              id="hotupgrade-execute"
              event="hotupgrade-execute"
              value={@downloaded_release.name}
            >
              Yes, Apply Hot Upgrade
            </Confirm.danger_button>
          </:footer>
        </Confirm.content>
      <% true -> %>
    <% end %>
    """
  end

  @impl true
  def mount(_params, _session, socket) when is_connected?(socket) do
    # Subscribe to system info if needed
    Host.Info.subscribe()

    # Subscribe to receive hot upgrade events
    HotUpgrade.subscribe_events()

    {:ok, default_assigns(socket)}
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, default_assigns(socket)}
  end

  defp default_assigns(socket) do
    socket
    |> assign(:host_info, nil)
    |> assign(:downloaded_release, nil)
    |> assign(:applying_upgrade, false)
    |> assign(:upgrade_progress, [])
    |> assign(:upgrade_state, :init)
    |> assign(:total_upgrade_steps, 9)
    |> assign(:current_path, "/hotupgrade")
    |> assign(:ui_settings, UiSettings.get())
    |> assign(:node, Node.self())
    |> allow_upload(:hotupgrade,
      accept: [".gz"],
      max_entries: 1,
      auto_upload: true,
      max_file_size: 100_000_000,
      progress: &handle_progress/3
    )
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Hot upgrade")
  end

  defp apply_action(%{assigns: %{downloaded_release: nil}} = socket, :apply, _params) do
    socket
    |> assign(:page_title, "Hot upgrade")
    |> push_navigate(to: ~p"/hotupgrade")
  end

  defp apply_action(socket, :apply, _params) do
    socket
    |> assign(:applying_upgrade, true)
    |> assign(:page_title, "Hot upgrade confirmation")
  end

  @impl true
  def handle_event("validate-upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :hotupgrade, ref)}
  end

  def handle_event("confirm-close-modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:applying_upgrade, false)
     |> assign(:upgrade_state, :init)
     |> push_patch(to: ~p"/hotupgrade")}
  end

  def handle_event(event, _params, socket)
      when event in ["remove-release", "hotupgrade-progress-done"] do
    {:noreply,
     socket
     |> assign(:downloaded_release, nil)
     |> assign(:applying_upgrade, false)
     |> assign(:upgrade_state, :init)
     |> assign(:upgrade_progress, [])
     |> push_patch(to: ~p"/hotupgrade")}
  end

  def handle_event("hotupgrade-execute", _params, socket) do
    # Start Hotupgrade execution
    HotUpgrade.deployex_execute(socket.assigns.downloaded_release.download_path,
      sync_execution: false
    )

    {:noreply,
     socket
     |> assign(:applying_upgrade, true)
     |> assign(:upgrade_state, :running)
     |> assign(:upgrade_progress, [])
     |> assign(:page_title, "Hot upgrade in progress")}
  end

  @impl true
  def handle_info({:update_system_info, host_info}, socket) do
    ui_settings = UiSettings.get()

    {:noreply,
     socket
     |> assign(:host_info, host_info)
     |> assign(:ui_settings, ui_settings)}
  end

  def handle_info(
        {:hot_upgrade_progress, source_node, _sname, msg},
        %{assigns: %{node: node, applying_upgrade: true}} = socket
      )
      when source_node == node do
    {:noreply,
     socket
     |> update(:upgrade_progress, fn logs -> logs ++ [msg] end)}
  end

  def handle_info(
        {:hot_upgrade_complete, source_node, _sname, :ok, msg},
        %{assigns: %{node: node, applying_upgrade: true}} = socket
      )
      when source_node == node do
    {:noreply,
     socket
     |> assign(:upgrade_state, :success)
     |> update(:upgrade_progress, fn logs -> logs ++ [msg] end)}
  end

  def handle_info(
        {:hot_upgrade_complete, source_node, _sname, :error, msg},
        %{assigns: %{node: node, applying_upgrade: true}} = socket
      )
      when source_node == node do
    {:noreply,
     socket
     |> assign(:upgrade_state, :error)
     |> update(:upgrade_progress, fn logs -> logs ++ [msg] end)}
  end

  def handle_info({_hot_upgrade_event, _source_node, _sname, _reason}, socket) do
    # NOTE: Ignore events from other nodes and applying_upgrade == false
    {:noreply, socket}
  end

  defp handle_progress(:hotupgrade, entry, socket) when entry.done? do
    downloaded_release =
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        handle_release(path, entry.client_name, entry.client_size)
      end)

    {:noreply, assign(socket, :downloaded_release, downloaded_release)}
  end

  defp handle_progress(:hotupgrade, _entry, socket) do
    {:noreply, socket}
  end

  # Helper Functions

  defp handle_release(path, filename, size) do
    uploads_path = "#{:code.priv_dir(:deployex_web)}/static/uploads"
    File.mkdir_p!(uploads_path)
    download_path = uploads_path <> "/#{filename}"
    File.cp!(path, download_path)

    hotupgrade = %Data{
      filename: filename,
      size: size,
      download_path: download_path
    }

    # Execute checks
    with true <- String.ends_with?(filename, ".tar.gz"),
         {:ok, check_data} <- HotUpgrade.deployex_check(download_path) do
      {:ok, struct(hotupgrade, Map.from_struct(check_data))}
    else
      false ->
        {:postpone, %{hotupgrade | error: " not a .tar.gz file"}}

      {:error, :full_deployment} ->
        {:postpone, %{hotupgrade | error: "full deployment only"}}

      {:error, _reason} ->
        {:postpone, %{hotupgrade | error: "invalid release"}}
    end
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 2)} KB"

  defp format_bytes(bytes) when bytes < 1_073_741_824,
    do: "#{Float.round(bytes / 1_048_576, 2)} MB"

  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_073_741_824, 2)} GB"

  defp error_to_string(:too_large), do: "File is too large"
  defp error_to_string(:not_accepted), do: "File type not accepted"
  defp error_to_string(:too_many_files), do: "Too many files"
  defp error_to_string(error), do: "Upload error: #{inspect(error)}"
end
