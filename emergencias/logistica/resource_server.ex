defmodule Emergencias.Logistica.ResourceServer do
  @moduledoc """
  GenServer dueño del inventario. Todas las operaciones se procesan una a una
  desde su buzón, por lo que la cantidad asignada nunca supera el inventario real
  (regla de concurrencia obligatoria).
  """
  use GenServer
  alias Emergencias.Logistica.{Recurso, Persistencia}

  @f_rec "recursos.txt"
  @f_mov "movimientos.txt"

  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  # ---- API ----
  def registrar(codigo, nombre, cat, cant, unidad, ubic, zona \\ "", s \\ __MODULE__),
    do: GenServer.call(s, {:registrar, {codigo, nombre, cat, cant, unidad, ubic, zona}})

  def entrada(codigo, cant, s \\ __MODULE__), do: GenServer.call(s, {:mover, :entrada, codigo, cant})
  def salida(codigo, cant, s \\ __MODULE__), do: GenServer.call(s, {:mover, :salida, codigo, cant})

  def transferir(codigo, origen, destino, cant, s \\ __MODULE__),
    do: GenServer.call(s, {:transferir, codigo, Recurso.normalizar(origen), Recurso.normalizar(destino), cant})

  def asignar(categoria, cant, motivo \\ "", s \\ __MODULE__),
    do: GenServer.call(s, {:asignar, Recurso.normalizar(categoria), cant, motivo})

  def disponibilidad(categoria, zona \\ nil, s \\ __MODULE__),
    do: GenServer.call(s, {:disp, Recurso.normalizar(categoria), zona && Recurso.normalizar(zona)})

  def listar(s \\ __MODULE__), do: GenServer.call(s, :listar)
  def historial(s \\ __MODULE__), do: GenServer.call(s, :historial)

  # ---- callbacks ----
  @impl true
  def init(opts) do
    dir = Keyword.get(opts, :dir, Application.get_env(:emergencias, :data_dir, "data"))

    recursos =
      for l <- Persistencia.leer(dir, @f_rec), {:ok, r} <- [safe(l)], into: %{}, do: {r.codigo, r}

    {:ok, %{dir: dir, recursos: recursos, historial: Persistencia.leer(dir, @f_mov) |> Enum.reverse()}}
  end

  @impl true
  def handle_call({:registrar, {c, n, cat, cant, u, ub, z}}, _from, st) do
    with {:ok, r} <- Recurso.nuevo(c, n, cat, cant, u, ub, z),
         :ok <- if(Map.has_key?(st.recursos, r.codigo), do: {:error, :codigo_duplicado}, else: :ok) do
      {:reply, {:ok, r}, commit(st, Map.put(st.recursos, r.codigo, r), [mov(r.codigo, :entrada, cant, "registro")])}
    else
      e -> {:reply, e, st}
    end
  end

  def handle_call({:mover, tipo, codigo, cant}, _from, st) do
    with {:ok, r} <- fetch(st, codigo),
         :ok <- positivo(cant),
         {:ok, nueva} <- aplicar(tipo, r.cantidad, cant) do
      r2 = %{r | cantidad: nueva}
      {:reply, {:ok, r2}, commit(st, Map.put(st.recursos, codigo, r2), [mov(codigo, tipo, cant, "manual")])}
    else
      e -> {:reply, e, st}
    end
  end

  def handle_call({:transferir, codigo, origen, destino, cant}, _from, st) do
    with {:ok, r} <- fetch(st, codigo),
         :ok <- positivo(cant),
         :ok <- if(r.ubicacion == origen and origen != destino, do: :ok, else: {:error, :ubicacion_invalida}),
         :ok <- if(cant <= r.cantidad, do: :ok, else: {:error, :inventario_insuficiente}) do
      cod_dest = "#{codigo}@#{destino}"
      dest = Map.get(st.recursos, cod_dest, %{r | codigo: cod_dest, cantidad: 0, ubicacion: destino})

      rec =
        st.recursos
        |> Map.put(codigo, %{r | cantidad: r.cantidad - cant})
        |> Map.put(cod_dest, %{dest | cantidad: dest.cantidad + cant})

      movs = [mov(codigo, :salida, cant, "transferencia a #{destino}"),
              mov(cod_dest, :entrada, cant, "transferencia desde #{origen}")]

      {:reply, {:ok, cod_dest}, commit(st, rec, movs)}
    else
      e -> {:reply, e, st}
    end
  end

  def handle_call({:asignar, categoria, cant, motivo}, _from, st) do
    candidatos =
      st.recursos
      |> Map.values()
      |> Enum.filter(&(&1.categoria == categoria))
      |> Enum.sort_by(&{-&1.cantidad, &1.codigo})

    with :ok <- positivo(cant),
         {:ok, {actualizados, tomados}} <- Recurso.tomar(candidatos, cant) do
      rec = Enum.reduce(actualizados, st.recursos, &Map.put(&2, &1.codigo, &1))
      movs = for {cod, t} <- tomados, do: mov(cod, :salida, t, "asignacion #{motivo}")
      {:reply, {:ok, tomados}, commit(st, rec, movs)}
    else
      e -> {:reply, e, st}
    end
  end

  def handle_call({:disp, cat, zona}, _from, st) do
    lista = st.recursos |> Map.values() |> Enum.filter(&(&1.categoria == cat and (zona == nil or &1.zona == zona)))
    {:reply, Recurso.total(lista), st}
  end

  def handle_call(:listar, _from, st), do: {:reply, st.recursos |> Map.values() |> Enum.sort_by(& &1.codigo), st}
  def handle_call(:historial, _from, st), do: {:reply, Enum.reverse(st.historial), st}

  # ---- helpers ----
  defp fetch(st, codigo) do
    case Map.fetch(st.recursos, codigo) do
      {:ok, r} -> {:ok, r}
      :error -> {:error, :recurso_no_existe}
    end
  end

  defp positivo(c) when is_integer(c) and c > 0, do: :ok
  defp positivo(_), do: {:error, :cantidad_invalida}
  defp aplicar(:entrada, actual, c), do: {:ok, actual + c}
  defp aplicar(:salida, actual, c) when c <= actual, do: {:ok, actual - c}
  defp aplicar(:salida, _, _), do: {:error, :inventario_insuficiente}

  defp mov(codigo, tipo, cant, detalle) do
    Enum.map_join([DateTime.to_iso8601(DateTime.utc_now()), codigo, tipo, cant, detalle], "|", &Persistencia.limpiar/1)
  end

  defp commit(st, recursos, movs) do
    lineas = recursos |> Map.values() |> Enum.sort_by(& &1.codigo) |> Enum.map(&Recurso.a_linea/1)
    Persistencia.guardar(st.dir, @f_rec, lineas)
    Persistencia.agregar(st.dir, @f_mov, movs)
    %{st | recursos: recursos, historial: Enum.reverse(movs) ++ st.historial}
  end

  defp safe(l) do
    Recurso.de_linea(l)
  rescue
    _ -> {:error, :linea_invalida}
  end
end
