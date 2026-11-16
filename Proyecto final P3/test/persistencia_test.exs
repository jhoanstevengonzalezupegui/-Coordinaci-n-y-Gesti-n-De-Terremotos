defmodule Emergencia.PersistenciaTest do
  use ExUnit.Case, async: true

  alias Emergencia.Modelos.{Albergue, Mascota, Necesidad, Recurso, Usuario, Zona}
  alias Emergencia.Persistencia

  setup do
    tmp_dir = Path.join(System.tmp_dir!(), "emergencia_persist_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    %{dir: tmp_dir}
  end

  test "guarda y recupera correctamente entidades en texto plano", %{dir: dir} do
    {:ok, u} = Usuario.nuevo("laura", "1234", "Laura", :coordinador, "centro")
    :ok = Persistencia.guardar_lista("usuarios.txt", [u], &Usuario.a_linea/1, dir)
    {:ok, [u_cargado]} = Persistencia.cargar_lista("usuarios.txt", &Usuario.desde_linea/1, dir)
    assert u_cargado.username == "laura"
    assert u_cargado.rol == :coordinador

    {:ok, z} = Zona.nueva("Z01", "Centro", :alto, 50)
    {:ok, z} = Zona.agregar_sector(z, "S01", "Sector 1", :critico, 25)
    :ok = Persistencia.guardar_lista("zonas.txt", [z], &Zona.a_linea/1, dir)
    {:ok, [z_cargada]} = Persistencia.cargar_lista("zonas.txt", &Zona.desde_linea/1, dir)
    assert z_cargada.codigo == "Z01"
    assert length(z_cargada.sectores) == 1

    {:ok, r} = Recurso.nuevo("R001", "agua", "agua", 100, "litros", "acopio_1", "centro")
    :ok = Persistencia.guardar_lista("recursos.txt", [r], &Recurso.a_linea/1, dir)
    {:ok, [r_cargado]} = Persistencia.cargar_lista("recursos.txt", &Recurso.desde_linea/1, dir)
    assert r_cargado.cantidad_disponible == 100

    {:ok, n} = Necesidad.nueva("N001", :agua, "Agua urgente", 30, "centro", :critica, "laura")
    :ok = Persistencia.guardar_lista("necesidades.txt", [n], &Necesidad.a_linea/1, dir)
    {:ok, [n_cargada]} = Persistencia.cargar_lista("necesidades.txt", &Necesidad.desde_linea/1, dir)
    assert n_cargada.prioridad == :critica

    {:ok, a} = Albergue.nuevo("A01", "Albergue Central", "centro", 120)
    :ok = Persistencia.guardar_lista("albergues.txt", [a], &Albergue.a_linea/1, dir)
    {:ok, [a_cargado]} = Persistencia.cargar_lista("albergues.txt", &Albergue.desde_linea/1, dir)
    assert a_cargado.capacidad_maxima == 120

    {:ok, m} = Mascota.nuevo("PET001", :perdida, "gato", "Michi", "cola corta", "blanco", "pequeno", "sur", "300000")
    :ok = Persistencia.guardar_lista("mascotas.txt", [m], &Mascota.a_linea/1, dir)
    {:ok, [m_cargada]} = Persistencia.cargar_lista("mascotas.txt", &Mascota.desde_linea/1, dir)
    assert m_cargada.nombre == "Michi"
  end
end
