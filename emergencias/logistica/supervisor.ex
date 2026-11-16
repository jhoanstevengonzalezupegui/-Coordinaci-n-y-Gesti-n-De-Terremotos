defmodule Emergencias.Logistica.Supervisor do
  @moduledoc "Supervisa el inventario y las necesidades. El estado se recarga desde archivo al reiniciar."
  use Supervisor

  def start_link(arg \\ []), do: Supervisor.start_link(__MODULE__, arg, name: __MODULE__)

  @impl true
  def init(_arg) do
    children = [Emergencias.Logistica.ResourceServer, Emergencias.Logistica.NeedServer]
    Supervisor.init(children, strategy: :one_for_one)
  end
end
