defmodule GithubViz.Stream.Deduplicator do
  @moduledoc ~S"""
  Filters out previously seen events.
  """

  use GenStage

  alias GithubViz.Metrics, as: M

  # We use a simple bitset to check if we've seen an event before. This scales
  # really well because Github uses monotonically increasing integers as a
  # unique identifiers. This has the added (and much needed) guarantee of
  # assuring we always identify duplicates, rather than identifying
  # duplicates for a small period time.
  alias GithubViz.Stream.Deduplicator.Bitset

  defstruct []

  def start_link do
    GenStage.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    sources = [GithubViz.Stream.Collector, GithubViz.Stream.Replayer]
    {:producer_consumer, %__MODULE__{}, subscribe_to: sources}
  end

  # BUG(mtwilliams): Erroneously deduplicates `code.pushes` and `code.commits`
  # messages as they share the same identifier.
  def handle_events(events, _from, state) do
    {:ok, seen_or_not} = Enum.map(events, &(&1.id))
                      |> Bitset.set

    unseen = Enum.zip(events, seen_or_not)
          |> Enum.filter_map(&(elem(&1, 1) == 0), &elem(&1, 0))

    M.count("events.duplicate", length(events) - length(unseen))

    {:noreply, unseen, state}
  end
end

defmodule GithubViz.Stream.Deduplicator.Bitset do
  @moduledoc ~S"""
  Wraps a bitset for `GithubViz.Stream.Deduplicator` lest it crashes or takes a
  while to perform an operation.
  """

  use GenServer

  #
  # Client
  #

  def get(bits) do
    GenServer.call(__MODULE__, {:get, bits})
  end

  def set(bits) do
    GenServer.call(__MODULE__, {:set, bits})
  end

  #
  # Server
  #

  require Logger
  alias Logger, as: L

  defstruct [
    path: nil,
    bitset: nil
  ]

  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    {path, config} = Keyword.pop(config(), :path)
    path = Path.expand(path)

    L.info "Deduplicator bitset stored at `#{path}`..."
    {:ok, bitset} = GithubViz.Bitset.open(path, config)

    Process.flag(:trap_exit, true)

    {:ok, %__MODULE__{path: path, bitset: bitset}}
  end

  defp config do
    Application.get_env(:githubviz_stream, :deduplicator, [])
    |> Keyword.fetch!(:bitset)
  end

  def handle_call({:get, bits}, _from, state) do
    result = GithubViz.Bitset.get(state.bitset, bits)
    {:reply, result, state}
  end

  def handle_call({:set, bits}, _from, state) do
    with {:ok, previous} <- GithubViz.Bitset.get(state.bitset, bits),
         :ok <- GithubViz.Bitset.set(state.bitset, bits)
    do
      {:reply, {:ok, previous}, state}
    else
      result ->
        {:reply, result, state}
    end
  end

  def terminate(:normal, state), do: flush(state.bitset)
  def terminate(:shutdown, state), do: flush(state.bitset)
  def terminate({:shutdown, _}, state), do: flush(state.bitset)

  def terminate(_, state) do
    path = "#{state.path}.dirty"
    L.warn "Flushing deduplicator's bitset to `#{path}`!"
    :ok = GithubViz.Bitset.close(state.bitset)
    :ok = File.rename(state.path, path)
  end

  defp flush(bitset) do
    L.info "Flushing deduplicator's bitset to disk..."
    :ok = GithubViz.Bitset.close(bitset)
  end
end
