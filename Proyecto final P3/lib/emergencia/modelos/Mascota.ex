defmodule Emergencia.Modelos.Mascota do
  @moduledoc """
  Modelo de dominio para reportes de mascotas perdidas y encontradas.
  """

  @tipos_validos [:perdida, :encontrada]
  @estados_validos [:activa, :posible_coincidencia, :resuelta]

  defstruct [
    :id,
    :tipo_reporte,
    :especie,
    :nombre,
    :caracteristicas,
    :color,
    :tamano,
    :zona,
    :contacto,
    estado: :activa,
    id_pareja_resuelta: nil
  ]

  def nuevo(id, tipo_reporte, especie, nombre, caracteristicas, color, tamano, zona, contacto) do
    tipo_atom = normalizar_tipo(tipo_reporte)

    cond do
      is_nil(id) or String.trim(to_string(id)) == "" ->
        {:error, :id_invalido}

      tipo_atom not in @tipos_validos ->
        {:error, :tipo_reporte_mascota_invalido}

      is_nil(especie) or String.trim(to_string(especie)) == "" ->
        {:error, :especie_invalida}

      is_nil(zona) or String.trim(to_string(zona)) == "" ->
        {:error, :zona_invalida}

      is_nil(contacto) or String.trim(to_string(contacto)) == "" ->
        {:error, :contacto_invalido}

      true ->
        nombre_norm =
          if is_nil(nombre) or String.trim(to_string(nombre)) == "",
            do: "desconocido",
            else: String.trim(to_string(nombre))

        {:ok,
         %__MODULE__{
           id: String.trim(to_string(id)),
           tipo_reporte: tipo_atom,
           especie: String.downcase(String.trim(to_string(especie))),
           nombre: nombre_norm,
           caracteristicas: String.downcase(String.trim(to_string(caracteristicas || ""))),
           color: String.downcase(String.trim(to_string(color || ""))),
           tamano: String.downcase(String.trim(to_string(tamano || ""))),
           zona: String.trim(to_string(zona)),
           contacto: String.trim(to_string(contacto)),
           estado: :activa,
           id_pareja_resuelta: nil
         }}
    end
  end

  def marcar_posible_coincidencia(%__MODULE__{estado: :resuelta}),
    do: {:error, :reporte_ya_resuelto}

  def marcar_posible_coincidencia(%__MODULE__{} = m),
    do: {:ok, %{m | estado: :posible_coincidencia}}

  @doc """
  Cierra el reporte asociándolo al reporte contraparte. Impide doble resolución.
  """
  def resolver(%__MODULE__{estado: :resuelta}, _id_pareja),
    do: {:error, :reporte_ya_resuelto}

  def resolver(%__MODULE__{} = m, id_pareja) do
    {:ok, %{m | estado: :resuelta, id_pareja_resuelta: id_pareja}}
  end

  def a_linea(%__MODULE__{} = m) do
    [
      m.id,
      Atom.to_string(m.tipo_reporte),
      m.especie,
      m.nombre,
      String.replace(m.caracteristicas, "|", "/"),
      m.color,
      m.tamano,
      m.zona,
      m.contacto,
      Atom.to_string(m.estado),
      m.id_pareja_resuelta || ""
    ]
    |> Enum.join("|")
  end

  def desde_linea(linea) do
    case String.split(String.trim(linea), "|") do
      [id, tipo, esp, nom, car, col, tam, zona, cont, est, pareja] ->
        {:ok,
         %__MODULE__{
           id: id,
           tipo_reporte: String.to_existing_atom(tipo),
           especie: esp,
           nombre: nom,
           caracteristicas: car,
           color: col,
           tamano: tam,
           zona: zona,
           contacto: cont,
           estado: String.to_existing_atom(est),
           id_pareja_resuelta: if(pareja == "", do: nil, else: pareja)
         }}

      _ ->
        {:error, :formato_mascota_invalido}
    end
  end

  def normalizar_tipo(t) when is_atom(t) and t in @tipos_validos, do: t

  def normalizar_tipo(t) when is_binary(t) do
    case String.downcase(String.trim(t)) do
      "perdida" -> :perdida
      "lost" -> :perdida
      "encontrada" -> :encontrada
      "found" -> :encontrada
      _ -> :invalido
    end
  end

  def normalizar_tipo(_), do: :invalido

  def estados_validos, do: @estados_validos
end
