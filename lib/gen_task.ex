defmodule GenTask do
  @moduledoc """
  This module provides helper functions and extended GenServer behaviour to run concurrent tasks
  with guarantee that error results can be processed.

  You need to implement two callback functions:
    * `run/1` that defines task business logic
    * `handle_info/3` that processes task result
  """
  use Application

  @task_supervisor_name GenTask.Supervisor

  @doc """
  This function will should be used to process task result.

  Result should be same as `GenServer.handle_info/2`.
  """
  @callback handle_result(status :: atom, result :: term, state :: term) ::
    {:noreply, new_state} |
    {:noreply, new_state, timeout | :hibernate} |
    {:stop, reason :: term, new_state} when new_state: term

  @doc """
  Callback function that should implement worker function that must be securely processed.
  """
  @callback run(state :: term) :: term

  @doc false
  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [opts: opts] do
      use GenServer
      @behaviour GenServer
      @behaviour GenTask

      @yield_timeout opts[:timeout] || 30_000

      @doc false
      def start_link(state) do
        GenServer.start_link(__MODULE__, state)
      end

      @doc false
      def init(state) do
        {:ok, state, 100}
      end

      @doc false
      def run(state) do
        throw "Behaviour function __MODULE__.run/1 is not implemented!"
      end

      @doc false
      def handle_info(:timeout, state) do
        {status, reason} = GenTask.start_task(__MODULE__, :run, [state], @yield_timeout)
        handle_result(status, reason, state)
      end

      def handle_result(:ok, _result, state) do
        {:stop, :normal, state}
      end

      def handle_result(:exit, reason, state) do
        {:stop, reason, state}
      end

      def handle_result(:timeout, task, state) do
        Task.shutdown(task)
        handle_result(:exit, :timeout, state)
      end

      defoverridable [start_link: 1, init: 1, run: 1, handle_result: 3]
    end
  end

  @doc false
  # This is an entry point for application that starts tasks supervisor.
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      # Start Task.Supervisor
      supervisor(Task.Supervisor, [[name: @task_supervisor_name]])
    ]

    Supervisor.start_link(children, [strategy: :one_for_one, name: GenTask.ApplicationSupervisor])
  end

  @doc """
  Start function as a tack under `Task.Supervisor` without linking it to a current process and yield for it's result.

  This function can be called without using behaviour, but you will need to match task result manually.

  A timeout, in milliseconds, can be given with default value
  of `30_000`.

  If the time runs out before a message from
  the task is received, this function will return `{:timeout, Task.t}`
  and the monitor will remain active. Therefore `yield/2` can be
  called on task.

  This function assumes the task's monitor is still active or the
  monitor's `:DOWN` message is in the message queue. If it has been
  demonitored or the message already received, this function will wait
  for the duration of the timeout awaiting the message.

  If you intend to shut the task down if it has not responded within `timeout`
  milliseconds, you should chain this together with `shutdown/1`.
  (This is default implementation for `handle_result(:timeout, reason, state)`.)
  """
  @spec start_task(fun, timeout) :: {:ok, term} | {:exit, term} | {:timeout, Task.t}
  def start_task(fun, timeout \\ 30_000) when is_function(fun) do
    task = @task_supervisor_name
    |> Task.Supervisor.async_nolink(fun)

    case Task.yield(task, timeout) do
      {reason, term} -> {reason, term}
      nil -> {:timeout, task}
    end
  end

  @doc """
  Same as `start_task/2` but allows to call function in a module.
  """
  @spec start_task(module, atom, [term], timeout) :: {:ok, term} | {:exit, term} | {:timeout, Task.t}
  def start_task(module, fun, args, timeout \\ 30_000) do
    task = @task_supervisor_name
    |> Task.Supervisor.async_nolink(module, fun, args)

    case Task.yield(task, timeout) do
      {reason, term} -> {reason, term}
      nil -> {:timeout, task}
    end
  end
end
