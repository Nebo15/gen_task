defmodule TestConsumer do
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, [], name: TestConsumer)
  end

  def handle_info({:job, job}, state) do
    {:ok, _pid} = TestWorkerSupervisor.start_worker(job)
    {:noreply, state}
  end
end
