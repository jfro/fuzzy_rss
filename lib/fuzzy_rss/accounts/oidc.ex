defmodule FuzzyRss.Accounts.OIDC do
  @moduledoc "OIDC provider integration with Assent"

  alias FuzzyRss.Accounts

  defp repo, do: Application.fetch_env!(:fuzzy_rss, :repo_module)

  def enabled?, do: Application.get_env(:fuzzy_rss, :oidc_enabled, false)

  def find_or_create_user(provider, user_info) do
    # Extract info from Assent user_info
    provider_uid = to_string(user_info["sub"])
    email = user_info["email"] || user_info["mail"]
    name = user_info["name"] || user_info["preferred_username"]
    avatar_url = user_info["picture"] || user_info["avatar_url"]

    # Download and store avatar as blob to avoid provider throttling
    avatar_blob =
      if avatar_url do
        download_avatar_blob(avatar_url)
      else
        nil
      end

    identity_attrs = %{
      provider: to_string(provider),
      provider_uid: provider_uid,
      email: email,
      name: name,
      avatar: avatar_blob,
      raw_data: user_info
    }

    case repo().get_by(Accounts.UserIdentity,
           provider: to_string(provider),
           provider_uid: provider_uid
         ) do
      nil ->
        # Create new user and identity
        create_user_with_identity(email, identity_attrs)

      identity ->
        # Return existing user
        {:ok, repo().preload(identity, :user).user}
    end
  end

  defp download_avatar_blob(url) do
    case Req.get(url) do
      {:ok, response} ->
        response.body

      {:error, _reason} ->
        nil
    end
  rescue
    _ -> nil
  end

  defp create_user_with_identity(email, identity_attrs) do
    repo().transaction(fn ->
      user =
        case repo().get_by(Accounts.User, email: email) do
          nil ->
            repo().insert!(%Accounts.User{
              email: email,
              confirmed_at: DateTime.utc_now(:second)
            })

          user ->
            user
        end

      identity_attrs = Map.delete(identity_attrs, :user_id)

      %Accounts.UserIdentity{user_id: user.id}
      |> Accounts.UserIdentity.changeset(identity_attrs)
      |> repo().insert!()

      user
    end)
  end
end
