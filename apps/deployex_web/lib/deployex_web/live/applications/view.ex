defmodule DeployexWeb.ApplicationsLive.View do
  @moduledoc """
  Turns the status of this host's applications into what the Applications page shows: the This host card,
  one row per application, its instances, their limits, and the problems that need an action.
  """

  alias Deployer.Resources
  alias Deployer.Resources.Limit

  # The watchdog's values for a limit type the app's monitoring names without them. A type it does not
  # name is not watched, and its level uses these values too
  @watch_defaults %{
    enable_restart: true,
    warning_threshold_percent: 75,
    restart_threshold_percent: 90
  }
  # A count that grew this much, and by this share of its limit, over this many minutes is a trend worth a note
  @trend_percent 10
  @trend_share 0.5
  @trend_minutes 10
  @tls_warn_days 30

  @doc """
  The This host card: the system, its uptime, and the DeployEx and OTP versions.
  """
  @spec host(Deployer.Status.t() | nil, Host.Info.t() | nil) :: map()
  def host(deployex, host_info) do
    %{
      system: system(host_info),
      icon: system_icon(host_info),
      up: up(host_info),
      version: deployex && deployex.version,
      otp: :erlang.system_info(:otp_release) |> to_string()
    }
  end

  @doc """
  One row for each application, in the order of the status, with DeployEx left out.
  """
  @spec apps([Deployer.Status.t()], DateTime.t()) :: [map()]
  def apps(statuses, now \\ DateTime.utc_now()) do
    statuses
    |> Enum.reject(&(&1.name == "deployex"))
    |> Enum.sort_by(& &1.name)
    |> Enum.map(&app(&1, now))
  end

  @doc """
  Whether an app needs attention: an alert, like a ghosted version, or a problem on its row.
  """
  @spec attention?(map()) :: boolean()
  def attention?(app), do: app.alert != nil or app.problems != []

  @doc """
  The apps that need attention, and whether one of them is blocked, with nothing running.
  """
  @spec attention([map()]) :: %{count: non_neg_integer(), blocking: boolean()}
  def attention(apps) do
    apps = Enum.filter(apps, &attention?/1)
    %{count: length(apps), blocking: Enum.any?(apps, &(&1.alert != nil and &1.alert.blocking))}
  end

  defp app(status, now) do
    instances = Enum.map(status.children, &instance(&1, status.language, now))
    running = Enum.count(status.children, &(&1.status == :running))
    total = max(status.replicas, length(status.children))

    problems =
      Enum.map(tls(status, @tls_warn_days), & &1.text) ++
        for(
          instance <- instances,
          warning <- instance.warnings,
          do: "#{instance.sname} #{warning}"
        ) ++
        recent_crashes(instances, now)

    ghosted = ghosted(status, instances)

    %{
      name: status.name,
      language: status.language,
      language_name: language_name(status.language),
      logo: Enum.find_value(status.children, & &1.logo),
      sub: sub(status),
      status: app_status(running, total, status.children),
      problems: problems,
      cpu: sum_text(instances, :cpu_value, &"#{&1}%"),
      memory: sum_text(instances, :memory_value, &bytes/1),
      restarts: restarts(status.children),
      deploy: deploy(status, ghosted, now),
      alert: alert(status, ghosted, running),
      notes: notes(status, instances),
      instances: instances
    }
  end

  defp instance(child, language, now) do
    resources = child.resources
    limits = limits(resources, child.monitoring)
    warnings = Enum.flat_map(limits, & &1.warning)

    %{
      sname: child.sname,
      node: child.node && to_string(child.node),
      version: child.version,
      status: instance_status(child.status),
      cpu_value: resources && resources.cpu,
      memory_value: resources && resources.memory,
      cpu: if(resources && resources.cpu, do: "#{resources.cpu}%", else: "--"),
      memory: if(resources && resources.memory, do: bytes(resources.memory), else: "--"),
      restarts: restarts([child]),
      ports: Enum.map(List.wrap(child.ports), &Map.take(&1, [:key, :base])),
      urls: List.wrap(child.urls),
      deploy: child.last_deployment,
      up: up_text(child.uptime),
      shell: if(language == "elixir", do: "IEx shell", else: "Erlang shell"),
      limits: limits,
      warnings: warnings,
      last_crash_at: child.last_crash_at,
      deployed_at: child.deployed_at,
      age: age(child.deployed_at, now)
    }
  end

  defp limits(%Resources{} = resources, monitoring) do
    for {name, type, %Limit{} = limit} <- [
          {"Processes", :process, resources.process},
          {"Ports", :port, resources.port},
          {"Atoms", :atom, resources.atom}
        ] do
      limit_row(name, limit, watch(monitoring, type))
    end
  end

  defp limits(_resources, _monitoring), do: []

  # The app's monitoring settings for one limit type, from the YAML (a struct) or the config (a map)
  defp watch(monitoring, type) do
    case Enum.find_value(List.wrap(monitoring), fn {key, value} -> key == type && value end) do
      %_{} = config -> watch_config(Map.from_struct(config))
      %{} = config -> watch_config(config)
      _ -> Map.put(@watch_defaults, :watched, false)
    end
  end

  defp watch_config(config) do
    @watch_defaults
    |> Map.merge(Map.take(config, Map.keys(@watch_defaults)), fn _key, default, value ->
      if is_nil(value), do: default, else: value
    end)
    |> Map.put(:watched, true)
  end

  defp limit_row(name, limit, watch) do
    level = level(limit.percent, watch)
    trend = trend(limit)

    %{
      name: name,
      count: number(limit.count),
      limit: number(limit.limit),
      percent: limit.percent,
      percent_text:
        if(limit.count > 0 and limit.percent < 1, do: "<1%", else: "#{limit.percent}%"),
      level: level,
      trend: trend,
      restart_at: watch.watched && watch.enable_restart && watch.restart_threshold_percent,
      watch: watch_text(watch),
      warning: limit_warning(String.downcase(name), limit.percent, level, trend)
    }
  end

  defp level(percent, %{restart_threshold_percent: restart}) when percent >= restart, do: 2
  defp level(percent, %{warning_threshold_percent: warning}) when percent >= warning, do: 1
  defp level(_percent, _watch), do: 0

  defp watch_text(%{watched: false}), do: nil

  defp watch_text(%{enable_restart: true, restart_threshold_percent: restart}),
    do: "restarts at #{restart}%"

  defp watch_text(_watch), do: "restart off"

  defp limit_warning(name, percent, level, _trend) when level > 0,
    do: ["#{name} at #{percent}% of the limit"]

  defp limit_warning(name, _percent, _level, "+" <> trend), do: ["#{name} grew #{trend}"]

  defp limit_warning(_name, _percent, _level, _trend), do: []

  # The growth in the count, from its change in percent, so a few ports more on a small count is no trend
  defp trend(%Limit{count: count, limit: limit, change_percent: change, change_minutes: minutes})
       when is_integer(change) and change >= @trend_percent and minutes >= @trend_minutes and
              is_integer(limit) and limit > 0 do
    grown = count - count * 100 / (100 + change)

    if grown * 100 / limit >= @trend_share do
      over = if minutes >= 60, do: "1 hour", else: "#{minutes} minutes"
      "+#{change}% in #{over}"
    end
  end

  defp trend(_limit), do: nil

  # A ghosted version is the latest event of the app when it is newer than the last deploy
  defp ghosted(%{config: %{last_ghosted_version: version} = config}, instances)
       when is_binary(version) and version != "-/-" do
    # A status from before a hot upgrade has no last_ghosted_at until its next update
    at = Map.get(config, :last_ghosted_at)

    last_deploy =
      instances
      |> Enum.map(& &1.deployed_at)
      |> Enum.reject(&is_nil/1)
      |> Enum.max(DateTime, fn -> nil end)

    if is_nil(last_deploy) or (at && DateTime.compare(at, last_deploy) == :gt) do
      %{version: version, at: at}
    end
  end

  defp ghosted(_status, _instances), do: nil

  defp deploy(_status, %{at: at}, _now) do
    %{type: :ghosted, label: "ghosted", when: at && Calendar.strftime(at, "%H:%M")}
  end

  defp deploy(status, nil, now) do
    latest =
      status.children
      |> Enum.filter(& &1.deployed_at)
      |> Enum.max_by(& &1.deployed_at, DateTime, fn -> nil end)

    case latest do
      nil ->
        nil

      %{last_deployment: :hot_upgrade} = child ->
        %{type: :hot, label: "hot", when: age(child.deployed_at, now)}

      child ->
        %{type: :full, label: "full", when: age(child.deployed_at, now)}
    end
  end

  defp alert(status, %{version: version}, running) do
    tail =
      if running == 0,
        do: "No earlier version runs on this host.",
        else: "#{running_version(status)} keeps running."

    %{
      kind: :ghosted,
      blocking: running == 0,
      version: version,
      text: "#{version} failed and is ghosted. #{tail}"
    }
  end

  defp alert(status, nil, _running) do
    case Enum.find(status.children, &(&1.status == :pre_commands)) do
      nil ->
        nil

      child ->
        %{
          kind: :pre_commands,
          blocking: false,
          version: child.version,
          text: "#{child.sname} runs its pre_commands for #{child.version}."
        }
    end
  end

  # The TLS certificates of the app that expire within the given days
  defp tls(status, within) do
    for %{expires_in_days: days} <-
          status.children |> Enum.flat_map(&(&1.certificates || [])) |> Enum.uniq(),
        is_integer(days) and days <= within do
      %{
        tone: if(days <= 7, do: :error, else: :warning),
        text: "TLS certificate expires in #{days} days"
      }
    end
  end

  # A crash in the last hour is a problem. An older one stays in the notes and the restart count
  defp recent_crashes(instances, now) do
    for %{last_crash_at: %DateTime{} = at} = instance <- instances,
        DateTime.diff(now, at) < 3_600 do
      "#{instance.sname} crashed at #{Calendar.strftime(at, "%H:%M")}"
    end
  end

  defp notes(status, instances) do
    tls = tls(status, @tls_warn_days)

    near =
      for instance <- instances, warning <- instance.warnings do
        %{tone: :warning, text: "#{instance.sname} #{warning}"}
      end

    crashes =
      for %{last_crash_at: %DateTime{} = at} = instance <- instances do
        %{
          tone: :warning,
          text: "#{instance.sname} crash restart at #{Calendar.strftime(at, "%H:%M")}"
        }
      end

    Enum.uniq(tls) ++ near ++ crashes
  end

  defp app_status(running, total, children) do
    cond do
      total > 0 and running == total ->
        %{text: "#{running}/#{total} running", tone: :success}

      Enum.any?(children, &(&1.status in [:starting, :pre_commands])) ->
        %{text: "#{running}/#{total} running", tone: :warning}

      running == 0 ->
        %{text: "0/#{total} running", tone: :error}

      true ->
        %{text: "#{running}/#{total} running", tone: :warning}
    end
  end

  defp instance_status(:running), do: %{text: "running", tone: :success}
  defp instance_status(:starting), do: %{text: "starting", tone: :warning}
  defp instance_status(:pre_commands), do: %{text: "pre_commands", tone: :warning}
  defp instance_status(_status), do: %{text: "stopped", tone: :error}

  defp sub(status) do
    child = Enum.find(status.children, &(&1.status == :running)) || List.first(status.children)

    parts =
      case child do
        nil ->
          ["no version"]

        child ->
          [
            child.version || "no version",
            child.otp_version && "OTP #{child.otp_version}",
            status.language == "elixir" && child.elixir_version &&
              "Elixir #{child.elixir_version}"
          ]
      end

    parts |> Enum.filter(&is_binary/1) |> Enum.join(" · ")
  end

  defp running_version(status) do
    case Enum.find(status.children, &(&1.status == :running)) do
      %{version: version} when is_binary(version) -> version
      _ -> "The current version"
    end
  end

  # One count for the board, amber only for crashes, with a tooltip that tells crashes from the restarts an
  # operator or the watchdog asked for
  defp restarts(children) do
    crash = Enum.reduce(children, 0, &(&1.crash_restart_count + &2))
    forced = Enum.reduce(children, 0, &(&1.force_restart_count + &2))

    last_crash =
      children
      |> Enum.map(& &1.last_crash_at)
      |> Enum.reject(&is_nil/1)
      |> Enum.max(DateTime, fn -> nil end)

    lines =
      [
        crash > 0 && crash_text(crash, last_crash),
        forced > 0 && "#{count(forced, "restart")} by an operator or the watchdog"
      ]
      |> Enum.filter(& &1)

    %{
      count: crash + forced,
      crash: crash > 0,
      lines: if(lines == [], do: ["No restarts"], else: lines)
    }
  end

  defp crash_text(crash, nil), do: count(crash, "crash restart")

  defp crash_text(crash, at),
    do: "#{count(crash, "crash restart")}, the last at #{Calendar.strftime(at, "%H:%M")}"

  defp count(1, noun), do: "1 #{noun}"
  defp count(n, noun), do: "#{n} #{noun}s"

  defp sum_text(instances, key, format) do
    case instances |> Enum.map(&Map.get(&1, key)) |> Enum.reject(&is_nil/1) do
      [] -> "--"
      values -> format.(Enum.sum(values))
    end
  end

  @doc """
  A time in milliseconds in words, in the largest whole unit, like "5 seconds" or "10 minutes".
  """
  @spec duration(pos_integer()) :: String.t()
  def duration(ms) when rem(ms, 3_600_000) == 0, do: count(div(ms, 3_600_000), "hour")
  def duration(ms) when rem(ms, 60_000) == 0, do: count(div(ms, 60_000), "minute")
  def duration(ms) when rem(ms, 1_000) == 0, do: count(div(ms, 1_000), "second")
  def duration(ms), do: count(ms, "millisecond")

  @doc false
  def bytes(bytes) when bytes >= 1_073_741_824,
    do: "#{:erlang.float_to_binary(bytes / 1_073_741_824, decimals: 1)} GB"

  def bytes(bytes), do: "#{div(bytes, 1_048_576)} MB"

  @doc false
  def age(nil, _now), do: nil

  def age(at, now) do
    seconds = max(DateTime.diff(now, at), 0)

    cond do
      seconds < 60 -> "now"
      seconds < 3_600 -> "#{div(seconds, 60)}m ago"
      seconds < 86_400 -> "#{div(seconds, 3_600)}h ago"
      true -> "#{div(seconds, 86_400)}d ago"
    end
  end

  defp up_text(nil), do: nil
  defp up_text(uptime), do: String.replace_suffix(uptime, " ago", "")

  defp number(value),
    do: value |> Integer.to_string() |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")

  defp language_name("elixir"), do: "Elixir"
  defp language_name("erlang"), do: "Erlang"
  defp language_name("gleam"), do: "Gleam"
  defp language_name(other), do: to_string(other)

  defp system(%Host.Info{host: host, description: description})
       when is_binary(host) and host != "" do
    arch = :erlang.system_info(:system_architecture) |> to_string() |> String.split("-") |> hd()

    # macOS reports only its version, like 15.7.4, so the name goes in front of it
    os =
      case description do
        <<digit, _rest::binary>> when digit in ?0..?9 -> "#{host} #{description}"
        description when description in [nil, ""] -> host
        description -> description
      end

    "#{os} · #{arch}"
  end

  defp system(_host_info), do: "--"

  defp system_icon(%Host.Info{host: host}) when is_binary(host) do
    if String.contains?(String.downcase(host), "mac"), do: "macos", else: "linux"
  end

  defp system_icon(_host_info), do: "linux"

  defp up(%Host.Info{uptime: uptime}) when is_binary(uptime), do: uptime
  defp up(_host_info), do: "--"
end
