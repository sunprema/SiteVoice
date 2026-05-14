defmodule Sitevoice.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SitevoiceWeb.Telemetry,
      Sitevoice.Repo,
      {DNSCluster, query: Application.get_env(:sitevoice, :dns_cluster_query) || :ignore},
      {Oban,
       AshOban.config(
         Application.fetch_env!(:sitevoice, :ash_domains),
         Application.fetch_env!(:sitevoice, Oban)
       )},
      {Phoenix.PubSub, name: Sitevoice.PubSub},
      # Start a worker by calling: Sitevoice.Worker.start_link(arg)
      # {Sitevoice.Worker, arg},
      # Start to serve requests, typically the last entry
      SitevoiceWeb.Endpoint,
      {AshAuthentication.Supervisor, [otp_app: :sitevoice]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Sitevoice.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SitevoiceWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
