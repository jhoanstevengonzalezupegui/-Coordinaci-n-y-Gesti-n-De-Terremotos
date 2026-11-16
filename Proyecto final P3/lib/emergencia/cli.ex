defmodule Emergencia.CLI do
  @moduledoc """
  Interfaz de línea de comandos (CLI) interactiva para el Sistema Distribuido
  de Gestión de Emergencias.
  """

  alias Emergencia.Servidores.{
    AlberguesServer,
    FamiliaresServer,
    InventarioServer,
    MascotasServer,
    UsuariosServer,
    ZonasServer
  }

  def main(_args \\ []) do
    iniciar()
  end

  def iniciar do
    IO.puts("\n============================================================")
    IO.puts("  SISTEMA DE GESTION DE EMERGENCIAS Y AYUDA HUMANITARIA")
    IO.puts("============================================================")
    IO.puts("Escribe 'ayuda' para ver los comandos disponibles o 'salir'.\n")
    ciclo(%{usuario: nil})
  end

  defp ciclo(sesion) do
    prompt =
      case sesion.usuario do
        nil -> "emergencia(sin_sesion)> "
        u -> "emergencia(#{u.username}:#{u.rol}@#{u.zona_principal})> "
      end

    case IO.gets(prompt) do
      :eof ->
        IO.puts("\nSaliendo del sistema...")
        :ok

      {:error, razon} ->
        IO.puts("Error leyendo entrada: #{inspect(razon)}")
        :ok

      linea ->
        tokens = tokenizar(linea)

        case procesar_comando(tokens, sesion) do
          {:salir, _} ->
            IO.puts("Sesión finalizada. Hasta pronto.")
            :ok

          {:ok, nueva_sesion} ->
            ciclo(nueva_sesion)
        end
    end
  end

  # ============================================================================
  # PROCESAMIENTO DE COMANDOS
  # ============================================================================

  defp procesar_comando([], sesion), do: {:ok, sesion}

  defp procesar_comando(["salir"], sesion), do: {:salir, sesion}
  defp procesar_comando(["exit"], sesion), do: {:salir, sesion}

  defp procesar_comando(["ayuda"], sesion) do
    mostrar_ayuda()
    {:ok, sesion}
  end

  defp procesar_comando(["help"], sesion) do
    mostrar_ayuda()
    {:ok, sesion}
  end

  # --- SESIÓN Y USUARIOS ---

  defp procesar_comando(["connect", username, password, rol_str, zona | resto], sesion) do
    nombre =
      case resto do
        [] -> username
        [n | _] -> n
      end

    rol = String.to_atom(rol_str)

    case UsuariosServer.connect(username, password, rol, zona, nombre) do
      {:ok, estado, usuario} ->
        IO.puts(
          "[OK] Usuario '#{usuario.username}' (#{estado}) con rol #{usuario.rol} en zona #{usuario.zona_principal}."
        )

        {:ok, %{sesion | usuario: usuario}}

      {:error, razon} ->
        IO.puts("[ERROR] No se pudo iniciar sesión: #{inspect(razon)}")
        {:ok, sesion}
    end
  end

  defp procesar_comando(["whoami"], sesion) do
    case sesion.usuario do
      nil ->
        IO.puts("No hay sesión activa. Usa: connect <usuario> <clave> <rol> <zona> [nombre]")

      u ->
        IO.puts(
          "Usuario: #{u.username} | Nombre: #{u.nombre_completo} | Rol: #{u.rol} | Zona: #{u.zona_principal}"
        )
    end

    {:ok, sesion}
  end

  defp procesar_comando(["disconnect"], sesion) do
    IO.puts("[OK] Sesión cerrada localmente.")
    {:ok, %{sesion | usuario: nil}}
  end

  # --- ZONAS AFECTADAS ---

  defp procesar_comando(["zona_registrar", codigo, nombre, riesgo_str, afectados_str], sesion) do
    with {:ok, _} <- verificar_permiso(sesion, :registrar_zona),
         {afectados, ""} <- Integer.parse(afectados_str),
         {:ok, zona} <- ZonasServer.registrar_zona(codigo, nombre, String.to_atom(riesgo_str), afectados) do
      IO.puts("[OK] Zona registrada: #{zona.codigo} - #{zona.nombre} (Afectación: #{zona.nivel_afectacion})")
    else
      err -> imprimir_error(err)
    end

    {:ok, sesion}
  end

  defp procesar_comando(["sector_agregar", zona_cod, sec_cod, nombre, riesgo_str, afectados_str], sesion) do
    with {:ok, _} <- verificar_permiso(sesion, :registrar_zona),
         {afectados, ""} <- Integer.parse(afectados_str),
         {:ok, _zona} <-
           ZonasServer.agregar_sector(zona_cod, sec_cod, nombre, String.to_atom(riesgo_str), afectados) do
      IO.puts("[OK] Sector #{sec_cod} agregado a la zona #{zona_cod}.")
    else
      err -> imprimir_error(err)
    end

    {:ok, sesion}
  end

  defp procesar_comando(["punto_agregar", zona_cod, sec_cod, punto_cod, nombre, tipo], sesion) do
    with {:ok, _} <- verificar_permiso(sesion, :registrar_zona),
         {:ok, _zona} <- ZonasServer.agregar_punto_atencion(zona_cod, sec_cod, punto_cod, nombre, tipo) do
      IO.puts("[OK] Punto de atención #{punto_cod} (#{tipo}) agregado al sector #{sec_cod}.")
    else
      err -> imprimir_error(err)
    end

    {:ok, sesion}
  end

  defp procesar_comando(["zona_stats", zona_cod], sesion) do
    case ZonasServer.estadisticas_zona(zona_cod) do
      {:ok, stats} ->
        IO.puts("--- Estadísticas Recursivas Zona #{zona_cod} ---")
        IO.puts("  Total afectados       : #{stats.total_afectados}")
        IO.puts("  Total sectores        : #{stats.total_sectores}")
        IO.puts("  Sectores críticos     : #{stats.sectores_criticos}")
        IO.puts("  Puntos de atención    : #{stats.total_puntos_atencion}")

      err ->
        imprimir_error(err)
    end

    {:ok, sesion}
  end

  # --- INVENTARIO Y NECESIDADES ---

  defp procesar_comando(
         ["recurso_registrar", id, nombre, categoria, cant_str, unidad, ubicacion, zona],
         sesion
       ) do
    with {:ok, _} <- verificar_permiso(sesion, :registrar_recurso),
         {cantidad, ""} <- Integer.parse(cant_str),
         {:ok, rec} <-
           InventarioServer.registrar_recurso(id, nombre, categoria, cantidad, unidad, ubicacion, zona) do
      u_med = Map.get(rec, :unidad) || Map.get(rec, :unidad_medida, "unidades")
      IO.puts("[OK] Recurso #{rec.id} (#{rec.nombre}): #{rec.cantidad_disponible} #{u_med} en #{rec.zona}.")
    else
      err -> imprimir_error(err)
    end

    {:ok, sesion}
  end

  defp procesar_comando(["necesidad_registrar", tipo_str, cant_str, prio_str, zona, descripcion], sesion) do
    usuario = if sesion.usuario, do: sesion.usuario.username, else: "anonimo"

    with {:ok, _} <- verificar_permiso(sesion, :registrar_necesidad),
         {cantidad, ""} <- Integer.parse(cant_str),
         {:ok, nec} <-
           InventarioServer.registrar_necesidad(
             String.to_atom(tipo_str),
             cantidad,
             String.to_atom(prio_str),
             zona,
             descripcion,
             usuario,
             "general",
             nil
           ) do
      IO.puts("[OK] Necesidad registrada con ID: #{nec.id} (Prioridad: #{nec.prioridad}, Cantidad: #{nec.cantidad})")
    else
      err -> imprimir_error(err)
    end

    {:ok, sesion}
  end

  defp procesar_comando(["recurso_asignar", necesidad_id, recurso_id, cant_str], sesion) do
    with {:ok, _} <- verificar_permiso(sesion, :asignar_recurso),
         {cantidad, ""} <- Integer.parse(cant_str),
         {:ok, resultado} <- InventarioServer.asignar_recurso(necesidad_id, recurso_id, cantidad) do
      IO.puts("[OK] Asignación completada: #{inspect(resultado)}")
    else
      err -> imprimir_error(err)
    end

    {:ok, sesion}
  end

  defp procesar_comando(["inventario", nombre_recurso], sesion) do
    disp = InventarioServer.consultar_disponibilidad(nombre_recurso, nil)
    IO.puts("Disponibilidad para '#{nombre_recurso}': #{disp}")
    {:ok, sesion}
  end

  defp procesar_comando(["inventario", nombre_recurso, zona], sesion) do
    disp = InventarioServer.consultar_disponibilidad(nombre_recurso, zona)
    IO.puts("Disponibilidad para '#{nombre_recurso}' en zona '#{zona}': #{disp}")
    {:ok, sesion}
  end

  # --- ALBERGUES ---

  defp procesar_comando(["albergue_registrar", id, nombre, zona, cap_str], sesion) do
    with {:ok, _} <- verificar_permiso(sesion, :gestionar_albergue),
         {capacidad, ""} <- Integer.parse(cap_str),
         {:ok, alb} <- AlberguesServer.registrar_albergue(id, nombre, zona, capacidad) do
      IO.puts("[OK] Albergue #{alb.id} (#{alb.nombre}) creado con capacidad #{alb.capacidad_maxima}.")
    else
      err -> imprimir_error(err)
    end

    {:ok, sesion}
  end

  defp procesar_comando(["albergue_ingreso", albergue_id, documento], sesion) do
    with {:ok, _} <- verificar_permiso(sesion, :gestionar_albergue),
         {:ok, alb} <- AlberguesServer.registrar_ingreso(albergue_id, documento) do
      IO.puts("[OK] Ingreso registrado en #{alb.id}. Ocupación actual: #{MapSet.size(alb.ocupantes)}/#{alb.capacidad_maxima}.")
    else
      err -> imprimir_error(err)
    end

    {:ok, sesion}
  end

  defp procesar_comando(["albergue_salida", albergue_id, documento], sesion) do
    with {:ok, _} <- verificar_permiso(sesion, :gestionar_albergue),
         {:ok, alb} <- AlberguesServer.registrar_salida(albergue_id, documento) do
      IO.puts("[OK] Salida registrada en #{alb.id}. Ocupación actual: #{MapSet.size(alb.ocupantes)}/#{alb.capacidad_maxima}.")
    else
      err -> imprimir_error(err)
    end

    {:ok, sesion}
  end

  # --- FAMILIARES Y MENSAJERÍA ---

  defp procesar_comando(["persona_reportar", doc, nombre, zona, estado_str, edad_str], sesion) do
    with {edad, ""} <- Integer.parse(edad_str),
         {:ok, p} <-
           FamiliaresServer.reportar_o_actualizar_persona(
             doc,
             nombre,
             zona,
             String.to_atom(estado_str),
             edad
           ) do
      IO.puts("[OK] Persona #{p.nombre} (Doc: #{p.documento}) registrada con estado '#{p.estado}'.")
    else
      err -> imprimir_error(err)
    end

    {:ok, sesion}
  end

  defp procesar_comando(["mensaje_enviar", doc_destino, contenido], sesion) do
    remitente = if sesion.usuario, do: sesion.usuario.username, else: "familiar_externo"

    case FamiliaresServer.enviar_mensaje(remitente, doc_destino, contenido) do
      {:ok, msg} ->
        IO.puts("[OK] Mensaje #{msg.id} enviado para documento #{doc_destino}.")

      err ->
        imprimir_error(err)
    end

    {:ok, sesion}
  end

  defp procesar_comando(["mensajes", doc], sesion) do
    msgs = FamiliaresServer.listar_mensajes(doc)

    if msgs == [] do
      IO.puts("No hay mensajes registrados para el documento #{doc}.")
    else
      IO.puts("--- Mensajes para #{doc} ---")

      Enum.each(msgs, fn m ->
        IO.puts("  [#{m.id}] De #{m.remitente} (#{m.estado}): #{m.contenido}")
      end)
    end

    {:ok, sesion}
  end

  # --- MASCOTAS ---

  defp procesar_comando(
         ["mascota_reportar", tipo_str, especie, nombre, caract, color, tamano, zona, contacto | resto],
         sesion
       ) do
    id_opc =
      case resto do
        [id | _] -> id
        [] -> nil
      end

    case MascotasServer.reportar_mascota(
           String.to_atom(tipo_str),
           especie,
           nombre,
           caract,
           color,
           tamano,
           zona,
           contacto,
           id_opc
         ) do
      {:ok, m} ->
        IO.puts("[OK] Reporte de mascota #{m.id} (#{m.tipo_reporte}) registrado en zona #{m.zona}.")

      err ->
        imprimir_error(err)
    end

    {:ok, sesion}
  end

  defp procesar_comando(["mascota_confirmar", id_perdida, id_encontrada], sesion) do
    case MascotasServer.confirmar_coincidencia(id_perdida, id_encontrada) do
      {:ok, res} ->
        IO.puts("[OK] Coincidencia confirmada: #{inspect(res)}")

      err ->
        imprimir_error(err)
    end

    {:ok, sesion}
  end

  # --- DEMOSTRACIÓN DE CONCURRENCIA ---

  defp procesar_comando(["simular_concurrencia"], sesion) do
    IO.puts("\n--- Simulación de Conflicto Concurrente sobre Inventario ---")
    rec_id = "agua_sim_#{System.unique_integer([:positive])}"

    {:ok, _} =
      InventarioServer.registrar_recurso(rec_id, rec_id, "hidratacion", 50, "litros", "acopio_sim", "centro")

    {:ok, n1} =
      InventarioServer.registrar_necesidad(:agua, 30, :critica, "centro", "Hospital Centro", "coord1", "general", nil)

    {:ok, n2} =
      InventarioServer.registrar_necesidad(:agua, 25, :alta, "centro", "Refugio Sur", "coord2", "general", nil)

    IO.puts("Stock inicial (#{rec_id}): 50 litros.")
    IO.puts("Lanzando 2 procesos simultáneos: Proceso A pide 30L y Proceso B pide 25L...")

    t1 = Task.async(fn -> {:proceso_a, InventarioServer.asignar_recurso(n1.id, rec_id, 30)} end)
    t2 = Task.async(fn -> {:proceso_b, InventarioServer.asignar_recurso(n2.id, rec_id, 25)} end)

    resultados = Task.await_many([t1, t2])

    Enum.each(resultados, fn {proc, res} ->
      IO.puts("  Resultado #{proc}: #{inspect(res)}")
    end)

    stock_final = InventarioServer.consultar_disponibilidad(rec_id, nil)
    IO.puts("Stock final garantizado (nunca negativo): #{stock_final} litros.\n")
    {:ok, sesion}
  end

  defp procesar_comando(otro, sesion) do
    IO.puts("Comando no reconocido: #{Enum.join(otro, " ")}. Escribe 'ayuda' para ver opciones.")
    {:ok, sesion}
  end

  # ============================================================================
  # AUXILIARES
  # ============================================================================

  defp verificar_permiso(%{usuario: nil}, _accion) do
    {:error, :debe_iniciar_sesion_con_connect}
  end

  defp verificar_permiso(%{usuario: usuario}, accion) do
    UsuariosServer.autorizar(usuario.username, accion)
  end

  defp imprimir_error({:error, razon}) do
    IO.puts("[ERROR] #{inspect(razon)}")
  end

  defp imprimir_error(otro) do
    IO.puts("[ERROR] Parámetros inválidos: #{inspect(otro)}")
  end

  defp tokenizar(linea) do
    patron = Regex.compile!("\"([^\"]*)\"|(\\S+)")

    Regex.scan(patron, String.trim(linea))
    |> Enum.map(fn
      [_, con_comillas] when con_comillas != "" -> con_comillas
      [_, "", sin_comillas] -> sin_comillas
      [_, con_comillas] -> con_comillas
    end)
  end

  defp mostrar_ayuda do
    [
      "Comandos disponibles (usa comillas dobles para textos con espacios):",
      "  connect <user> <pass> <rol> <zona> [nombre]   - Inicia sesión (roles: coordinador, voluntario, ciudadano, organizacion)",
      "  whoami                                        - Muestra usuario actual",
      "  disconnect                                    - Cierra sesión actual",
      "  zona_registrar <cod> <nombre> <riesgo> <afec> - Registra zona (riesgo: bajo, medio, alto, critico)",
      "  sector_agregar <z_cod> <s_cod> <nom> <r> <af> - Agrega sector a zona",
      "  punto_agregar <z_cod> <s_cod> <p_cod> <n> <t> - Agrega punto de atención",
      "  zona_stats <zona_cod>                         - Calcula estadísticas recursivas de zona",
      "  recurso_registrar <id> <nom> <cat> <cant> <u_med> <ubic> <zona>",
      "  necesidad_registrar <tipo> <cant> <prio> <zona> <desc>",
      "  recurso_asignar <necesidad_id> <recurso_id> <cant>",
      "  inventario <nombre_recurso> [zona]",
      "  albergue_registrar <id> <nombre> <zona> <capacidad>",
      "  albergue_ingreso <albergue_id> <documento>",
      "  albergue_salida <albergue_id> <documento>",
      "  persona_reportar <doc> <nombre> <zona> <estado> <edad>",
      "  mensaje_enviar <doc_destino> <contenido>",
      "  mensajes <doc>",
      "  mascota_reportar <perdida|encontrada> <esp> <nom> <caract> <color> <tam> <zona> <contacto> [id]",
      "  mascota_confirmar <id_perdida> <id_encontrada>",
      "  simular_concurrencia                          - Ejecuta prueba de carrera en inventario en vivo",
      "  salir                                         - Termina el programa"
    ]
    |> Enum.each(&IO.puts/1)
  end
end
