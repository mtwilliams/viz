defmodule GithubViz.StatisticsReporter do
  @moduledoc ~S"""
  Logs a breakdown of events by type.
  """

  use GenStage

  require Logger
  alias Logger, as: L

  @events ~W{repos.created repos.forked repos.open_sourced code.pushes
             code.commits issues.opened issues.reopened issues.closed
             pull_requests.opened pull_requests.reopened pull_requests.closed
             comments.commit comments.issue comments.review collaborators.added
             collaborators.removed wiki.edits releases}a

  defstruct [
    totals: @events |> Enum.map(&{&1, 0}) |> Map.new,
    all: 0
  ]

  def start_link do
    GenStage.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    {:consumer, %__MODULE__{}, subscribe_to: [GithubViz.Events.Broadcaster]}
  end

  def handle_events(events, _from, state) do
    all = state.all + Enum.count(events)

    totals =
      Enum.reduce(events, state.totals, fn (event, totals) ->
        Map.put(totals, event.type, totals[event.type] + 1)
      end)

    @events
    |> Enum.map(&"#{&1}=#{totals[&1]}")
    |> Enum.concat(["all=#{all}"])
    |> Enum.join(" ")
    |> L.info

    {:noreply, [], %__MODULE__{state | totals: totals, all: all}}
  end
end
