defmodule GithubViz.Events.Enricher do
  @moduledoc ~S"""
  Tags every `GithubViz.Event` with related programming languages.
  """

  use GenStage

  defstruct [
    # Cached list of the related programming languages for repositories.
    cache: nil
  ]

  def start_link do
    GenStage.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    {:producer_consumer, %__MODULE__{}, subscribe_to: [GithubViz.Events.Collector]}
  end

  def handle_events(events, _from, state) do
    # TODO(mtwilliams): Enrich events.
    {:noreply, events, state}
  end
end
