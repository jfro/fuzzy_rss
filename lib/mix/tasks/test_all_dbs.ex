defmodule Mix.Tasks.TestAllDbs do
  use Mix.Task

  @shortdoc "Run tests against all supported database adapters"

  @moduledoc """
  Run tests against all supported database adapters (SQLite, MySQL, PostgreSQL).

  This task sequentially runs the full test suite with each database adapter
  to ensure the application works correctly across all supported databases.

  Usage:
    mix test_all_dbs

  Note: For MySQL and PostgreSQL to work, ensure the databases are set up and
  accessible with the default credentials:
    - MySQL: root user with no password on localhost
    - PostgreSQL: postgres user with password 'postgres' on localhost
  """

  def run(_args) do
    adapters = ["sqlite", "mysql", "postgresql"]

    failed_adapters =
      Enum.reduce(adapters, [], fn adapter, failures ->
        IO.puts("\n" <> String.duplicate("=", 80))
        IO.puts("Testing with DATABASE_ADAPTER=#{adapter}")
        IO.puts(String.duplicate("=", 80) <> "\n")

        case System.cmd("mix", ["test"], env: [{"DATABASE_ADAPTER", adapter}]) do
          {_output, 0} ->
            IO.puts("\n✓ Tests passed with #{adapter}\n")
            failures

          {_output, _code} ->
            IO.puts("\n✗ Tests failed with #{adapter}\n")
            [adapter | failures]
        end
      end)

    if failed_adapters == [] do
      IO.puts("\n" <> String.duplicate("=", 80))
      IO.puts("✓ All tests passed for all database adapters!")
      IO.puts(String.duplicate("=", 80))
    else
      IO.puts("\n" <> String.duplicate("=", 80))
      IO.puts("✗ Tests failed for: #{Enum.join(Enum.reverse(failed_adapters), ", ")}")
      IO.puts(String.duplicate("=", 80))
      System.halt(1)
    end
  end
end
