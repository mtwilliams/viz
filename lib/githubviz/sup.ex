defmodule GithubViz.Supervisor do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, name: __MODULE__)
  end

  def init(_options) do
    children = [
      worker(GithubViz.Events.Collector, [], restart: :permanent),
      worker(GithubViz.Events.Deduplicator, [], restart: :permanent),
      worker(GithubViz.Events.Enricher, [], restart: :permanent),
      worker(GithubViz.StatisticsReporter, [], restart: :permanent)
    ]

    supervise(children, strategy: :one_for_one)
  end
end
