defmodule GenTaskTest do
  use ExUnit.Case
  doctest GenTask

  setup_all do
    {:ok, pid} = TestQueue.start_link([prefetch_count: 5])
    {:ok, _supervisor_pid} = TestAppSupervisor.start_link()
    # :sys.trace(pid, true)

    {:ok, %{pid: pid}}
  end

  test "process jobs" do
    # :observer.start()
    # :timer.sleep(30000)
    TestQueue.attach_observer(self())
    TestQueue.subscribe(TestConsumer)
    assert_receive {:undelivered_jobs, 0}, 10_000
  end
end
