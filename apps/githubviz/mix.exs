defmodule GithubViz.Mixfile do
  use Mix.Project

  def project do [
    app: :githubviz,
    version: "0.0.0",
    elixir: "~> 1.4",
    compilers: ~W{nif elixir app}a,
    aliases: aliases(),
    config_path: "../../config/config.exs",
    build_path: "../../_build",
    deps_path: "../../_deps",
    lockfile: "../../mix.lock",
    build_embedded: Mix.env == :prod,
    start_permanent: Mix.env == :prod,
    deps: deps()
  ] end

  def application do [
    mod: {GithubViz, []},
    extra_applications: [:logger],
    env: []
  ] end

  defp aliases do [
    clean: ["clean", "clean.nif"]
  ] end

  defp deps do [
    # Basics
    {:poison, "~> 3.1"},
    {:httpoison, "~> 0.11"},

    # Metrics
  ] end
end

defmodule Mix.Tasks.Compile.Nif do
  @shortdoc "Compiles native code in `c_src`"

  use Mix.Task

  def run(_args) do
    success = run_in_dir(__DIR__, fn ->
      Mix.shell.cmd(cmd()) == 0
    end)

    unless success do
      Mix.raise "Could not compile native code!"
    end
  end

  defp cmd do
    case :os.type do
      {:win32, _} ->
        "nmake /F Makefile.win"
      {:unix, type} when type in ~W{freebsd openbsd} ->
        "gmake"
      _ ->
        "make"
    end
  end

  defp run_in_dir(directory, fun) do
    {:ok, previous_working_dir} = File.cwd()
    :ok = File.cd(directory)
    result = fun.()
    :ok = File.cd(previous_working_dir)
    result
  end
end

defmodule Mix.Tasks.Clean.Nif do
  @shortdoc "Cleans native code build artifacts"

  use Mix.Task

  def run(_args) do
    run_in_dir(__DIR__, fn ->
      Mix.shell.cmd(cmd())
    end)

    :ok
  end

  defp cmd do
    case :os.type do
      {:win32, _} ->
        "nmake /F Makefile.win clean"
      {:unix, type} when type in ~W{freebsd openbsd} ->
        "gmake clean"
      _ ->
        "make clean"
    end
  end

  defp run_in_dir(directory, fun) do
    {:ok, previous_working_dir} = File.cwd()
    :ok = File.cd(directory)
    result = fun.()
    :ok = File.cd(previous_working_dir)
    result
  end
end
