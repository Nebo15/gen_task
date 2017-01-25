defmodule TestWorker do
  use GenTask, timeout: 1_000
  require Logger

  def run(%{payload: _payload, tag: tag}) do
    # Simulated errors
    if :rand.uniform(2) == 1 do
      throw "Error!"
    end

    Logger.info("Processed job ##{tag}")
    :timer.sleep(100)
    :ok
  end

  def handle_result(:ok, _result, %{tag: tag} = state) do
    TestQueue.ack(tag)
    {:stop, :normal, state}
  end

  def handle_result(:exit, reason, %{tag: tag} = state) do
    Logger.error("Task with tag #{inspect tag} terminated with reason: #{inspect reason}")
    TestQueue.nack(tag)
    {:stop, :normal, state}
  end

  def handle_result(:timeout, task, state) do
    Task.shutdown(task)
    handle_result(:exit, :timeout, state)
  end
end
