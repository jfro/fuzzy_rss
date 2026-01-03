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

  describe "Feed Management with Import/Export tabs" do
    test "renders feed management page without errors", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/app/feeds")

      # The component should render successfully
      assert view != nil
      assert html =~ "Manage Feeds"
      assert html =~ ~s|id="feeds-tab"|
      assert html =~ ~s|id="import-export-tab"|
    end

    test "displays My Feeds tab by default", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/app/feeds")

      # My Feeds tab should be active by default
      assert html =~ ~s|id="feeds-panel"|
      assert html =~ "Refresh All"
      assert html =~ "Add Feed"
    end

    test "switches to Import & Export tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/app/feeds")

      # Click on the Import & Export tab
      html = view |> element("#import-export-tab") |> render_click()

      # Verify the Import & Export content is now visible
      assert html =~ "OPML Subscriptions"
      assert html =~ "Starred Articles"
      assert html =~ "Download OPML"
      assert html =~ "Download Starred Articles"
      assert html =~ ~s|id="import-export-panel"|
    end

    test "switches back to My Feeds tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/app/feeds")

      # First switch to Import & Export tab
      view |> element("#import-export-tab") |> render_click()

      # Then switch back to My Feeds tab
      html = view |> element("#feeds-tab") |> render_click()

      # Verify we're back on the My Feeds tab
      assert html =~ ~s|id="feeds-panel"|
      assert html =~ "Refresh All"
      assert html =~ "Add Feed"
    end

    test "displays import/export UI elements in Import & Export tab", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/app/feeds")

      # Switch to Import & Export tab
      html = view |> element("#import-export-tab") |> render_click()

      # Verify all import/export UI elements are present
      assert html =~ "OPML Subscriptions"
      assert html =~ "Starred Articles"
      assert html =~ ~s|id="export-opml-btn"|
      assert html =~ ~s|id="export-starred-btn"|
      assert html =~ ~s|id="import-opml-form"|
      assert html =~ ~s|id="import-starred-form"|
      assert html =~ "OPML files can be imported from any RSS reader"
    end

    test "sidebar persists when navigating to feed management", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/app")

      # Verify sidebar is visible on reader view
      assert html =~ "FuzzyRSS"

      # Navigate to feeds management
      html = view |> element("a[href=\"/app/feeds\"]") |> render_click()

      # Verify sidebar still present and we're viewing Manage Feeds
      assert html =~ "FuzzyRSS"
      assert html =~ "Manage Feeds"
    end
  end
end
