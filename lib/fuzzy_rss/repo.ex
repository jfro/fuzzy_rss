defmodule FuzzyRss.Repo do
  @moduledoc """
  Repo module that delegates to the actual adapter-specific repo at runtime.
  The actual repo module is determined based on DATABASE_ADAPTER.
  """

  defp actual_repo, do: Application.fetch_env!(:fuzzy_rss, :repo_module)

  # Delegate all common Ecto.Repo functions to the actual repo
  def all(queryable, opts \\ []), do: actual_repo().all(queryable, opts)
  def get(queryable, id, opts \\ []), do: actual_repo().get(queryable, id, opts)
  def get!(queryable, id, opts \\ []), do: actual_repo().get!(queryable, id, opts)
  def get_by(queryable, clauses, opts \\ []), do: actual_repo().get_by(queryable, clauses, opts)
  def get_by!(queryable, clauses, opts \\ []), do: actual_repo().get_by!(queryable, clauses, opts)
  def one(queryable, opts \\ []), do: actual_repo().one(queryable, opts)
  def one!(queryable, opts \\ []), do: actual_repo().one!(queryable, opts)
  def exists?(queryable, opts \\ []), do: actual_repo().exists?(queryable, opts)

  def insert(struct_or_changeset, opts \\ []), do: actual_repo().insert(struct_or_changeset, opts)

  def insert!(struct_or_changeset, opts \\ []),
    do: actual_repo().insert!(struct_or_changeset, opts)

  def insert_all(schema_or_source, entries, opts \\ []),
    do: actual_repo().insert_all(schema_or_source, entries, opts)

  def update(changeset, opts \\ []), do: actual_repo().update(changeset, opts)
  def update!(changeset, opts \\ []), do: actual_repo().update!(changeset, opts)

  def update_all(queryable, updates, opts \\ []),
    do: actual_repo().update_all(queryable, updates, opts)

  def delete(struct_or_changeset, opts \\ []), do: actual_repo().delete(struct_or_changeset, opts)

  def delete!(struct_or_changeset, opts \\ []),
    do: actual_repo().delete!(struct_or_changeset, opts)

  def delete_all(queryable, opts \\ []), do: actual_repo().delete_all(queryable, opts)

  def preload(struct_or_structs, preloads, opts \\ []),
    do: actual_repo().preload(struct_or_structs, preloads, opts)

  def aggregate(queryable, aggregate, opts \\ []),
    do: actual_repo().aggregate(queryable, aggregate, opts)

  # Transaction support
  def transaction(fun_or_multi, opts \\ []), do: actual_repo().transaction(fun_or_multi, opts)
  def rollback(value), do: actual_repo().rollback(value)
end
