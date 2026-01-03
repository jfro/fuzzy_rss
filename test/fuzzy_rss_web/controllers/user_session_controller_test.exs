defmodule FuzzyRssWeb.UserSessionControllerTest do
  use FuzzyRssWeb.ConnCase

  import FuzzyRss.AccountsFixtures
  alias FuzzyRss.Accounts

  defp repo, do: Application.fetch_env!(:fuzzy_rss, :repo_module)

  setup do
    %{unconfirmed_user: unconfirmed_user_fixture(), user: user_fixture()}
  end

  describe "GET /users/log-in" do
    test "renders login page", %{conn: conn} do
      conn = get(conn, ~p"/users/log-in")
      response = html_response(conn, 200)
      assert response =~ "Log in"
      assert response =~ ~p"/users/register"
      assert response =~ "Log in with email"
    end

    test "renders login page with email filled in (sudo mode)", %{conn: conn, user: user} do
      html =
        conn
        |> log_in_user(user)
        |> get(~p"/users/log-in")
        |> html_response(200)

      assert html =~ "You need to reauthenticate"
      refute html =~ "Register"
      assert html =~ "Log in with email"

      assert html =~
               ~s(<input type="email" name="user[email]" id="login_form_magic_email" value="#{user.email}")
    end

    test "renders login page (email + password)", %{conn: conn} do
      conn = get(conn, ~p"/users/log-in?mode=password")
      response = html_response(conn, 200)
      assert response =~ "Log in"
      assert response =~ ~p"/users/register"
      assert response =~ "Log in with email"
    end
  end

  describe "GET /users/log-in/:token" do
    test "renders confirmation page for unconfirmed user", %{conn: conn, unconfirmed_user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      conn = get(conn, ~p"/users/log-in/#{token}")
      assert html_response(conn, 200) =~ "Confirm and stay logged in"
    end

    test "renders login page for confirmed user", %{conn: conn, user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      conn = get(conn, ~p"/users/log-in/#{token}")
      html = html_response(conn, 200)
      refute html =~ "Confirm my account"
      assert html =~ "Log me in"
    end

    test "raises error for invalid token", %{conn: conn} do
      conn = get(conn, ~p"/users/log-in/invalid-token")
      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Magic link is invalid or it has expired."
    end
  end

  describe "POST /users/log-in - email and password" do
    test "logs the user in", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/app"
    end

    test "logs the user in with remember me", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_fuzzy_rss_web_user_remember_me"]
      assert redirected_to(conn) == ~p"/app"
    end

    test "logs the user in with return to", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        conn
        |> init_test_session(user_return_to: "/foo/bar")
        |> post(~p"/users/log-in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert redirected_to(conn) == "/foo/bar"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome back!"
    end

    test "emits error message with invalid credentials", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log-in?mode=password", %{
          "user" => %{"email" => user.email, "password" => "invalid_password"}
        })

      response = html_response(conn, 200)
      assert response =~ "Log in"
      assert response =~ "Invalid email or password"
    end
  end

  describe "POST /users/log-in - magic link" do
    test "sends magic link email when user exists", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "If your email is in our system"
      assert repo().get_by!(Accounts.UserToken, user_id: user.id).context == "login"
    end

    test "logs the user in", %{conn: conn, user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => token}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/app"
    end

    test "confirms unconfirmed user", %{conn: conn, unconfirmed_user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)
      refute user.confirmed_at

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => token},
          "_action" => "confirmed"
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/app"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "User confirmed successfully."

      assert Accounts.get_user!(user.id).confirmed_at
    end

    test "emits error message when magic link is invalid", %{conn: conn} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"token" => "invalid"}
        })

      assert html_response(conn, 200) =~ "The link is invalid or it has expired."
    end
  end

  describe "DELETE /users/log-out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end
  end

  describe "Password mode (magic link disabled)" do
    @tag :capture_log
    test "rejects magic link tokens when magic link is disabled", %{conn: conn, user: user} do
      original_config = Application.get_env(:fuzzy_rss, :auth)

      try do
        Application.put_env(:fuzzy_rss, :auth, signup_enabled: "true", disable_magic_link: true)

        {token, _hashed_token} = generate_user_magic_link_token(user)

        conn =
          post(conn, ~p"/users/log-in", %{
            "user" => %{"token" => token}
          })

        assert redirected_to(conn) == ~p"/users/log-in"

        assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
                 "Magic link login is not available"
      after
        Application.put_env(:fuzzy_rss, :auth, original_config)
      end
    end

    test "rejects magic link confirm page when magic link is disabled", %{
      conn: conn,
      unconfirmed_user: user
    } do
      original_config = Application.get_env(:fuzzy_rss, :auth)

      try do
        Application.put_env(:fuzzy_rss, :auth, signup_enabled: "true", disable_magic_link: true)

        token =
          extract_user_token(fn url ->
            Accounts.deliver_login_instructions(user, url)
          end)

        conn = get(conn, ~p"/users/log-in/#{token}")
        assert redirected_to(conn) == ~p"/users/log-in"

        assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
                 "Magic link login is not available"
      after
        Application.put_env(:fuzzy_rss, :auth, original_config)
      end
    end

    test "password field is shown when magic link is disabled", %{conn: conn} do
      original_config = Application.get_env(:fuzzy_rss, :auth)

      try do
        Application.put_env(:fuzzy_rss, :auth, signup_enabled: "true", disable_magic_link: true)

        conn = get(conn, ~p"/users/log-in")
        response = html_response(conn, 200)
        # Should show password form, not magic link form
        refute response =~ "Log in with email"
        assert response =~ "type=\"password\""
      after
        Application.put_env(:fuzzy_rss, :auth, original_config)
      end
    end

    test "email and password login works when magic link is disabled", %{conn: conn, user: user} do
      original_config = Application.get_env(:fuzzy_rss, :auth)

      try do
        Application.put_env(:fuzzy_rss, :auth, signup_enabled: "true", disable_magic_link: true)

        user = set_password(user)

        conn =
          post(conn, ~p"/users/log-in", %{
            "user" => %{"email" => user.email, "password" => valid_user_password()}
          })

        assert get_session(conn, :user_token)
        assert redirected_to(conn) == ~p"/app"
      after
        Application.put_env(:fuzzy_rss, :auth, original_config)
      end
    end

    test "magic link email request is rejected when magic link is disabled", %{
      conn: conn,
      user: user
    } do
      original_config = Application.get_env(:fuzzy_rss, :auth)

      try do
        Application.put_env(:fuzzy_rss, :auth, signup_enabled: "true", disable_magic_link: true)

        conn =
          post(conn, ~p"/users/log-in", %{
            "user" => %{"email" => user.email}
          })

        assert redirected_to(conn) == ~p"/users/log-in"

        assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
                 "Please enter your email and password"
      after
        Application.put_env(:fuzzy_rss, :auth, original_config)
      end
    end
  end

  describe "Magic link mode (default)" do
    test "magic link forms are shown when magic link is enabled", %{conn: conn} do
      original_config = Application.get_env(:fuzzy_rss, :auth)

      try do
        Application.put_env(:fuzzy_rss, :auth, signup_enabled: "true", disable_magic_link: false)

        conn = get(conn, ~p"/users/log-in")
        response = html_response(conn, 200)
        # Should show both magic link and password forms
        assert response =~ "Log in with email"
        assert response =~ "type=\"password\""
      after
        Application.put_env(:fuzzy_rss, :auth, original_config)
      end
    end

    test "magic link tokens work when magic link is enabled", %{conn: conn, user: user} do
      original_config = Application.get_env(:fuzzy_rss, :auth)

      try do
        Application.put_env(:fuzzy_rss, :auth, signup_enabled: "true", disable_magic_link: false)

        {token, _hashed_token} = generate_user_magic_link_token(user)

        conn =
          post(conn, ~p"/users/log-in", %{
            "user" => %{"token" => token}
          })

        assert get_session(conn, :user_token)
        assert redirected_to(conn) == ~p"/app"
      after
        Application.put_env(:fuzzy_rss, :auth, original_config)
      end
    end
  end
end
