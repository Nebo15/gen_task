# GenTask

[![Deps Status](https://beta.hexfaktor.org/badge/all/github/Nebo15/gen_task.svg)](https://beta.hexfaktor.org/github/Nebo15/gen_task) [![Hex.pm Downloads](https://img.shields.io/hexpm/dw/gen_task.svg?maxAge=3600)](https://hex.pm/packages/gen_task) [![Latest Version](https://img.shields.io/hexpm/v/gen_task.svg?maxAge=3600)](https://hex.pm/packages/gen_task) [![License](https://img.shields.io/hexpm/l/gen_task.svg?maxAge=3600)](https://hex.pm/packages/gen_task) [![Build Status](https://travis-ci.org/Nebo15/gen_task.svg?branch=master)](https://travis-ci.org/Nebo15/gen_task) [![Coverage Status](https://coveralls.io/repos/github/Nebo15/gen_task/badge.svg?branch=master)](https://coveralls.io/github/Nebo15/gen_task?branch=master)

Generic Task behavior that helps to encapsulate worker errors and recover from them in classic GenStage's.

## Motivation

Whenever you use RabbitMQ or similar tool for background job processing you may want to leverage acknowledgments mechanism.

For example, we spawn a supervisioned GenServer worker each time we receive a job from RabbitMQ. Job `payload` comes with a `tag` that should be used to send acknowledgment (ack) or negative acknowledgment (nack) when it is finished. All nack'ed jobs will be re-scheduled and retried (to reach "at-least once" job processing). Also, RabbitMQ remembers which tasks was sent to a connection and will nack all unacknowledged tasks when connection dies. After task is processed we send ack or nack (depending on business logic) and exit with a normal reason. (This our supervisor restart strategy is `:transient`).

Jobs intensity is limited by `prefetch_count` option that limits maximum amount of unacknowledged jobs that may be processed on a single node at a single moment in time.

But in real life jobs can have bugs or other errors because of third-party services unavailability, in this case GenServer will die. Of course Supervisor will try to restart it, but in most cases of third-party outages it will reach max restart intensity within seconds and die taking all active jobs with itself.

Supervisor gets restarted, but it **won't receive receive any jobs** resulting in a zombie background processing node. This happens because connection is not linked to a individual jobs or their supervisors, and will stay alive after supervisor restart, so RabbitMQ will think that node "is working on all jobs at max capacity" (because of `prefetch_count`) and will not send any additional jobs to it. Additionally we will loose all tags and won't be able to nack died processes within node.

### Possible solutions

  1. Leverage [GenServer `terminate/2`](https://hexdocs.pm/elixir/GenServer.html#c:terminate/2) callback.

  This option is not safe by-default, because process that doesn't trap exits will not call this callback when supervisor is sending exit signal to it (due to supervisor restart).

  2. Linking RabbitMQ client lib channel/connection processes to a workers.

  May be a bad solution because all jobs will be re-scheduled whenever a single job fails, resulting in a many duplicate-processed jobs.

  2. Store tags in a separate process which monitors supervisor and it's workers.

  3. Keep storing tags and job payload within GenStage state, but wrap any unsafe code in a [`Task`](https://hexdocs.pm/elixir/Task.html). [[1]](https://github.com/elixir-lang/gen_stage/issues/131#issuecomment-265758380)

  Internally this looks familiar to pt. 2, but doesn't require us to re-invent supervisor behavior.

## Picked solution description

Tasks is started under `Task.Supervisor` (via `async_nolink/2`) inside `GenTask` application. They are not linked to a caller process which allows to persist state without risking that caller pid will be terminated along with task itself, so further processing is possible when error occurs. Task result is received via `Task.yield/1` function.

Tasks are started with a `:temporary` restart strategy (never restart), to protect supervisor from exits.

The package itself provides two ways to handle asynchronous jobs:

  1. Runner functions `GenTask.start_task/1` and `GenTask.start_task/3` to start function under unlinked supervisioned process and yield for task result.

  2. `GenTask` behaviour that is based on GenServer that will start task (from `run/1` callback) processing after it's start and deliver status into `handle_result/3` callbacks.

## Installation and usage

It's [available in Hex](https://hex.pm/packages/gen_task), the package can be installed as:

  1. Add `gen_task` to your list of dependencies in `mix.exs`:

  ```elixir
  def deps do
    [{:gen_task, "~> 0.1.4"}]
  end
  ```

  2. Ensure `gen_task` is started before your application:

  ```elixir
  def application do
    [applications: [:gen_task]]
  end
  ```

  3. Define your business logic and result handling:

  ```elixir
  defmodule MyWorker do
    use GenTask
    require Logger

    # Define business logic
    def run(%{payload: _payload, tag: tag}) do
      # Simulated errors
      if :rand.uniform(2) == 1 do
        throw "Error!"
      end

      Logger.info("Processed job ##{tag}")
      :timer.sleep(100)
      :ok
    end

    # Handle task statuses
    def handle_result(:ok, _result, %{tag: tag} = state) do
      # MyQueue.ack(tag)
      {:stop, :normal, state}
    end

    def handle_result(:exit, reason, %{tag: tag} = state) do
      Logger.error("Task with tag #{inspect tag} terminated with reason: #{inspect reason}")
      # MyQueue.nack(tag)
      {:stop, :normal, state}
    end

    def handle_result(:timeout, task, state) do
      Task.shutdown(task) # Shut down task on yield timeout
      handle_result(:exit, :timeout, state)
    end
  end
  ```

  4. (Optional.) Supervise your workers:

  Define `MyWorker` supervisor:

  ```elixir
  defmodule MyWorkerSupervisor do
    use Supervisor

    def start_link do
      Supervisor.start_link(__MODULE__, [], name: __MODULE__)
    end

    def start_worker(job) do
      Supervisor.start_child(__MODULE__, [job])
    end

    def init(_) do
      children = [
        worker(MyWorker, [], restart: :transient)
      ]

      supervise(children, strategy: :simple_one_for_one)
    end
  end
  ```

  Add it to a application supervision tree:

  ```elixir
  # File: lib/my_app.ex
  # ...

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      supervisor(MyWorkerSupervisor, [])
      # ...
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # ...
  ```

  Then you can use `MyWorkerSupervisor.start_worker/1` to start your workers.


The docs can be found at [https://hexdocs.pm/gen_task](https://hexdocs.pm/gen_task)

