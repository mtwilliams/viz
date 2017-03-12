use Mix.Config

config :logger,
  level: :debug,
  utc_log: true,
  handle_otp_reports: false,
  handle_sasl_reports: false

config :githubviz_stream, :deduplicator,
  bitset: [
    path: "duplicates.#{Mix.env}.bits",
    size: 8_589_934_592
  ]

import_config "config.secrets.exs"
