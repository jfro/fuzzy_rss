defmodule FuzzyRss.Repo do
  @moduledoc """
  Minimal repo module for schema validation.
  The actual repo module is determined at runtime based on DATABASE_ADAPTER.
  """

  defp actual_repo, do: Application.fetch_env!(:fuzzy_rss, :repo_module)

  # Only exists? is needed for schema validations
  def exists?(queryable, opts \\ []) do
    actual_repo().exists?(queryable, opts)
  end
end
