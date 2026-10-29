defmodule DeployexWeb.ApplicationsLive.Filter do
  @moduledoc """
  The tags that filter the Applications list, like `runtime: erlang` or `status: attention`, as the
  search bar shows them and the URL keeps them (`?filter=runtime:erlang,status:attention`).

  An app shows when it matches every key. Two tags with the same key match either value.
  """

  alias DeployexWeb.ApplicationsLive.View

  @type tag :: {String.t(), String.t()}

  @keys ~w(app instance runtime status deploy mode version)
  @statuses ~w(attention running starting stopped ghosted pre_commands)

  @doc """
  Returns the tags of the query params: `filter`, and the `app` and `instance` of older links.
  """
  @spec parse(map()) :: [tag()]
  def parse(params) do
    filter =
      for token <- String.split(params["filter"] || "", ",", trim: true),
          [key, value] <- [String.split(token, ":", parts: 2)],
          key = String.trim(key),
          value = String.trim(value),
          key in @keys and value != "",
          do: {key, value}

    older = for key <- ["app", "instance"], is_binary(params[key]), do: {key, params[key]}
    Enum.uniq(filter ++ older)
  end

  @doc """
  Returns the Applications path for the tags.
  """
  @spec path([tag()]) :: String.t()
  def path([]), do: "/applications"

  def path(tags),
    do:
      "/applications?" <>
        URI.encode_query(filter: Enum.map_join(tags, ",", fn {k, v} -> "#{k}:#{v}" end))

  @doc """
  Adds the tag, or removes it when it is there.
  """
  @spec toggle([tag()], tag()) :: [tag()]
  def toggle(tags, tag), do: if(tag in tags, do: List.delete(tags, tag), else: tags ++ [tag])

  @doc """
  Returns the apps that match the tags.
  """
  @spec select([map()], [tag()]) :: [map()]
  def select(apps, []), do: apps

  def select(apps, tags) do
    by_key = Enum.group_by(tags, &elem(&1, 0), &elem(&1, 1))

    Enum.filter(apps, fn app ->
      Enum.all?(by_key, fn {key, values} -> Enum.any?(values, &matches?(app, key, &1)) end)
    end)
  end

  @doc """
  The text of a tag, like `status: needs attention`.
  """
  @spec label(tag()) :: String.t()
  def label({"status", "attention"}), do: "status: needs attention"
  def label({key, value}), do: "#{key}: #{value}"

  @doc """
  Returns the tags that the apps offer and that are not set yet, with the number of apps each one
  matches, for the search: `%{tag: tag, label: ..., count: ...}`.
  """
  @spec suggestions([map()], [tag()]) :: [map()]
  def suggestions(apps, tags) do
    candidates =
      Enum.map(apps, &{"app", &1.name}) ++
        Enum.flat_map(apps, fn app -> Enum.map(app.instances, &{"instance", &1.sname}) end) ++
        (apps |> Enum.map(&{"runtime", &1.language}) |> Enum.uniq()) ++
        Enum.map(@statuses, &{"status", &1}) ++
        [{"deploy", "hot"}, {"deploy", "full"}, {"mode", "pinned"}, {"mode", "automatic"}] ++
        (apps |> Enum.flat_map(&versions/1) |> Enum.uniq() |> Enum.map(&{"version", &1}))

    for tag <- candidates,
        tag not in tags,
        count = length(select(apps, [tag])),
        count > 0 do
      %{tag: tag, label: label(tag), count: count}
    end
  end

  defp matches?(app, "app", name), do: app.name == name
  defp matches?(app, "instance", sname), do: Enum.any?(app.instances, &(&1.sname == sname))
  defp matches?(app, "runtime", runtime), do: app.language == runtime
  defp matches?(app, "status", "attention"), do: View.attention?(app)
  defp matches?(app, "status", "running"), do: app.total > 0 and app.running == app.total

  defp matches?(app, "status", "starting"),
    do: Enum.any?(app.instances, &(&1.status.text == "starting"))

  defp matches?(app, "status", "stopped"), do: app.running == 0
  defp matches?(%{alert: %{kind: :ghosted}}, "status", "ghosted"), do: true
  defp matches?(%{alert: %{kind: :pre_commands}}, "status", "pre_commands"), do: true
  defp matches?(%{deploy: %{type: type}}, "deploy", value), do: Atom.to_string(type) == value
  defp matches?(app, "mode", "pinned"), do: app.pinned != nil
  defp matches?(app, "mode", "automatic"), do: is_nil(app.pinned)
  defp matches?(app, "version", version), do: version in versions(app)
  defp matches?(_app, _key, _value), do: false

  defp versions(app),
    do: Enum.reject([app.pinned | Enum.map(app.instances, & &1.version)], &is_nil/1)
end
