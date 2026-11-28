# WSL から Windows 側の LM Studio に届くか: 切り替えの前の確認

Refs R-20261128-5（2 節）、`skoba/anlage#268`。2026-11-28。読むだけで測った。設定は、どれも変えていない。

## 1. 先に結論

- いまの WSL は **NAT**。WSL の中から、Windows 側の `127.0.0.1:1234` には届かない
- Windows と WSL の版は、mirrored の条件（Windows 11 22H2 以上）を満たす。`.wslconfig` は、まだ無い
- mirrored にすると、WSL の中の `127.0.0.1:1234` が、Windows 側の LM Studio に届く（Microsoft の文書）。反映には WSL の再起動が要り、
  4 つのレーンと Docker のコンテナが止まる
- mirrored で確かめ直すものは、Docker の公開ポート（`anlage-ollama` の `127.0.0.1:11434`）と、Windows と WSL でのポートの取り合い。
  いまの時点で、取り合いになるポートは見つからなかった
- 切り替えずに届く道は、1 つある（Windows 側の `curl.exe` を WSL から起こして中継する。5 節）。試しの 3 問には足りる見込みだが、まだ試していない
- **切り替えとは別の問題が 1 つ**: Windows 側の空きメモリが、測ったとき **0.2 GB**（全体 31.7 GB）だった。12B のモデルは 7 GB ほどを使う。
  試しの前に、Windows 側のメモリを空ける必要がある（6 節）

## 2. いまの形（実測）

| 項目 | 値 | 測り方 |
|---|---|---|
| WSL のネットワークの形 | `nat` | `wslinfo --networking-mode` |
| WSL の版 | 3.0.5.0 | `wsl.exe --version`、`wslinfo --wsl-version` |
| カーネル | 6.18.58.1-microsoft-standard-WSL2 | `uname -r` |
| Windows の版 | 10.0.26300.10075 | `cmd.exe /c ver` |
| `.wslconfig` | 無い（`C:\Users\<利用者>\.wslconfig`） | `ls` |
| `/etc/wsl.conf` | `systemd=true` と、既定の利用者だけ | `cat` |
| WSL の中のアドレス | `eth0` 172.31.118.233/20、既定の経路は 172.31.112.1（Windows 側） | `ip addr`、`ip route` |
| 名前の解決 | 10.255.255.254（WSL が作った `resolv.conf`） | `cat /etc/resolv.conf` |
| Hyper-V のファイアウォール（WSL の VM） | 有効。外から入る通信は Block、出る通信は Allow、LoopbackEnabled は True | `Get-NetFirewallHyperVVMSetting` |
| Docker | WSL の中のエンジン（29.9.1。Docker Desktop ではない） | `docker info` |
| コンテナ | `anlage-ollama`（止まっている。公開ポートは `127.0.0.1:11434`）、ほか 1 つ（止まっている） | `docker ps -a`、`docker inspect` |
| WSL の中で待ち受けているポート | 631（CUPS。`0.0.0.0` と `[::]`）、53（名前の解決）、ほかは `127.0.0.1` の、その場かぎりのポート（エディタとセッション） | `ss -ltnp` |
| Windows 側で待ち受けているポート（1234、3000、3001、5432、6379、8080、11434、631 のうち） | 631 だけ（`127.0.0.1` と `::1`） | `Get-NetTCPConnection -State Listen` |
| LM Studio | **動いていない**（プロセスが無い。1234 で待ち受けていない） | `tasklist.exe`、`netstat -ano` |
| WSL から `127.0.0.1:1234` | つながらない（すぐ拒否） | `curl` |
| WSL から `172.31.112.1:1234`（Windows 側のアドレス） | 3 秒で時間切れ | `curl` |

- 届かない、の実測は、LM Studio が動いていないときのもの。動いていても届かない、とは、この実測だけでは言えない。
  Microsoft の文書は、NAT では Windows 側のアドレスを使い、アプリを `127.0.0.1` ではなく `0.0.0.0` で待ち受けさせる必要がありうる、と書いている（3 節）
- WSL の版 3.0.5.0 は、Microsoft の文書に出てこない（文書に出る版は 2.x まで）。3.x で何かが変わっているかは、文書からは分からない

## 3. Microsoft の文書で確かめたこと（2026-11-28 に読んだ）

読んだページ: `learn.microsoft.com/en-us/windows/wsl/networking`、`…/wsl/wsl-config`、`…/wsl/troubleshooting`（最後のページは、後ろの 3 割ほどが要約でしか読めていない）。

