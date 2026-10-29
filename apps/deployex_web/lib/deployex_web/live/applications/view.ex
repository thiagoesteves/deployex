defmodule DeployexWeb.ApplicationsLive.View do
  @moduledoc """
  Turns the status of this host's applications into what the Applications page shows: the This host card,
  one row per application, its instances, their limits, and the problems that need an action.
  """

  alias Deployer.Resources
  alias Deployer.Resources.Limit

  @limit_warn 80
  @limit_alert 90
  # A count that grew this much is a trend worth a note, when the series covers this many minutes
  @trend_percent 10
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
    |> Enum.map(&app(&1, now))
  end

  @doc """
  The number of applications with a problem that blocks them.
  """
  @spec attention([map()]) :: non_neg_integer()
  def attention(apps), do: Enum.count(apps, &(&1.alert != nil and &1.alert.blocking))

  defp app(status, now) do
    instances = Enum.map(status.children, &instance(&1, status.language, now))
    running = Enum.count(status.children, &(&1.status == :running))
    total = max(status.replicas, length(status.children))
    problems = Enum.flat_map(instances, & &1.warnings)
    ghosted = ghosted(status, instances)

    restarts =
      Enum.reduce(status.children, 0, &(&1.crash_restart_count + &1.force_restart_count + &2))

    %{
      name: status.name,
      language: status.language,
      language_name: language_name(status.language),
      sub: sub(status),
      status: app_status(running, total, status.children),
      problems: problems,
      cpu: sum_text(instances, :cpu_value, &"#{&1}%"),
      memory: sum_text(instances, :memory_value, &bytes/1),
      restarts: restarts,
      restarts_title: restarts_title(status.children),
      deploy: deploy(status, ghosted, now),
      alert: alert(status, ghosted, running),
      notes: notes(status, instances),
      instances: instances
    }
  end

  defp instance(child, language, now) do
    resources = child.resources
    limits = limits(resources)
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
      restarts: child.crash_restart_count + child.force_restart_count,
      restarts_title: "#{child.crash_restart_count} crash, #{child.force_restart_count} forced",
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

  defp limits(%Resources{} = resources) do
    for {name, %Limit{} = limit} <- [
          {"Processes", resources.process},
          {"Ports", resources.port},
          {"Atoms", resources.atom}
        ] do
      limit_row(name, limit)
    end
  end

  defp limits(_resources), do: []

  defp limit_row(name, limit) do
    level = level(limit.percent)
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
      warning: limit_warning(String.downcase(name), limit.percent, level, trend)
    }
  end

  defp level(percent) when percent >= @limit_alert, do: 2
  defp level(percent) when percent >= @limit_warn, do: 1
  defp level(_percent), do: 0

  defp limit_warning(name, percent, level, _trend) when level > 0,
    do: ["#{name} at #{percent}% of the limit"]

  defp limit_warning(name, _percent, _level, trend) when is_binary(trend),
    do: ["#{name} #{trend}"]

  defp limit_warning(_name, _percent, _level, _trend), do: []

  defp trend(%Limit{change_percent: change, change_minutes: minutes})
       when is_integer(change) and change >= @trend_percent and minutes >= @trend_minutes do
    over = if minutes >= 60, do: "1 hour", else: "#{minutes} minutes"
    "+#{change}% in #{over}"
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

  defp notes(status, instances) do
    tls =
      for %{expires_in_days: days} <-
            status.children |> Enum.flat_map(&(&1.certificates || [])) |> Enum.uniq(),
          is_integer(days) and days <= @tls_warn_days do
        %{
          tone: if(days <= 7, do: :error, else: :warning),
          text: "TLS certificate expires in #{days} days"
        }
      end

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

  defp restarts_title(children) do
    crash = Enum.reduce(children, 0, &(&1.crash_restart_count + &2))
    forced = Enum.reduce(children, 0, &(&1.force_restart_count + &2))
    "#{crash} crash, #{forced} forced"
  end

  defp sum_text(instances, key, format) do
    case instances |> Enum.map(&Map.get(&1, key)) |> Enum.reject(&is_nil/1) do
      [] -> "--"
      values -> format.(Enum.sum(values))
    end
  end

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
