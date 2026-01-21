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
  def handle_event("generate_api_password", %{"password" => password}, socket) do
    user = socket.assigns.current_user

    # Verify the user's password
    case Accounts.get_user_by_email_and_password(user.email, password) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Invalid password. Please enter your current password.")}

      verified_user ->
        {:ok, updated_user} = Accounts.set_api_password(verified_user, password)

        {:noreply,
         socket
         |> assign(:current_user, updated_user)
         |> assign(:show_api_password, true)
         |> put_flash(:info, "API password generated successfully.")}
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

              <div class="form-control">
                <label class="label">
                  <span class="label-text font-medium">Your API Password</span>
                </label>
                <div class="flex gap-2">
                  <input
                    type={if @show_api_password, do: "text", else: "password"}
                    value={@current_user.api_password}
                    readonly
                    class="input input-bordered flex-1 font-mono text-sm"
                  />
                  <button
                    type="button"
                    phx-click="toggle_api_password_visibility"
                    phx-target={@myself}
                    class="btn btn-square btn-outline"
                  >
                    <%= if @show_api_password do %>
                      <svg
                        xmlns="http://www.w3.org/2000/svg"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke-width="1.5"
                        stroke="currentColor"
                        class="w-5 h-5"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d="M3.98 8.223A10.477 10.477 0 001.934 12C3.226 16.338 7.244 19.5 12 19.5c.993 0 1.953-.138 2.863-.395M6.228 6.228A10.45 10.45 0 0112 4.5c4.756 0 8.773 3.162 10.065 7.498a10.523 10.523 0 01-4.293 5.774M6.228 6.228L3 3m3.228 3.228l3.65 3.65m7.894 7.894L21 21m-3.228-3.228l-3.65-3.65m0 0a3 3 0 10-4.243-4.243m4.242 4.242L9.88 9.88"
                        />
                      </svg>
                    <% else %>
                      <svg
                        xmlns="http://www.w3.org/2000/svg"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke-width="1.5"
                        stroke="currentColor"
                        class="w-5 h-5"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d="M2.036 12.322a1.012 1.012 0 010-.639C3.423 7.51 7.36 4.5 12 4.5c4.638 0 8.573 3.007 9.963 7.178.07.207.07.431 0 .639C20.577 16.49 16.64 19.5 12 19.5c-4.638 0-8.573-3.007-9.963-7.178z"
                        />
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
                        />
                      </svg>
                    <% end %>
                  </button>
                </div>
              </div>

              <details class="collapse collapse-arrow bg-base-200">
                <summary class="collapse-title text-sm font-medium">
                  How to use this in your RSS reader
                </summary>
                <div class="collapse-content text-sm space-y-2">
                  <p><strong>For Fever API clients:</strong></p>
                  <ul class="list-disc list-inside ml-4 space-y-1">
                    <li>Server URL: <code class="bg-base-300 px-1 rounded">https://your-server.com/fever/</code></li>
                    <li>Email: <code class="bg-base-300 px-1 rounded"><%= @current_user.email %></code></li>
                    <li>API Key: Use the password above</li>
                  </ul>
                  <p class="mt-3"><strong>For Google Reader API clients:</strong></p>
                  <ul class="list-disc list-inside ml-4 space-y-1">
                    <li>Server URL: <code class="bg-base-300 px-1 rounded">https://your-server.com/reader/api/0/</code></li>
                    <li>Email: <code class="bg-base-300 px-1 rounded"><%= @current_user.email %></code></li>
                    <li>Password: Your account password (not the API password)</li>
                  </ul>
                </div>
              </details>

              <div class="pt-2">
                <p class="text-sm text-base-content/60 mb-2">
                  Need to regenerate? Enter your password:
                </p>
                <form phx-submit="generate_api_password" phx-target={@myself} class="flex gap-2">
                  <input
                    type="password"
                    name="password"
                    placeholder="Your account password"
                    required
                    class="input input-bordered flex-1"
                  />
                  <button type="submit" class="btn btn-warning">Regenerate</button>
                </form>
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

              <form phx-submit="generate_api_password" phx-target={@myself} class="space-y-4">
                <div class="form-control">
                  <label class="label">
                    <span class="label-text">Enter your password to generate API password</span>
                  </label>
                  <input
                    type="password"
                    name="password"
                    placeholder="Your account password"
                    required
                    class="input input-bordered"
                  />
                </div>
                <button type="submit" class="btn btn-primary">Generate API Password</button>
              </form>
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
