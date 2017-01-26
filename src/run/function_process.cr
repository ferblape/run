module Run
  class FunctionProcess
    include AsProcess

    @impl : Impl?
    getter signal_channel = Channel(Signal).new

    # Returns the source function.
    def function : Function
      @command.as(Function)
    end

    # :nodoc:
    class Impl
      @future : Concurrent::Future(Int32)?
      @wait_mutex = Mutex.new

      def initialize(@process : FunctionProcess)
        @future = future do
          @process.function.proc.call(@process)
        end
      end

      @exit_code : Int32?
      def exit_code
        wait
        @exit_code.not_nil!
      end

      def wait
        @wait_mutex.synchronize do
          if future = @future
            @exit_code = future.get
            @future = nil
          end
        end
        self
      end

      def input
      end

      def output
      end

      def error
      end

      def exists?
        @future
      end

      def kill(signal)
        @process.signal_channel.send signal
      end
    end

    def new_impl
      Impl.new(self)
    end
  end
end
