defmodule FuzzyRssWeb.ReaderLive.AccountSettings do
  use FuzzyRssWeb, :live_component

  alias FuzzyRss.Accounts

  @impl true
  def update(assigns, socket) do
    user = assigns.current_user

    socket =
      socket
      |> assign(:current_user, user)
      |> assign(:email_changeset, Accounts.change_user_email(user))
      |> assign(:password_changeset, Accounts.change_user_password(user))

    {:ok, socket}
  end

  @impl true
  def handle_event("update_email", %{"user" => user_params}, socket) do
    user = socket.assigns.current_user

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        # Build absolute URL for email confirmation link
        uri = URI.parse(socket.root_address || "http://localhost:4000")
        base_url = "#{uri.scheme}://#{uri.host}#{if uri.port, do: ":#{uri.port}", else: ""}"

        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          fn token ->
            "#{base_url}#{~p"/users/settings/confirm-email/#{token}"}"
          end
        )

        {:noreply,
         socket
         |> put_flash(
           :info,
           "A link to confirm your email change has been sent to the new address."
         )
         |> assign(:email_changeset, Accounts.change_user_email(user))}

      changeset ->
        {:noreply,
         socket
         |> assign(:email_changeset, %{changeset | action: :insert})}
    end
  end

  @impl true
  def handle_event("update_password", %{"user" => user_params}, socket) do
    user = socket.assigns.current_user

    case Accounts.update_user_password(user, user_params) do
      {:ok, {_user, _}} ->
        {:noreply,
         socket
         |> put_flash(:info, "Password updated successfully.")
         |> assign(:password_changeset, Accounts.change_user_password(user))}

      {:error, changeset} ->
        {:noreply, assign(socket, :password_changeset, changeset)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto p-6">
      <div class="mb-6">
        <.link patch={~p"/app/settings"} class="btn btn-ghost btn-sm">← Settings</.link>
      </div>

      <div class="text-center mb-6">
        <h1 class="text-3xl font-bold">Account Settings</h1>
        <p class="text-base-content/60 mt-2">
          Manage your account email address and password settings
        </p>
      </div>
      
    <!-- Email Update Form -->
      <div class="card bg-base-100 shadow mb-6">
        <div class="card-body">
          <h2 class="card-title text-lg">Change Email</h2>

          <.form
            :let={f}
            for={@email_changeset}
            phx-submit="update_email"
            phx-target={@myself}
            class="space-y-4"
          >
            <.input field={f[:email]} type="email" label="Email" autocomplete="email" required />

            <button type="submit" class="btn btn-primary">Change Email</button>
          </.form>
        </div>
      </div>

      <div class="divider"></div>
      
    <!-- Password Update Form -->
      <div class="card bg-base-100 shadow mb-6">
        <div class="card-body">
          <h2 class="card-title text-lg">Change Password</h2>

          <.form
            :let={f}
            for={@password_changeset}
            phx-submit="update_password"
            phx-target={@myself}
            class="space-y-4"
          >
            <.input
              field={f[:password]}
              type="password"
              label="New password"
              autocomplete="new-password"
              required
            />
            <.input
              field={f[:password_confirmation]}
              type="password"
              label="Confirm new password"
              autocomplete="new-password"
              required
            />
            <button type="submit" class="btn btn-primary">Save Password</button>
          </.form>
        </div>
      </div>

      <div class="mt-8">
        <.link patch={~p"/app"} class="btn btn-ghost">← Back to Reader</.link>
      </div>
    </div>
    """
  end
end
