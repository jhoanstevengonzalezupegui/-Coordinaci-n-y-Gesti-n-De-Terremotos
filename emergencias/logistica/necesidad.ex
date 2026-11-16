defmodule Emergencias.Logistica.Necesidad do
  @moduledoc "Funciones puras sobre necesidades puntuales. La prioridad ordena la atención."
  alias Emergencias.Logistica.Persistencia, as: P

  @tipos ~w(agua alimentos medicamentos primeros_auxilios refugio transporte rescate otra)
  @prioridades [critica: 0, alta: 1, media: 2, baja: 3]
  @transiciones %{
    pendiente: [:asignada, :cancelada],
    asignada: [:en_atencion, :cancelada],
    en_atencion: [:atendida, :cancelada],
    atendida: [],
    cancelada: []
  }

  defstruct [:id, :tipo, :descripcion, :cantidad, :zona, :prioridad, :responsable,
             asignado: 0, estado: :pendiente]

  def norm(s) do
    s |> to_string() |> String.trim() |> String.downcase() |> String.replace("í", "i") |> String.replace(" ", "_")
  end

  def parse_prioridad(p) do
    n = norm(p)
    case Enum.find(@prioridades, fn {k, _} -> Atom.to_string(k) == n end) do
      {k, _} -> {:ok, k}
      nil -> {:error, :prioridad_invalida}
    end
  end

  def parse_estado(e) do
    n = norm(e)
    case Enum.find(Map.keys(@transiciones), &(Atom.to_string(&1) == n)) do
      nil -> {:error, :estado_invalido}
      k -> {:ok, k}
    end
  end

  def nuevo(id, tipo, cantidad, prioridad, zona, descripcion, responsable) do
    tipo = norm(tipo)

    with true <- tipo in @tipos or {:error, :tipo_invalido},
         true <- (is_integer(cantidad) and cantidad > 0) or {:error, :cantidad_invalida},
         {:ok, prio} <- parse_prioridad(prioridad),
         true <- norm(zona) != "" or {:error, :zona_vacia} do
      {:ok, %__MODULE__{id: id, tipo: tipo, cantidad: cantidad, prioridad: prio, zona: norm(zona),
                        descripcion: descripcion, responsable: responsable}}
    end
  end

  def restante(n), do: n.cantidad - n.asignado

  def puede_asignar(%{estado: :pendiente} = n, cantidad) do
    cond do
      not (is_integer(cantidad) and cantidad > 0) -> {:error, :cantidad_invalida}
      cantidad > restante(n) -> {:error, :excede_necesidad}
      true -> :ok
    end
  end

  def puede_asignar(_, _), do: {:error, :necesidad_cerrada_o_ya_asignada}

  @doc "Registra una asignación; al completar la cantidad pasa a :asignada."
  def aplicar_asignacion(n, cantidad) do
    n = %{n | asignado: n.asignado + cantidad}
    if n.asignado == n.cantidad, do: %{n | estado: :asignada}, else: n
  end

  def transicion(n, nuevo) do
    if nuevo in Map.get(@transiciones, n.estado, []),
      do: {:ok, %{n | estado: nuevo}},
      else: {:error, :transicion_invalida}
  end

  def filtrar(needs, filtros) do
    filtros = Keyword.take(filtros, [:zona, :tipo, :prioridad, :estado])
    Enum.filter(needs, fn n ->
      Enum.all?(filtros, fn {k, v} -> norm(Map.get(n, k)) == norm(v) end)
    end)
  end

  @doc "RECURSIVA (merge sort): ordena por prioridad (crítica primero) y luego por id."
  def ordenar([]), do: []
  def ordenar([x]), do: [x]

  def ordenar(lista) do
    {a, b} = Enum.split(lista, div(length(lista), 2))
    mezclar(ordenar(a), ordenar(b))
  end

  defp mezclar([], b), do: b
  defp mezclar(a, []), do: a

  defp mezclar([x | xs] = a, [y | ys] = b) do
    if clave(x) <= clave(y), do: [x | mezclar(xs, b)], else: [y | mezclar(a, ys)]
  end

  defp clave(n), do: {Keyword.fetch!(@prioridades, n.prioridad), n.id}

  def a_linea(n) do
    [n.id, n.tipo, n.cantidad, n.asignado, n.prioridad, n.zona, n.descripcion, n.responsable, n.estado]
    |> Enum.map_join("|", &P.limpiar/1)
  end

  def de_linea(linea) do
    with [id, tipo, cant, asig, prio, zona, desc, resp, est] <- String.split(linea, "|"),
         {:ok, n} <- nuevo(id, tipo, String.to_integer(cant), prio, zona, desc, resp),
         {:ok, e} <- parse_estado(est) do
      {:ok, %{n | asignado: String.to_integer(asig), estado: e}}
    else
      _ -> {:error, :linea_invalida}
    end
  end
end
