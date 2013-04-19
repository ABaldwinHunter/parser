module Parser

  class Builders::Default
    attr_accessor :parser

    #
    # Literals
    #

    # Singletons

    def nil(nil_t)
      n0(:nil,
        expr_map(nil_t))
    end

    def true(true_t)
      n0(:true,
        expr_map(true_t))
    end

    def false(false_t)
      n0(:false,
        expr_map(false_t))
    end

    # Numerics

    def integer(integer_t, negate=false)
      val = value(integer_t)
      val = -val if negate

      n(:int, [ val ],
        expr_map(integer_t))
    end

    def __LINE__(__LINE__t)
      n0(:__LINE__,
        expr_map(__LINE__t))
    end

    def float(float_t, negate=false)
      val = value(float_t)
      val = -val if negate

      n(:float, [ val ],
        expr_map(float_t))
    end

    # Strings

    def string(string_t)
      n(:str, [ value(string_t) ],
        expr_map(string_t))
    end

    def string_compose(begin_t, parts, end_t)
      if collapse_string_parts?(parts)
        parts.first
      else
        n(:dstr, [ *parts ],
          collection_map(begin_t, end_t))
      end
    end

    def __FILE__(__FILE__t)
      n0(:__FILE__,
        expr_map(__FILE__t))
    end

    # Symbols

    def symbol(symbol_t)
      n(:sym, [ value(symbol_t).to_sym ],
        expr_map(symbol_t))
    end

    def symbol_compose(begin_t, parts, end_t)
      n(:dsym, [ *parts ],
        collection_map(begin_t, end_t))
    end

    # Executable strings

    def xstring_compose(begin_t, parts, end_t)
      n(:xstr, [ *parts ],
        collection_map(begin_t, end_t))
    end

    # Regular expressions

    def regexp_options(regopt_t)
      options = value(regopt_t).
        each_char.sort.uniq.
        map(&:to_sym)

      n(:regopt, options,
        expr_map(regopt_t))
    end

    def regexp_compose(begin_t, parts, end_t, options)
      n(:regexp, [ *(parts << options) ],
        collection_map(begin_t, end_t))
    end

    # Arrays

    def array(begin_t, elements, end_t)
      n(:array, elements,
        collection_map(begin_t, end_t))
    end

    def splat(star_t, arg=nil)
      if arg.nil?
        n0(:splat, nil)
      else
        n(:splat, [ arg ], nil)
      end
    end

    def word(parts)
      if collapse_string_parts?(parts)
        parts.first
      else
        n(:dstr, [ *parts ], nil)
      end
    end

    def words_compose(begin_t, parts, end_t)
      n(:array, [ *parts ],
        collection_map(begin_t, end_t))
    end

    def symbols_compose(begin_t, parts, end_t)
      parts = parts.map do |part|
        case part.type
        when :str
          value, = *part
          part.updated(:sym, [ value.to_sym ])
        when :dstr
          part.updated(:dsym)
        else
          part
        end
      end

      n(:array, [ *parts ],
        collection_map(begin_t, end_t))
    end

    # Hashes

    def pair(key, assoc_t, value)
      n(:pair, [ key, value ],
        nil)
    end

    def pair_list_18(list)
      if list.size % 2 != 0
        # TODO better location info here
        message = ERRORS[:odd_hash]
        diagnostic :error, message, list.last.src.expression
      else
        list.
          each_slice(2).map do |key, value|
            n(:pair, [ key, value ], nil)
          end
      end
    end

    def associate(begin_t, pairs, end_t)
      n(:hash, [ *pairs ],
        nil)
    end

    def kwsplat(dstar_t, arg)
      n(:kwsplat, [ arg ],
        nil)
    end

    # Ranges

    def range_inclusive(lhs, token, rhs)
      n(:irange, [ lhs, rhs ],
        nil)
    end

    def range_exclusive(lhs, token, rhs)
      n(:erange, [ lhs, rhs ],
        nil)
    end

    #
    # Expression grouping
    #

    def parenthesize(begin_t, expr, end_t)
      if expr.nil?
        n0(:nil, nil)
      else
        expr
      end
    end

    #
    # Access
    #

    def self(token)
      n0(:self,
        expr_map(token))
    end

    def ident(token)
      n(:ident, [ value(token).to_sym ],
        expr_map(token))
    end

    def ivar(token)
      n(:ivar, [ value(token).to_sym ],
        expr_map(token))
    end

    def gvar(token)
      n(:gvar, [ value(token).to_sym ],
        expr_map(token))
    end

    def cvar(token)
      n(:cvar, [ value(token).to_sym ],
        expr_map(token))
    end

    def back_ref(token)
      n(:back_ref, [ value(token).to_sym ],
       expr_map(token))
    end

    def nth_ref(token)
      n(:nth_ref, [ value(token) ],
        expr_map(token))
    end

    def accessible(node)
      case node.type
      when :__FILE__
        n(:str, [ node.src.expression.source_buffer.name ],
          node.src)

      when :__LINE__
        n(:int, [ node.src.expression.line ],
          node.src)

      when :__ENCODING__
        n(:const, [ n(:const, [ nil, :Encoding], nil), :UTF_8 ],
          node.src)

      when :ident
        name, = *node

        if @parser.static_env.declared?(name)
          node.updated(:lvar)
        else
          name, = *node
          node.updated(:send, [ nil, name ])
        end

      else
        node
      end
    end

    def const(name_t)
      n(:const, [ nil, value(name_t).to_sym ],
        expr_map(name_t))
    end

    def const_global(t_colon3, name_t)
      n(:const, [ n0(:cbase, nil), value(name_t).to_sym ],
        nil)
    end

    def const_fetch(scope, t_colon2, name_t)
      n(:const, [ scope, value(name_t).to_sym ],
        nil)
    end

    def __ENCODING__(__ENCODING__t)
      n0(:__ENCODING__,
        expr_map(__ENCODING__t))
    end

    #
    # Assignment
    #

    def assignable(node)
      case node.type
      when :cvar
        if @parser.in_def?
          node.updated(:cvasgn)
        else
          node.updated(:cvdecl)
        end

      when :ivar
        node.updated(:ivasgn)

      when :gvar
        node.updated(:gvasgn)

      when :const
        if @parser.in_def?
          message = ERRORS[:dynamic_const]
          diagnostic :error, message, node.src.expression
        end

        node.updated(:cdecl)

      when :ident
        name, = *node
        @parser.static_env.declare(name)

        node.updated(:lvasgn)

      when :nil, :self, :true, :false,
           :__FILE__, :__LINE__, :__ENCODING__
        message = ERRORS[:invalid_assignment]
        diagnostic :error, message, node.src.expression

      when :back_ref, :nth_ref
        message = ERRORS[:backref_assignment]
        diagnostic :error, message, node.src.expression

      else
        raise NotImplementedError, "build_assignable #{node.inspect}"
      end
    end

    def assign(lhs, eql_t, rhs)
      case lhs.type
      when :lvasgn, :masgn, :gvasgn, :ivasgn, :cvdecl,
           :cvasgn, :cdecl,
           :send
        lhs << rhs

      when :const
        (lhs << rhs).updated(:cdecl)

      else
        raise NotImplementedError, "build assign #{lhs.inspect}"
      end
    end

    def op_assign(lhs, operator_t, rhs)
      case lhs.type
      when :gvasgn, :ivasgn, :lvasgn, :cvasgn, :cvdecl,
           :cdecl,
           :send
        operator = value(operator_t)[0..-1].to_sym

        case operator
        when :'&&'
          n(:and_asgn, [ lhs, rhs ],
            nil)
        when :'||'
          n(:or_asgn, [ lhs, rhs ],
            nil)
        else
          n(:op_asgn, [ lhs, operator, rhs ],
            nil)
        end

      when :back_ref, :nth_ref
        message = ERRORS[:backref_assignment]
        diagnostic :error, message, lhs.src.expression

      else
        raise NotImplementedError, "build op_assign #{lhs.inspect}"
      end
    end

    def multi_lhs(begin_t, items, end_t)
      n(:mlhs, [ *items ],
        nil)
    end

    def multi_assign(lhs, eql_t, rhs)
      n(:masgn, [ lhs, rhs ],
        nil)
    end

    #
    # Class and module definition
    #

    def def_class(class_t, name,
                  lt_t, superclass,
                  body, end_t)
      n(:class, [ name, superclass, body ],
        nil)
    end

    def def_sclass(class_t, lshft_t, expr,
                   body, end_t)
      n(:sclass, [ expr, body ],
        nil)
    end

    def def_module(module_t, name,
                   body, end_t)
      n(:module, [ name, body ],
        nil)
    end

    #
    # Method (un)definition
    #

    def def_method(def_t, name, args,
                   body, end_t, comments)
      n(:def, [ value(name).to_sym, args, body ],
        nil)
    end

    def def_singleton(def_t, definee, dot_t,
                      name, args,
                      body, end_t, comments)
      case definee.type
      when :int, :str, :dstr, :sym, :dsym,
           :regexp, :array, :hash

        message = ERRORS[:singleton_literal]
        diagnostic :error, message, nil # TODO definee.src.expression

      else
        n(:defs, [ definee, value(name).to_sym, args, body ],
          nil)
      end
    end

    def undef_method(undef_t, names)
      n(:undef, [ *names ],
        nil)
    end

    #
    # Aliasing
    #

    def alias(alias_t, to, from)
      n(:alias, [ to, from ],
        nil)
    end

    def keyword_cmd(type, keyword_t, lparen_t=nil, args=[], rparen_t=nil)
      case type
      when :return,
           :break, :next, :redo,
           :retry,
           :super, :zsuper, :yield,
           :defined?

        n(type, args,
          nil)

      else
        raise NotImplementedError, "build_keyword_cmd #{type} #{args.inspect}"
      end
    end

    #
    # Formal arguments
    #

    def args(begin_t, args, end_t)
      n(:args, [ *check_duplicate_args(args) ],
        nil)
    end

    def arg(name_t)
      n(:arg, [ value(name_t).to_sym ],
        expr_map(name_t))
    end

    def optarg(name_t, eql_t, value)
      n(:optarg, [ value(name_t).to_sym, value ],
        nil)
    end

    def restarg(star_t, name_t=nil)
      if name_t
        n(:restarg, [ value(name_t).to_sym ],
          nil)
      else
        n0(:restarg,
          expr_map(star_t))
      end
    end

    def kwarg(name_t)
      n(:kwarg, [ value(name_t).to_sym ],
        nil)
    end

    def kwoptarg(name_t, value)
      n(:kwoptarg, [ value(name_t).to_sym, value ],
        nil)
    end

    def kwrestarg(dstar_t, name_t=nil)
      if name_t
        n(:kwrestarg, [ value(name_t).to_sym ],
          nil)
      else
        n0(:kwrestarg, expr_map(dstar_t))
      end
    end

    def shadowarg(name_t)
      n(:shadowarg, [ value(name_t).to_sym ],
        nil)
    end

    def blockarg(amper_t, name_t)
      n(:blockarg, [ value(name_t).to_sym ],
        nil)
    end

    # Ruby 1.8 block arguments

    def arg_expr(expr)
      if expr.type == :lvasgn
        expr.updated(:arg)
      else
        n(:arg_expr, [ expr ],
          nil)
      end
    end

    def restarg_expr(star_t, expr=nil)
      if expr.nil?
        n0(:restarg, expr_map(star_t))
      elsif expr.type == :lvasgn
        expr.updated(:restarg)
      else
        n(:restarg_expr, [ expr ],
          nil)
      end
    end

    def blockarg_expr(amper_t, expr)
      if expr.type == :lvasgn
        expr.updated(:blockarg)
      else
        n(:blockarg_expr, [ expr ],
          nil)
      end
    end

    #
    # Method calls
    #

    def call_method(receiver, dot_t, selector_t,
                    begin_t=nil, args=[], end_t=nil)
      if selector_t.nil?
        n(:send, [ receiver, :call, *args ],
          nil)
      else
        n(:send, [ receiver, value(selector_t).to_sym, *args ],
          send_map(loc(selector_t), loc(begin_t), loc(end_t)))
      end
    end

    def call_lambda(lambda_t)
      n(:send, [ nil, :lambda ],
        nil)
    end

    def block(method_call, begin_t, args, body, end_t)
      _receiver, _selector, *call_args = *method_call
      last_arg = call_args.last

      if last_arg && last_arg.type == :block_pass
        # TODO uncomment when source maps are ready
        # diagnostic :error, :block_and_blockarg,
        #            last_arg.src.expression

        diagnostic :error, ERRORS[:block_and_blockarg],
                   last_arg.children.last.src.expression
      end

      n(:block, [ method_call, args, body ],
        nil)
    end

    def block_pass(amper_t, arg)
      n(:block_pass, [ arg ],
        nil)
    end

    def attr_asgn(receiver, dot_t, selector_t)
      method_name = (value(selector_t) + '=').to_sym

      # Incomplete method call.
      n(:send, [ receiver, method_name ],
        nil)
    end

    def index(receiver, lbrack_t, indexes, rbrack_t)
      n(:send, [ receiver, :[], *indexes ],
        nil)
    end

    def index_asgn(receiver, lbrack_t, indexes, rbrack_t)
      # Incomplete method call.
      n(:send, [ receiver, :[]=, *indexes ],
        nil)
    end

    def binary_op(receiver, op_t, arg)
      if @parser.version == 18
        if value(op_t) == '!='
          return n(:not, [ n(:send, [ receiver, :==, arg ], nil) ], nil)
        elsif value(op_t) == '!~'
          return n(:not, [ n(:send, [ receiver, :=~, arg ], nil) ], nil)
        end
      end

      n(:send, [ receiver, value(op_t).to_sym, arg ],
        send_operator_map(loc(op_t), receiver, arg))
    end

    def unary_op(op_t, receiver)
      case value(op_t)
      when '+', '-'
        method = value(op_t) + '@'
      else
        method = value(op_t)
      end

      n(:send, [ receiver, method.to_sym ],
        nil)
    end

    def not_op(not_t, receiver=nil)
      if @parser.version == 18
        n(:not, [ receiver ],
          nil)
      else
        if receiver.nil?
          n(:send, [ n0(:nil, nil), :'!' ],
            nil)
        else
          n(:send, [ receiver, :'!' ],
            nil)
        end
      end
    end

    #
    # Control flow
    #

    # Logical operations: and, or

    def logical_op(type, lhs, token, rhs)
      n(type, [ check_condition(lhs), check_condition(rhs) ],
        nil)
    end

    # Conditionals

    def condition(cond_t, cond, then_t,
                  if_true, else_t, if_false, end_t)
      n(:if, [ check_condition(cond), if_true, if_false ],
        nil)
    end

    def condition_mod(if_true, if_false, cond_t, cond)
      n(:if, [ check_condition(cond), if_true, if_false ],
        nil)
    end

    def ternary(cond, question_t, if_true, colon_t, if_false)
      n(:if, [ check_condition(cond), if_true, if_false ],
        nil)
    end

    # Case matching

    def when(when_t, patterns, then_t, body)
      n(:when, (patterns << body),
        nil)
    end

    def case(case_t, expr, body, end_t)
      n(:case, [ expr, *body ],
        nil)
    end

    # Loops

    def loop(loop_t, cond, do_t, body, end_t)
      n(value(loop_t).to_sym, [ check_condition(cond), body ],
        nil)
    end

    def loop_mod(body, loop_t, cond)
      n(value(loop_t).to_sym, [ check_condition(cond), body ],
        nil)
    end

    def for(for_t, iterator, in_t, iteratee,
            do_t, body, end_t)
      n(:for, [ iterator, iteratee, body ], nil)
    end

    # Exception handling

    def begin(begin_t, body, end_t)
      body
    end

    def rescue_body(rescue_t,
                    exc_list, assoc_t, exc_var,
                    then_t, compound_stmt)
      n(:resbody, [ exc_list, exc_var, compound_stmt ],
        nil)
    end

    def begin_body(compound_stmt, rescue_bodies=[],
                   else_t=nil,    else_=nil,
                   ensure_t=nil,  ensure_=nil)
      if rescue_bodies.any?
        if else_t
          compound_stmt = n(:rescue,
                            [ compound_stmt, *(rescue_bodies << else_) ],
                            nil)
        else
          compound_stmt = n(:rescue,
                            [ compound_stmt, *(rescue_bodies << nil) ],
                            nil)
        end
      end

      if ensure_t
        compound_stmt = n(:ensure, [ compound_stmt, ensure_ ],
                          nil)
      end

      compound_stmt
    end

    def compstmt(statements)
      case
      when statements.one?
        statements.first
      when statements.none?
        n0(:nil, nil)
      else
        n(:begin, [ *statements ],
          nil)
      end
    end

    # BEGIN, END

    def preexe(preexe_t, lbrace_t, compstmt, rbrace_t)
      n(:preexe, [ compstmt ],
        kw_block_map(loc(preexe_t), loc(lbrace_t), loc(rbrace_t)))
    end

    def postexe(postexe_t, lbrace_t, compstmt, rbrace_t)
      n(:postexe, [ compstmt ],
        kw_block_map(loc(postexe_t), loc(lbrace_t), loc(rbrace_t)))
    end

    private

    #
    # VERIFICATION
    #

    def check_condition(cond)
      if cond.type == :masgn
        # TODO source maps
        diagnostic :error, ERRORS[:masgn_as_condition],
                   nil #cond.src.expression
      end

      cond
    end

    def check_duplicate_args(args, map={})
      args.each do |this_arg|
        case this_arg.type
        when :arg, :optarg, :restarg, :blockarg,
             :kwarg, :kwoptarg, :kwrestarg,
             :shadowarg

          this_name, = *this_arg

          that_arg   = map[this_name]
          that_name, = *that_arg

          if that_arg.nil?
            map[this_name] = this_arg
          elsif arg_name_collides?(this_name, that_name)
            # TODO reenable when source maps are done
            diagnostic :error, ERRORS[:duplicate_argument],
                       nil # this_arg.src.expression, [ that_arg.src.expression ]
          end

        when :mlhs
          check_duplicate_args(this_arg.children, map)
        end
      end
    end

    def arg_name_collides?(this_name, that_name)
      case @parser.version
      when 18
        this_name == that_name
      when 19
        # Ignore underscore.
        this_name != :_ &&
          this_name == that_name
      else
        # Ignore everything beginning with underscore.
        this_name[0] != '_' &&
          this_name == that_name
      end
    end

    #
    # SOURCE MAPS
    #

    def n(type, children, map)
      AST::Node.new(type, children, :source_map => map)
    end

    def n0(type, map)
      n(type, [], map)
    end

    def j(left_expr, right_expr)
      left_expr.src.expression.
        join(right_expr.src.expression)
    end

    def expr_map(expr_t)
      Source::Map.new(loc(expr_t))
    end

    def collection_map(begin_t, end_t)
      Source::Map::Collection.new(loc(begin_t), loc(end_t))
    end

    def operator_map(left_e, op_l, right_e)
      Source::Map::Operator.new(op_l, j(left_e, right_e))
    end

    def send_map(selector_l, begin_l, end_l)
      nil # Source::Map::Send.new(selector_l, begin_l.join(end_l))
    end

    def send_operator_map(selector_l, begin_e, end_e)
      Source::Map::SendOperator.new(selector_l, j(begin_e, end_e))
    end

    def kw_block_map(keyword_l, begin_l, end_l)
      Source::Map::KeywordWithBlock.new(keyword_l, begin_l, end_l)
    end

    #
    # HELPERS
    #

    def collapse_string_parts?(parts)
      parts.one? &&
          [:str, :dstr].include?(parts.first.type)
    end

    def value(token)
      token[0]
    end

    def loc(token)
      token[1] if token
    end

    def diagnostic(type, message, location, highlights=[])
      @parser.diagnostics.process(
          Diagnostic.new(type, message, location, highlights))

      if type == :error
        @parser.send :yyerror
      end
    end
  end

end
