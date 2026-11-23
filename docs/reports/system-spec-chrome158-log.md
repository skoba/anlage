# 手元の system spec が Chrome 158 で落ちる件の切り分け

裁定 ID: R-20261123-3。Issue: `skoba/anlage#73`。このログは切り分けと直し方の案まで。直すのはゲート承認のあと。

## R1 切り分け（2026-11-24、main `25ade57`、Ruby 4.0.10）

### 結論

Capybara 3.40.0 が例の後始末で送る CDP 呼び出し `Storage.clearDataForOrigin`（`origin: '*'`）を、
Chrome 158 が `* is not a valid URL` で拒否する。開発機の Chromium は 11/23 の snap 自動更新で
158 になった。CI のランナーは Chrome 157 なので通っている。ランナーのイメージが 158 に
上がれば、CI でも同じ 14 件が落ちる見込み（推論。根拠は下の版の表と呼び出しの実測）。

### 版の差

| | 開発機 | CI（run 45195483125） |
|---|---|---|
| ブラウザ | Chromium 158.0.8127.36（snap rev 3604） | Google Chrome 157.0.8103.78 |
| chromedriver | 158.0.8127.36（snap 同梱、`spec/rails_helper.rb:17-18` が指定） | 157.0.8103.78 |
| selenium-webdriver | 4.53.0 | 4.53.0 |
| capybara | 3.40.0 | 3.40.0 |
| 結果 | 236 例 14 失敗 | 236 例 0 失敗 |

- 開発機: `snap list chromium`、`/snap/bin/chromium.chromedriver --version`。
  `snap changes` に「Auto-refresh snap "chromium"」（2026-11-23 15:43〜15:58 JST）。
  1 つ前の rev 3559 は 155.0.8059.79（`/snap/chromium/3559/meta/snap.yaml`）
- CI: ログにブラウザの版は出ない。ログのイメージ版（ubuntu-26.04、20261116.202.1）を、
  actions/runner-images の `images/ubuntu/Ubuntu2604-Readme.md`（同じイメージ版）で引いた値
- gem の版は両方とも `Gemfile.lock`

### エラーを出している呼び出し

capybara 3.40.0 `lib/capybara/selenium/driver_specializations/chrome_driver.rb:54`
（`Capybara::Selenium::Driver::ChromeDriver#reset!` の末尾）:

```ruby
execute_cdp('Storage.clearDataForOrigin', origin: '*', storageTypes: storage_types_to_clear)
```

呼び出しの経路は 2 本あり、どちらも例の本体が終わったあとに走る。

- `capybara/rspec.rb:20`（`Capybara.reset_sessions!`）
- actionpack `action_dispatch/system_testing/test_helpers/setup_and_teardown.rb:16`（`after_teardown`）

anlage の設定に、この呼び出しを変える箇所は無い。`spec/rails_helper.rb:12` が
`:selenium_chrome_headless`（Capybara 同梱の登録）を選んでいるだけ。
`reset!` の 54 行目は、ドライバのオプションにかかわらず必ず実行される。

Chrome 158 に直接送った結果（素の selenium-webdriver、`about:blank`）:

| CDP 呼び出し | 結果 |
|---|---|
| `Storage.clearDataForOrigin`、`origin: '*'` | 失敗（`invalid argument: * is not a valid URL`） |
| `Storage.clearDataForOrigin`、`origin: 'http://127.0.0.1'` | 成功 |
| `Network.clearBrowserCookies` | 成功 |
| `Storage.clearCookies` | 成功 |

### 落ちる 14 件の内訳

- 13 件は `js: true` の例（9 ファイル）。例の本体ではなく後始末で落ちる
- 1 件（`spec/system/forms_spec.rb:10`、rack_test）は巻き添え。単独では通る（1 例 0 失敗）。
  `js: true` の例のあとに走ると、残っているブラウザのセッションも `reset_sessions!` が
  後始末するので落ちる（`demo_lab_result_spec.rb` と並べて 2 例 2 失敗）

### 1 件で再現する最小の手順

```
bundle exec rspec spec/system/demo_pathcard_search_spec.rb:36
```

Chrome 158 と chromedriver 158 の組で、1 例 1 失敗になる。

### 上流の状況

- capybara の最新リリースは 3.40.0（`gem search -r capybara`）。修正を含むリリースは無い
- 上流 master の同じ行も `origin: '*'` のまま
- teamcapybara/capybara#2865（open、同じエラーの報告）、修正 PR #2868（open、未マージ）
- selenium-webdriver の最新は 4.54.0。拒否しているのは Chrome 側なので、
  selenium-webdriver の更新では直らない見込み（推論。4.54.0 では試していない）

## R2 直し方の案（影響の小さい順）

| 案 | 中身 | 変わるもの | 開発機 | CI が 158 に上がったあと |
|---|---|---|---|---|
| A（推奨） | spec の設定で、`reset!` の当該呼び出しを置き換える。`origin: '*'` が拒否されたときだけ、cookie の全消去（`Storage.clearCookies`）と、アプリの origin に対する `Storage.clearDataForOrigin` に切り替える | `spec/` のみ。gem・開発機・CI は変えない | 直る | 通る |
| B | capybara を上流の修正 PR のブランチに向ける | `Gemfile`・`Gemfile.lock`（未リリースのコードへの依存） | 直る見込み | 通る見込み |
| C | 開発機の Chromium を 157 以前に戻して固定する（`snap revert`＋`snap refresh --hold`）、または Chrome for Testing 157 を別に入れて `SE_CHROMEDRIVER` で指す | 開発機の設定 | 直る | **落ちる**（CI は直らない） |
| D | ドライバを Selenium 以外（cuprite 等）に替える | gem の追加、`js: true` の全 spec の再検証 | 未実測 | 未実測 |

- **A を勧める理由**: リポジトリの中で閉じ、157 と 158 の両方で通る形にできる。CI が 158 に
  上がったときの赤も先に防げる。上流の修正がリリースされたら消す（消す条件を
  コメントと Issue に書く）
- **A の注意**: Capybara の内部メソッドに手を入れる。capybara の版が上がるたびに
  要否を確かめる必要がある。後始末で消える範囲が「全 origin」から「cookie 全部と
  アプリの origin のストレージ」に狭まる（system spec が触る origin はアプリだけなので、
  実害は無い見込み。推論）
- **A の検証**: Red は今の 14 件（開発機）。Green は開発機の全 suite と CI の 4 ジョブ
- **B を勧めない理由**: 未マージの PR に依存し、依存 gem の変更になる
- **C を勧めない理由**: 開発機の設定の変更になり、CI の側は直らない
- **A〜D のどれも、この裁定では実施していない**

### 裁定を求める点

1. 案 A で進めてよいか
2. 案 A の置き場所。`spec/rails_helper.rb` に直接書くか、`spec/support/` を新設して分けるか
   （今は `spec/support/` が無い）
3. CI にブラウザの版を出す 1 行（`google-chrome --version`）を足すか。
   次に版の差で落ちたとき、ログだけで切り分けられる
