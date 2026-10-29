defmodule DeployexWeb.Components.Search do
  @moduledoc """
  Searches this host's applications, instances and dashboard pages. The index is read from
  `Deployer.Status.monitoring/0` when the text changes, so no page receives it on every status update.
  """
  use DeployexWeb, :live_component

  alias DeployexWeb.UI.Search

  @max_per_group 6

  @pages [
    {"Applications", "every app on this host", "/applications"},
    {"Live Logs", "stdout and stderr of every instance", "/logs/live"},
    {"History Logs", "stored log lines", "/logs/history"},
    {"Observer Web", "processes, ETS, tracing", "/embedded-observer"},
    {"Terminal", "IEx on an instance, or a shell on this host", "/terminal"},
    {"Hot Upgrade", "apply a hot upgrade", "/hotupgrade"},
    {"Documentation", "guides and the YAML reference", "/documentation"}
  ]

  @impl true
  def mount(socket), do: {:ok, assign(socket, query: "", groups: [], hints: [])}

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <Search.combobox
        id={@id}
        query={@query}
        groups={@groups}
        hints={@hints}
        target={@myself}
        placeholder="Search apps, instances, pages"
        label="Search applications, instances and pages on this host"
      />
    </div>
    """
  end

  # The hints need the index, so they load when the field takes focus, not with every page
  @impl true
  def handle_event("focus", _params, %{assigns: %{hints: []}} = socket),
    do: {:noreply, assign(socket, :hints, hints(index()))}

  def handle_event("focus", _params, socket), do: {:noreply, socket}

  def handle_event("search", %{"q" => query}, socket) do
    {:noreply, assign(socket, query: query, groups: search(index(), query))}
  end

  @doc """
  Returns the groups of entries whose kind, label or context contain the text, in any case.
  """
  @spec search([map()], String.t()) :: [map()]
  def search(index, query) do
    case query |> String.trim() |> String.downcase() do
      "" ->
        []

      needle ->
        index
        |> Enum.filter(
          &String.contains?(String.downcase("#{&1.kind} #{&1.label} #{&1.context}"), needle)
        )
        |> Enum.group_by(& &1.kind)
        |> then(fn by_kind ->
          for kind <- ["Applications", "Instances", "Pages"],
              items = by_kind[kind],
              items != nil do
            %{title: kind, items: Enum.take(items, @max_per_group)}
          end
        end)
    end
  end

  @doc """
  Returns the searchable entries: the applications, their instances and the pages.
  """
  @spec index() :: [map()]
  def index do
    apps =
      case Deployer.Status.monitoring() do
        {:ok, apps} -> Enum.reject(apps, &(&1.name == "deployex"))
        _ -> []
      end

    Enum.map(apps, &app_entry/1) ++
      Enum.flat_map(apps, fn app -> Enum.map(app.children, &instance_entry(app, &1)) end) ++
      Enum.map(@pages, fn {label, context, href} ->
        %{kind: "Pages", label: label, context: context, href: href}
      end)
  end

  defp app_entry(app) do
    running = Enum.count(app.children, &(&1.status == :running))
    version = app.children |> Enum.map(& &1.version) |> Enum.find(& &1)

    %{
      kind: "Applications",
      label: app.name,
      context:
        Enum.join(
          Enum.reject(["#{running}/#{length(app.children)} running", version], &is_nil/1),
          " · "
        ),
      href: "/applications?app=#{app.name}"
    }
  end

  defp instance_entry(app, child) do
    port =
      case child.ports do
        [%{key: key, base: base} | _] -> "#{key} #{base} · "
        _ -> ""
      end

    %{
      kind: "Instances",
      label: child.sname,
      context: "#{port}#{child.version || "no version"} #{child.status}",
      href: "/applications?app=#{app.name}&instance=#{child.sname}"
    }
  end

  defp hints(index) do
    app = Enum.find(index, &(&1.kind == "Applications"))
    instance = Enum.find(index, &(&1.kind == "Instances"))
    suffix = instance && instance.label |> String.split("-") |> List.last()

    Enum.reject([app && app.label, suffix, "logs"], &is_nil/1)
  end
end
