defmodule Emergencia.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MascotasServer,
      FamiliaresServer,
      UsuariosServer,
      ZonasServer,
      AlberguesServer
    ]

    opts = [strategy: :one_for_one, name: Emergencia.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
