# TODO(mtwilliams): Use a circuit breaker, or at the very least backoff, if
# fetching fails.

defmodule GithubViz.Github do
  @moduledoc ~S"""
  Our (simple) wrapper around Github's REST API.
  """

  @base "https://api.github.com"

  @config Application.get_env(:githubviz, :githubviz, [])

  @user_agent Keyword.get(@config, :user_agent, "Elixir/#{System.version()}")
  @client_id Keyword.get(@config, :client_id)
  @client_secret Keyword.get(@config, :client_secret)

  def get(path, headers \\ %{}, parameters \\ %{}) do
    headers =
      headers
      |> Map.put("User-Agent", @user_agent)
      |> Enum.into([])

    parameters =
      parameters
      |> Map.put("client_id", @client_id)
      |> Map.put("client_secret", @client_secret)

    case HTTPoison.get(@base <> path, headers, params: parameters) do
      {:ok, %HTTPoison.Response{} = response} ->
        {:ok, {response.status_code, Map.new(response.headers), response.body}}
      {:error, error} ->
        {:error, error}
    end
  end
end