- **NAT**: Linux の側から Windows のアプリに届くには、Windows 側のアドレス（既定の経路のアドレス）を使う。アプリを `0.0.0.0` で待ち受けさせる必要がありうる
- **mirrored の設定**: `.wslconfig` の `[wsl2]` に `networkingMode=mirrored`。Windows 11 22H2 以上
- **mirrored でできること**: Linux の中から、`127.0.0.1` で Windows 側のサーバーにつながる。**IPv6 の `::1` は使えない**
- **反映**: 動いているディストリビューションが全部止まってから（8 秒ほど）。`wsl --shutdown` が早いが、全部のディストリビューションが止まる
- **`localhostForwarding`**（Windows から WSL の中へ `localhost` で届く設定）は、mirrored では無視される。mirrored では、どちら向きも `127.0.0.1` で届く
- **Docker**: 「Docker Desktop の、公開ポートを持つコンテナは、作るのに失敗する」。回避は、`--network host` か、`.wslconfig` の `ignoredPorts`。
  **WSL の中の Docker エンジン（この開発機の形）については、書いていない**
- **ポート**: `ignoredPorts` は、Windows 側で使われているポートでも、Linux のアプリが待ち受けられるようにする設定。
  つまり、既定では、Windows 側で使っているポートを、Linux の側で待ち受けられないことがある
- **Windows が受けた通信のうち、Linux に回らないポート**: UDP 68、TCP 135・1900・2869・5004・3702・5357・5358
- **Hyper-V のファイアウォール**: Windows 11 22H2 以上と WSL 2.0.9 以上で、既定で有効。外から WSL の中に入る通信を通すには、規則を足す
- **mirrored で動かないと確かめられている VPN**: Bitdefender、OpenVPN、McAfee Safe Connect（版つきで載っている）
- troubleshooting のページは、mirrored を「experimental」と書いている。設定のページは、`[wsl2]` の正式な設定として載せている（食い違い）

## 4. mirrored にしたときに変わりうるもの

実測と文書から言えることと、推論を分ける。

| もの | どうなるか | 根拠 |
|---|---|---|
| WSL の中から LM Studio（`127.0.0.1:1234`） | 届く | 文書 |
| `anlage-ollama`（`-p 127.0.0.1:11434:11434`） | **切り替えのあとに確かめる**。文書の失敗の記述は Docker Desktop のもので、WSL の中のエンジンについては書いていない。失敗したら `--network host` で立て直す（そのときは、Ollama の待ち受けを `127.0.0.1` に限る指定が要る） | 文書に無い。未実測 |
| Windows と WSL のポートの取り合い | いま、Windows 側が待ち受けているのは 631 だけ（調べた 8 つのうち）。WSL の CUPS も 631。**CUPS の待ち受けが失敗するかもしれない**（開発には使っていない）。LM Studio が 1234 を取ったあとは、WSL の中で 1234 を使えない | 実測と文書 |
| Rails のサーバー（3000）、Docker で立てたアプリ（8080） | WSL の中で待ち受けたものに、Windows のブラウザから `localhost` で届くのは、いまと同じ | 文書 |
| 実ブラウザの spec（Capybara と Chromium） | 変わらない見込み。どちらも WSL の中で、`127.0.0.1` の、その場かぎりのポートを使う。Windows 側が同じポートを使っていると、待ち受けに失敗しうるが、ポートは毎回変わる | 推論。未実測 |
| `::1`（IPv6 の localhost） | WSL の中から Windows 側へは、使えない。アダプタの接続先は `127.0.0.1` と書く | 文書 |
| WSL の中のアドレス（172.31.118.233） | 無くなり、Windows と同じアドレスになる。このアドレスを書いている設定は、引く側には無い | 推論 |
| LAN からの見え方 | mirrored では、LAN から WSL の中に直接届く形になる。ただし、Hyper-V のファイアウォールが、外から入る通信を止めている（実測: Block）。この設定を変えなければ、WSL の中の `0.0.0.0` の待ち受け（CUPS など）は、LAN に出ない | 文書と実測 |
| VPN | 上の 3 つを使っていれば、動かない | 文書。使っているかは未確認 |
| 止まるもの | `wsl --shutdown` で、4 つのレーンのセッション、エディタの接続、Docker のコンテナ。未コミットの作業は残るが、動いている最中の処理は切れる | 文書 |

切り替えの前に、人間に頼むこと（案）:

1. 4 つのレーンが、作業ツリーを空にしたことを確かめる（途中の作業は commit・push）
2. `C:\Users\<利用者>\.wslconfig` を作り、`[wsl2]` と `networkingMode=mirrored` の 2 行を書く
3. `wsl --shutdown` のあと、WSL を起こす
4. 起こしたあとに確かめる（引く側が測って、status に書く）: `wslinfo --networking-mode` が `mirrored`、
   `curl http://127.0.0.1:1234/v1/models`、`docker start anlage-ollama` と `curl http://127.0.0.1:11434/api/version`、
   `bundle exec rspec spec/system`（実ブラウザ）
