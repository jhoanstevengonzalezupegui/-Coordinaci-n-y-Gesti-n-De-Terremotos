defmodule Emergencia.CLI do
  @moduledoc """
  Interfaz de línea de comandos (CLI) interactiva para el Sistema Distribuido
  de Gestión de Emergencias. Soporta los comandos oficiales del proyecto (en inglés)
  y sus alias en español.
  """

  alias Emergencia.OperacionesExtendidas

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
    IO.puts("Escribe 'ayuda' (o 'help') para ver los comandos o 'salir'.\n")
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

  defp procesar_comando([cmd], sesion) when cmd in ["salir", "exit", "quit"], do: {:salir, sesion}

  defp procesar_comando([cmd], sesion) when cmd in ["ayuda", "help"] do
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

    rol = normalizar_atomo(rol_str)

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

  # --- ZONAS AFECTADAS (register_zone) ---

  defp procesar_comando([cmd, codigo, nombre, riesgo_str], sesion)
       when cmd in ["register_zone", "zona_registrar"] do
    with {:ok, _} <- verificar_permiso(sesion, :registrar_zona),
         {:ok, zona} <- ZonasServer.registrar_zona(codigo, nombre, normalizar_atomo(riesgo_str), 0) do
      IO.puts("[OK] Zona registrada: #{zona.codigo} - #{zona.nombre} (Nivel: #{zona.nivel_afectacion})")
    else
      err -> imprimir_error(err)
    end

    {:ok, sesion}
  end

  defp procesar_comando([cmd, codigo, nombre, riesgo_str, afectados_str], sesion)
       when cmd in ["register_zone", "zona_registrar"] do
    with {:ok, _} <- verificar_permiso(sesion, :registrar_zona),
         {afectados, ""} <- Integer.parse(afectados_str),
         {:ok, zona} <-
           ZonasServer.registrar_zona(codigo, nombre, normalizar_atomo(riesgo_str), afectados) do
      IO.puts("[OK] Zona registrada: #{zona.codigo} - #{zona.nombre} (Nivel: #{zona.nivel_afectacion})")
    else
      err -> imprimir_error(err)
    end

    {:ok, sesion}
  end

  defp procesar_comando([cmd, zona_cod, sec_cod, nombre, riesgo_str, afectados_str], sesion)
       when cmd in ["add_sector", "sector_agregar"] do
    with {:ok, _} <- verificar_permiso(sesion, :registrar_zona),
         {afectados, ""} <- Integer.parse(afectados_str),
         {:ok, _zona} <-
           ZonasServer.agregar_sector(zona_cod, sec_cod, nombre, normalizar_atomo(riesgo_str), afectados) do
      IO.puts("[OK] Sector #{sec_cod} agregado a la zona #{zona_cod}.")
    else
      err -> imprimir_error(err)
    end

    {:ok, sesion}
  end

  defp procesar_comando([cmd, zona_cod, sec_cod, punto_cod, nombre, tipo], sesion)
       when cmd in ["add_point", "punto_agregar"] do
    with {:ok, _} <- verificar_permiso(sesion, :registrar_zona),
         {:ok, _zona} <- ZonasServer.agregar_punto_atencion(zona_cod, sec_cod, punto_cod, nombre, tipo) do
      IO.puts("[OK] Punto de atención #{punto_cod} (#{tipo}) agregado al sector #{sec_cod}.")
    else
      err -> imprimir_error(err)
    end

    {:ok, sesion}
  end

  defp procesar_comando([cmd, zona_cod], sesion) when cmd in ["zone_stats", "zona_stats"] do
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

  # --- INVENTARIO, TRANSFERENCIAS Y NECESIDADES ---

  # Formato oficial: register_resource R001 agua 200 litros centro_acopio_1
  defp procesar_comando([cmd, id, nombre, cant_str, unidad, ubicacion], sesion)
       when cmd in ["register_resource", "recurso_registrar"] do
    zona =
      if sesion.usuario do
        sesion.usuario.zona_principal
      else
        inferir_zona_ubicacion(ubicacion)
      end

    categoria = inferir_categoria(nombre)

    with {:ok, _} <- verificar_permiso(sesion, :registrar_recurso),
         {cantidad, ""} <- Integer.parse(cant_str),
         {:ok, rec} <-
           InventarioServer.registrar_recurso(id, nombre, categoria, cantidad, unidad, ubicacion, zona) do
      cod = OperacionesExtendidas.id_de(rec)
      u_med = Map.get(rec, :unidad) || Map.get(rec, :unidad_medida, "unidades")
      IO.puts("[OK] Recurso #{cod} (#{rec.nombre}): #{rec.cantidad_disponible} #{u_med} en #{rec.ubicacion} (#{rec.zona}).")
    else
      err -> imprimir_error(err)
    end

    {:ok, sesion}
  end

  # Formato extendido: register_resource R01 agua hidratacion 100 litros acopio_centro centro
  defp procesar_comando([cmd, id, nombre, categoria, cant_str, unidad, ubicacion, zona], sesion)
       when cmd in ["register_resource", "recurso_registrar"] do
    with {:ok, _} <- verificar_permiso(sesion, :registrar_recurso),
         {cantidad, ""} <- Integer.parse(cant_str),
         {:ok, rec} <-
           InventarioServer.registrar_recurso(id, nombre, categoria, cantidad, unidad, ubicacion, zona) do
      cod = OperacionesExtendidas.id_de(rec)
      u_med = Map.get(rec, :unidad) || Map.get(rec, :unidad_medida, "unidades")
      IO.puts("[OK] Recurso #{cod} (#{rec.nombre}): #{rec.cantidad_disponible} #{u_med} en #{rec.zona}.")
    else
      err -> imprimir_error(err)
    end

    {:ok, sesion}
  end

  # Formato oficial: transfer_resource R001 centro_acopio_1 albergue_2 30
  defp procesar_comando(["transfer_resource", rec_id, ubic_origen, ubic_dest, cant_str], sesion) do
    usuario = if sesion.usuario, do: sesion.usuario.username, else: "anonimo"

    with {:ok, _} <- verificar_permiso(sesion, :asignar_recurso),
         {cantidad, ""} <- Integer.parse(cant_str),
         {:ok, info} <-
           OperacionesExtendidas.transferir_desde_origen(rec_id, ubic_origen, ubic_dest, cantidad, usuario) do
      IO.puts(
        "[OK] Transferidos #{info.cantidad_transferida} de '#{info.recurso}' desde #{ubic_origen} (#{info.origen_id}) hacia #{info.ubicacion_destino} (#{info.zona_destino}) -> Nuevo lote: #{info.destino_id}."
      )
    else
      err -> imprimir_error(err)
    end

    {:ok, sesion}
  end

  # Alias en español: recurso_transferir R02 albergue_norte norte 20
  defp procesar_comando(["recurso_transferir", rec_id, ubic_dest, zona_dest, cant_str], sesion) do
    usuario = if sesion.usuario, do: sesion.usuario.username, else: "anonimo"

    with {:ok, _} <- verificar_permiso(sesion, :asignar_recurso),
         {cantidad, ""} <- Integer.parse(cant_str),
         {:ok, info} <-
           OperacionesExtendidas.transferir_recurso(rec_id, ubic_dest, zona_dest, cantidad, usuario) do
      IO.puts(
        "[OK] Transferidos #{info.cantidad_transferida} de '#{info.recurso}' desde #{info.origen_id} hacia #{info.ubicacion_destino} (#{info.zona_destino}) -> Nuevo lote: #{info.destino_id}."
      )
    else
      err -> imprimir_error(err)
    end

    {:ok, sesion}
  end

  defp procesar_comando([cmd | resto], sesion) when cmd in ["list_resources", "recursos"] do
    zona =
      case resto do
        ["zona=" <> z | _] -> z
        [z | _] -> z
        [] -> nil
      end

    lista = OperacionesExtendidas.listar_recursos(zona)

    if lista == [] do
      IO.puts("No hay recursos registrados para el filtro indicado.")
    else
      IO.puts("--- Inventario de Recursos ---")

      Enum.each(lista, fn r ->
        cod = OperacionesExtendidas.id_de(r)
        u_med = Map.get(r, :unidad) || Map.get(r, :unidad_medida, "unidades")

        IO.puts(
          "  [#{cod}] #{r.nombre} (#{r.categoria}): #{r.cantidad_disponible} #{u_med} | Ubic: #{r.ubicacion} | Zona: #{r.zona}"
        )
      end)
    end

    {:ok, sesion}
  end

  defp procesar_comando([cmd | resto], sesion) when cmd in ["critical_resources", "recursos_criticos"] do
    umbral =
      case resto do
        [u_str | _] ->
          case Integer.parse(u_str) do
            {n, ""} -> n
            _ -> 30
          end

        [] ->
          30
      end

    lista = OperacionesExtendidas.recursos_criticos(umbral)

    if lista == [] do
      IO.puts("No hay recursos en nivel crítico (<= #{umbral} unidades).")
    else
      IO.puts("--- Recursos en Nivel Crítico (<= #{umbral}) ---")

      Enum.each(lista, fn r ->
        cod = OperacionesExtendidas.id_de(r)
        u_med = Map.get(r, :unidad) || Map.get(r, :unidad_medida, "unidades")
        IO.puts("  [#{cod}] #{r.nombre}: #{r.cantidad_disponible} #{u_med} | Ubic: #{r.ubicacion} | Zona: #{r.zona}")
      end)
    end

    {:ok, sesion}
  end

  defp procesar_comando([cmd, tipo_str, cant_str, prio_str, zona, descripcion], sesion)
       when cmd in ["register_need", "necesidad_registrar"] do
    usuario = if sesion.usuario, do: sesion.usuario.username, else: "anonimo"

    with {:ok, _} <- verificar_permiso(sesion, :registrar_necesidad),
         {cantidad, ""} <- Integer.parse(cant_str),
         {:ok, nec} <-
           InventarioServer.registrar_necesidad(
             normalizar_atomo(tipo_str),
             cantidad,
             normalizar_atomo(prio_str),
             zona,
             descripcion,
             usuario,
             "general",
             nil
           ) do
      cod = OperacionesExtendidas.id_de(nec)
      cant = Map.get(nec, :cantidad) || Map.get(nec, :cantidad_requerida)
      IO.puts("[OK] Necesidad registrada con ID: #{cod} (Prioridad: #{nec.prioridad}, Cantidad: #{cant})")
    else
      err -> imprimir_error(err)
    end

    {:ok, sesion}
  end

  defp procesar_comando([cmd | resto], sesion) when cmd in ["list_needs", "necesidades"] do
    {zona, prio} = parsear_filtros_necesidades(resto)
    lista = OperacionesExtendidas.listar_necesidades(zona, prio)

    if lista == [] do
      IO.puts("No hay necesidades registradas con ese criterio.")
    else
      IO.puts("--- Necesidades Ordenadas por Prioridad ---")

      Enum.each(lista, fn n ->
        cod = OperacionesExtendidas.id_de(n)
        tipo = Map.get(n, :tipo) || Map.get(n, :categoria, :general)
        cant = Map.get(n, :cantidad) || Map.get(n, :cantidad_requerida, 0)

        IO.puts(
          "  [#{cod}] Prio: #{n.prioridad} | Estado: #{n.estado} | #{tipo} (#{cant}) | Zona: #{n.zona} | #{n.descripcion}"
        )
      end)
    end

    {:ok, sesion}
  end

  defp procesar_comando([cmd], sesion) when cmd in ["pending_needs", "necesidades_pendientes"] do
    lista = OperacionesExtendidas.listar_necesidades_pendientes()

    if lista == [] do
      IO.puts("No hay necesidades pendientes.")
    else
      IO.puts("--- Necesidades Pendientes (Ordenadas por Prioridad) ---")

      Enum.each(lista, fn n ->
        cod = OperacionesExtendidas.id_de(n)
        tipo = Map.get(n, :tipo) || Map.get(n, :categoria, :general)
        cant = Map.get(n, :cantidad) || Map.get(n, :cantidad_requerida, 0)
        asig = Map.get(n, :cantidad_asignada, 0)

        IO.puts(
          "  [#{cod}] Prio: #{n.prioridad} | Estado: #{n.estado} | #{tipo} (#{asig}/#{cant}) | Zona: #{n.zona} | #{n.descripcion}"
        )
      end)
    end

    {:ok, sesion}
  end

  defp procesar_comando([cmd, necesidad_id, recurso_o_nombre, cant_str], sesion)
       when cmd in ["assign_resource", "recurso_asignar"] do
    with {:ok, _} <- verificar_permiso(sesion, :asignar_recurso),
         {cantidad, ""} <- Integer.parse(cant_str),
         {:ok, resultado} <-
           OperacionesExtendidas.asignar_recurso_flexible(necesidad_id, recurso_o_nombre, cantidad) do
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

  defp procesar_comando([cmd, id, nombre, zona, cap_str], sesion)
       when cmd in ["register_shelter", "albergue_registrar"] do
    with {:ok, _} <- verificar_permiso(sesion, :gestionar_albergue),
         {capacidad, ""} <- Integer.parse(cap_str),
         {:ok, alb} <- AlberguesServer.registrar_albergue(id, nombre, zona, capacidad) do
      cod = OperacionesExtendidas.id_de(alb)
      cap = Map.get(alb, :capacidad_maxima) || Map.get(alb, :capacidad)
      IO.puts("[OK] Albergue #{cod} (#{alb.nombre}) creado con capacidad #{cap}.")
    else
      err -> imprimir_error(err)
    end

    {:ok, sesion}
  end

  defp procesar_comando([cmd, albergue_id, documento], sesion)
       when cmd in ["register_entry", "albergue_ingreso"] do
    with {:ok, _} <- verificar_permiso(sesion, :gestionar_albergue),
         {:ok, alb} <- AlberguesServer.registrar_ingreso(albergue_id, documento) do
      cod = OperacionesExtendidas.id_de(alb)
      cap = Map.get(alb, :capacidad_maxima) || Map.get(alb, :capacidad)
      ocup = MapSet.size(Map.get(alb, :personas_alojadas, MapSet.new()))
      IO.puts("[OK] Ingreso registrado en #{cod}. Ocupación actual: #{ocup}/#{cap}.")
    else
      err -> imprimir_error(err)
    end

    {:ok, sesion}
  end

  defp procesar_comando([cmd, albergue_id, documento], sesion)
       when cmd in ["register_exit", "albergue_salida"] do
    with {:ok, _} <- verificar_permiso(sesion, :gestionar_albergue),
         {:ok, alb} <- AlberguesServer.registrar_salida(albergue_id, documento) do
      cod = OperacionesExtendidas.id_de(alb)
      cap = Map.get(alb, :capacidad_maxima) || Map.get(alb, :capacidad)
      ocup = MapSet.size(Map.get(alb, :personas_alojadas, MapSet.new()))
      IO.puts("[OK] Salida registrada en #{cod}. Ocupación actual: #{ocup}/#{cap}.")
    else
      err -> imprimir_error(err)
    end

    {:ok, sesion}
  end

  defp procesar_comando([cmd, albergue_id], sesion)
       when cmd in ["check_shelter", "albergue_consultar"] do
    case OperacionesExtendidas.consultar_albergue(albergue_id) do
      {:ok, info} ->
        IO.puts("--- Albergue #{info.id}: #{info.nombre} (Zona: #{info.zona}) ---")
        IO.puts("  Ocupación   : #{info.ocupados}/#{info.capacidad} (#{info.porcentaje}%)")
        IO.puts("  Disponibles : #{info.disponibles} cupos")
        IO.puts("  Ocupantes   : #{inspect(info.lista_ocupantes)}")

      err ->
        imprimir_error(err)
    end

    {:ok, sesion}
  end

  defp procesar_comando([cmd], sesion) when cmd in ["shelters_report", "albergues_reporte"] do
    reporte = OperacionesExtendidas.reporte_albergues()

    if reporte == [] do
      IO.puts("No hay albergues registrados.")
    else
      IO.puts("--- Reporte de Albergues por Ocupación ---")

      Enum.each(reporte, fn a ->
        IO.puts(
          "  [#{a.id}] #{a.nombre} (#{a.zona}): #{a.ocupados}/#{a.capacidad} (#{a.porcentaje}%) - Libres: #{a.disponibles}"
        )
      end)
    end

    {:ok, sesion}
  end

  # --- FAMILIARES Y MENSAJERÍA ---

  # Formato oficial (4 args): report_person documento nombre zona estado
  defp procesar_comando([cmd, doc, nombre, zona, estado_str], sesion)
       when cmd in ["report_person", "persona_reportar"] do
    estado = normalizar_estado_persona(estado_str)

    res =
      case FamiliaresServer.reportar_o_actualizar_persona(doc, nombre, zona, estado, 0) do
        {:error, _} -> FamiliaresServer.reportar_o_actualizar_persona(doc, nombre, zona, estado, 1)
        ok -> ok
      end

    case res do
      {:ok, p} ->
        IO.puts("[OK] Persona #{p.nombre} (Doc: #{p.documento}) registrada con estado '#{p.estado}'.")

      err ->
        imprimir_error(err)
    end

    {:ok, sesion}
  end

  # Formato con edad (5 args): report_person documento nombre zona estado edad
  defp procesar_comando([cmd, doc, nombre, zona, estado_str, edad_str], sesion)
       when cmd in ["report_person", "persona_reportar"] do
    estado = normalizar_estado_persona(estado_str)

    with {edad, ""} <- Integer.parse(edad_str),
         {:ok, p} <- FamiliaresServer.reportar_o_actualizar_persona(doc, nombre, zona, estado, edad) do
      IO.puts("[OK] Persona #{p.nombre} (Doc: #{p.documento}) registrada con estado '#{p.estado}'.")
    else
      err -> imprimir_error(err)
    end

    {:ok, sesion}
  end

  defp procesar_comando([cmd, criterio], sesion) when cmd in ["find_person", "persona_buscar"] do
    resultados = OperacionesExtendidas.buscar_personas(criterio)

    if resultados == [] do
      IO.puts("No se encontraron personas con el criterio '#{criterio}'.")
    else
      IO.puts("--- Personas Encontradas ---")

      Enum.each(resultados, fn p ->
        hist = Map.get(p, :historial_estados, [])
        IO.puts(
          "  Doc: #{p.documento} | #{p.nombre} (Edad: #{p.edad}) | Zona: #{p.zona} | Estado: #{p.estado} | Historial: #{inspect(hist)}"
        )
      end)
    end

    {:ok, sesion}
  end

  defp procesar_comando([cmd, doc_destino, contenido], sesion)
       when cmd in ["send_family_message", "mensaje_enviar"] do
    remitente = if sesion.usuario, do: sesion.usuario.username, else: "familiar_externo"

    case FamiliaresServer.enviar_mensaje(remitente, doc_destino, contenido) do
      {:ok, msg} ->
        cod = OperacionesExtendidas.id_de(msg)
        IO.puts("[OK] Mensaje #{cod} enviado para documento #{doc_destino}.")

      err ->
        imprimir_error(err)
    end

    {:ok, sesion}
  end

  defp procesar_comando([cmd, doc], sesion) when cmd in ["list_family_messages", "mensajes"] do
    msgs = FamiliaresServer.listar_mensajes(doc)

    if msgs == [] do
      IO.puts("No hay mensajes registrados para el documento #{doc}.")
    else
      IO.puts("--- Mensajes para #{doc} ---")

      Enum.each(msgs, fn m ->
        cod = OperacionesExtendidas.id_de(m)
        IO.puts("  [#{cod}] De #{m.remitente} (#{m.estado}): #{m.contenido}")
      end)
    end

    {:ok, sesion}
  end

  # --- MASCOTAS ---

  # Formato oficial (7 args): report_pet lost perro "Luna" negra mediana zona_norte contacto
  defp procesar_comando([cmd, tipo_str, especie, nombre, color, tamano, zona, contacto], sesion)
       when cmd in ["report_pet", "mascota_reportar"] do
    tipo = normalizar_tipo_mascota(tipo_str)

    case MascotasServer.reportar_mascota(tipo, especie, nombre, color, color, tamano, zona, contacto, nil) do
      {:ok, m} ->
        cod = OperacionesExtendidas.id_de(m)
        t = Map.get(m, :tipo_reporte) || Map.get(m, :tipo)
        IO.puts("[OK] Reporte de mascota #{cod} (#{t}) registrado en zona #{m.zona}.")

      err ->
        imprimir_error(err)
    end

    {:ok, sesion}
  end

  # Formato extendido (8 o 9 args): report_pet lost perro "Luna" "collar rojo" negra mediana zona_norte contacto [id]
  defp procesar_comando(
         [cmd, tipo_str, especie, nombre, caract, color, tamano, zona, contacto | resto],
         sesion
       )
       when cmd in ["report_pet", "mascota_reportar"] do
    id_opc =
      case resto do
        [id | _] -> id
        [] -> nil
      end

    tipo = normalizar_tipo_mascota(tipo_str)

    case MascotasServer.reportar_mascota(
           tipo,
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
        cod = OperacionesExtendidas.id_de(m)
        t = Map.get(m, :tipo_reporte) || Map.get(m, :tipo)
        IO.puts("[OK] Reporte de mascota #{cod} (#{t}) registrado en zona #{m.zona}.")

      err ->
        imprimir_error(err)
    end

    {:ok, sesion}
  end

  defp procesar_comando([cmd], sesion) when cmd in ["match_pets", "mascota_coincidencias"] do
    parejas = OperacionesExtendidas.buscar_coincidencias_mascotas()

    if parejas == [] do
      IO.puts("No se encontraron posibles coincidencias activas.")
    else
      IO.puts("--- Posibles Coincidencias de Mascotas ---")

      Enum.each(parejas, fn c ->
        IO.puts(
          "  Perdida: #{c.id_perdida} (#{c.nombre_perdida}) <-> Encontrada: #{c.id_encontrada} | #{c.especie} en #{c.zona} | Similitud: #{c.puntaje}%"
        )
      end)
    end

    {:ok, sesion}
  end

  defp procesar_comando([cmd, id_perdida, id_encontrada], sesion)
       when cmd in ["confirm_pet_match", "mascota_confirmar"] do
    case MascotasServer.confirmar_coincidencia(id_perdida, id_encontrada) do
      {:ok, res} ->
        IO.puts("[OK] Coincidencia confirmada: #{inspect(res)}")

      err ->
        imprimir_error(err)
    end

    {:ok, sesion}
  end

  # --- RESUMEN GLOBAL Y CONCURRENCIA ---

  defp procesar_comando([cmd], sesion) when cmd in ["resumen", "summary"] do
    r = OperacionesExtendidas.resumen_global()
    IO.puts("\n================ RESUMEN GLOBAL DE EMERGENCIA ================")
    IO.puts("Zonas afectadas registradas : #{r.total_zonas}")
    IO.puts("Necesidades               : #{r.necesidades_pendientes} pendientes / #{r.necesidades_atendidas} atendidas")
    IO.puts("Personas reportadas       : #{r.total_personas} | Mensajes familiares: #{r.total_mensajes}")
    IO.puts("Mascotas                  : #{r.mascotas_activas} activas / #{r.mascotas_resueltas} resueltas")
    IO.puts("Recursos en inventario:")

    Enum.each(r.recursos, fn rec ->
      cod = OperacionesExtendidas.id_de(rec)
      u_med = Map.get(rec, :unidad) || Map.get(rec, :unidad_medida, "unidades")
      IO.puts("  - [#{cod}] #{rec.nombre}: #{rec.cantidad_disponible} #{u_med} (#{rec.ubicacion} @ #{rec.zona})")
    end)

    IO.puts("Albergues:")

    Enum.each(r.albergues, fn a ->
      IO.puts("  - [#{a.id}] #{a.nombre} (#{a.zona}): #{a.ocupados}/#{a.capacidad} cupos (#{a.porcentaje}%)")
    end)

    IO.puts("==============================================================\n")
    {:ok, sesion}
  end

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

    t1 =
      Task.async(fn ->
        {:proceso_a, InventarioServer.asignar_recurso(OperacionesExtendidas.id_de(n1), rec_id, 30)}
      end)

    t2 =
      Task.async(fn ->
        {:proceso_b, InventarioServer.asignar_recurso(OperacionesExtendidas.id_de(n2), rec_id, 25)}
      end)

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
  # AUXILIARES Y NORMALIZACIÓN
  # ============================================================================

  defp parsear_filtros_necesidades(tokens) do
    Enum.reduce(tokens, {nil, nil}, fn tok, {z, p} ->
      cond do
        String.starts_with?(tok, "zona=") ->
          {String.replace_prefix(tok, "zona=", ""), p}

        String.starts_with?(tok, "prioridad=") ->
          {z, String.replace_prefix(tok, "prioridad=", "")}

        is_nil(z) ->
          {tok, p}

        is_nil(p) ->
          {z, tok}

        true ->
          {z, p}
      end
    end)
  end

  defp normalizar_atomo(str) do
    str
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> String.replace("á", "a")
    |> String.replace("é", "e")
    |> String.replace("í", "i")
    |> String.replace("ó", "o")
    |> String.replace("ú", "u")
    |> String.to_atom()
  end

  defp normalizar_tipo_mascota(str) do
    case String.downcase(String.trim(to_string(str))) do
      "lost" -> :perdida
      "perdida" -> :perdida
      "found" -> :encontrada
      "encontrada" -> :encontrada
      otro -> normalizar_atomo(otro)
    end
  end

  defp normalizar_estado_persona(str) do
    case String.downcase(String.trim(to_string(str))) do
      "localizada" -> :localizada
      "localizado" -> :localizada
      "desaparecida" -> :desaparecida
      "desaparecido" -> :desaparecida
      "herida" -> :herida
      "herido" -> :herida
      "en_albergue" -> :en_albergue
      otro -> normalizar_atomo(otro)
    end
  end

  defp inferir_categoria(nombre) do
    n = String.downcase(to_string(nombre))

    cond do
      String.contains?(n, "agua") -> "hidratacion"
      String.contains?(n, "alimento") or String.contains?(n, "comida") -> "alimentacion"
      String.contains?(n, "medic") or String.contains?(n, "botiquin") -> "salud"
      String.contains?(n, "frazada") or String.contains?(n, "carpa") -> "abrigo"
      true -> "general"
    end
  end

  defp inferir_zona_ubicacion(ubicacion) do
    u = String.downcase(to_string(ubicacion))

    cond do
      String.contains?(u, "norte") -> "zona_norte"
      String.contains?(u, "sur") -> "zona_sur"
      String.contains?(u, "este") -> "zona_este"
      String.contains?(u, "oeste") -> "zona_oeste"
      true -> "centro"
    end
  end

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
      "Comandos oficiales del sistema (usa comillas dobles para textos con espacios):",
      "  connect <user> <pass> <rol> <zona> [nombre]   - Inicia sesión (coordinador, voluntario, ciudadano, organizacion)",
      "  whoami | disconnect | salir                   - Sesión actual, cerrar sesión o salir",
      "  register_zone <codigo> <nombre> <nivel> [afec]",
      "  zone_stats <zona_cod>                         - Estadísticas recursivas de zona",
      "  register_resource <id> <nom> <cant> <u_med> <ubic>",
      "  list_resources [zona] | critical_resources    - Inventario y recursos con stock crítico",
      "  transfer_resource <id> <origen> <destino> <cant>",
      "  register_need <tipo> <cant> <prio> <zona> <desc>",
      "  list_needs [zona=X] [prioridad=Y]             - Lista necesidades ordenadas por prioridad",
      "  pending_needs                                 - Lista necesidades pendientes/parciales",
      "  assign_resource <need_id> <recurso_o_id> <cant>",
      "  register_shelter <id> <nombre> <zona> <capacidad>",
      "  check_shelter <id> | shelters_report          - Cupos disponibles y ranking de ocupación",
      "  register_entry <albergue_id> <documento>",
      "  register_exit <albergue_id> <documento>",
      "  report_person <doc> <nombre> <zona> <estado> [edad]",
      "  find_person <criterio>                        - Búsqueda recursiva de familiares",
      "  send_family_message <doc> <mensaje>",
      "  list_family_messages <doc>",
      "  report_pet <lost|found> <esp> <nom> <color> <tam> <zona> <contacto>",
      "  match_pets | confirm_pet_match <id_p> <id_e>",
      "  summary (o resumen)                           - Vista consolidada global del sistema",
      "  simular_concurrencia                          - Prueba de carrera en inventario en vivo"
    ]
    |> Enum.each(&IO.puts/1)
  end
end
