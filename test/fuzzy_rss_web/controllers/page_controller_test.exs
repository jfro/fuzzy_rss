defmodule FuzzyRssWeb.PageControllerTest do
  use FuzzyRssWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/app"
  end
end
