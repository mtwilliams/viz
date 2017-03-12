defmodule GithubViz.Stream do
  @moduledoc ~S"""
  """

  use Application

  def start(_type, _args) do
    GithubViz.Stream.Supervisor.start_link()
  end
end
