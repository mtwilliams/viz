defmodule GithubViz.Event.Parser do
  @moduledoc ~S"""
  Parses events from Github into zero or more `GithubViz.Event`s.
  """

  @doc "Parses an event into zero or more `GithubViz.Event`s."
  def parse(event) do
    event |> do_parse |> List.wrap
  end

  defp generate(type, event) do
    %GithubViz.Event{
      id: event["id"],
      type: type,
      actor: %GithubViz.Event.Actor{
        id: event["actor"]["id"],
        url: event["actor"]["url"],
        avatar: event["actor"]["avatar_url"],
        login: event["actor"]["login"]},
      repository: %GithubViz.Event.Repository{
        id: event["repo"]["id"],
        url: event["repo"]["url"],
        name: event["repo"]["name"]}
    }
  end

  defp do_parse(%{"type" => "CreateEvent"} = event) do
    if event["payload"]["ref_type"] == "repository" do
      generate(:"repos.created", event)
    end
  end

  defp do_parse(%{"type" => "ForkEvent"} = event) do
    generate(:"repos.forked", event)
  end

  defp do_parse(%{"type" => "PublicEvent"} = event) do
    generate(:"repos.open_sourced", event)
  end

  defp do_parse(%{"type" => "PushEvent"} = event) do
    push = generate(:"code.pushes", event)

    # HACK(mtwilliams): Not necessarily the author of the commits...
    commits = Stream.repeatedly(fn -> generate(:"code.commits", event) end)
           |> Enum.take(event["payload"]["distinct_size"])

    [push | commits]
  end

  defp do_parse(%{"type" => "PullRequestEvent"} = event) do
    case event["payload"]["action"] do
      action when action in ~W{opened reopened closed} ->
        generate(:"pull_requests.#{action}", event)
      _ ->
        nil
    end
  end

  defp do_parse(%{"type" => "IssuesEvent"} = event) do
    case event["payload"]["action"] do
      action when action in ~W{opened reopened closed} ->
        generate(:"issues.#{action}", event)
      _ ->
        nil
    end
  end

  defp do_parse(%{"type" => "CommitCommentEvent"} = event) do
    if event["payload"]["action"] == "created" do
      generate(:"comments.commit", event)
    end
  end

  defp do_parse(%{"type" => "IssueCommentEvent"} = event) do
    if event["payload"]["action"] == "created" do
      generate(:"comments.issue", event)
    end
  end

  defp do_parse(%{"type" => "PullRequestReviewCommentEvent"} = event) do
    if event["payload"]["action"] == "created" do
      generate(:"comments.review", event)
    end
  end

  defp do_parse(%{"type" => "MemberEvent"} = event) do
    case event["payload"]["action"] do
      "added" -> generate(:"collaborators.added", event)
      "deleted" -> generate(:"collaborators.removed", event)
      _ -> nil
    end
  end

  defp do_parse(%{"type" => "GollumEvent"} = event) do
    generate(:"wiki.edits", event)
  end

  defp do_parse(%{"type" => "ReleaseEvent"} = event) do
    if event["payload"]["action"] == "published" do
      generate(:"releases", event)
    end
  end

  defp do_parse(_event), do: nil
end