5. 戻すとき: `.wslconfig` の行を消して、`wsl --shutdown`

## 5. 切り替えずに届く道

| 道 | 判定 | 理由 |
|---|---|---|
| LM Studio を LAN に開く（「Serve on Local Network」、`--bind 0.0.0.0`） | **採らない**（裁定） | 待ち受けが LAN に出る |
| LM Studio を、WSL 向けの仮想のアダプタのアドレス（いまは 172.31.112.1）だけで待ち受けさせる（`lms server start --bind <アドレス>`） | 勧めない | LAN には出ないが、接続先が `127.0.0.1` でなくなり、アプリの「同じ機械の中だけ」の検査を緩めることになる。アドレスは再起動で変わりうる。Windows のファイアウォールの規則も要りそう（未実測） |
| Windows 側で、ポートの転送を足す（`netsh interface portproxy`） | 勧めない | Windows の設定の変更（管理者）。文書にあるのは逆向き（外から WSL へ）の例だけ。上と同じ問題 |
| **WSL から、Windows 側の `curl.exe` を起こして中継する** | 試しには使えそう（**未実測**） | 設定を変えない。再起動が要らない。LAN に出ない。WSL からは Windows のプログラムを起こせる（この確認でも `powershell.exe` などを使った）。`curl.exe` は Windows 側の `127.0.0.1:1234` に届く |

中継の道の中身（やるなら）:

- WSL の中の `127.0.0.1` に、小さな中継を立てる。受けた要求の本文を、Windows 側の `curl.exe`（`C:\Windows\System32\curl.exe`。あることは確かめた）に
  標準入力で渡し、応答を返す。アプリのアダプタは、WSL の中の `127.0.0.1` につなぐので、「同じ機械の中だけ」の検査は変えない
- 中継は、アプリのコードに入れない（開発機だけの道具）。置き場所と作りは、採ると決まってから
- 1 回ごとに Windows のプログラムを起こす分、遅くなる（モデルの応答の時間に比べれば小さい見込み。未実測）
- LM Studio が動いていないので、届くことは、まだ確かめていない

統括と人間に決めてほしいこと: **mirrored に切り替えるか、まず中継で試しの 3 問を回すか**。引く側の推しは、
「試しは中継で回し、測定に使うと決まったら mirrored に切り替える」。理由は、切り替えが 4 つのレーンを止めるのに対して、
この開発機でモデルが使える速さで動くかが、まだ分かっていないため（6 節）。

## 6. 試しの前に見えたこと（Windows 側。実測）

| 項目 | 値 |
|---|---|
| Windows 側のメモリ | 全体 31.7 GB、**空き 0.2 GB**（測ったとき。WSL の VM、エディタ、ブラウザなどが使っている） |
| CPU | Intel Core i7-11390H（WSL から見えるのは 8 コア） |
| GPU | Intel Iris Xe（内蔵）だけ。NVIDIA の GPU は無い |
| LM Studio の実行系（入っているもの） | `llama.cpp-win-x86_64-avx2-2.83.0`、同じ版の `nvidia-cuda` と `vulkan` |
| Gemma 4 12B | `lmstudio-community/gemma-4-12B-it-QAT-GGUF/gemma-4-12B-it-QAT-Q4_0.gguf`、6,975,879,008 バイト。入っている |
| Gemma 4 26B A4B | `…/gemma-4-26B-A4B-it-QAT-GGUF/` に、ダウンロードの途中のファイル（9.8 GB まで）。**まだ入っていない** |

- **メモリが足りない見込み**。WSL の VM は、Windows のメモリを 15 GB まで使う。そこに 12B（7 GB ほど）を足すと、Windows 側のほかのアプリと取り合う。
  26B A4B（統括が読んだ表で 14.4 GB）は、WSL を動かしたままでは、入らない見込み（推論。32 − 15 − 14.4 = 2.6 GB しか残らない）
- GPU が内蔵だけなので、Windows 側でも、CPU で動かす形になりそう。WSL の中の Ollama（CPU 4 コアの上限）より速いかは、測らないと分からない
- モデルのファイルの sha256、ライセンス、LM Studio の版、読み込みの設定は、試しのときに記録する（裁定の 3 節）

## 7. LM Studio の側で確かめたこと（公式の文書。2026-11-28 に読んだ）

アダプタの計画（`docs/design/s4-nl-aql-plan.md` 15 節）に書く。ここには、つなぎ方にかかわるものだけ。

- サーバーの待ち受けは、既定で `127.0.0.1`（`lms server start` の `--bind` の説明）。ポートは「前に使ったもの」。文書の例は 1234
- 既定では、API のトークンを求めない。「Require Authentication」をオンにすると、`Authorization: Bearer <トークン>` が要る（LM Studio 0.4.0 以上）
- LAN に開く設定は「Serve on Local Network」。オンにしない
