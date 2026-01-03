defmodule FuzzyRss.RepoMySQL do
  use Ecto.Repo,
    otp_app: :fuzzy_rss,
    adapter: Ecto.Adapters.MyXQL

  # Create wrapper module to intercept calls
  defmodule MySQLCompat do
    def strip_conflict_target(opts) do
      Keyword.delete(opts, :conflict_target)
    end
  end

  # Redefine insert, insert!, and insert_all to strip :conflict_target
  # This works around MySQL's lack of support for explicit conflict targets
  defoverridable insert: 2, insert!: 2, insert_all: 3

  def insert(struct_or_changeset, opts) do
    super(struct_or_changeset, MySQLCompat.strip_conflict_target(opts))
  end

  def insert!(struct_or_changeset, opts) do
    super(struct_or_changeset, MySQLCompat.strip_conflict_target(opts))
  end

  def insert_all(schema_or_source, entries, opts) do
    super(schema_or_source, entries, MySQLCompat.strip_conflict_target(opts))
  end
end
