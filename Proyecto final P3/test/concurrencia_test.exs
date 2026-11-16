defmodule Emergencia.ConcurrenciaTest do
  use ExUnit.Case, async: true

  alias Emergencia.Servidores.{
    AlberguesServer,
    FamiliaresServer,
    InventarioServer,
    MascotasServer,
    UsuariosServer,
    ZonasServer
  }

  setup do
    uid = System.unique_integer([:positive])
    tmp_dir = Path.join(System.tmp_dir!(), "emergencia_conc_#{uid}")
    File.mkdir_p!(tmp_dir)

    inv = start_supervised!({InventarioServer, [name: :"inv_#{uid}", data_dir: tmp_dir]})
    alb = start_supervised!({AlberguesServer, [name: :"alb_#{uid}", data_dir: tmp_dir]})
    mas = start_supervised!({MascotasServer, [name: :"mas_#{uid}", data_dir: tmp_dir]})
    usr = start_supervised!({UsuariosServer, [name: :"usr_#{uid}", data_dir: tmp_dir]})
    zon = start_supervised!({ZonasServer, [name: :"zon_#{uid}", data_dir: tmp_dir]})
    fam = start_supervised!({FamiliaresServer, [name: :"fam_#{uid}", data_dir: tmp_dir]})

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{inv: inv, alb: alb, mas: mas, usr: usr, zon: zon, fam: fam}
  end

  test "Conflicto concurrente de inventario: 50L disponibles ante dos solicitudes simultáneas de 30L y 25L", %{inv: inv} do
    {:ok, _} = InventarioServer.registrar_recurso("R001", "agua", "agua", 50, "litros", "centro_acopio_1", "centro", inv)
    {:ok, n1} = InventarioServer.registrar_necesidad(:agua, 30, :critica, "centro", "Punto 1", "laura", "general", nil, inv)
    {:ok, n2} = InventarioServer.registrar_necesidad(:agua, 25, :alta, "centro", "Punto 2", "carlos", "general", nil, inv)

    tarea_1 = Task.async(fn -> InventarioServer.asignar_recurso(n1.id, "R001", 30, inv) end)
    tarea_2 = Task.async(fn -> InventarioServer.asignar_recurso(n2.id, "R001", 25, inv) end)

    resultados = Task.await_many([tarea_1, tarea_2])

    exitosos = Enum.filter(resultados, &match?({:ok, _}, &1))
    rechazados = Enum.filter(resultados, &match?({:error, :inventario_insuficiente}, &1))

    assert length(exitosos) == 1
    assert length(rechazados) == 1

    stock_final = InventarioServer.consultar_disponibilidad("agua", nil, inv)
    assert stock_final in [20, 25]
    assert stock_final >= 0
  end

  test "Concurrencia en albergues: no permite superar capacidad máxima bajo ingresos simultáneos", %{alb: alb} do
    {:ok, _} = AlberguesServer.registrar_albergue("A01", "Albergue Norte", "norte", 2, alb)

    tareas =
      for doc <- ["1001", "1002", "1003", "1004"] do
        Task.async(fn -> AlberguesServer.registrar_ingreso("A01", doc, alb) end)
      end

    resultados = Task.await_many(tareas)
    ingresados = Enum.count(resultados, &match?({:ok, _}, &1))
    sin_cupo = Enum.count(resultados, &match?({:error, :albergue_sin_cupos}, &1))

    assert ingresados == 2
    assert sin_cupo == 2
  end

  test "Concurrencia en mascotas: evita resolver dos veces el mismo reporte", %{mas: mas} do
    {:ok, p} = MascotasServer.reportar_mascota(:perdida, "perro", "Max", "mancha blanca", "cafe", "grande", "sur", "300123", "PET1", mas)
    {:ok, e} = MascotasServer.reportar_mascota(:encontrada, "perro", "desconocido", "mancha blanca", "cafe", "grande", "sur", "300987", "PET2", mas)

    t1 = Task.async(fn -> MascotasServer.confirmar_coincidencia(p.id, e.id, mas) end)
    t2 = Task.async(fn -> MascotasServer.confirmar_coincidencia(p.id, e.id, mas) end)

    resultados = Task.await_many([t1, t2])
    assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1
    assert Enum.count(resultados, &match?({:error, :reporte_ya_resuelto}, &1)) == 1
  end

  test "Flujo integrado multiusuario: conexión, zona, familiares y mensajes", %{usr: usr, zon: zon, fam: fam} do
    {:ok, :registrado_y_conectado, _} = UsuariosServer.connect("laura", "1234", :coordinador, "centro", "Laura", usr)
    assert {:ok, _} = UsuariosServer.autorizar("laura", :registrar_zona, usr)

    {:ok, _} = ZonasServer.registrar_zona("centro", "Zona Centro", :critico, 150, zon)
    {:ok, _} = ZonasServer.agregar_sector("centro", "S3", "Sector 3", :critico, 50, zon)
    {:ok, _} = ZonasServer.agregar_punto_atencion("centro", "S3", "P1", "Punto Norte", "acopio", zon)
    {:ok, stats} = ZonasServer.estadisticas_zona("centro", zon)
    assert stats.total_afectados == 200

    {:ok, _} = FamiliaresServer.reportar_o_actualizar_persona("1094555", "Andrés", "norte", :en_albergue, 25, fam)
    {:ok, _} = FamiliaresServer.enviar_mensaje("laura", "1094555", "Estoy bien, voy para el albergue", fam)
    msgs = FamiliaresServer.listar_mensajes("1094555", fam)
    assert length(msgs) == 1
  end
end
