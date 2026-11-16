defmodule Emergencias.Logistica.Recurso do
  @moduledoc "Funciones puras sobre recursos (sin procesos)."
  alias Emergencias.Logistica.Persistencia, as: P

  defstruct [:codigo, :nombre, :categoria, :cantidad, :unidad, :ubicacion, :zona]

  def normalizar(s) do
    s |> to_string() |> String.trim() |> String.downcase() |> String.replace(" ", "_")
  end

  def nuevo(codigo, nombre, categoria, cantidad, unidad, ubicacion, zona \\ "") do
    cond do
      Enum.any?([codigo, nombre, categoria, unidad, ubicacion], &(String.trim(to_string(&1)) == "")) ->
        {:error, :campo_vacio}

      not (is_integer(cantidad) and cantidad >= 0) ->
        {:error, :cantidad_invalida}

      true ->
        {:ok,
         %__MODULE__{
           codigo: String.trim(codigo),
           nombre: nombre,
           categoria: normalizar(categoria),
           cantidad: cantidad,
           unidad: unidad,
           ubicacion: normalizar(ubicacion),
           zona: normalizar(zona)
         }}
    end
  end

  @doc "RECURSIVA: suma el inventario de una lista de recursos."
  def total([]), do: 0
  def total([r | resto]), do: r.cantidad + total(resto)

  @doc "Descuenta `cantidad` de varios recursos. Retorna {:ok, {lista_actualizada, [{codigo, tomado}]}}."
  def tomar(recursos, cantidad) do
    if total(recursos) < cantidad,
      do: {:error, :inventario_insuficiente},
      else: {:ok, descontar(recursos, cantidad)}
  end

  # RECURSIVA: reparte lo pedido entre los recursos, uno a uno.
  defp descontar([], _), do: {[], []}
  defp descontar(lista, 0), do: {lista, []}

  defp descontar([r | resto], pendiente) do
    tomado = min(r.cantidad, pendiente)
    {resto2, movs} = descontar(resto, pendiente - tomado)
    movs = if tomado > 0, do: [{r.codigo, tomado} | movs], else: movs
    {[%{r | cantidad: r.cantidad - tomado} | resto2], movs}
  end

  def a_linea(r),
    do: Enum.map_join([r.codigo, r.nombre, r.categoria, r.cantidad, r.unidad, r.ubicacion, r.zona], "|", &P.limpiar/1)

  def de_linea(linea) do
    case String.split(linea, "|") do
      [c, n, cat, cant, u, ub, z] -> nuevo(c, n, cat, String.to_integer(cant), u, ub, z)
      _ -> {:error, :linea_invalida}
    end
  end
end
