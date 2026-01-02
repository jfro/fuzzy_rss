defmodule FuzzyRssWeb.PageController do
  use FuzzyRssWeb, :controller

  def redirect_to_app(conn, _params) do
    redirect(conn, to: ~p"/app")
  end
end
