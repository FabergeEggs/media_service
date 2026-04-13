ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(MediaService.Repo, :manual)

# Mox registers a dynamic module that stands in for the real
# `MediaService.Storage.S3` in tests. `config/test.exs` points
# `:storage_adapter` at this module so the code under test calls the mock.
Mox.defmock(MediaService.Storage.S3Mock, for: MediaService.Storage.S3.Behaviour)
