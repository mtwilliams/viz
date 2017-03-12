defmodule GithubViz.Bitset.Test do
  use ExUnit.Case, async: false

  test "open and close" do
    name = temporary()
    {:ok, bitset} = GithubViz.Bitset.open(name, size: 0)
    :ok = GithubViz.Bitset.close(bitset)
    assert File.exists?(name) == true
  end

  test "reopen" do
    name = temporary()
    {:ok, bitset} = GithubViz.Bitset.open(name, size: 0)
    :ok = GithubViz.Bitset.close(bitset)
    assert File.exists?(name) == true
    {:ok, bitset} = GithubViz.Bitset.open(name, size: 0)
    :ok = GithubViz.Bitset.close(bitset)
    assert File.exists?(name) == true
  end

  test "delete" do
    name = temporary()
    {:ok, bitset} = GithubViz.Bitset.open(name, size: 0)
    :ok = GithubViz.Bitset.delete(bitset)
    assert File.exists?(name) == false
  end

  test "operations" do
    {:ok, bitset} = GithubViz.Bitset.open(temporary(), size: 3)

    {:ok, [0, 0, 0]} = GithubViz.Bitset.get(bitset, [0, 1, 2])
    :ok = GithubViz.Bitset.set(bitset, [0])
    {:ok, [1, 0, 0]} = GithubViz.Bitset.get(bitset, [0, 1, 2])
    :ok = GithubViz.Bitset.set(bitset, [1])
    {:ok, [1, 1, 0]} = GithubViz.Bitset.get(bitset, [0, 1, 2])
    :ok = GithubViz.Bitset.set(bitset, [2])
    {:ok, [1, 1, 1]} = GithubViz.Bitset.get(bitset, [0, 1, 2])

    :ok = GithubViz.Bitset.unset(bitset, [0])
    {:ok, [0, 1, 1]} = GithubViz.Bitset.get(bitset, [0, 1, 2])
    :ok = GithubViz.Bitset.unset(bitset, [1])
    {:ok, [0, 0, 1]} = GithubViz.Bitset.get(bitset, [0, 1, 2])
    :ok = GithubViz.Bitset.unset(bitset, [2])
    {:ok, [0, 0, 0]} = GithubViz.Bitset.get(bitset, [0, 1, 2])

    :ok = GithubViz.Bitset.set(bitset, [0, 1, 2])
    {:ok, [1, 1, 1]} = GithubViz.Bitset.get(bitset, [0, 1, 2])
    :ok = GithubViz.Bitset.unset(bitset, [0, 1, 2])
    {:ok, [0, 0, 0]} = GithubViz.Bitset.get(bitset, [0, 1, 2])

    :ok = GithubViz.Bitset.delete(bitset)
  end

  test "resizing" do
    {:ok, bitset} = GithubViz.Bitset.open(temporary(), size: 0)
    {:ok, [0, 0, 0]} = GithubViz.Bitset.get(bitset, [0, 1, 2])
    :ok = GithubViz.Bitset.set(bitset, [3])
    {:ok, [0, 0, 0, 1]} = GithubViz.Bitset.get(bitset, [0, 1, 2, 3])
    :ok = GithubViz.Bitset.delete(bitset)
  end

  test "persistence" do
    name = temporary()

    {:ok, bitset} = GithubViz.Bitset.open(name, size: 3)
    {:ok, [0, 0, 0]} = GithubViz.Bitset.get(bitset, [0, 1, 2])
    :ok = GithubViz.Bitset.set(bitset, [1])
    {:ok, [0, 1, 0]} = GithubViz.Bitset.get(bitset, [0, 1, 2])
    :ok = GithubViz.Bitset.close(bitset)

    {:ok, bitset} = GithubViz.Bitset.open(name)
    {:ok, [0, 1, 0]} = GithubViz.Bitset.get(bitset, [0, 1, 2])
    :ok = GithubViz.Bitset.delete(bitset)
  end

  defp temporary do
    random = :crypto.strong_rand_bytes(20)
          |> Base.encode32(case: :lower)

    Path.join(["/tmp", "#{random}.bits"])
  end
end
