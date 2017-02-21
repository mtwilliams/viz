defmodule GithubViz.Events.Collector do
  @moduledoc ~S"""
  Periodically polls Github for new events.
  """

  use GenStage

  # NOTE(mtwilliams): I've hardcoded these rather than parsing the `Link`
  # headers Github returns. While this isn't conforming to Github's guidelines,
  # it probably won't break. Fingers crossed.
  @pages 3
  @events_per_page 100

  defstruct [
    # Amount of time (in seconds) we wait between requests. This varies at
    # Github's behest, as our way of being respectful.
    interval: 60,

    # Last seen entity tags for each page.
    etags: %{}
  ]

  def start_link do
    GenStage.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    for page <- 1..@pages do
      send(self(), {:fetch, page})
    end

    {:producer, %__MODULE__{}}
  end

  def handle_info({:fetch, page}, state) do
    spawn fn ->
      headers = %{"If-None-Match" => state.etags[page]}
      parameters = %{page: page, per_page: @events_per_page}
      {:ok, response} = GithubViz.Github.get("/events", headers, parameters)
      send(__MODULE__, {:fetched, page, response})
    end

    {:noreply, [], state}
  end

  def handle_info({:fetched, page, {status, headers, body} = response}, state) do
    # TODO(mtwilliams): Track these metrics.
    # {limit, _} = Map.fetch!(headers, "X-RateLimit-Limit") |> Integer.parse
    # {remaining, _} = Map.fetch!(headers, "X-RateLimit-Remaining") |> Integer.parse
    # {reset, _} = Map.fetch!(headers, "X-RateLimit-Reset") |> Integer.parse
    # delta = reset - System.system_time(:seconds)

    {interval, _} = Map.fetch!(headers, "X-Poll-Interval") |> Integer.parse
    etag = Map.get(headers, "ETag")

    events = extract(response)

    # TODO(mtwilliams): Try fetching quicker than the suggested interval? We
    # might be missing events. Although it's not respectful, it isn't
    # unprecedented...

    # Nomially, we'll fetch the page again in 60 seconds.
    Process.send_after(__MODULE__, {:fetch, page}, interval * 1_000)

    {:noreply, events, %__MODULE__{
      state | interval: interval,
              etags: Map.put(state.etags, page, etag)
    }}
  end

  def handle_demand(_demand, state) do
    {:noreply, [], state}
  end

  defp extract({200, _, body}) do
    body |> Poison.decode! |> Enum.flat_map(&GithubViz.Event.Parser.parse/1)
  end

  defp extract({304, _, _}) do
    []
  end
end
