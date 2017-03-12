defmodule GithubViz.Metrics do
  @moduledoc ~S"""
  Metrics!

  We have two types of metrics: counters and gauges.

  ### Counters

  Counters are integers that can be incremented and decremented by an arbitrary
  amount.

  See `count/2`.

  ### Gauges

  Gauges are point-in-time scalar values.

  See `sample/2` and `time/3`.
  """

  @type metric :: string

  @spec count(metric :: metric, value :: pos_integer) :: no_return
  @doc "Increments or decrements a counter by `value`."
  def count(_, 0) do end
  def count(metric, value \\ 1) do end

  @spec sample(metric :: metric, value :: number) :: no_return
  @doc "Reports a sample `value`."
  def sample(metric, value) do end

  @type resolution :: :second | :millisecond | :microsecond | :nanosecond
  @spec time(metric :: metric, options :: [{:resolution, resolution}], fun :: fun) :: any
  @doc """
  Samples the runtime of `fun`.

  ## Options

    * `:resolution` – what unit of time to report in. Can be `:second`,
      `:millisecond`, `:microsecond`, or `:nanosecond`.
      Defaults to `:millisecond`.
  """
  def time(metric, options \\ [], fun) do
    resolution = Keyword.get(options, :resolution, :millisecond)

    start  = :erlang.monotonic_time(resolution)
    result = nil

    try do
      result = fun.()
    after
      duration = :erlang.monotonic_time(resolution) - start
      sample(metric, duration)
    end

    result
  end
end
