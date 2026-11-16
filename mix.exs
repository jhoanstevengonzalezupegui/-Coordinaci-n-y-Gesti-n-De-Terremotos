defmodule Emergencia.MixProject do
  use Mix.Project

  def project do
    [
      app: :emergencia,
      version: "0.1.0",
      elixir: "~> 1.14", # Asegura compatibilidad con versiones recientes de Elixir
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Configuración del arranque de la aplicación
  def application do
    [
      # Herramientas extra que arranca Elixir (logger sirve para ver mensajes en consola)
      extra_applications: [:logger],

      # Aquí es donde conectamos tu Emergencia.Application para que encienda los servidores
      mod: {Emergencia.Application, []}
    ]
  end

  # Manejo de dependencias (librerías de terceros)
  defp deps do
    [
      # Como estás usando puro Elixir nativo y archivos .txt, esto va vacío por ahora.
      # Si luego necesitaran una librería externa (ej. para JSON), se pone aquí.
    ]
  end
end
