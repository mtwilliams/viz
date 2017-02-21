defmodule GithubViz.Events.Deduplicator do
  @moduledoc ~S"""
  Removes duplicated events.
  """

  use GenStage

  # NOTE(mtwilliams): I've hardcoded this rather than adjusting it based on
  # the number of duplicates in real-time. This should work fine. More
  # extensive testing during peak times is required.
  @window 300

  defstruct [
    seen: {MapSet.new, MapSet.new}
  ]

  def start_link do
    GenStage.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    {:producer_consumer, %__MODULE__{}, subscribe_to: [GithubViz.Events.Collector]}
  end

  def handle_events(events, _from, state) do
    unseen = Enum.reject(events, &(seen?(&1, state.seen)))
    seen = note(unseen, state.seen)
    {:noreply, unseen, %__MODULE__{state | seen: seen}}
  end

  defp seen?(event, {seen, prev_seen}) do
    MapSet.member?(prev_seen, event.id) or MapSet.member?(seen, event.id)
  end

  defp note(unseen, {seen, prev_seen}) do
    just_seen = unseen |> Enum.map(&(&1.id)) |> MapSet.new
    new_seen = MapSet.union(just_seen, seen)

    if MapSet.size(new_seen) >= @window do
      {MapSet.new, new_seen}
    else
      {seen, prev_seen}
    end
  end
end
