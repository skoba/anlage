module Opt
  # config/form_behaviors.yml の式の評価器（skoba/anlage#47 変更 4）。GDL2 の式と互換な安全サブセットだけを
  # 再帰下降で読む（eval しない。トークン集合は閉じている）。12 月の GDL2 評価器導入で置き換える
  # （docs/ideas-2027.md）。クライアント側の写しは app/javascript/controllers/form_behaviors_controller.js。
  #
  #   comparison := additive (("<" | "<=" | ">" | ">=" | "==" | "!=") additive)?
  #   additive   := term (("+" | "-") term)*
  #   term       := unary (("*" | "/") unary)*
  #   unary      := "-" unary | power           # -2 ^ 2 は -(2 ^ 2)
  #   power      := primary ("^" unary)?        # 右結合（2 ^ 3 ^ 2 = 2 ^ 9）
  #   primary    := NUMBER | IDENT | "round" "(" comparison "," comparison ")" | "(" comparison ")"
  class Formula
    class Error < StandardError; end

    TOKEN = /\s*(?:(?<number>\d+(?:\.\d+)?)|(?<ident>[A-Za-z_][A-Za-z0-9_]*)|(?<op><=|>=|==|!=|[-+*\/^()<>,]))/
    COMPARISONS = {
      "<" => :<, "<=" => :<=, ">" => :>, ">=" => :>=, "==" => :==, "!=" => :!=
    }.freeze

    def self.evaluate(expression, variables = {})
      new(expression, variables).evaluate
    end

    def initialize(expression, variables)
      @tokens = tokenize(expression)
      @variables = variables.transform_keys(&:to_s)
      @position = 0
    end

    def evaluate
      value = comparison
      raise Error, "unexpected token #{peek.inspect}" if peek

      value
    end

    private

    def tokenize(expression)
      tokens = []
      rest = expression.to_s
      until rest.strip.empty?
        match = TOKEN.match(rest)
        raise Error, "unexpected character in #{rest.strip.inspect}" unless match&.begin(0)&.zero?

        tokens << (match[:number] ? Float(match[:number]) : (match[:ident] || match[:op]))
        rest = match.post_match
      end
      tokens
    end

    def comparison
      left = additive
      return left unless COMPARISONS.key?(peek)

      operator = COMPARISONS.fetch(advance)
      left.public_send(operator, additive)
    end

    def additive
      value = term
      value = advance == "+" ? value + term : value - term while %w[+ -].include?(peek)
      value
    end

    def term
      value = unary
      value = advance == "*" ? value * unary : value / unary while %w[* /].include?(peek)
      value
    end

    def unary
      return -unary if peek == "-" && advance

      power
    end

    def power
      base = primary
      return base unless peek == "^"

      advance
      base**unary
    end

    def primary
      token = advance
      case token
      when Float then token
      when "(" then comparison.tap { expect(")") }
      when "round" then round_call
      when /\A[A-Za-z_]/
        raise Error, "unknown identifier #{token}" unless @variables.key?(token)

        Float(@variables.fetch(token))
      else
        raise Error, "unexpected token #{token.inspect}"
      end
    end

    def round_call
      expect("(")
      value = comparison
      expect(",")
      digits = comparison
      expect(")")
      value.round(digits.to_i)
    end

    def expect(token)
      raise Error, "expected #{token.inspect}, got #{peek.inspect}" unless advance == token
    end

    def peek = @tokens[@position]

    def advance
      token = @tokens[@position]
      @position += 1
      token
    end
  end
end
