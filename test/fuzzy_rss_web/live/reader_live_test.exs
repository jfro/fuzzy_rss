defmodule FuzzyRssWeb.ReaderLiveTest do
  use FuzzyRssWeb.ConnCase

  import Phoenix.LiveViewTest

  alias FuzzyRss.ContentFixtures

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

  describe "Entry Detail Component" do
    test "entry detail component properly updates with all required assigns", %{conn: conn} do
      # This test ensures that the EntryDetail component receives all necessary assigns
      # and doesn't raise KeyError when trying to access them.
      # This specifically tests the bug fix where EntryDetail.update/2 wasn't properly
      # assigning selected_entry, causing KeyError when render/1 tried to access it.
      {:ok, view, html} = live(conn, ~p"/app")

      # The component should render without errors (no KeyError)
      assert view != nil
      assert html =~ "FuzzyRSS"
    end

    test "layout mode is properly passed to entry detail component", %{conn: conn} do
      # This test ensures that the EntryDetail component receives the layout_mode assign
      # and renders without errors when switching between layouts.
      # Regression test for: KeyError when layout_mode not properly assigned to EntryDetail
      {:ok, view, _html} = live(conn, ~p"/app")

      # Switch to horizontal layout
      view
      |> element("button[title=\"Horizontal layout (sidebar, list, and article side-by-side)\"]")
      |> render_click()

      # The view should still be connected and rendering without KeyError
      assert view != nil

      assert has_element?(
               view,
               "button[title=\"Horizontal layout (sidebar, list, and article side-by-side)\"].btn-primary"
             )

      # Switch back to vertical layout
      view
      |> element("button[title=\"Vertical layout (list on top, article below)\"]")
      |> render_click()

      # Should render without errors
      assert has_element?(
               view,
               "button[title=\"Vertical layout (list on top, article below)\"].btn-primary"
             )
    end

    test "entry detail component renders with selected entry", %{conn: conn, user: user} do
      # Create test data using fixtures
      feed = ContentFixtures.feed_fixture(%{"title" => "Test Feed"})
      ContentFixtures.subscription_fixture(user, feed)

      entry =
        ContentFixtures.entry_fixture(feed, %{
          "title" => "Test Entry",
          "summary" => "Test summary",
          "content" => "Test content"
        })

      {:ok, view, _html} = live(conn, ~p"/app")

      # Select the entry by clicking it
      view |> element("[phx-value-entry_id=\"#{entry.id}\"]") |> render_click()

      # The entry detail should now be rendered with the entry's title
      assert has_element?(view, "h1", "Test Entry")
    end

    test "entry detail component renders with layout mode and selected entry", %{
      conn: conn,
      user: user
    } do
      # Create test data using fixtures
      feed = ContentFixtures.feed_fixture(%{"title" => "Test Feed"})
      ContentFixtures.subscription_fixture(user, feed)

      entry =
        ContentFixtures.entry_fixture(feed, %{
          "title" => "Test Entry with Mode",
          "summary" => "Test summary",
          "content" => "Test content"
        })

      {:ok, view, _html} = live(conn, ~p"/app")

      # Select the entry - in vertical layout
      view |> element("[phx-value-entry_id=\"#{entry.id}\"]") |> render_click()

      # Entry detail should render in vertical layout
      assert has_element?(view, "h1", "Test Entry with Mode")

      # Switch to horizontal layout
      view
      |> element("button[title=\"Horizontal layout (sidebar, list, and article side-by-side)\"]")
      |> render_click()

      # Entry detail component should still exist without errors
      # (it's hidden in horizontal layout, but doesn't crash)
      assert view != nil
    end
  end

  describe "Layout Mode Toggle" do
    test "renders layout mode toggle buttons", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/app")

      # Verify both layout toggle buttons are present
      assert html =~ "hero-rectangle-stack"
      assert html =~ "hero-view-columns"
    end

    test "vertical layout mode is selected by default", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/app")

      # The vertical layout button should have btn-primary class
      assert has_element?(
               view,
               "button[title=\"Vertical layout (list on top, article below)\"].btn-primary"
             )
    end

    test "switching to horizontal layout mode", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/app")

      # Click the horizontal layout button
      view
      |> element("button[title=\"Horizontal layout (sidebar, list, and article side-by-side)\"]")
      |> render_click()

      # The horizontal layout button should now have btn-primary class
      assert has_element?(
               view,
               "button[title=\"Horizontal layout (sidebar, list, and article side-by-side)\"].btn-primary"
             )
    end

    test "layout mode preference is persisted", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/app")

      # Switch to horizontal layout
      view
      |> element("button[title=\"Horizontal layout (sidebar, list, and article side-by-side)\"]")
      |> render_click()

      # Reload the page
      {:ok, new_view, _html} = live(conn, ~p"/app")

      # The horizontal layout button should still be active (preference persisted)
      assert has_element?(
               new_view,
               "button[title=\"Horizontal layout (sidebar, list, and article side-by-side)\"].btn-primary"
             )

      # Also verify the preference was saved in the database
      updated_user = FuzzyRss.Accounts.get_user!(user.id)
      assert updated_user.preferences["layout_mode"] == "horizontal"
    end

    test "switching layouts preserves selected entry", %{conn: conn, user: user} do
      # Create test data using fixtures
      feed = ContentFixtures.feed_fixture(%{"title" => "Test Feed"})
      ContentFixtures.subscription_fixture(user, feed)

      entry =
        ContentFixtures.entry_fixture(feed, %{
          "title" => "Test Entry to Preserve",
          "summary" => "Test summary",
          "content" => "Test content"
        })

      {:ok, view, _html} = live(conn, ~p"/app")

      # Select an entry in vertical layout
      view |> element("[phx-value-entry_id=\"#{entry.id}\"]") |> render_click()

      # Verify entry is displayed
      assert has_element?(view, "h1", "Test Entry to Preserve")

      # Switch to horizontal layout
      view
      |> element("button[title=\"Horizontal layout (sidebar, list, and article side-by-side)\"]")
      |> render_click()

      # Entry should still be displayed in the right pane
      assert has_element?(view, "h1", "Test Entry to Preserve")

      # Switch back to vertical layout
      view
      |> element("button[title=\"Vertical layout (list on top, article below)\"]")
      |> render_click()

      # Entry should still be displayed in the bottom pane
      assert has_element?(view, "h1", "Test Entry to Preserve")
    end
  end
end
