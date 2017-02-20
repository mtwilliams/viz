use Mix.Config

config :logger,
  level: :debug,
  utc_log: true,
  handle_otp_reports: true,
  handle_sasl_reports: true

import_config "config.secrets.exs"
