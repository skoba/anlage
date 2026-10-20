import { Controller } from "@hotwired/stimulus"

// 帳票の振る舞い（skoba/anlage#47 変更 4）。config/form_behaviors.yml の rules を input のたびに評価し、
// target 欄へ即時に書く。権威はサーバ（Opt::FormBehaviors が保存時に再計算する）。
//   - editable: false の target は readonly、inputs が揃えば常に書く
//   - editable: true の target は提案。人間が書き換えたら hidden の <target>__edited を立て、以後は書かない
// 式の評価器は app/lib/opt/formula.rb の写し（同じ文法・同じ閉じたトークン集合。eval しない）。
export default class extends Controller {
  static values = { rules: Array }

  connect() {
    this.edited = new Set()
    for (const rule of this.rulesValue) {
      if (!rule.editable) this.field(rule.target)?.setAttribute("readonly", "readonly")
    }
  }

  recalculate(event) {
    const editedTarget = this.rulesValue.find((rule) => rule.editable && event.target === this.field(rule.target))
    if (editedTarget) {
      this.markEdited(editedTarget.target)
      return
    }

    for (const rule of this.rulesValue) {
      const target = this.field(rule.target)
      if (!target || (rule.editable && this.edited.has(rule.target))) continue

      const inputs = this.numericInputs(rule)
      if (inputs) target.value = this.evaluate(rule, inputs)
    }
  }

  markEdited(name) {
    this.edited.add(name)
    const flagName = `values[${name}__edited]`
    if (this.element.querySelector(`input[name="${flagName}"]`)) return

    const flag = document.createElement("input")
    flag.type = "hidden"
    flag.name = flagName
    flag.value = "1"
    this.element.appendChild(flag)
  }

  numericInputs(rule) {
    const inputs = {}
    for (const name of rule.inputs) {
      const raw = this.field(name)?.value?.trim()
      const number = raw === "" || raw === undefined ? NaN : Number(raw)
      if (Number.isNaN(number)) return null
      inputs[name] = number
    }
    return inputs
  }

  evaluate(rule, inputs) {
    if (rule.cases) {
      const matched = rule.cases.find((c) => "else" in c || evaluateFormula(c.when, inputs))
      return "else" in matched ? matched.else : matched.value
    }
    const value = evaluateFormula(rule.formula, inputs)
    return String(rule.round == null ? value : roundTo(value, rule.round))
  }

  field(name) {
    return this.element.querySelector(`#field_${name}`)
  }
}

// Ruby の Float#round(n) と同じく 0 から遠い側へ丸める（正の値では四捨五入）
function roundTo(value, digits) {
  const factor = 10 ** digits
  return Math.sign(value) * Math.round(Math.abs(value) * factor) / factor
}

const TOKEN = /^\s*(?:(\d+(?:\.\d+)?)|([A-Za-z_][A-Za-z0-9_]*)|(<=|>=|==|!=|[-+*/^()<>,]))/
const COMPARISONS = {
  "<": (a, b) => a < b, "<=": (a, b) => a <= b, ">": (a, b) => a > b,
  ">=": (a, b) => a >= b, "==": (a, b) => a === b, "!=": (a, b) => a !== b
}

function tokenize(expression) {
  const tokens = []
  let rest = String(expression)
  while (rest.trim() !== "") {
    const match = TOKEN.exec(rest)
    if (!match) throw new Error(`unexpected character in ${rest.trim()}`)
    tokens.push(match[1] !== undefined ? Number(match[1]) : (match[2] ?? match[3]))
    rest = rest.slice(match[0].length)
  }
  return tokens
}

// comparison := additive (cmp additive)? / additive := term ((+|-) term)* / term := unary ((*|/) unary)*
// unary := "-" unary | power / power := primary ("^" unary)? / primary := NUMBER | IDENT | round(...) | (...)
export function evaluateFormula(expression, variables) {
  const tokens = tokenize(expression)
  let position = 0
  const peek = () => tokens[position]
  const advance = () => tokens[position++]
  const expect = (token) => {
    if (advance() !== token) throw new Error(`expected ${token}`)
  }

  const comparison = () => {
    const left = additive()
    if (!(peek() in COMPARISONS)) return left
    const operator = COMPARISONS[advance()]
    return operator(left, additive())
  }
  const additive = () => {
    let value = term()
    while (peek() === "+" || peek() === "-") value = advance() === "+" ? value + term() : value - term()
    return value
  }
  const term = () => {
    let value = unary()
    while (peek() === "*" || peek() === "/") value = advance() === "*" ? value * unary() : value / unary()
    return value
  }
  const unary = () => {
    if (peek() === "-") {
      advance()
      return -unary()
    }
    return power()
  }
  const power = () => {
    const base = primary()
    if (peek() !== "^") return base
    advance()
    return base ** unary()
  }
  const primary = () => {
    const token = advance()
    if (typeof token === "number") return token
    if (token === "(") {
      const value = comparison()
      expect(")")
      return value
    }
    if (token === "round") {
      expect("(")
      const value = comparison()
      expect(",")
      const digits = comparison()
      expect(")")
      return roundTo(value, digits)
    }
    if (typeof token === "string" && /^[A-Za-z_]/.test(token)) {
      if (!(token in variables)) throw new Error(`unknown identifier ${token}`)
      return variables[token]
    }
    throw new Error(`unexpected token ${token}`)
  }

  const value = comparison()
  if (position < tokens.length) throw new Error(`unexpected token ${peek()}`)
  return value
}
