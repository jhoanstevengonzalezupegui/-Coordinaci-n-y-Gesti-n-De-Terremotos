defmodule Emergencias.Application do
  @moduledoc "Árbol de supervisión raíz. Cada desarrollador agrega aquí su supervisor."
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Desarrollador 2
      Emergencias.Logistica.Supervisor
      # Otros desarrolladores: agregar sus supervisores aquí
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Emergencias.Supervisor)
  end
end
