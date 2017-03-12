defmodule GithubViz.Stream.Broadcaster do
  @moduledoc ~S"""
  Broadcasts events to all consumers.
  """

  use GenStage

  defstruct []

  def start_link do
    GenStage.start_link(__MODULE__, [], name: __MODULE__)
  end

  alias GithubViz.Metrics, as: M

  def init([]) do
    {:producer_consumer, %__MODULE__{}, subscribe_to: [GithubViz.Stream.Deduplicator], dispatcher: GenStage.BroadcastDispatcher}
  end

  def handle_events(events, _from, state) do
    {:noreply, events, state}
  end
end
