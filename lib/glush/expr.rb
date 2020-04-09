module Glush
  module Expr
    class Base
      def consume!
        return copy.consume! if defined?(@consumed)
        @consumed = true
        self
      end

      def terminal?
        raise NotImplementedError, "@is_terminal not set" if !defined?(@is_terminal)
        @is_terminal
      end

      def >>(other)
        Seq.new(self, other)
      end

      def |(other)
        Alt.new(self, other)
      end

      def &(other)
        Conj.new(self, other)
      end

      def plus
        Plus.new(self)
      end

      def star
        plus.maybe
      end

      def maybe
        (self | Eps.new)
      end
    end

    class Final < Base
      def initialize
        @is_terminal = false
      end

      def matches?(token)
        false
      end
    end

    class Less < Base
      attr_reader :token

      def initialize(token)
        @token = token
        @is_terminal = true
      end

      def inspect
        "less(#{token})"
      end
    end

    class Greater < Base
      attr_reader :token

      def initialize(token)
        @token = token
        @is_terminal = true
      end

      def inspect
        "greater(#{token})"
      end
    end

    class Equal < Base
      attr_reader :token

      def initialize(token)
        @token = token
        @is_terminal = true
      end

      def copy
        Equal.new(@token)
      end

      def inspect
        "eq(#{token.chr})"
      end
    end

    class Any < Base
      def initialize
        @is_terminal = true
      end

      def copy
        Any.new
      end

      def inspect
        "any"
      end
    end

    class Eps < Base
      def initialize
        @is_terminal = false
      end

      def copy
        Eps.new
      end

      def inspect
        "eps"
      end
    end

    class Alt < Base
      attr_reader :left, :right

      def initialize(left, right)
        @left = left.consume!
        @right = right.consume!
        @is_terminal = @left.terminal? && @right.terminal?
      end

      def copy
        Alt.new(@left, @right)
      end

      def inspect
        "alt(#{@left.inspect}, #{@right.inspect})"
      end
    end

    class Seq < Base
      attr_reader :left, :right

      def initialize(left, right)
        @left = left.consume!
        @right = right.consume!
        @is_terminal = false
      end

      def copy
        Seq.new(@left, @right)
      end

      def inspect
        "seq(#{@left.inspect}, #{@right.inspect})"
      end
    end

    class Conj < Base
      attr_reader :left, :right

      def initialize(left, right)
        @left = left.consume!
        @right = right.consume!
        @is_terminal = @left.terminal? && @right.terminal?
      end

      def inspect
        "conj(#{@left.inspect}, #{@right.inspect})"
      end
    end

    class Plus < Base
      attr_reader :child

      def initialize(child)
        @child = child.consume!
        @is_terminal = false
      end

      def copy
        Plus.new(@child)
      end

      def inspect
        "plus(#{@child.inspect})"
      end
    end

    class Rule
      attr_reader :name, :calls
      attr_accessor :mark

      def initialize(name, &blk)
        @name = name
        @code = blk
        @calls = []
        @mark = nil
      end

      def call
        name = "#{@name}_#{@calls.size}"
        call = RuleCall.new(name, self)
        @calls << call
        call
      end

      def body
        @body ||= @code.call.consume!
      end

      def inspect
        "<#{@name}>"
      end
    end

    class RuleCall < Base
      attr_reader :name, :rule

      def initialize(name, rule)
        @name = name
        @rule = rule
        @is_terminal = false
      end

      def copy
        RuleCall.new(@name, @rule)
      end

      def inspect
        "<#{@name}>"
      end
    end
  end
end

