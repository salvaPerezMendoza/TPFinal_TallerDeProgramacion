import Config

# Carpeta donde Booking.Persistence guarda los archivos DETS (relativa a la del backend).
config :booking, data_dir: "data"

# En tests usamos una carpeta temporal del sistema para no ensuciar el repo ni arrastrar
# estado entre corridas. (Los tests aislados de Persistence usan, además, su propia carpeta.)
if config_env() == :test do
  config :booking, data_dir: Path.join(System.tmp_dir!(), "booking_test_data")
end
