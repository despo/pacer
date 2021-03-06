require 'set'
module Pacer
  module Core

    # The basic internal logic for routes and core route shared methods are
    # defined here. Many of these methods are designed to be specialized by
    # other modules included after Core::Route is included.
    module Route

      # Each route object is extended with these class or 'static' methods.
      module RouteClassMethods
        def from_edge_ids(graph, ids)
          Pacer::Route.new :element_type => :edge,
            :graph => graph,
            :back => proc { graph.load_edges ids },
            :info => ids.count
        end

        def from_vertex_ids(graph, ids)
          Pacer::Route.new :element_type => :vertex,
            :graph => graph,
            :back => proc { graph.load_vertices ids },
            :info => ids.count
        end
      end

      def self.included(target)
        target.send :include, Enumerable
        target.extend RouteClassMethods
      end

      # Set these to effect how the route is displayed when inspected.
      attr_accessor :route_name, :info

      # Specify which pipe class will be instantiated when an iterator is created.
      attr_accessor :pipe_class

      # Boolean whether the route alone should be returned by inspect. If
      # false, the the elements that the route matches will also be displayed.
      attr_accessor :hide_elements

      # The previous route in the path
      def back
        @back
      end

      # Set which graph this route will operate on.
      def graph=(graph)
        @graph = graph
      end

      # Return which graph this route operates on.
      def graph
        @graph ||= (@back || @source).graph rescue nil
      end

      # Returns true if the given graph is the one this route operates on.
      def from_graph?(g)
        graph.equals g
      end

      def pipe_args=(args)
        if args.is_a? Array
          @pipe_args = args
        else
          @pipe_args = [args]
        end
      end

      # Return true if this route is at the beginning of the route definition.
      def root?
        !@source.nil? or @back.nil?
      end

      # Prevents the route from being evaluated when it is inspected. Useful
      # for computationally expensive routes.
      def route
        @hide_elements = true
        self
      end

      # Returns the hash of variables used during the previous evaluation of
      # the route.
      #
      # The contents of vars is expected to be in a state relevant to the
      # latest route being evaluated and is primarily meant for internal use,
      # but YMMV.
      def vars
        if @back
          @back.vars
        else
          @vars ||= {}
        end
      end

      def each(&block)
        each_element(&block)
      end

      # Yields each matching element or returns an iterator if no block is given.
      def each_element
        iter = iterator
        g = graph
        if extensions.empty?
          if block_given?
            while item = iter.next
              item.graph ||= g if g and item.respond_to? :graph=
              yield item
            end
          else
            iter
          end
        else
          if block_given?
            while item = iter.next
              if item.respond_to? :graph=
                item.graph ||= g if g and item.respond_to? :graph=
                item = item.add_extensions(extensions)
              end
              yield item
            end
          else
            iter.extend IteratorExtensionsMixin
            iter.graph = g
            iter.extensions = extensions
            iter
          end
        end
      rescue java.util.NoSuchElementException
        self
      end

      # Yields each matching path or returns an iterator if no block is given.
      def each_path
        iter = iterator
        iter.enable_path
        if block_given?
          g = graph
          while item = iter.next
            path = iter.path.collect do |e|
              e.graph ||= g rescue nil
              e
            end
            yield path
          end
        else
          iter.extend IteratorPathMixin
          iter.graph = graph
          iter
        end
      rescue java.util.NoSuchElementException
        self
      end

      def each_context
        iter = iterator
        if block_given?
          g = graph
          while item = iter.next
            item.graph ||= g
            item.extend Pacer::Extensions::BlockFilterElement
            item.back = self
            yield item
          end
        else
          iter.extend IteratorContextMixin
          iter.graph = graph
          iter.context = self
          iter
        end
      rescue java.util.NoSuchElementException
        self
      end

      def each_object
        iter = iterator
        if block_given?
          while item = iter.next
            yield item
          end
        else
          iter
        end
      rescue java.util.NoSuchElementException
        self
      end

      # Returns a string representation of the route definition. If there are
      # less than Graph#inspect_limit matches, it will also output all matching
      # elements formatted in columns up to a maximum character width of
      # Graph#columns.  If this output behaviour is undesired, it may be turned
      # off by calling #route on the current route.
      def inspect(limit = nil)
        if Pacer.hide_route_elements or hide_elements or source.nil?
          "#<#{inspect_strings.join(' -> ')}>"
        else
          count = 0
          limit ||= Pacer.inspect_limit
          results = collect do |v|
            count += 1
            return route.inspect if count > limit
            v.inspect
          end
          if count > 0
            lens = results.collect { |r| r.length }
            max = lens.max
            cols = (Pacer.columns / (max + 1).to_f).floor
            cols = 1 if cols < 1
            template_part = ["%-#{max}s"]
            template = (template_part * cols).join(' ')
            results.each_slice(cols) do |row|
              template = (template_part * row.count).join(' ') if row.count < cols
              puts template % row
            end
          end
          puts "Total: #{ count }"
          "#<#{inspect_strings.join(' -> ')}>"
        end
      end

      # Returns true if the other route is defined the same as the current route.
      #
      # Note that block filters will prevent matches even with identically
      # defined routes unless the routes are actually the same object.
      def ==(other)
        other.class == self.class and
          other.graph == graph and
          other.send(:inspect_strings) == inspect_strings
      end

      def empty?
        none?
      end

      def add_extension(mod)
        return self unless mod.respond_to?(:const_defined?)
        is_extension = false
        if mod.const_defined? :Route
          is_extension = true
          extend mod::Route
        end
        if is_extension or mod.const_defined? :Vertex or mod.const_defined? :Edge
          extensions << mod
        end
        self
      end

      def extensions=(exts)
        @extensions ||= Set[]
        add_extensions Set[*exts]
      end

      def extensions
        @extensions ||= Set[]
      end

      # If any objects in the given array are modules that contain a Route
      # submodule, extend this route with the Route module.
      def add_extensions(exts)
        modules = exts.select { |obj| obj.is_a? Module or obj.is_a? Class }
        modules.each do |mod|
          add_extension(mod)
        end
        self
      end

      def set_pipe_source(source)
        if @back
          @back.set_pipe_source source
        else
          self.source = source
        end
      end

      def element_type
        Object
      end

      protected

      # Initializes some basic instance variables.
      # TODO: rename initialize_path initialize_route
      def initialize_path(back = nil, *pipe_args)
        self.back = back
        @pipe_args = pipe_args || []
      end

      # Set the previous route in the chain.
      def back=(back)
        if back.is_a? Route and not back.is_a? GraphMixin
          @back = back
        else
          @source = back
        end
      end

      def source=(source)
        self.back = source
      end

      # Return the route which is attached to the given route.
      def route_after(route)
        if route == self
          nil
        elsif @back
          if @back == route
            self
          elsif @back.is_a? Route
            @back.route_after(route)
          end
        end
      end

      # Returns a HashSet of element ids from the collection, but
      # only if all elements in the collection have an element_id.

      # This should not normally need to be set. It can be used to inject a route
      # into another route during iterator generation.
      def source=(source)
        @back = nil
        @source = source
      end

      # Get the actual source of data for this route.
      def source
        if @source
          iterator_from_source(@source)
        elsif @back
          @back.send(:source)
        end
      end

      # Get the first and last pipes in the pipeline before the current route's pipes are added.
      def pipe_source
        if @source
          nil
        elsif @back
          @back.send(:build_pipeline)
        end
      end

      # Return an iterator for a variety of source object types.
      def iterator_from_source(src)
        if src.is_a? Pacer::GraphMixin
          al = java.util.ArrayList.new
          al << src
          al.iterator
        elsif src.is_a? Pacer::ElementWrapper
          Pacer::Pipes::EnumerablePipe.new src.element
        elsif src.is_a? Proc
          iterator_from_source(src.call)
        elsif src.is_a? Iterator
          src
        elsif src
          Pacer::Pipes::EnumerablePipe.new src
        end
      end

      # Return an iterator for this route loading data from all previous routes
      # in the chain.
      def iterator
        @vars = {}
        start, end_pipe = build_pipeline
        if start
          src = source
          Pacer.debug_source = src if Pacer.debug_pipes
          start.set_starts src
          end_pipe
        elsif end_pipe
          raise "End pipe without start pipe"
        else
          pipe = Pacer::Pipes::IdentityPipe.new
          pipe.set_starts source
          pipe
        end
      end

      def attach_pipe(end_pipe)
        if @pipe_class
          if @pipe_args
            begin
              pipe = @pipe_class.new(*@pipe_args)
            rescue ArgumentError
              raise ArgumentError, "Invalid args for pipe: #{ @pipe_class.inspect }.new(*#{@pipe_args.inspect})"
            end
          else
            begin
              pipe = @pipe_class.new
            rescue ArgumentError
              raise ArgumentError, "Invalid args for pipe: #{ @pipe_class.inspect }.new()"
            end
          end
          pipe.set_starts end_pipe if end_pipe
          pipe
        else
          end_pipe
        end
      end

      def build_pipeline
        start, end_pipe = pipe_source
        pipe = attach_pipe(end_pipe)
        Pacer.debug_pipes << { :name => inspect_class_name, :start => start, :end => pipe } if Pacer.debug_pipes
        [start || pipe, pipe]
      end

      # Returns an array of strings representing each route object in the
      # chain.
      def inspect_strings
        ins = []
        ins += @back.inspect_strings unless root?

        ins << inspect_string
        ins
      end

      def inspect_string
        return @route_name if @route_name
        if @pipe_class
          ps = @pipe_class.name
          if ps =~ /FilterPipe$/
            ps = ps.split('::').last.sub(/FilterPipe/, '')
            pipeargs = @pipe_args.collect do |arg|
              if arg.is_a? Enumerable and arg.count > 10
                "[...#{ arg.count } items...]"
              else
                arg.to_s
              end
            end
            ps = "#{ps}(#{pipeargs.join(', ')})" if pipeargs.any?
          else
            ps = @pipe_args
          end
        end
        s = inspect_class_name
        s = "#{s}(#{ ps })" if ps
        s
      end

      # Return the class name of the current route.
      def inspect_class_name
        s = "#{self.class.name.split('::').last.sub(/Route$/, '')}"
        s = "#{s} #{ @info }" if @info
        s
      end

    end
  end
end
