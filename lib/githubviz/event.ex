defmodule GithubViz.Event do
  defmodule Actor do
    defstruct [:id, :url, :avatar, :login]
  end

  defmodule Repository do
    defstruct [:id, :url, :name]
  end

  defstruct [:id, :type, :actor, :repository]
end
