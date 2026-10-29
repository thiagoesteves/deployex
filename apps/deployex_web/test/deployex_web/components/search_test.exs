defmodule DeployexWeb.Components.SearchTest do
  use DeployexWeb.ConnCase, async: false

  import Mox
  import Phoenix.LiveViewTest

  alias DeployexWeb.Components.Search
  alias DeployexWeb.Fixture.Status, as: FixtureStatus

  setup [:set_mox_global, :verify_on_exit!, :log_in_default_user]

  @index [
    %{kind: "Applications", label: "myphoenixapp", context: "2/2 running · 1.4.2", href: "/a"},
    %{
      kind: "Instances",
      label: "myphoenixapp-1a2b3c",
      context: "PORT 4000 · 1.4.2 running",
      href: "/i"
    },
    %{
      kind: "Pages",
      label: "Live Logs",
      context: "stdout and stderr of every instance",
      href: "/logs"
    }
  ]

  test "search/2 groups the entries that hold the text, in any case" do
    assert [%{title: "Applications"}, %{title: "Instances"}] = Search.search(@index, "PHOENIX")

    assert [%{title: "Instances", items: [%{label: "myphoenixapp-1a2b3c"}]}] =
             Search.search(@index, "4000")

    assert [%{title: "Pages"}] = Search.search(@index, "pages")
    assert Search.search(@index, "nothing") == []
    assert Search.search(@index, "  ") == []
  end

  test "index/0 lists the applications, their instances and the pages" do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:ok, FixtureStatus.list()} end)

    index = Search.index()

    assert [%{label: name, context: "1/1 running · 4.5.6"}] =
             Enum.filter(index, &(&1.kind == "Applications"))

    assert [%{label: sname, context: "PORT 5678 · 4.5.6 running"}] =
             Enum.filter(index, &(&1.kind == "Instances"))

    assert String.starts_with?(sname, name)
    assert Enum.any?(index, &(&1.kind == "Pages" and &1.label == "Terminal"))
  end

  test "index/0 has only the pages when the status is not there" do
    Deployer.StatusMock
    |> expect(:monitoring, fn -> {:error, :not_ready} end)

    assert Enum.all?(Search.index(), &(&1.kind == "Pages"))
  end

  @tag :capture_log
  test "the top bar search shows hints on focus, then results and no match", %{conn: conn} do
    Deployer.StatusMock
    |> stub(:monitoring, fn -> {:ok, FixtureStatus.list()} end)

    {:ok, view, _html} = live(conn, ~p"/documentation")

    html = view |> element("#search-input") |> render_focus()
    assert html =~ "Try"
    assert html =~ ~s(class="dx-ctx")

    html = view |> element("#search form") |> render_change(%{"q" => "terminal"})
    assert html =~ ~s(role="option")
    assert html =~ "IEx on an instance, or a shell on this host"

    html = view |> element("#search form") |> render_change(%{"q" => "zzz"})
    assert html =~ "No match for zzz."

    # A second focus keeps the hints it has
    assert view |> element("#search-input") |> render_focus() =~ "No match for zzz."
  end
end
