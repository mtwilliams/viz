defmodule GithubViz.Supervisor do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, name: __MODULE__)
  end

  def init(_options) do
    children = [
    ]

    supervise(children, strategy: :one_for_one)
  end
end
