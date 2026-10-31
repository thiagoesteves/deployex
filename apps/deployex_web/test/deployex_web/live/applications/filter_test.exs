defmodule DeployexWeb.ApplicationsLive.FilterTest do
  use ExUnit.Case, async: true

  alias DeployexWeb.ApplicationsLive.Filter

  defp app(attrs) do
    Map.merge(
      %{
        name: "myapp",
        language: "elixir",
        running: 1,
        total: 1,
        pinned: nil,
        alert: nil,
        problems: [],
        deploy: %{type: :full},
        instances: [%{sname: "myapp-abc", version: "1.0.0", status: %{text: "running"}}]
      },
      attrs
    )
  end

  test "parse/1 reads the filter and the older app and instance params, and drops unknown keys" do
    assert Filter.parse(%{"filter" => "runtime:erlang, status:attention,color:red,app:"}) ==
             [{"runtime", "erlang"}, {"status", "attention"}]

    assert Filter.parse(%{"app" => "myapp", "instance" => "myapp-abc"}) ==
             [{"app", "myapp"}, {"instance", "myapp-abc"}]

    assert Filter.parse(%{}) == []
  end

  test "path/1 and toggle/2 build the list's URL" do
    assert Filter.path([]) == "/applications"
    assert Filter.path([{"runtime", "erlang"}]) == "/applications?filter=runtime%3Aerlang"
    assert Filter.toggle([{"runtime", "erlang"}], {"runtime", "erlang"}) == []
    assert Filter.toggle([], {"status", "attention"}) == [{"status", "attention"}]
  end

  test "select/2 needs every key, and either value of one key" do
    erlang = app(%{name: "erl", language: "erlang"})
    hot = app(%{name: "hot", deploy: %{type: :hot}, pinned: "2.0.0"})
    down = app(%{name: "down", running: 0, alert: %{kind: :ghosted, blocking: true}})
    apps = [erlang, hot, down]

    assert Filter.select(apps, []) == apps
    assert Filter.select(apps, [{"runtime", "erlang"}]) == [erlang]
    assert Filter.select(apps, [{"runtime", "erlang"}, {"deploy", "hot"}]) == []
    assert Filter.select(apps, [{"app", "erl"}, {"app", "hot"}]) == [erlang, hot]
    assert Filter.select(apps, [{"status", "attention"}]) == [down]
    assert Filter.select(apps, [{"status", "ghosted"}]) == [down]
    assert Filter.select(apps, [{"status", "stopped"}]) == [down]
    assert Filter.select(apps, [{"status", "running"}]) == [erlang, hot]
    assert Filter.select(apps, [{"mode", "pinned"}]) == [hot]
    assert Filter.select(apps, [{"version", "2.0.0"}]) == [hot]
    assert Filter.select(apps, [{"instance", "myapp-abc"}]) == apps
  end

  test "suggestions/2 offers the tags that match an app and are not set, with their counts" do
    apps = [app(%{name: "erl", language: "erlang"}), app(%{name: "ex"})]
    suggestions = Filter.suggestions(apps, [{"runtime", "erlang"}])

    assert %{label: "runtime: elixir", count: 1} =
             Enum.find(suggestions, &(&1.tag == {"runtime", "elixir"}))

    refute Enum.any?(suggestions, &(&1.tag == {"runtime", "erlang"}))
    refute Enum.any?(suggestions, &(&1.tag == {"status", "attention"}))
    assert %{count: 2} = Enum.find(suggestions, &(&1.tag == {"status", "running"}))
    assert Filter.label({"status", "attention"}) == "status: needs attention"
  end
end
