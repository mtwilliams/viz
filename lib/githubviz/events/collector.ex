# TOOD(mtwilliams): Use a circuit breaker, or at the very least backoff, if
# fetching fails.

defmodule GithubViz.Events.Collector do
  @moduledoc ~S"""
  Periodically polls Github for new events.
  """

  use GenStage

  require Logger
  alias Logger, as: L

  @pages 10

  defstruct [
    demand: 0,

    # Amount of time, in seconds, we wait between requests.
    interval: 60,

    # Last seen entity tags by page.
    etags: %{}
  ]

  def start_link do
    GenStage.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    for page <- 1..@pages, do: send(self(), {:fetch, page})
    {:producer, %__MODULE__{}}
  end

  def handle_demand(demand, state) do
    {:noreply, [], %__MODULE__{state | demand: state.demand + demand}}
  end

  @user_agent Application.get_env(:github_viz, :user_agent, "Elixir/#{System.version()}")

  @client_id Application.get_env(:github_viz, :client_id)
  @client_secret Application.get_env(:github_viz, :client_secret)

  def handle_info({:fetch, page}, state) do
    L.debug "fetching #{page}/#{@pages}, etag=#{state.etags[page] || "<none>"}"

    collector = self()

    # TODO(mtwilliams): Spawn an unlinked process and monitor.
    Task.async(fn ->
      headers = [
        {"User-Agent", @user_agent},
        {"If-None-Match", state.etags[page]}
      ]

      params = [
        page: page,
        client_id: @client_id,
        client_secret: @client_secret
      ]

      {:ok, response} =
        HTTPoison.get("https://api.github.com/events", headers, params: params)

      {:fetched, page, response}
    end)

    {:noreply, [], state}
  end

  def handle_info({_, {:fetched, page, response}}, state) do
    headers = response.headers |> Map.new

    etag = Map.get(headers, "ETag")
    {interval, _} = Map.fetch!(headers, "X-Poll-Interval") |> Integer.parse
    {remaining, _} = Map.fetch!(headers, "X-RateLimit-Remaining") |> Integer.parse
    {reset, _} = Map.fetch!(headers, "X-RateLimit-Reset") |> Integer.parse
    delta = reset - System.system_time(:seconds)

    events = extract(response)
    supply = length(events)

    L.debug "fetched #{page}/#{@pages}, demand=#{state.demand} events=#{supply} interval=#{interval}s remaining=#{remaining} reset=#{delta}"

    Process.send_after(self(), {:fetch, page}, interval * 1_000 + page)

    {:noreply, events, %__MODULE__{
      state | demand: max(state.demand - supply, 0),
              interval: interval,
              etags: Map.put(state.etags, page, etag || state.etags[page])
    }}
  end

  def handle_info({:DOWN, _, _, _, :normal}, state) do
    {:noreply, [], state}
  end

  defp extract(%HTTPoison.Response{status_code: 304} = _response) do
    []
  end

  defp extract(%HTTPoison.Response{status_code: 200} = response) do
    response.body
    |> Poison.decode!
    |> Enum.flat_map(&GithubViz.Event.Parser.parse/1)
  end
end
