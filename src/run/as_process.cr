module Run
  # Represents a runinng process.
  module AsProcess
    # Returns this parent group.
    getter parent : ProcessGroup

    # Returns this root group.
    def root_group : ProcessGroup
      @parent.root
    end

    # Returns this source command.
    getter command : AsCommand

    # Returns this context.
    getter context : Context

    @run_context : Context
    @start_mutex = Mutex.new
    @wait_mutex = Mutex.new
    @abort_mutex = Mutex.new
    @attempt : Attempt::Context

    # :nodoc:
    def initialize(@parent, @command, @run_context)
      @context = @run_context.dup.set(
        parent: @command.context,
        name: @command.context.name
      )
      @context.attempt = @command.context.self_attempt unless @context.self_attempt
      @attempt = @context.attempt.new_context
    end

    # :nodoc:
    def start
      @start_mutex.synchronize do
        if @started.nil?
          @attempt.attempt_once do
            with_startup do
              @impl = new_impl
            end
          end
          @started = true
        end
      end
      @started
    end

    # :nodoc:
    def unstart
      @start_mutex.synchronize do
        if @started.nil?
          @started = false
        end
      end
      @started
    end

    # :nodoc:
    def restart
      @start_mutex.synchronize do
        unless terminated?
          @attempt.attempt_once do
            with_startup do
              @impl = new_impl
            end
          end
        end
      end
    end

    # :nodoc:
    def wait
      @wait_mutex.synchronize do
        if @waited.nil?
          if start
            exit_status = ExitStatus.new(-1)
            loop do
              exit_status = @impl.not_nil!.wait
              break if exit_status.success? || !@attempt.attempts?
              restart
            end
            @exit_status = exit_status
            @exited = true
            @waited = true
            if exit_status.error?
              if context.aborts_on_error?
                root_group.abort
              end
            end
          else
            @waited = false
          end
        end
      end
    end

    # Aborts this process.
    def abort(signal : Signal? = nil)
      @abort_mutex.synchronize do
        if @aborted.nil?
          if unstart && !exited?
            _abort signal
          else
            @aborted = false
          end
        end
      end
    end

    # :nodoc:
    def _abort(signal)
      kill signal
      context.abort_wait.start do
        break unless exists?
      end
      @aborted = true
    end

    # :nodoc:
    def with_startup
      Dir.mkdir_p context.chdir
      show_dir if context.shows_dir?
      show_command if context.shows_command?
      yield
    end

    # :nodoc:
    def show_dir
      if File.real_path(context.chdir) != Dir.current
        puts "\u{1F4C2} #{context.chdir}"
      end
    end

    # :nodoc:
    def show_command
      a = [context.command]
      a += context.args if context.args.size > 0
      puts a.join(" ")
    end

    # Returns this input IO.
    def input? : IO?
      context.input.input_for_process?(@impl)
    end

    # Returns this input IO.
    def input : IO
      input?.not_nil!
    end

    # Returns this output IO.
    def output? : IO?
      context.input.output_for_process?(@impl)
    end

    # Returns this output IO.
    def output : IO
      output?.not_nil!
    end

    # Returns this error IO.
    def error? : IO?
      context.input.error_for_process?(@impl)
    end

    # Returns this error IO.
    def error : IO
      error?.not_nil!
    end

    # Returns the exit code returned by the running process.
    #
    # It waits for the running process to terminate.
    def exit_code
      exit_status.code
    end

    @exit_status = ExitStatus.new(-1)
    # Returns the exit status returned by the running process.
    #
    # It waits for the running process to terminate.
    def exit_status
      wait
      @exit_status
    end

    @exited : Bool?
    # Tests if the process is started and exited.
    def exited?
      @exited
    end

    # Tests if the running process is successfully terminated.
    #
    # It waits for the running process to terminate.
    def success?
      exit_status.success?
    end

    # Tests if the process is unstarted, exited or aborted.
    def terminated?
      unstarted? || exited? || aborted?
    end

    # Tests if the running process is started.
    getter? started : Bool?

    # Tests if the running process is aborted.
    getter? aborted : Bool?

    # Tests if the running process is unstarted.
    def unstarted?
      @started == false
    end

    # Kills this process.
    def kill(signal : Signal? = nil)
      begin
        kill! signal
      rescue ex : Errno
        raise ex if ex.errno != Errno::ESRCH
      end
    end

    # Kills this process.
    #
    # Raises an Errno (ESRCH) exception if no process or process group can be found.
    def kill!(signal : Signal? = nil)
      if impl = exists?
        impl.kill signal || context.abort_signal
      end
    end

    # Tests if the running process exists.
    def exists?
      if impl = @impl
        return impl if !exited? && !aborted? && impl.exists?
      end
    end
  end
end
