defmodule GithubViz.Mixfile do
  use Mix.Project

  def project do [
    app: :github_viz,
    version: "0.0.0",
    elixir: "~> 1.4",
    config_path: "config/config.exs",
    build_path: "_build",
    deps_path: "_deps",
    lockfile: "mix.lock",
    build_embedded: Mix.env == :prod,
    start_permanent: Mix.env == :prod,
    deps: deps()
  ] end

  def application do [
    mod: {GithubViz, []},
    extra_applications: [:logger],
    env: []
  ] end

  defp deps do [
    # Basics
    {:poison, "~> 3.1"},
    {:httpoison, "~> 0.11"}
  ] end
end
