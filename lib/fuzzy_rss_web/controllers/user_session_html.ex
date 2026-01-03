defmodule FuzzyRssWeb.UserSessionHTML do
  use FuzzyRssWeb, :html

  embed_templates "user_session_html/*"

  defp local_mail_adapter? do
    Application.get_env(:fuzzy_rss, FuzzyRss.Mailer)[:adapter] == Swoosh.Adapters.Local
  end

  defp oidc_enabled? do
    FuzzyRss.Accounts.OIDC.enabled?()
  end
end
