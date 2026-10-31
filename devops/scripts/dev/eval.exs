# Evaluates a dev script on the DeployEx node that `make start` runs, with `count` bound to the second
# argument: elixir --sname <name> --cookie <cookie> eval.exs <script> [count]
[script | rest] = System.argv()
[_name, host] = node() |> Atom.to_string() |> String.split("@")
target = :"deployex@#{host}"

if Node.connect(target) do
  count = rest |> List.first("19") |> String.to_integer()
  binding = [count: count]

  {message, _binding} =
    :erpc.call(target, Code, :eval_string, [File.read!(script), binding, [file: script]])

  IO.puts(message)
else
  IO.puts("DeployEx is not running. Start it with make start, then run this again.")
  System.halt(1)
end
