defmodule Sitevoice.Workers.AudioProcessor do
  use Oban.Worker, queue: :audio, max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"log_id" => log_id, "organization_id" => org_id}}) do
    _tenant = org_id
    Logger.info("AudioProcessor: processing log #{log_id} for org #{org_id}")
    :ok
  end
end
