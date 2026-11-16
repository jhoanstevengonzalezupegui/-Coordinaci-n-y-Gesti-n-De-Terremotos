defmodule Emergencia.Application do
  @moduledoc """
  Árbol de supervisión OTP de la plataforma distribuida de gestión de emergencias.
  Supervisa los servidores GenServer de estado y un DynamicSupervisor para tareas concurrentes.
  """
  use Application

  @impl true
  def start(_type, _args) do
    data_dir = Application.get_env(:emergencia, :data_dir, "data")

    children = [
      {Emergencia.Servidores.UsuariosServer, [data_dir: data_dir]},
      {Emergencia.Servidores.ZonasServer, [data_dir: data_dir]},
      {Emergencia.Servidores.InventarioServer, [data_dir: data_dir]},
      {Emergencia.Servidores.AlberguesServer, [data_dir: data_dir]},
      {Emergencia.Servidores.FamiliaresServer, [data_dir: data_dir]},
      {Emergencia.Servidores.MascotasServer, [data_dir: data_dir]},
      {DynamicSupervisor, strategy: :one_for_one, name: Emergencia.TareasSupervisor}
    ]

    opts = [strategy: :one_for_one, name: Emergencia.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
