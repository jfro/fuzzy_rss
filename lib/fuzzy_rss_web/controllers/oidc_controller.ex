defmodule FuzzyRssWeb.OIDCController do
  use FuzzyRssWeb, :controller
  require Logger

  alias FuzzyRss.Accounts
  alias FuzzyRssWeb.UserAuth

  def authorize(conn, _params) do
    config = Application.get_env(:fuzzy_rss, :oidc)

    case Assent.Strategy.OIDC.authorize_url(config) do
      {:ok, %{url: url, session_params: session_params}} ->
        conn
        |> put_session(:oidc_state, session_params["state"])
        |> put_session(:oidc_nonce, session_params["nonce"])
        # Store full session params as backup
        |> put_session(:oidc_session_params, session_params)
        |> redirect(external: url)

      {:error, error} ->
        Logger.error("OIDC authorize failed: #{inspect(error, pretty: true)}")

        conn
        |> put_flash(
          :error,
          "Authentication service is currently unavailable. Please try again later or contact support."
        )
        |> redirect(to: ~p"/users/log-in")
    end
  end

  def callback(conn, params) do
    config = Application.get_env(:fuzzy_rss, :oidc)

    # Try to get session params from different sources
    state = get_session(conn, :oidc_state)
    nonce = get_session(conn, :oidc_nonce)
    stored_session_params = get_session(conn, :oidc_session_params)

    # Use stored session params if individual values are missing, or fallback to params
    session_params =
      cond do
        state && nonce ->
          %{
            "state" => state,
            "nonce" => nonce
          }

        stored_session_params ->
          # Convert atom keys to string keys if needed
          stored_session_params
          |> Enum.map(fn
            {k, v} when is_atom(k) -> {Atom.to_string(k), v}
            {k, v} -> {k, v}
          end)
          |> Enum.into(%{})

        params["state"] ->
          # Fallback: use state from callback params if session is lost
          Logger.warning(
            "Using state from callback params as fallback - session may have been lost"
          )

          %{
            "state" => params["state"],
            "nonce" => nil
          }

        true ->
          %{}
      end

    # Check if we have required state parameter
    state_value = session_params["state"]

    if is_nil(state_value) do
      Logger.error("OIDC callback missing state parameter - possible session issue")

      conn
      |> put_flash(:error, "Authentication session expired. Please try signing in again.")
      |> redirect(to: ~p"/users/log-in")
    else
      # Convert session_params to atom keys for Assent compatibility
      session_params_atoms =
        session_params
        |> Enum.map(fn
          {"state", v} -> {:state, v}
          {"nonce", v} -> {:nonce, v}
          {k, v} -> {String.to_atom(k), v}
        end)
        |> Enum.into(%{})

      # Merge session_params into config for Assent
      config_with_session = Keyword.put(config, :session_params, session_params_atoms)

      case Assent.Strategy.OIDC.callback(config_with_session, params) do
        {:ok, %{user: user_info, token: token}} ->
          # If user_info is sparse, try to fetch from userinfo endpoint
          user_info =
            if is_nil(user_info["email"]) || is_nil(user_info["mail"]) do
              case Assent.Strategy.OIDC.fetch_userinfo(config_with_session, token) do
                {:ok, fetched_user_info} -> Map.merge(user_info, fetched_user_info)
                {:error, _error} -> user_info
              end
            else
              user_info
            end

          handle_successful_auth(conn, user_info)

        {:error, error} ->
          Logger.error("OIDC callback failed: #{inspect(error, pretty: true)}")

          error_message =
            case error do
              %Assent.MissingConfigError{key: :session_params} ->
                "Authentication session expired. Please try signing in again."

              %{error: "invalid_grant"} ->
                "Authentication expired or invalid. Please try signing in again."

              %{error: "access_denied"} ->
                "Access was denied. Please try again or contact support."

              %{error: error_type} when is_binary(error_type) ->
                "Authentication failed: #{String.replace(error_type, "_", " ")}. Please try again."

              _ ->
                "Authentication failed. Please try again or contact support if the problem persists."
            end

          conn
          |> put_flash(:error, error_message)
          |> redirect(to: ~p"/users/log-in")
      end
    end
  end

  defp handle_successful_auth(conn, user_info) do
    provider = "oidc"

    case Accounts.OIDC.find_or_create_user(provider, user_info) do
      {:ok, user} ->
        conn
        |> delete_session(:oidc_state)
        |> delete_session(:oidc_nonce)
        |> delete_session(:oidc_session_params)
        |> put_flash(:info, "Successfully authenticated with OIDC")
        |> UserAuth.log_in_user(user)

      {:error, reason} ->
        Logger.error("OIDC user login failed: #{inspect(reason)}")

        conn
        |> put_flash(:error, "Failed to authenticate: #{inspect(reason)}")
        |> redirect(to: ~p"/users/log-in")
    end
  end
end
