defmodule GithubViz.Bitset do
  @moduledoc ~S"""
  Our custom resizeable, out-of-core, file-backed bitset.
  """

  @type t :: reference()

  @type bit :: non_neg_integer
  @type state :: 0 | 1

  @type error :: {:error, :not_a_bitset} |
                 {:error, :unsupported} |
                 {:error, :permissions} |
                 {:error, :out_of_memory} |
                 {:error, :out_of_storage} |
                 {:error, :uknown}

  @spec open(path :: Path.t, options :: [{:size, non_neg_integer}]) :: {:ok, t} | error
  @doc """
  Opens or creates a new file-backed bitset.

  ## Options

    * `:size` – the initial number of bits to size or resize the bitset to.
  """
  def open(path, options \\ []), do: stub()

  @spec close(bitset :: t) :: :ok
  @doc """
  Closes a bitset, making sure to persist changes to the backing file.
  """
  def close(bitset), do: stub()

  @spec delete(bitset :: t) :: :ok
  @doc """
  Closes a bitset and deletes the backing file.
  """
  def delete(bitset), do: stub()

  @spec get(bitset :: t, bits :: [bit]) :: {:ok, [state]} | error
  @doc """
  Gets the state of every bit in `bits`.

  Resizes the bitset to encompass the largest bit specified in `bits` if it is
  too small.
  """
  def get(bitset, bits) when is_list(bits), do: stub()

  @spec set(bitset :: t, bits :: [bit]) :: :ok | error
  @doc """
  Sets every bit in `bits`.

  Resizes the bitset to encompass the largest bit specified in `bits` if it is
  too small.
  """
  def set(bitset, bits) when is_list(bits), do: stub()

  @spec unset(bitset :: t, bits :: [bit]) :: :ok | error
  @doc """
  Unsets every bit in `bits`.

  Resizes the bitset to encompass the largest bit specified in `bits` if it is
  too small.
  """
  def unset(bitset, bits) when is_list(bits), do: stub()

  @on_load :init

  @doc false
  def init do
    nif = Path.join(:code.priv_dir(:githubviz), "bitset")
    :ok = :erlang.load_nif(nif, 0)
  end

  defp stub, do: :erlang.nif_error("Not loaded!")
end
