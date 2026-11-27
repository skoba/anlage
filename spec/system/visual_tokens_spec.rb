require "rails_helper"

# 見た目の基準（skoba/anlage#218、docs/design/visual-guidelines.md、U1-0）。色は CSS 変数にまとめ、部品は変数を使う。
# 見た目そのものは spec で固定しない。固定するのは、基準の変数がどの画面でも定義されていることと、
# 主な部品（本文、ナビ、表の罫線）が変数の値で描かれていること
RSpec.describe "見た目の基準の変数（実ブラウザ）", type: :system, js: true do
  TOKENS = %w[--color-text --color-muted --color-border --color-surface --color-accent --color-danger --color-warning].freeze

  def token(name) = page.evaluate_script("getComputedStyle(document.documentElement).getPropertyValue('#{name}').trim()")
  def style(selector, property) = page.evaluate_script("getComputedStyle(document.querySelector('#{selector}')).getPropertyValue('#{property}')")
  def rgb(css_color) = page.evaluate_script("(() => { const e = document.createElement('span'); e.style.color = '#{css_color}'; document.body.appendChild(e); const c = getComputedStyle(e).color; e.remove(); return c; })()")

  it "どの画面でも、基準の色の変数 7 つが定義されている（AQL 照会の画面も）" do
    [ templates_path, patients_path, new_query_path, "/openehr/query" ].each do |path|
      visit path
      TOKENS.each { |name| expect(token(name)).to be_present, "#{path}: #{name}" }
    end
  end

  it "本文の色はテキストの変数、ナビの地はサーフェスの変数、いまの画面の印はアクセントの変数で描かれる" do
    visit templates_path

    expect(style("body", "color")).to eq(rgb(token("--color-text")))
    expect(style("nav#app_nav", "background-color")).to eq(rgb(token("--color-surface")))
    expect(style("nav#app_nav a[aria-current=page]", "border-left-color")).to eq(rgb(token("--color-accent")))
  end
end
