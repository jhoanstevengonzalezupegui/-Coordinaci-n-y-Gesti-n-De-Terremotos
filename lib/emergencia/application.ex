defmodule Emergencia.Application do
  use Application

  @impl true
  def start(_type, _args) do
    # Aquí definimos los servidores (hijos) que el Supervisor va a encender y vigilar
    children = [
      MascotasServer,
      FamiliaresServer
      # Nota: Aquí es donde tus compañeros (Desarrollador 1 y 2)
      # agregarán sus propios servidores más adelante.
    ]

    # :one_for_one significa que si un servidor falla, el Supervisor solo reinicia ese servidor
    # sin afectar a los demás, manteniendo el sistema distribuido estable.
    opts = [strategy: :one_for_one, name: Emergencia.Supervisor]

    Supervisor.start_link(children, opts)
  end
end
