ExUnit.start()

# Al terminar la suite: frenar la app (corre terminate/2 → cierra los DETS del Persistence
# global) y borrar la carpeta de datos de test, para que la próxima corrida arranque limpia
# (sin el "dets: ... not properly closed, repairing"). Los tests aislados de Persistence
# usan su propia carpeta temporal (@tag :tmp_dir) y se limpian solos.
ExUnit.after_suite(fn _result ->
  Application.stop(:booking)
  File.rm_rf!(Application.fetch_env!(:booking, :data_dir))
end)
