module Glush
  class JavaScriptGenerator
    def self.generate(grammar)
      output = ""
      generator = new(grammar, output)
      generator.emit_all
      output
    end

    def initialize(grammar, output)
      @output = output
      @sm = grammar.state_machine
    end

    def emit(line)
      @output << line << "\n"
    end

    def emit_all
      emit_runtime
      emit_states
      emit_inital_frames
      emit_rule_initial_states
    end

    def emit_runtime
      @output << RUNTIME
    end

    def emit_inital_frames
      emit("var initialContext = new Context(null, null);")
      emit("var initialFrame = new Frame(initialContext);")
      @sm.initial_states.each do |state|
        emit("initialFrame.addNextState(%s);" % state_lvar(state))
      end
      emit("var initialFrames = [initialFrame];")
    end

    def emit_rule_initial_states
      emit("var ruleInitialStates = {}")
      @sm.rules.each do |rule|
        lvars = @sm.rule_first[rule].map { |s| state_lvar(s) }
        str = "[#{lvars.join(", ")}]"
        emit("ruleInitialStates[%s] = %s;" % [rule_id(rule), str])
      end
    end

    def emit_states
      @sm.states.each do |state|
        emit("var %s = new State();" % [state_lvar(state)])
      end

      @sm.states.each do |state|
        emit("%s.p = %s;" % [state_lvar(state), process_func(state)])
        emit("%s.id = %s;" % [state_lvar(state), state.id])
      end
    end

    def process_func(state)
      result = []
      state.actions.each do |action|
        case action
        when StateMachine::TokenAction
          result << "if (%s) { frame.addNextState(%s); }" % [
            match_pattern(action.pattern),
            state_lvar(action.next_state),
          ]
        when StateMachine::CallAction
          rule = action.rule
          result << "step.startCall(%s).addReturn(frame.context, %s);" % [
            rule_id(rule),
            state_lvar(action.return_state),
          ]
        when StateMachine::ReturnAction
          rule = action.rule
          if rule.guard
            guard = "if (%s) " % match_pattern(rule.guard)
          else
            guard = ""
          end
          result << "#{guard}step.returnCall(%s, frame);" % rule_id(rule)
        when StateMachine::AcceptAction
          result << "step.addAccept(frame.context);"
        when StateMachine::MarkAction
          state = state_lvar(action.next_state)
          result << "step.addMark(%p, frame.context, %s);" % [action.name.to_s, state]
        else
          raise "unknown action: #{action}"
        end
      end
      "(function(step, frame) {\nvar token = step.token;\n#{result.join("\n")}\n})"
    end

    def match_pattern(pattern, var_name = "token")
      case pattern
      when Patterns::Token
        case pattern.choice
        when Integer
          "#{var_name} === #{pattern.choice}"
        when Patterns::Less
          "#{var_name} <= #{pattern.choice.token}"
        when Patterns::Greater
          "#{var_name} >= #{pattern.choice.token}"
        when nil
          "true"
        when Range
          a = "#{var_name} >= #{pattern.choice.begin}"
          b = "#{var_name} <= #{pattern.choice.end}"
          "(#{a} && #{b})"
        else
          raise "unknown: #{pattern.choice}"
        end
      when Patterns::Conj
        left = match_pattern(pattern.left, var_name)
        right = match_pattern(pattern.right, var_name)
        "(#{left} && #{right})"
      when Patterns::Alt
        left = match_pattern(pattern.left, var_name)
        right = match_pattern(pattern.right, var_name)
        "(#{left} || #{right})"
      else
        raise "unknown: #{pattern}"
      end
    end

    def state_lvar(state)
      "state#{state.id}"
    end

    def rule_id(rule)
      rule.name.inspect
    end

    RUNTIME = <<~JS
    function State() { }

    function Step(token, position) {
      this.token = token;
      this.position = position;
      this.nextFrames = [];
      this.acceptedContexts = [];
      this.callers = {};
    }

    Step.prototype.hasNextFrames = function hasNextFrames() {
      return this.nextFrames.length > 0;
    }

    Step.prototype.addNextFrame = function addNextFrame(frame) {
      this.nextFrames.push(frame);
    }

    Step.prototype.wasAccepted = function wasAccepted() {
      return this.acceptedContexts.length > 0;
    }

    Step.prototype.addAccept = function addAccept(context) {
      this.acceptedContexts.push(context);
    }

    Step.prototype.addMark = function addMark(name, context, nextState) {
      var mark = {
        type: "mark",
        name: name,
        position: this.position,
      };
      var marks = context.marks
        ? {
            type: "concat",
            left: context.marks,
            right: mark,
          }
        : mark;
      var nextContext = new Context(context.caller, marks);
      var nextFrame = new Frame(nextContext);
      nextState.p(this, nextFrame);
      addNextFrame(this, nextFrame);
    }

    Step.prototype.startCall = function startCall(ruleId) {
      var caller = this.callers[ruleId];

      if (!caller) {
        caller = new Caller();
        this.callers[ruleId] = caller;
        var callContext = new Context(caller, null);
        var callFrame = new Frame(callContext);
        var states = ruleInitialStates[ruleId];
        for (var i = 0; i < states.length; i++) {
          var state = states[i];
          state.p(this, callFrame);
        }
        addNextFrame(this, callFrame);
      }

      return caller;
    }

    Step.prototype.returnCall = function returnCall(ruleId, frame) {
      // TODO: Implement proper grouping
      var caller = frame.context.caller;
      var returns = caller.returns;
      for (var i = 0; i < returns.length; i++) {
        var ret = returns[i];
        var callerContext = ret[0];
        var state = ret[1];

        var leftMarks = callerContext.marks;
        var rightMarks = frame.context.marks;
        var marks = (leftMarks && rightMarks)
          ?  {
              type: "concat",
              left: callerContext.marks,
              right: frame.context.marks
            }
          : (leftMarks || rightMarks);

        var context = new Context(callerContext.caller, marks);
        var nextFrame = new Frame(context);
        state.p(this, nextFrame);
        addNextFrame(this, nextFrame);
      }
    }

    function Caller() {
      this.returns = [];
    }

    Caller.prototype.addReturn = function(context, nextState) {
      this.returns.push([context, nextState]);
    }

    function Context(caller, marks) {
      this.caller = caller;
      this.marks = marks;
    }

    function Frame(context) {
      this.context = context;
      this.nextStates = [];
    }

    Frame.prototype.addNextState = function addNextState(state) {
      this.nextStates.push(state);
    }

    Frame.prototype.eachNextState = function eachNextState(fn) {
      this.nextStates.forEach(fn);
    }

    Frame.prototype.hasNextStates = function hasNextStates() {
      return this.nextStates.length > 0;
    }

    Frame.prototype.copy = function copy() {
      return new Frame(this.context, this.marks);
    }

    function processToken(token, position, frames) {
      var step = new Step(token, position);
      for (var i = 0; i < frames.length; i++) {
        var frame = frames[i];
        processFrame(step, frame);
      }
      return step;
    }

    function processFrame(step, frame) {
      var newFrame = frame.copy();
      frame.eachNextState(function(state) {
        state.p(step, newFrame);
      });
      addNextFrame(step, newFrame);
    }

    function addNextFrame(step, frame) {
      if (frame.hasNextStates()) {
        step.addNextFrame(frame);
      }
    }

    function recognize(input) {
      var frames = initialFrames;

      var i = 0;
      for (; i < input.length; i++) {
        var token = input.charCodeAt(i);
        var step = processToken(token, i, frames);
        if (!step.hasNextFrames()) return false;
        frames = step.nextFrames;
      }

      step = processToken(null, i, frames);
      return step.wasAccepted();
    }

    function flattenMarks(marks) {
      if (!marks) return []

      var queue = [marks];
      var result = [];

      while (queue.length) {
        var m = queue.shift();
        if (m.type === "concat") {
          queue.unshift(m.left, m.right);
        } else if (m.type === "mark") {
          result.push(m);
        } else {
          throw new Error("unknown mark type: " + m.type);
        }
      }

      return result;
    }

    function parse(input) {
      var frames = initialFrames;

      var i = 0;
      for (; i < input.length; i++) {
        var token = input.charCodeAt(i);
        var step = processToken(token, i, frames);
        if (!step.hasNextFrames()) {
          return { type: "error", position: i };
        }
        frames = step.nextFrames;
      }

      step = processToken(null, i, frames);

      if (!step.wasAccepted()) {
        return { type: "error", position: i };
      }

      var ctx = step.acceptedContexts[0];
      var marks = flattenMarks(ctx.marks);

      return {
        type: "success",
        marks: marks
      }
    }
    JS
  end
end

