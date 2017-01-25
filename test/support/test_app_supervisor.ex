defmodule TestAppSupervisor do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    children = [
      supervisor(TestWorkerSupervisor, []),
      supervisor(TestConsumer, [])
    ]

    supervise(children, strategy: :one_for_one)
  end
end
