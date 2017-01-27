module Run
  class FiberFunction
    include AsCommand

    alias ProcType = Proc(Int32)

    getter proc : ProcType

    # :nodoc:
    def initialize(**named, &block : ProcType)
      @context = Context.new(**named)
      @proc = block
    end

    # :nodoc:
    def new_process(parent : ProcessGroup) : FunctionFiber
      new_process(parent, Context.new)
    end

    # :nodoc:
    def new_process(parent : ProcessGroup?, attrs : Context) : FunctionFiber
      if parent
        rc = parent.run_context.dup.set(attrs)
        FunctionFiber.new(parent, self, rc)
      else
        parent = ProcessGroup.new
        process = FunctionFiber.new(parent, self, attrs.dup)
        parent << process
        process
      end
    end
  end
end