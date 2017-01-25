defmodule TestWorkerSupervisor do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def start_worker(job) do
    {:ok, pid} = Supervisor.start_child(__MODULE__, [job])
    # :sys.trace(pid, true)
    {:ok, pid}
  end

  def init(_) do
    children = [
      worker(TestWorker, [], restart: :transient)
    ]

    supervise(children, strategy: :simple_one_for_one)
  end
end
