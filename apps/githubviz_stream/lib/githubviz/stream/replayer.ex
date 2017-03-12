defmodule GithubViz.Stream.Replayer do
  @moduledoc ~S"""
  Replays events from the [GithubArchive](https://www.githubarchive.org).
  """

  use GenStage

  defstruct []

  def start_link do
    GenStage.start_link(__MODULE__, [], name: __MODULE__)
  end

  alias GithubViz.Metrics, as: M

  def init([]) do
    {:producer, %__MODULE__{}}
  end

  def handle_demand(_demand, state) do
    {:noreply, [], state}
  end
end
