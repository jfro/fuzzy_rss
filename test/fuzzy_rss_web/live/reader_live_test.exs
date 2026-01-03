defmodule FuzzyRssWeb.ReaderLiveTest do
  use FuzzyRssWeb.ConnCase

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  describe "Reader component" do
    test "renders reader component without errors", %{conn: conn} do
      # This is the critical test - it verifies the Reader component
      # has a single root element and renders successfully
      {:ok, view, html} = live(conn, ~p"/app")

      # Verify the Reader component is rendered
      assert html =~ "All Entries"

      # Verify sidebar is present
      assert html =~ "FuzzyRSS"
      assert html =~ "All Unread"

      # Verify view is connected (no errors occurred during render)
      assert view != nil
    end

    test "displays empty state when no entries", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/app")

      assert html =~ "No entries to display"
      assert html =~ "Add some feeds to get started"
    end

    test "sidebar persists across navigation", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/app")

      # Verify sidebar is visible on reader view
      assert html =~ "FuzzyRSS"

      # Navigate to feeds management (using patch, not redirect)
      html = view |> element("a[href=\"/app/feeds\"]") |> render_click()

      # Verify sidebar still present
      assert html =~ "FuzzyRSS"
      assert html =~ "Manage Feeds"
    end
  end

  describe "ImportExport component" do
    test "renders import/export without errors", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/app/settings/import-export")

      # The component should render successfully (single root element)
      assert view != nil
      assert html =~ "Import & Export" || html =~ "Starred Articles"
    end
  end
end
