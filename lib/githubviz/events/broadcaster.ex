defmodule GithubViz.Events.Broadcaster do
  @moduledoc ~S"""
  Broadcasts `GithubViz.Event`s to all consumers.
  """

  use GenStage

  defstruct []

  def start_link do
    GenStage.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    {:producer_consumer, %__MODULE__{}, subscribe_to: [GithubViz.Events.Deduplicator], dispatcher: GenStage.BroadcastDispatcher}
  end

  def handle_events(events, _from, state) do
    {:noreply, events, state}
  end
end
