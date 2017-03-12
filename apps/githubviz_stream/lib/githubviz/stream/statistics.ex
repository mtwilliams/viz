defmodule GithubViz.Stream.Statistics do
  @moduledoc ~S"""
  Reports metrics about our event stream.
  """

  use GenStage

  defstruct []

  def start_link do
    GenStage.start_link(__MODULE__, [], name: __MODULE__)
  end

  alias GithubViz.Metrics, as: M

  def init([]) do
    # TODO(mtwilliams): Allow subscriptions to `GithubViz.Stream.Broadcaster`
    # that don't create demand, thereby allowing passive observers.
    {:consumer, %__MODULE__{}, subscribe_to: [GithubViz.Stream.Broadcaster]}
  end

  def handle_events(events, _from, state) do
    M.count("events.all", length(events))

    for {type, count} <- total(events) do
      M.count("events.#{type}", count)
    end

    {:noreply, [], state}
  end

  defp total(events) do
    Enum.reduce events, %{}, fn (event, totals) ->
      Map.put(totals, event.type, Map.get(totals, event.type, 0) + 1)
    end
  end
end
