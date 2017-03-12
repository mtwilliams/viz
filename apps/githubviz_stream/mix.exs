defmodule GithubViz.Stream.Mixfile do
  use Mix.Project

  def project do [
    app: :githubviz_stream,
    version: "0.0.0",
    elixir: "~> 1.4",
    compilers: ~W{elixir app}a,
    config_path: "../../config/config.exs",
    build_path: "../../_build",
    deps_path: "../../_deps",
    lockfile: "../../mix.lock",
    build_embedded: Mix.env == :prod,
    start_permanent: Mix.env == :prod,
    deps: deps()
  ] end

  def application do [
    mod: {GithubViz.Stream, []},
    env: []
  ] end

  defp deps do [
    {:githubviz, in_umbrella: true},

    # Infrastructure
    {:gen_stage, "~> 0.11"}
  ] end
end
