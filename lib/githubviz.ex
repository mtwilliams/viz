defmodule GithubViz do
  @moduledoc ~S"""
  """

  use Application

  def start(_type, _args) do
    GithubViz.Supervisor.start_link()
  end
end
