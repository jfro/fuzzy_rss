defmodule FuzzyRss.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Configure database adapter at runtime based on DATABASE_ADAPTER env var
    configure_database_adapter()

    # Get the selected repo module
    repo_module = Application.fetch_env!(:fuzzy_rss, :repo_module)

    children = [
      FuzzyRssWeb.Telemetry,
      repo_module,
      {Oban, Application.fetch_env!(:fuzzy_rss, Oban)},
      {DNSCluster, query: Application.get_env(:fuzzy_rss, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: FuzzyRss.PubSub},
      # Start a worker by calling: FuzzyRss.Worker.start_link(arg)
      # {FuzzyRss.Worker, arg},
      # Start to serve requests, typically the last entry
      FuzzyRssWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: FuzzyRss.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp configure_database_adapter do
    db_adapter = System.get_env("DATABASE_ADAPTER", "sqlite") |> String.to_atom()

    repo_module =
      case db_adapter do
        :sqlite ->
          FuzzyRss.RepoSQLite

        :mysql ->
          FuzzyRss.RepoMySQL

        :postgresql ->
          FuzzyRss.RepoPostgres

        invalid ->
          raise """
          Invalid DATABASE_ADAPTER: #{inspect(invalid)}

          Supported values are: sqlite, mysql, postgresql, postgres

          Set the DATABASE_ADAPTER environment variable to one of the supported values.
          Example: DATABASE_ADAPTER=postgresql mix phx.server
          """
      end

    # Set repo_module in application config so it can be retrieved later
    Application.put_env(:fuzzy_rss, :repo_module, repo_module)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FuzzyRssWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
