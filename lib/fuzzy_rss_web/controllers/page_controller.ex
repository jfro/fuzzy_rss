defmodule FuzzyRssWeb.PageController do
  use FuzzyRssWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
