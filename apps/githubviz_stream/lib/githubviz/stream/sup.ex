defmodule GithubViz.Stream.Supervisor do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, name: __MODULE__)
  end

  def init(_options) do
    children = [
      worker(GithubViz.Stream.Collector, [], restart: :permanent),
      worker(GithubViz.Stream.Replayer, [], restart: :permanent),
      worker(GithubViz.Stream.Deduplicator.Bitset, [], restart: :permanent),
      worker(GithubViz.Stream.Deduplicator, [], restart: :permanent),
      worker(GithubViz.Stream.Broadcaster, [], restart: :permanent),
      worker(GithubViz.Stream.Statistics, [], restart: :permanent)
    ]

    supervise(children, strategy: :one_for_one)
  end
end
