defmodule DeployexWeb.Components.Search do
  @moduledoc """
  Searches this host's applications, instances, filter values and dashboard pages. An app, an instance or a
  value like `runtime: erlang` adds a tag that filters the Applications list, and the bar shows the tags.
  A page opens. The index is read from `Deployer.Status.monitoring/0` when the text changes, so no page
  receives it on every status update.
  """
  use DeployexWeb, :live_component

  alias DeployexWeb.ApplicationsLive.Filter
  alias DeployexWeb.ApplicationsLive.View
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
  def mount(socket),
    do: {:ok, assign(socket, query: "", groups: [], hints: [], tags: [], on_apps: false)}

  # New tags, after a result was picked, start a new search
  @impl true
  def update(assigns, socket) do
    changed = Map.has_key?(assigns, :tags) and assigns.tags != socket.assigns.tags
    socket = assign(socket, assigns)
    {:ok, if(changed, do: assign(socket, query: "", groups: [], hints: []), else: socket)}
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:chips, Enum.map(assigns.tags, &chip(&1, assigns)))
      |> assign(:links, Enum.map(assigns.groups, &links(&1, assigns)))

    ~H"""
    <div>
      <Search.combobox
        id={@id}
        query={@query}
        groups={@links}
        hints={@hints}
        tags={@chips}
        target={@myself}
        placeholder={if @tags == [], do: "Search apps, instances, pages", else: "Add a filter"}
        label="Search applications, instances and pages on this host"
      />
    </div>
    """
  end

  # The hints need the index, so they load when the field takes focus, not with every page
  @impl true
  def handle_event("focus", _params, %{assigns: %{hints: []}} = socket),
    do: {:noreply, assign(socket, :hints, hints(index(socket.assigns.tags)))}

  def handle_event("focus", _params, socket), do: {:noreply, socket}

  def handle_event("search", %{"q" => query}, socket) do
    index = index(socket.assigns.tags)
    hints = if socket.assigns.hints == [], do: hints(index), else: socket.assigns.hints
    {:noreply, assign(socket, query: query, groups: search(index, query), hints: hints)}
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
          for kind <- ["Applications", "Instances", "Filters", "Pages"],
              items = by_kind[kind],
              items != nil do
            %{title: kind, items: Enum.take(items, @max_per_group)}
          end
        end)
    end
  end

  @doc """
  Returns the searchable entries: the applications, their instances and the filter values not in the tags,
  each with the `tag` it adds, and the pages, each with its `href`.
  """
  @spec index([Filter.tag()]) :: [map()]
  def index(tags \\ []) do
    apps =
      case Deployer.Status.monitoring() do
        {:ok, statuses} -> View.apps(statuses)
        _ -> []
      end

    instances =
      Map.new(for app <- apps, instance <- app.instances, do: {instance.sname, instance})

    by_name = Map.new(apps, &{&1.name, &1})

    Enum.map(Filter.suggestions(apps, tags), &entry(&1, by_name, instances)) ++
      Enum.map(@pages, fn {label, context, href} ->
        %{kind: "Pages", label: label, context: context, href: href}
      end)
  end

  defp entry(%{tag: {"app", name} = tag}, by_name, _instances) do
    app = by_name[name]
    version = app.instances |> Enum.map(& &1.version) |> Enum.find(& &1)
    context = Enum.join(Enum.reject([app.status.text, version], &is_nil/1), " · ")
    %{kind: "Applications", label: name, context: context, tag: tag}
  end

  defp entry(%{tag: {"instance", sname} = tag}, _by_name, instances) do
    instance = instances[sname]

    port =
      case instance.ports do
        [%{key: key, base: base} | _] -> "#{key} #{base} · "
        _ -> ""
      end

    context = "#{port}#{instance.version || "no version"} #{instance.status.text}"
    %{kind: "Instances", label: sname, context: context, tag: tag}
  end

  defp entry(%{tag: tag, label: label, count: count}, _by_name, _instances),
    do: %{
      kind: "Filters",
      label: label,
      context: if(count == 1, do: "1 app", else: "#{count} apps"),
      tag: tag
    }

  # A tag result adds its tag to the ones set. On the Applications page it patches, elsewhere it opens it
  defp links(group, assigns) do
    items =
      Enum.map(group.items, fn
        %{tag: tag} = item ->
          Map.merge(item, %{href: Filter.path(assigns.tags ++ [tag]), patch: assigns.on_apps})

        item ->
          Map.put(item, :patch, false)
      end)

    %{group | items: items}
  end

  defp chip(tag, assigns),
    do: %{
      label: Filter.label(tag),
      href: Filter.path(List.delete(assigns.tags, tag)),
      patch: assigns.on_apps
    }

  defp hints(index) do
    app = Enum.find(index, &(&1.kind == "Applications"))
    instance = Enum.find(index, &(&1.kind == "Instances"))
    suffix = instance && instance.label |> String.split("-") |> List.last()

    Enum.reject([app && app.label, suffix, "attention", "logs"], &is_nil/1)
  end
end
