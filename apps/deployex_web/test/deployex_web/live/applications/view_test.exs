defmodule DeployexWeb.ApplicationsLive.ViewTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Deployer.Resources
  alias Deployer.Resources.Limit
  alias Deployer.Status
  alias DeployexWeb.ApplicationsLive.View
  alias DeployexWeb.UI.Tags
  alias Foundation.Certificates.PublicKey

  @now ~U[2026-10-28 16:00:00Z]

  defp child(attrs) do
    Map.merge(
      %Status{
        name: "myapp",
        sname: "myapp-abc",
        version: "1.0.0",
        status: :running,
        last_deployment: :full_deployment,
        crash_restart_count: 0,
        force_restart_count: 0,
        uptime: "2h ago",
        otp_version: "29",
        elixir_version: "1.20.4",
        certificates: []
      },
      attrs
    )
  end

  defp app(children, attrs \\ %{}) do
    Map.merge(
      %Status{
        name: "myapp",
        language: "elixir",
        replicas: length(children),
        children: children,
        config: %{
          last_ghosted_version: "-/-",
          mode: :automatic,
          manual_version: nil,
          versions: []
        }
      },
      attrs
    )
  end

  test "leaves DeployEx out and builds a row for each app" do
    assert [%{name: "myapp", status: %{text: "1/1 running", tone: :success}}] =
             View.apps([%Status{name: "deployex"}, app([child(%{})])], @now)
  end

  test "sums CPU and memory over the instances, with -- when nothing was read" do
    children = [
      child(%{resources: %Resources{cpu: 3, memory: 2_147_483_648}}),
      child(%{sname: "myapp-def", resources: %Resources{cpu: 4, memory: 1_073_741_824}})
    ]

    assert [%{cpu: "7%", memory: "3.0 GB"}] = View.apps([app(children)], @now)

    assert [%{cpu: "--", memory: "--", instances: [%{cpu: "--"}]}] =
             View.apps([app([child(%{})])], @now)
  end

  test "the status follows the running instances" do
    assert [%{status: %{text: "0/1 running", tone: :error}}] =
             View.apps([app([child(%{status: :idle})])], @now)

    assert [%{status: %{tone: :warning}, instances: [_, %{status: %{text: "starting"}}]}] =
             View.apps([app([child(%{}), child(%{sname: "myapp-def", status: :starting})])], @now)

    assert [%{status: %{text: "1/2 running", tone: :warning}}] =
             View.apps([app([child(%{}), child(%{sname: "myapp-def", status: :idle})])], @now)
  end

  test "the last deploy is the newest one, hot or full, with its age" do
    children = [
      child(%{deployed_at: ~U[2026-10-28 14:00:00Z]}),
      child(%{
        sname: "myapp-def",
        last_deployment: :hot_upgrade,
        deployed_at: ~U[2026-10-28 15:59:30Z]
      })
    ]

    assert [%{deploy: %{type: :hot, when: "now"}}] = View.apps([app(children)], @now)
    assert [%{deploy: %{type: :full, when: "2h ago"}}] = View.apps([app([hd(children)])], @now)
    assert [%{deploy: nil}] = View.apps([app([child(%{})])], @now)
  end

  test "a version ghosted after the last deploy is the alert, and the rest keeps running" do
    config = %{last_ghosted_version: "1.1.0", last_ghosted_at: ~U[2026-10-28 15:00:00Z]}
    children = [child(%{deployed_at: ~U[2026-10-28 14:00:00Z]})]

    assert [
             %{
               alert: %{kind: :ghosted, blocking: false, text: text},
               deploy: %{type: :ghosted, when: "15:00"}
             } = row
           ] =
             View.apps([app(children, %{config: config})], @now)

    assert text == "1.1.0 failed and is ghosted. 1.0.0 keeps running."
    assert View.attention([row]) == 0

    # A version ghosted before the last deploy is history, not an alert
    old = %{config | last_ghosted_at: ~U[2026-10-28 13:00:00Z]}
    assert [%{alert: nil}] = View.apps([app(children, %{config: old})], @now)
  end

  test "the notes list the TLS expiry, the limits near the end and the crashes" do
    resources = %Resources{
      process: %Limit{count: 950, limit: 1_000, percent: 95},
      port: %Limit{count: 0, limit: 65_536, percent: 0},
      atom: %Limit{
        count: 10,
        limit: 1_048_576,
        percent: 0,
        change_percent: 20,
        change_minutes: 20
      }
    }

    children = [
      child(%{
        certificates: [%PublicKey{expires_in_days: 5}],
        resources: resources,
        last_crash_at: ~U[2026-10-28 14:31:00Z]
      }),
      child(%{sname: "myapp-def", certificates: [%PublicKey{expires_in_days: 20}]})
    ]

    assert [%{notes: notes, instances: [first | _], problems: problems}] =
             View.apps([app(children)], @now)

    assert %{tone: :error, text: "TLS certificate expires in 5 days"} in notes
    assert %{tone: :warning, text: "TLS certificate expires in 20 days"} in notes
    assert %{tone: :warning, text: "myapp-abc processes at 95% of the limit"} in notes
    assert %{tone: :warning, text: "myapp-abc atoms +20% in 20 minutes"} in notes
    assert %{tone: :warning, text: "myapp-abc crash restart at 14:31"} in notes
    assert length(problems) == 2

    assert [
             %{level: 2, percent_text: "95%"},
             %{percent_text: "0%"},
             %{percent_text: "<1%", trend: "+20% in 20 minutes"}
           ] =
             first.limits
  end

  test "a running instance near no limit has no warning" do
    resources = %Resources{
      process: %Limit{
        count: 100,
        limit: 1_000,
        percent: 10,
        change_percent: 5,
        change_minutes: 60
      },
      port: %Limit{count: 1, limit: 100, percent: 1},
      atom: %Limit{count: 900, limit: 1_000, percent: 85}
    }

    assert [
             %{
               instances: [
                 %{
                   warnings: ["atoms at 85% of the limit"],
                   limits: [%{trend: nil}, _, %{level: 1}]
                 }
               ]
             }
           ] =
             View.apps([app([child(%{resources: resources})])], @now)
  end

  test "an Erlang or Gleam instance gets the Erlang shell, and a status with no instance says so" do
    assert [%{language_name: "Erlang", instances: [%{shell: "Erlang shell"}]}] =
             View.apps([app([child(%{})], %{language: "erlang"})], @now)

    assert [%{language_name: "Gleam", sub: "no version", status: %{text: "0/0 running"}}] =
             View.apps([app([], %{language: "gleam"})], @now)
  end

  test "the host card shows the system with its architecture, and -- with no reading" do
    assert %{system: "macOS 15.7.4 · " <> _, icon: "macos", up: "3 days"} =
             View.host(nil, %Host.Info{host: "macOS", description: "15.7.4", uptime: "3 days"})

    assert %{system: "Ubuntu 24.04 · " <> _, icon: "linux"} =
             View.host(%Status{version: "0.10.0"}, %Host.Info{
               host: "Linux",
               description: "Ubuntu 24.04"
             })

    assert %{system: "--", up: "--", icon: "linux"} = View.host(nil, nil)
  end

  test "bytes and ages read as short text" do
    assert View.bytes(52_428_800) == "50 MB"
    assert View.age(~U[2026-10-28 15:55:00Z], @now) == "5m ago"
    assert View.age(~U[2026-10-26 16:00:00Z], @now) == "2d ago"
    assert View.age(nil, @now) == nil
  end

  test "Tags render the status, the deploy tags and the icons" do
    assert render_component(&Tags.status/1, text: "running", tone: :success) =~
             "var(--dx-success-text)"

    assert render_component(&Tags.deploy_tag/1, type: :failed) =~ "failed"
    assert render_component(&Tags.deploy_tag/1, type: :ghosted) =~ "dx-dtag-fail"
    assert render_component(&Tags.deploy_tag/1, type: :hot, label: "hot upgrade") =~ "dx-dtag-hot"
    assert render_component(&Tags.lang/1, name: "gleam", small: true) =~ "dx-lang-sm"
    assert render_component(&Tags.lang/1, name: "erlang", label: "Erlang") =~ ~s(role="img")
  end
end
