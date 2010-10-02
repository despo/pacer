module Pacer
  class Path
    include Enumerable

    class << self
      def vertex_path(name)

      end

      def edge_path(name)

      end

      def path(name)
      end
    end

    def initialize(pipe, back = nil)
      @back = back
      @current = current
    end

    def back
      @back
    end

    def root?
      @back.nil?
    end

    def each
      @pipe.to_enum(:each)
    end

    # bias is the chance the element will be returned from 0 to 1 (0% to 100%)
    def random(bias = 0.5)
      self.class.new(RandomFilterPipe.new(bias), self)
    end

    def uniq
      self.class.new(DuplicateFilterPipe.new, self)
    end

    def [](prop_or_subset)
      case prop_or_subset
      when String, Symbol
      when Fixnum
        self.class.new(RangeFilterPipe.new(prop_or_subset, prop_or_subset), self)
      when Range
        end_index = prop_or_subset.end
        end_index -= 1 if prop_or_subset.exclude_end?
        self.class.new(RangeFilterPipe.new(prop_or_subset.begin, end_index), self)
      when Array
      end
    end
    protected

    def filter_pipe(pipe, args_array, block)
      if args_array.empty? and block.nil?
        pipe
      else

      end
    end
  end

  class GraphPath < Path
    def vertexes(*args, &block)
      pipe = GraphElementPipe.new(GraphElementPipe.ElementType.VERTEX);
      @pipe = GraphPath.new(filter_pipe(pipe, args, block), self)
      self
    end

    def edges(*args, &block)
      pipe = GraphElementPipe.new(GraphElementPipe.ElementType.EDGE);
      @pipe = GraphPath.new(filter_pipe(pipe, args, block), self)
      self
    end
  end

  class EdgePath < Path
    def out_v(*args, &block)
      pipe = VertexEdgePipe.new(VertexEdgePipe.Step.OUT_VERTEX)
      @pipe = VertexPath.new(filter_pipe(pipe, args, block), self)
      self
    end

    def in_v(*args, &block)
      pipe = VertexEdgePipe.new(VertexEdgePipe.Step.IN_VERTEX)
      @pipe = VertexPath.new(filter_pipe(pipe, args, block), self)
      self
    end

    def both_v(*args, &block)
      pipe = VertexEdgePipe.new(VertexEdgePipe.Step.BOTH_VERTICES)
      @pipe = VertexPath.new(filter_pipe(pipe, args, block), self)
      self
    end

    protected

    def filter_pipe(pipe, args_array, block)
      labels = args_array.select { |arg| arg.is_a? Symbol or arg.is_a? String }
      if labels.empty?
        super
      else
        new_pipe = labels.inject(pipe) do |label|
          p = LabelFilterPipe.new(label.to_s, ComparisonFilterPipe::Filter::EQUAL)
          p.set_start pipe
          p
        end
        super(new_pipe, args_array - labels, block)
      end
    end
  end

  class VertexPath < Path
    def out_e(*args, &block)
      pipe = EdgeVertexPipe.new(EdgeVertexPipe.Step.OUT_EDGES)
      @pipe = EdgePath.new(filter_pipe(pipe, args, block), self)
      self
    end

    def in_e(*args, &block)
      pipe = EdgeVertexPipe.new(EdgeVertexPipe.Step.IN_EDGES)
      @pipe = EdgePath.new(filter_pipe(pipe, args, block), self)
      self
    end

    def both_e(*args, &block)
      pipe = EdgeVertexPipe.new(EdgeVertexPipe.Step.BOTH_EDGES)
      @pipe = EdgePath.new(filter_pipe(pipe, args, block), self)
      self
    end
  end
end
