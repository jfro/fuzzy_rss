defmodule FuzzyRssWeb.UserRegistrationController do
  use FuzzyRssWeb, :controller

  alias FuzzyRss.Accounts
  alias FuzzyRss.Accounts.User

  def new(conn, _params) do
    if not Accounts.can_signup?() do
      conn
      |> put_flash(:error, "Signup is currently disabled.")
      |> redirect(to: ~p"/users/log-in")
    else
      changeset = User.registration_changeset(%User{}, %{})
      render(conn, :new, changeset: changeset)
    end
  end

  def create(conn, %{"user" => user_params}) do
    if not Accounts.can_signup?() do
      conn
      |> put_flash(:error, "Signup is currently disabled.")
      |> redirect(to: ~p"/users/log-in")
    else
      case Accounts.register_user(user_params) do
        {:ok, user} ->
          if Accounts.magic_link_enabled?() do
            # Magic link mode: send confirmation email
            {:ok, _} =
              Accounts.deliver_login_instructions(
                user,
                &url(~p"/users/log-in/#{&1}")
              )

            conn
            |> put_flash(
              :info,
              "An email was sent to #{user.email}, please access it to confirm your account."
            )
            |> redirect(to: ~p"/users/log-in")
          else
            # Password mode: user can login immediately
            conn
            |> put_flash(:info, "Account created successfully. Please log in.")
            |> redirect(to: ~p"/users/log-in")
          end

        {:error, %Ecto.Changeset{} = changeset} ->
          render(conn, :new, changeset: changeset)
      end
    end
  end
end
