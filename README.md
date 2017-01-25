# GenTask

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

Each time job is started we spawn a "sentitel" GenServer process that stores job that needs to be processed, this job is later started under `Task.Supervisor` via `async_nolink/2` that allows to process job asynchronously without linking it to the caller process.

To receive job status sentitel process leverages `Task.yield/1` function, that blocks current process until task completes (which saves reduction for sentinel process).

## Installation and usage

It's [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add `gen_task` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:gen_task, "~> 0.1.0"}]
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

The docs can be found at [https://hexdocs.pm/gen_task](https://hexdocs.pm/gen_task)

