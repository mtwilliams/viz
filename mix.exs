defmodule GithubViz.Umbrella.Mixfile do
  use Mix.Project

  def project do [
    name: "GithubViz",
    version: "0.0.0",
    apps_path: "apps",
    config_path: "config/config.exs",
    build_path: "_build",
    deps_path: "_deps",
    lockfile: "mix.lock",
    build_embedded: Mix.env == :prod,
    start_permanent: Mix.env == :prod,
    deps: []
  ] end
end
