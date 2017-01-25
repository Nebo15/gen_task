defmodule TestWorker do
  use GenServer
  require Logger

  def start_link(%{} = job) do
    GenServer.start_link(__MODULE__, job)
  end

  def init(state) do
    {:ok, state, 100}
  end

  def handle_info(:timeout, %{payload: payload, tag: tag}) do
    task = Task.Supervisor.async_nolink(GenTask.Supervisor, fn ->
      payload
      |> process(tag)
    end)
    |> Task.yield()

    case task do
      {:ok, result} ->
        send_ack(result, tag)
      {:exit, reason} ->
        Logger.error("Task with tag #{inspect tag} terminated with reason: #{inspect reason}")
        TestQueue.nack(tag)
    end

    {:stop, :normal, []}
  end

  def handle_info(any, state) do
    IO.inspect "Reseived info"
    IO.inspect {any, state}
    {:noreply, state}
  end

  # def terminate(:normal, _), do: :ok
  # def terminate(reason, %{tag: tag}) do
  #   IO.inspect reason
  #   TestQueue.nack(tag)
  # end

  # Success jobs
  defp process(_payload, tag) do
    # Simulated errors
    if :rand.uniform(2) == 1 do
      throw "Error!"
    end
    Logger.info("Processed job ##{tag}")
    :timer.sleep(100)
    :ok
  end

  defp send_ack(:ok, tag) do
    TestQueue.ack(tag)
  end

  defp send_ack(:error, tag) do
    TestQueue.nack(tag)
  end
end
