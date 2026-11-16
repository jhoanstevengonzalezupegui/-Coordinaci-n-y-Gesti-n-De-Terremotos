defmodule Emergencias.Logistica do
  @moduledoc "Fachada con los comandos del Desarrollador 2."
  alias Emergencias.Logistica.{ResourceServer, NeedServer}

  def register_resource(codigo, nombre, cat, cant, unidad, ubic, zona \\ ""),
    do: ResourceServer.registrar(codigo, nombre, cat, cant, unidad, ubic, zona)

  def list_resources, do: ResourceServer.listar()
  def transfer_resource(codigo, origen, destino, cant), do: ResourceServer.transferir(codigo, origen, destino, cant)
  def register_need(tipo, cant, prio, zona, desc, user \\ "anonimo"), do: NeedServer.registrar(tipo, cant, prio, zona, desc, user)
  def list_needs(filtros \\ []), do: NeedServer.listar(filtros)
  def pending_needs, do: NeedServer.pendientes()
  def assign_resource(id, categoria, cant), do: NeedServer.asignar_recurso(id, categoria, cant)
  def critical_resources(umbral \\ 20), do: Enum.filter(ResourceServer.listar(), &(&1.cantidad <= umbral))
end
