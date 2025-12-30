defmodule FuzzyRssWeb.AuthController do
  use FuzzyRssWeb, :controller

  alias FuzzyRss.Accounts
  alias FuzzyRssWeb.UserAuth

  def request(conn, _params) do
    render(conn, :request)
  end

  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    conn
    |> put_flash(:error, "Failed to authenticate")
    |> redirect(to: ~p"/")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, %{"provider" => provider}) do
    if Accounts.OIDC.enabled?() do
      case Accounts.OIDC.find_or_create_user(provider, auth) do
        {:ok, user} ->
          conn
          |> put_flash(:info, "Successfully authenticated with #{provider}")
          |> UserAuth.log_in_user(user)

        {:error, reason} ->
          conn
          |> put_flash(:error, "Failed to authenticate: #{inspect(reason)}")
          |> redirect(to: ~p"/")
      end
    else
      conn
      |> put_flash(:error, "OIDC is not enabled")
      |> redirect(to: ~p"/")
    end
  end
end
