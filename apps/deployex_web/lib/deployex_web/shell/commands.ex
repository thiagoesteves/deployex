defmodule DeployexWeb.Shell.Commands do
  @moduledoc """
  The command that each shell session runs: tmux on the host, or a remote shell into an instance's node.
  """

  alias DeployexWeb.Shell
  alias DeployexWeb.Shell.Session
  alias Foundation.Catalog
  alias Foundation.Common
  alias Host.Commander

  @rows 24
  @cols 80

  @doc """
  Returns the command, its erlexec options and what the session shows for the target.
  """
  @spec build(target :: String.t(), id :: String.t()) ::
          {:ok, map()} | {:error, :binary_not_found | :unknown_target}
  def build(target, id) do
    if target == Shell.host(), do: host_shell(id), else: remote_shell(target)
  end

  @doc """
  Removes what the session left on the host. The host shell's tmux session would keep running.
  """
  @spec cleanup(Session.t()) :: :ok
  def cleanup(%Session{kind: :host_shell, id: id}) do
    Commander.run("tmux kill-session -t #{tmux_session(id)}", [:sync])
    :ok
  end

  def cleanup(_session), do: :ok

  defp host_shell(id) do
    tmux_config_path = "#{:code.priv_dir(:deployex_web)}/static/.tmux.conf"
    name = tmux_session(id)

    {:ok,
     %{
       commands: """
       tmux new-session -s #{name} -d
       tmux source-file #{tmux_config_path} -t #{name}
       tmux attach -t #{name}
       """,
       options: options(),
       kind: :host_shell,
       language: "linux",
       command: "tmux on host · user #{System.get_env("USER", "deployex")}"
     }}
  end

  defp remote_shell(sname) do
    with %{hostname: hostname, language: language} <- Catalog.node_info(sname),
         bin_path = Catalog.bin_path(sname, :current),
         true <- File.exists?(bin_path) || {:error, :binary_not_found} do
      path = Common.remove_deployex_from_path()
      cookie = Common.shell_quote(Common.cookie())

      ssl_options =
        if Common.mtls_certificate(),
          do: "-proto_dist inet_tls -ssl_dist_optfile /tmp/inet_tls.conf",
          else: ""

      {commands, command} =
        remote_commands(sname, language, hostname, bin_path, path, cookie, ssl_options)

      {:ok,
       %{
         commands: commands,
         options: options(),
         kind: if(language == "elixir" or sname == "deployex", do: :iex, else: :erlang_shell),
         language: if(sname == "deployex", do: "elixir", else: language),
         command: command
       }}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :unknown_target}
    end
  end

  defp remote_commands("deployex", _language, _hostname, bin_path, path, cookie, _ssl_options) do
    {"""
     unset $(env | grep '^RELEASE_' | awk -F'=' '{print $1}')
     unset BINDIR ELIXIR_ERL_OPTIONS ROOTDIR
     export PATH=#{path}
     export RELEASE_COOKIE=#{cookie}
     #{bin_path} remote
     """, "bin/deployex remote"}
  end

  defp remote_commands(sname, "gleam", hostname, _bin_path, path, cookie, ssl_options) do
    {"""
     unset $(env | grep -E '^(RELEASE|DEPLOYEX)_' | awk -F'=' '{print $1}')
     unset BINDIR ELIXIR_ERL_OPTIONS ROOTDIR
     export PATH=#{path}
     erl -remsh #{sname}@#{hostname} -setcookie #{cookie} #{ssl_options}
     """, "erl -remsh #{sname}@#{hostname}"}
  end

  defp remote_commands(sname, "erlang", _hostname, bin_path, path, cookie, ssl_options) do
    {"""
     unset $(env | grep -E '^(RELEASE|DEPLOYEX)_' | awk -F'=' '{print $1}')
     unset BINDIR ELIXIR_ERL_OPTIONS ROOTDIR
     export PATH=#{path}
     export RELX_REPLACE_OS_VARS=true
     export RELEASE_NODE=#{sname}
     export RELEASE_COOKIE=#{cookie}
     export RELEASE_SSL_OPTIONS=\"#{ssl_options}\"
     #{bin_path} remote_console
     """, "bin/#{app_name(sname)} remote_console"}
  end

  defp remote_commands(sname, _elixir, _hostname, bin_path, path, cookie, _ssl_options) do
    {"""
     unset $(env | grep -E '^(RELEASE|DEPLOYEX)_' | awk -F'=' '{print $1}')
     unset BINDIR ELIXIR_ERL_OPTIONS ROOTDIR
     export PATH=#{path}
     export RELEASE_NODE=#{sname}
     export RELEASE_COOKIE=#{cookie}
     #{bin_path} remote
     """, "bin/#{app_name(sname)} remote"}
  end

  # Set the PTY size explicitly, erlexec leaves it undefined without winsz. The page resizes it when it attaches
  defp options, do: [:stdin, :stdout, :pty, :pty_echo, {:winsz, {@rows, @cols}}]

  defp tmux_session(id), do: "DeployEx-#{id}"

  defp app_name(sname), do: sname |> String.split("-") |> hd()
end
