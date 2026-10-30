defmodule DeployexWeb.ApplicationsLive.ViewTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Deployer.Resources
  alias Deployer.Resources.Limit
  alias Deployer.Status
  alias DeployexWeb.ApplicationsLive.View
  alias DeployexWeb.HostTime
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
    ghosted_at = HostTime.format(~U[2026-10-28 15:00:00Z], "%H:%M")
    children = [child(%{deployed_at: ~U[2026-10-28 14:00:00Z]})]

    assert [
             %{
               alert: %{kind: :ghosted, blocking: false, text: text},
               deploy: %{type: :ghosted, when: ^ghosted_at}
             } = row
           ] =
             View.apps([app(children, %{config: config})], @now)

    assert text == "1.1.0 failed and is ghosted. 1.0.0 keeps running, so the app is up."
    assert %{tone: :warning, title: "1.1.0 failed and is ghosted"} = row.alert
    # It needs attention, and nothing is blocked
    assert View.attention([row]) == %{count: 1, blocking: false}

    # A version ghosted before the last deploy is history, not an alert
    old = %{config | last_ghosted_at: ~U[2026-10-28 13:00:00Z]}
    assert [%{alert: nil}] = View.apps([app(children, %{config: old})], @now)
  end

  test "the notes list the TLS expiry, the limits near the end and the crashes" do
    resources = %Resources{
      process: %Limit{count: 950, limit: 1_000, percent: 95},
      port: %Limit{count: 0, limit: 65_536, percent: 0},
      atom: %Limit{
        count: 200_000,
        limit: 1_048_576,
        percent: 19,
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
    assert %{tone: :warning, text: "myapp-abc atoms grew 20% in 20 minutes"} in notes
    crashed = HostTime.format(~U[2026-10-28 14:31:00Z], "%H:%M")
    assert %{tone: :warning, text: "myapp-abc crash restart at #{crashed}"} in notes

    # The crash at 14:31 is more than an hour old, so it is a note and no problem
    assert problems == [
             "TLS certificate expires in 5 days",
             "TLS certificate expires in 20 days",
             "myapp-abc processes at 95% of the limit",
             "myapp-abc atoms grew 20% in 20 minutes"
           ]

    assert [
             %{level: 2, percent_text: "95%"},
             %{percent_text: "0%"},
             %{percent_text: "19%", trend: "+20% in 20 minutes"}
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
      # One port more on a small count is no trend
      port: %Limit{count: 8, limit: 65_536, percent: 0, change_percent: 14, change_minutes: 18},
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

  test "restarts count crashes apart from the restarts an operator or the watchdog asked for" do
    children = [
      child(%{
        crash_restart_count: 2,
        force_restart_count: 1,
        last_crash_at: ~U[2026-10-28 14:31:00Z]
      }),
      child(%{sname: "myapp-def", force_restart_count: 1}),
      child(%{sname: "myapp-ghi"})
    ]

    assert [%{restarts: app_restarts, instances: [crashed, forced, none]}] =
             View.apps([app(children)], @now)

    assert app_restarts == %{
             count: 4,
             crash: true,
             lines: [
               "2 crash restarts, the last at #{HostTime.format(~U[2026-10-28 14:31:00Z], "%H:%M")}",
               "2 restarts by an operator or the watchdog"
             ]
           }

    assert %{count: 3, crash: true} = crashed.restarts

    assert forced.restarts == %{
             count: 1,
             crash: false,
             lines: ["1 restart by an operator or the watchdog"]
           }

    assert none.restarts == %{count: 0, crash: false, lines: ["No restarts"]}
  end

  test "the limits follow the app's monitoring settings, and a type it does not name is not watched" do
    resources = %Resources{
      process: %Limit{count: 600, limit: 1_000, percent: 60},
      port: %Limit{count: 70, limit: 100, percent: 70},
      atom: %Limit{count: 500, limit: 1_000, percent: 50}
    }

    monitoring = [
      process: %{
        enable_restart: true,
        warning_threshold_percent: 50,
        restart_threshold_percent: 65
      },
      port: %Foundation.Yaml.Monitoring{
        enable_restart: false,
        warning_threshold_percent: 60,
        restart_threshold_percent: 80
      }
    ]

    assert [%{instances: [%{limits: [process, port, atom], warnings: warnings}]}] =
             View.apps([app([child(%{resources: resources, monitoring: monitoring})])], @now)

    assert %{level: 1, restart_at: 65, watch: "restarts at 65%"} = process
    assert %{level: 1, restart_at: false, watch: "restart off"} = port
    assert %{level: 0, restart_at: false, watch: nil} = atom
    assert warnings == ["processes at 60% of the limit", "ports at 70% of the limit"]
  end

  test "an instance lists its ports and served URLs, and the app shows its own logo" do
    logo = "data:image/svg+xml;base64,PHN2Zy8+"

    children = [
      child(%{ports: [%{key: "PORT", base: 4000}], urls: ["http://localhost:4000"], logo: logo}),
      child(%{sname: "myapp-def"})
    ]

    assert [
             %{
               logo: ^logo,
               instances: [
                 %{ports: [%{key: "PORT", base: 4000}], urls: ["http://localhost:4000"]},
                 _
               ]
             }
           ] =
             View.apps([app(children)], @now)

    assert [%{logo: nil}] = View.apps([app([child(%{})])], @now)
  end

  test "a subtitle leaves out the version when nothing runs" do
    children = [child(%{status: :idle, version: nil})]
    assert [%{sub: "OTP 29 · Elixir 1.20.4"}] = View.apps([app(children)], @now)
  end

  test "apps sort by name, and a crash in the last hour is a problem" do
    children = [child(%{last_crash_at: ~U[2026-10-28 15:40:00Z]})]

    assert [%{name: "alpha", problems: []}, %{name: "myapp", problems: problems} = crashed] =
             View.apps([app(children), app([child(%{})], %{name: "alpha"})], @now)

    assert problems == [
             "myapp-abc crashed at #{HostTime.format(~U[2026-10-28 15:40:00Z], "%H:%M")}"
           ]

    assert View.attention?(crashed)
  end

  test "severity ranks down first, then a restart threshold or TLS soon, then failures, then the rest" do
    ghosted = %{last_ghosted_version: "1.1.0", last_ghosted_at: ~U[2026-10-28 15:00:00Z]}
    deployed = ~U[2026-10-28 14:00:00Z]
    at_restart = %Resources{process: %Limit{count: 95, limit: 100, percent: 95}}
    warning = %Resources{process: %Limit{count: 80, limit: 100, percent: 80}}

    severity = fn app ->
      app |> List.wrap() |> View.apps(@now) |> hd() |> Map.fetch!(:severity)
    end

    assert severity.(
             app([child(%{status: :idle, version: nil, deployed_at: deployed})], %{
               config: ghosted
             })
           ) == 4

    assert severity.(app([child(%{resources: at_restart})])) == 3
    assert severity.(app([child(%{certificates: [%PublicKey{expires_in_days: 5}]})])) == 3
    assert severity.(app([child(%{deployed_at: deployed})], %{config: ghosted})) == 2
    assert severity.(app([child(%{last_crash_at: ~U[2026-10-28 15:40:00Z]})])) == 2
    assert severity.(app([child(%{resources: warning})])) == 2
    assert severity.(app([child(%{certificates: [%PublicKey{expires_in_days: 20}]})])) == 1
    assert severity.(app([child(%{status: :pre_commands})])) == 1
    assert severity.(app([child(%{})])) == 0

    # A failed pre_command is down when no instance runs, and failing while another one runs
    failed =
      child(%{
        status: :pre_commands,
        otp: :not_connected,
        failed_pre_commands: ["eval Migrator.run()"]
      })

    assert severity.(app([failed])) == 4
    assert severity.(app([failed, child(%{sname: "myapp-def"})])) == 2
  end

  test "a failed pre_command is an error callout that names the command" do
    failed =
      child(%{
        status: :pre_commands,
        otp: :not_connected,
        failed_pre_commands: ["eval Migrator.run()"]
      })

    assert [%{alert: %{kind: :pre_commands, tone: :error, blocking: true} = alert}] =
             View.apps([app([failed])], @now)

    assert alert.title == "pre_commands for 1.0.0 failed"
    assert alert.detail =~ "Failed: eval Migrator.run()."

    # While they run, it is a note
    assert [
             %{
               alert: %{
                 tone: :info,
                 blocking: false,
                 detail: "myapp-abc starts when they finish."
               }
             }
           ] =
             View.apps([app([child(%{status: :pre_commands, otp: :not_connected})])], @now)

    # A hot upgrade's pre_commands run while the instance runs, so it counts as running
    assert [%{running: 1, alert: %{title: "Running the hot upgrade's pre_commands"}}] =
             View.apps([app([child(%{status: :pre_commands, otp: :connected})])], @now)
  end

  test "a TLS certificate within 7 days and an instance at its restart threshold are urgent" do
    at_restart = %Resources{process: %Limit{count: 95, limit: 100, percent: 95}}

    children = [
      child(%{
        resources: at_restart,
        monitoring: [process: %{}],
        certificates: [%PublicKey{expires_in_days: 5}]
      }),
      child(%{sname: "myapp-def", certificates: [%PublicKey{expires_in_days: 20}]})
    ]

    assert [%{urgent: [tls, limit]}] = View.apps([app(children)], @now)
    assert %{kind: :tls, title: "TLS certificate expires in 5 days"} = tls

    assert %{
             kind: :limit,
             sname: "myapp-abc",
             title: "myapp-abc processes at 95% of the limit",
             detail: "The watchdog restarts the instance at 90%."
           } = limit

    off = [process: %{enable_restart: false}]

    assert [%{urgent: [%{detail: "Restart is off for this limit" <> _}]}] =
             View.apps([app([child(%{resources: at_restart, monitoring: off})])], @now)

    assert [%{urgent: []}] = View.apps([app([child(%{})])], @now)
  end

  test "a duration reads in its largest whole unit" do
    assert View.duration(5_000) == "5 seconds"
    assert View.duration(1_000) == "1 second"
    assert View.duration(600_000) == "10 minutes"
    assert View.duration(3_600_000) == "1 hour"
    assert View.duration(90_000) == "90 seconds"
    assert View.duration(1_500) == "1500 milliseconds"
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
