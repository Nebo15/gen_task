defmodule GenTaskTest do
  use ExUnit.Case
  doctest GenTask

  setup_all do
    {:ok, _pid} = TestQueue.start_link([prefetch_count: 5])
    {:ok, _supervisor_pid} = TestAppSupervisor.start_link()
    :ok
  end

  test "process all jobs with errors" do
    TestQueue.attach_observer(self())
    TestQueue.subscribe(TestConsumer)
    assert_receive {:undelivered_jobs, 0}, 10_000
  end
end
