defmodule TestQueue do
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    jobs = 1..100
    |> Enum.map(&generate_job/1)

    {:ok, %{opts: opts, workers: [], jobs: jobs}}
  end

  # Client

  def attach_observer(observer_pid) do
    GenServer.call(__MODULE__, {:attach_observer, observer_pid})
  end

  def subscribe(worker_pid) do
    GenServer.cast(__MODULE__, {:subscribe, worker_pid})
  end

  def ack(tag) do
    GenServer.cast(__MODULE__, {:ack, tag})
  end

  def nack(tag) do
    GenServer.cast(__MODULE__, {:nack, tag})
  end

  # Server

  def handle_call({:attach_observer, pid}, _from, state) do
    {:reply, :ok, %{state | opts: state.opts ++ [observer_pid: pid]}}
  end

  def handle_cast({:subscribe, pid}, %{workers: workers} = state) do
    state = %{state | workers: workers ++ [%{pid: pid, active_jobs: 0}]}

    {:noreply, dispatch_jobs(state)}
  end

  def handle_cast({:ack, tag}, %{jobs: jobs, workers: workers} = state) do
    job_index = Enum.find_index(jobs, fn %{tag: job_tag} -> job_tag == tag end)
    job = Enum.at(jobs, job_index)

    worker_index = Enum.find_index(workers, fn %{pid: worker_pid} -> worker_pid == job.worker end)
    worker = Enum.at(workers, worker_index)

    jobs = List.replace_at(jobs, job_index, %{job | state: :acked, worker: nil})
    workers = List.replace_at(workers, worker_index, %{worker | active_jobs: worker.active_jobs - 1})

    {:noreply, dispatch_jobs(%{state | workers: workers, jobs: jobs})}
  end

  def handle_cast({:nack, tag}, %{jobs: jobs, workers: workers} = state) do
    job_index = Enum.find_index(jobs, fn %{tag: job_tag} -> job_tag == tag end)
    job = Enum.at(jobs, job_index)

    worker_index = Enum.find_index(workers, fn %{pid: worker_pid} -> worker_pid == job.worker end)
    worker = Enum.at(workers, worker_index)

    jobs = List.replace_at(jobs, job_index, %{job | state: :nacked, worker: nil})
    workers = List.replace_at(workers, worker_index, %{worker | active_jobs: worker.active_jobs - 1})

    {:noreply, dispatch_jobs(%{state | workers: workers, jobs: jobs})}
  end

  # Helpers

  defp generate_job(tag) do
    %{payload: :rand.uniform(100_000), tag: tag, worker: nil, state: :undelivered}
  end

  defp dispatch_jobs(%{opts: opts, workers: workers, jobs: jobs}) do
    {jobs, workers, ack_count} = jobs
    |> Enum.reduce({[], workers, length(jobs)}, fn
      %{state: state} = job, {jobs, workers, ack_count} when state in [:undelivered, :nacked] ->
        {job, workers} = dispatch_job(job, workers, opts)
        {jobs ++ [job], workers, ack_count}

      %{state: :unacked} = job, {jobs, workers, ack_count} ->
        {jobs ++ [job], workers, ack_count}

      job, {jobs, workers, ack_count} ->
        {jobs ++ [job], workers, ack_count - 1}
    end)

    if(opts[:observer_pid]) do
      send(opts[:observer_pid], {:undelivered_jobs, ack_count})
    end

    %{opts: opts, workers: workers, jobs: jobs}
  end

  defp dispatch_job(job, workers, opts) do
    index = Enum.find_index(workers, fn %{active_jobs: active_jobs} -> active_jobs < opts[:prefetch_count] end)

    case index do
      nil ->
        {job, workers}

      index ->
        worker = Enum.at(workers, index)
        {job, worker} = send_job(job, worker)
        workers = List.replace_at(workers, index, worker)
        {job, workers}
    end
  end

  defp send_job(%{payload: payload, tag: tag} = job, %{pid: pid, active_jobs: active_jobs} = worker) do
    send(pid, {:job, %{payload: payload, tag: tag}})

    {
      %{job | worker: pid, state: :unacked},
      %{worker | active_jobs: active_jobs + 1}
    }
  end
end
