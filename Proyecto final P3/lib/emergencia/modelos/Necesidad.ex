defmodule Emergencia.Modelos.Necesidad do
  @moduledoc """
  Modelo de dominio para solicitudes de ayuda (necesidades puntuales).
  Incluye control estricto de transiciones de estado y ordenamiento recursivo por prioridad.
  """

  @tipos_validos [
    :agua,
    :alimentos,
    :medicamentos,
    :primeros_auxilios,
    :refugio,
    :transporte,
    :rescate,
    :otra
  ]

  @prioridades_validas [:critica, :alta, :media, :baja]
  @estados_validos [:pendiente, :asignada, :en_atencion, :atendida, :cancelada]

  defstruct [
    :id,
    :tipo,
    :descripcion,
    :cantidad_requerida,
    :zona,
    :prioridad,
    :responsable,
    entidad_asociada: "general",
    cantidad_asignada: 0,
    estado: :pendiente,
    fecha_registro: nil
  ]

  @doc """
  Crea una nueva necesidad validando tipo, prioridad y cantidad > 0.
  """
  def nueva(id, tipo, descripcion, cantidad, zona, prioridad, responsable, entidad \\ "general") do
    tipo_atom = normalizar_tipo(tipo)
    prio_atom = normalizar_prioridad(prioridad)

    cond do
      is_nil(id) or String.trim(to_string(id)) == "" ->
        {:error, :id_invalido}

      tipo_atom not in @tipos_validos ->
        {:error, :tipo_necesidad_invalido}

      is_nil(descripcion) or String.trim(to_string(descripcion)) == "" ->
        {:error, :descripcion_invalida}

      not is_integer(cantidad) or cantidad <= 0 ->
        {:error, :cantidad_invalida}

      is_nil(zona) or String.trim(to_string(zona)) == "" ->
        {:error, :zona_invalida}

      prio_atom not in @prioridades_validas ->
        {:error, :prioridad_invalida}

      is_nil(responsable) or String.trim(to_string(responsable)) == "" ->
        {:error, :responsable_invalido}

      true ->
        {:ok,
         %__MODULE__{
           id: String.trim(to_string(id)),
           tipo: tipo_atom,
           descripcion: String.trim(to_string(descripcion)),
           cantidad_requerida: cantidad,
           zona: String.trim(to_string(zona)),
           prioridad: prio_atom,
           responsable: String.trim(to_string(responsable)),
           entidad_asociada: String.trim(to_string(entidad)),
           cantidad_asignada: 0,
           estado: :pendiente,
           fecha_registro: timestamp_actual()
         }}
    end
  end

  @doc """
  Asigna una cantidad de recursos a la necesidad.
  Impide asignar recursos a necesidades ya atendidas o canceladas.
  """
  def asignar_recurso(%__MODULE__{estado: estado}, _cantidad)
      when estado in [:atendida, :cancelada] do
    {:error, :necesidad_cerrada}
  end

  def asignar_recurso(%__MODULE__{}, cantidad) when not is_integer(cantidad) or cantidad <= 0 do
    {:error, :cantidad_asignacion_invalida}
  end

  def asignar_recurso(%__MODULE__{} = nec, cantidad) do
    nueva_asignada = nec.cantidad_asignada + cantidad

    if nueva_asignada > nec.cantidad_requerida do
      {:error, :excede_cantidad_requerida}
    else
      nuevo_estado =
        if nueva_asignada == nec.cantidad_requerida do
          :atendida
        else
          :asignada
        end

      {:ok, %{nec | cantidad_asignada: nueva_asignada, estado: nuevo_estado}}
    end
  end

  @doc """
  Cambia el estado siguiendo transiciones válidas del ciclo de vida.
  """
  def cambiar_estado(%__MODULE__{estado: actual}, nuevo_estado) when actual == nuevo_estado do
    {:error, :estado_sin_cambios}
  end

  def cambiar_estado(%__MODULE__{estado: actual}, _nuevo_estado)
      when actual in [:atendida, :cancelada] do
    {:error, :transicion_desde_estado_final_no_permitida}
  end

  def cambiar_estado(%__MODULE__{estado: :pendiente} = nec, nuevo)
      when nuevo in [:asignada, :en_atencion, :cancelada] do
    {:ok, %{nec | estado: nuevo}}
  end

  def cambiar_estado(%__MODULE__{estado: :asignada} = nec, nuevo)
      when nuevo in [:en_atencion, :atendida, :cancelada] do
    {:ok, %{nec | estado: nuevo}}
  end

  def cambiar_estado(%__MODULE__{estado: :en_atencion} = nec, nuevo)
      when nuevo in [:atendida, :cancelada] do
    {:ok, %{nec | estado: nuevo}}
  end

  def cambiar_estado(%__MODULE__{}, _nuevo_estado) do
    {:error, :transicion_estado_invalida}
  end

  @doc """
  FUNCIÓN RECURSIVA #2:
  Ordena recursivamente una lista de necesidades por prioridad (critica > alta > media > baja)
  usando ordenamiento por inserción recursivo.
  """
  def ordenar_por_prioridad([]), do: []

  def ordenar_por_prioridad([cabeza | resto]) do
    insertar_ordenado(cabeza, ordenar_por_prioridad(resto))
  end

  defp insertar_ordenado(elemento, []), do: [elemento]

  defp insertar_ordenado(elemento, [cabeza | resto]) do
    if peso_prioridad(elemento.prioridad) >= peso_prioridad(cabeza.prioridad) do
      [elemento, cabeza | resto]
    else
      [cabeza | insertar_ordenado(elemento, resto)]
    end
  end

  def peso_prioridad(:critica), do: 4
  def peso_prioridad(:alta), do: 3
  def peso_prioridad(:media), do: 2
  def peso_prioridad(:baja), do: 1
  def peso_prioridad(_), do: 0

  @doc """
  Filtra necesidades por criterios opcionales (zona, tipo, prioridad, estado)
  y las retorna ordenadas por prioridad.
  """
  def filtrar(lista_necesidades, filtros \\ %{}) do
    lista_necesidades
    |> Enum.filter(fn n ->
      coincide_filtro?(n.zona, Map.get(filtros, :zona)) and
        coincide_filtro?(n.tipo, Map.get(filtros, :tipo)) and
        coincide_filtro?(n.prioridad, Map.get(filtros, :prioridad)) and
        coincide_filtro?(n.estado, Map.get(filtros, :estado))
    end)
    |> ordenar_por_prioridad()
  end

  defp coincide_filtro?(_valor, nil), do: true
  defp coincide_filtro?(valor, esperado), do: to_string(valor) == to_string(esperado)

  @doc """
  Serialización a texto plano para data/necesidades.txt.
  """
  def a_linea(%__MODULE__{} = n) do
    [
      n.id,
      Atom.to_string(n.tipo),
      String.replace(n.descripcion, "|", "/"),
      Integer.to_string(n.cantidad_requerida),
      Integer.to_string(n.cantidad_asignada),
      n.zona,
      Atom.to_string(n.prioridad),
      n.responsable,
      n.entidad_asociada,
      Atom.to_string(n.estado),
      n.fecha_registro || ""
    ]
    |> Enum.join("|")
  end

  def desde_linea(linea) do
    case String.split(String.trim(linea), "|") do
      [id, tipo, desc, req, asig, zona, prio, resp, ent, est, fecha] ->
        {:ok,
         %__MODULE__{
           id: id,
           tipo: String.to_existing_atom(tipo),
           descripcion: desc,
           cantidad_requerida: String.to_integer(req),
           cantidad_asignada: String.to_integer(asig),
           zona: zona,
           prioridad: String.to_existing_atom(prio),
           responsable: resp,
           entidad_asociada: ent,
           estado: String.to_existing_atom(est),
           fecha_registro: fecha
         }}

      _ ->
        {:error, :formato_necesidad_invalido}
    end
  end

  def normalizar_tipo(t) when is_atom(t) and t in @tipos_validos, do: t

  def normalizar_tipo(t) when is_binary(t) do
    case String.downcase(String.trim(t)) do
      "agua" -> :agua
      "alimentos" -> :alimentos
      "medicamentos" -> :medicamentos
      "primeros_auxilios" -> :primeros_auxilios
      "refugio" -> :refugio
      "transporte" -> :transporte
      "rescate" -> :rescate
      "otra" -> :otra
      _ -> :invalido
    end
  end

  def normalizar_tipo(_), do: :invalido

  def normalizar_prioridad(p) when is_atom(p) and p in @prioridades_validas, do: p

  def normalizar_prioridad(p) when is_binary(p) do
    case String.downcase(String.trim(p)) do
      "critica" -> :critica
      "crítica" -> :critica
      "alta" -> :alta
      "media" -> :media
      "baja" -> :baja
      _ -> :invalido
    end
  end

  def normalizar_prioridad(_), do: :invalido

  def estados_validos, do: @estados_validos

  defp timestamp_actual do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end
end
