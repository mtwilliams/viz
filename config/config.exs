use Mix.Config

config :logger,
  level: :debug,
  utc_log: true,
  handle_otp_reports: false,
  handle_sasl_reports: false

import_config "config.secrets.exs"
