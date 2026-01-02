defmodule FuzzyRss.Ecto.JSONArray do
  @moduledoc """
  Custom Ecto type for storing arrays as JSON strings.
  This provides cross-database compatibility (PostgreSQL, MySQL, SQLite).
  """
  use Ecto.Type

  def type, do: :string

  def cast(value) when is_list(value) do
    {:ok, value}
  end

  def cast(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_list(decoded) -> {:ok, decoded}
      {:ok, _} -> :error
      :error -> :error
    end
  end

  def cast(nil), do: {:ok, []}
  def cast(_), do: :error

  def load(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_list(decoded) -> {:ok, decoded}
      {:ok, _} -> {:ok, []}
      :error -> {:ok, []}
    end
  end

  def load(nil), do: {:ok, []}
  def load(_), do: {:ok, []}

  def dump(value) when is_list(value) do
    Jason.encode(value)
  end

  def dump(nil), do: {:ok, "[]"}
  def dump(_), do: :error
end
