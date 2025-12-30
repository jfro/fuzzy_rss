defmodule FuzzyRss.Accounts.OIDC do
  @moduledoc "OIDC/OAuth provider integration with Ueberauth"

  alias FuzzyRss.Accounts

  defp repo, do: Application.fetch_env!(:fuzzy_rss, :repo_module)

  def enabled?, do: Application.fetch_env!(:fuzzy_rss, :oidc_enabled)

  def find_or_create_user(provider, ueberauth_info) do
    # Extract info from Ueberauth callback
    provider_uid = ueberauth_info.uid
    email = ueberauth_info.info.email
    name = ueberauth_info.info.name
    avatar_url = ueberauth_info.info.image

    # Download and store avatar as blob to avoid provider throttling
    avatar_blob =
      if avatar_url do
        download_avatar_blob(avatar_url)
      else
        nil
      end

    identity_attrs = %{
      provider: to_string(provider),
      provider_uid: to_string(provider_uid),
      email: email,
      name: name,
      avatar: avatar_blob,
      raw_data: Map.from_struct(ueberauth_info)
    }

    case repo().get_by(Accounts.UserIdentity,
           provider: to_string(provider),
           provider_uid: to_string(provider_uid)
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
        repo().insert!(%Accounts.User{
          email: email,
          confirmed_at: DateTime.utc_now(:second)
        })

      identity_attrs = Map.put(identity_attrs, :user_id, user.id)

      repo().insert!(Accounts.UserIdentity.changeset(%Accounts.UserIdentity{}, identity_attrs))

      user
    end)
    |> case do
      {:ok, user} -> {:ok, user}
      {:error, reason} -> {:error, reason}
    end
  end
end
