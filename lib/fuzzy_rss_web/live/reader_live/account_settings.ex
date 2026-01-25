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
      |> assign(:show_api_password, false)
      |> assign(:generated_password, nil)

    {:ok, socket}
  end

  defp get_base_url do
    FuzzyRssWeb.Endpoint.url()
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
  def handle_event("generate_random_api_password", _params, socket) do
    user = socket.assigns.current_user

    # Generate a secure random password
    random_password = :crypto.strong_rand_bytes(16) |> Base.encode64(padding: false)

    {:ok, updated_user} = Accounts.set_api_password(user, random_password)

    {:noreply,
     socket
     |> assign(:current_user, updated_user)
     |> assign(:show_api_password, true)
     |> assign(:generated_password, random_password)
     |> put_flash(:info, "Random API password generated successfully. Make sure to copy it!")}
  end

  @impl true
  def handle_event("set_custom_api_password", %{"password" => password}, socket) do
    user = socket.assigns.current_user

    if String.length(password) < 8 do
      {:noreply,
       socket
       |> put_flash(:error, "Password must be at least 8 characters long.")}
    else
      {:ok, updated_user} = Accounts.set_api_password(user, password)

      {:noreply,
       socket
       |> assign(:current_user, updated_user)
       |> assign(:show_api_password, false)
       |> assign(:generated_password, nil)
       |> put_flash(:info, "Custom API password set successfully.")}
    end
  end

  @impl true
  def handle_event("toggle_api_password_visibility", _params, socket) do
    {:noreply, assign(socket, :show_api_password, !socket.assigns.show_api_password)}
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

      <div class="divider"></div>
      
    <!-- API Password Section -->
      <div class="card bg-base-100 shadow mb-6">
        <div class="card-body">
          <h2 class="card-title text-lg">API Password</h2>
          <p class="text-sm text-base-content/60 mb-4">
            Generate an API password to use with RSS reader apps that support Fever or Google Reader APIs.
          </p>

          <%= if @current_user.api_password do %>
            <div class="space-y-4">
              <div class="alert alert-info">
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  class="stroke-current shrink-0 w-6 h-6"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                  >
                  </path>
                </svg>
                <span>API password is already configured.</span>
              </div>

              <%= if @generated_password do %>
                <div class="alert alert-success">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    class="stroke-current shrink-0 h-6 w-6"
                    fill="none"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
                    />
                  </svg>
                  <div>
                    <div class="font-bold">Your generated password (copy it now!):</div>
                    <div class="font-mono text-sm">{@generated_password}</div>
                  </div>
                </div>
              <% end %>

              <details class="collapse collapse-arrow bg-base-200">
                <summary class="collapse-title text-sm font-medium">
                  How to use this in your RSS reader
                </summary>
                <div class="collapse-content text-sm space-y-2">
                  <p><strong>For Fever API clients:</strong></p>
                  <ul class="list-disc list-inside ml-4 space-y-1">
                    <li>
                      Server URL:
                      <code class="bg-base-300 px-1 rounded">{get_base_url()}/fever/</code>
                    </li>
                    <li>
                      Email: <code class="bg-base-300 px-1 rounded">{@current_user.email}</code>
                    </li>
                    <li>
                      Password: Enter the password you set/generated earlier (your client will hash it)
                    </li>
                  </ul>
                  <p class="mt-3"><strong>For Google Reader API clients:</strong></p>
                  <ul class="list-disc list-inside ml-4 space-y-1">
                    <li>
                      Server URL:
                      <code class="bg-base-300 px-1 rounded">{get_base_url()}/reader/api/0/</code>
                    </li>
                    <li>
                      Email: <code class="bg-base-300 px-1 rounded">{@current_user.email}</code>
                    </li>
                    <li>
                      Password: Enter the password you set/generated earlier (your client will hash it)
                    </li>
                  </ul>
                  <p class="mt-3 text-xs text-base-content/60">
                    Note: Enter the plain-text password in your RSS client. The client will automatically hash it before sending. If you generated a random password, make sure you copied it from the green alert box when it was shown.
                  </p>
                </div>
              </details>

              <div class="divider">Regenerate</div>

              <div class="space-y-4">
                <div>
                  <h3 class="font-medium mb-2">Generate New Random Password</h3>
                  <button
                    type="button"
                    phx-click="generate_random_api_password"
                    phx-target={@myself}
                    class="btn btn-warning"
                  >
                    Generate New Random Password
                  </button>
                </div>

                <div class="divider text-sm">OR</div>

                <div>
                  <h3 class="font-medium mb-2">Set New Custom Password</h3>
                  <form
                    phx-submit="set_custom_api_password"
                    phx-target={@myself}
                    class="flex gap-2"
                  >
                    <input
                      type="password"
                      name="password"
                      placeholder="Enter new custom password"
                      minlength="8"
                      required
                      class="input input-bordered flex-1"
                    />
                    <button type="submit" class="btn btn-warning">Set New Password</button>
                  </form>
                </div>
              </div>
            </div>
          <% else %>
            <div class="space-y-4">
              <div class="alert alert-warning">
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  class="stroke-current shrink-0 h-6 w-6"
                  fill="none"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
                  />
                </svg>
                <span>No API password configured. Generate one to use with RSS reader apps.</span>
              </div>

              <div class="space-y-4">
                <div>
                  <h3 class="font-medium mb-2">Option 1: Generate Random Password</h3>
                  <p class="text-sm text-base-content/60 mb-3">
                    We'll create a secure random password for you.
                  </p>
                  <button
                    type="button"
                    phx-click="generate_random_api_password"
                    phx-target={@myself}
                    class="btn btn-primary"
                  >
                    Generate Random Password
                  </button>
                </div>

                <div class="divider">OR</div>

                <div>
                  <h3 class="font-medium mb-2">Option 2: Set Custom Password</h3>
                  <p class="text-sm text-base-content/60 mb-3">
                    Choose your own password (minimum 8 characters).
                  </p>
                  <form
                    phx-submit="set_custom_api_password"
                    phx-target={@myself}
                    class="flex gap-2"
                  >
                    <input
                      type="password"
                      name="password"
                      placeholder="Enter custom password"
                      minlength="8"
                      required
                      class="input input-bordered flex-1"
                    />
                    <button type="submit" class="btn btn-primary">Set Password</button>
                  </form>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>

      <div class="mt-8">
        <.link patch={~p"/app"} class="btn btn-ghost">← Back to Reader</.link>
      </div>
    </div>
    """
  end
end
