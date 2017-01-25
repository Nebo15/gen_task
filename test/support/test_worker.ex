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
    {:ok, res} = Task.async(fn ->
      payload
      |> process(tag)
    end)
    |> Task.yield() # TODO: add timeout

    res
    |> send_ack(tag)

    {:stop, :normal, []}
  end

  # # Simulated errors
  # defp process(_payload, tag) when rem(tag, 2) == 0 do
  #   throw "Error!"
  # end

  # Success jobs
  defp process(_payload, tag) do
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
