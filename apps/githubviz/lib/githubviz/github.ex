# TODO(mtwilliams): Use a circuit breaker, or at the very least backoff, if
# fetching fails.

defmodule GithubViz.Github do
  @moduledoc ~S"""
  Our (simple) wrapper around Github's REST API.
  """

  alias GithubViz.Metrics, as: M

  @base "https://api.github.com"

  @config Application.get_env(:githubviz, :github, [])

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
      |> Enum.into([])

    case HTTPoison.get(@base <> path, headers, params: parameters) do
      {:ok, %HTTPoison.Response{} = response} ->
        headers = Map.new(response.headers)

        M.count("github.status_codes.#{response.status_code}")
        M.count("github.status_codes.#{round(response.status_code / 100)}xx")

        {limit, _} = Map.fetch!(headers, "X-RateLimit-Limit") |> Integer.parse
        {remaining, _} = Map.fetch!(headers, "X-RateLimit-Remaining") |> Integer.parse
        {reset, _} = Map.fetch!(headers, "X-RateLimit-Reset") |> Integer.parse
        delta = reset - System.system_time(:seconds)

        M.sample("github.rate_limit.allowed", limit)
        M.sample("github.rate_limit.remaining", remaining)
        M.sample("github.rate_limit.used", limit - remaining)
        M.sample("github.rate_limit.reset", delta)

        {:ok, {response.status_code, headers, response.body}}
      {:error, error} ->
        {:error, error}
    end
  end
end
