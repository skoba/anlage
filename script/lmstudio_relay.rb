#!/usr/bin/env ruby
# 開発機の道具: WSL の中から、Windows 側の LM Studio（127.0.0.1:1234 だけで待ち受け）への中継。
# docs/reports/s4-lmstudio-network-check.md 5 節。R-20261128-10。skoba/anlage#286。アプリのコードではない。
#
# WSL のネットワークが NAT のとき、WSL の中の 127.0.0.1 は、Windows 側の 127.0.0.1 に届かない。
# WSL からは Windows のプログラムを起こせるので、WSL の中の 127.0.0.1 で要求を受け、本文を Windows 側の curl.exe に
# 標準入力で渡して、状態の番号と本文を返す。WSL の設定も、LM Studio の待ち受けも、変えない。LAN には出ない。
#
# 使い方（WSL の中で）:
#   ruby script/lmstudio_relay.rb            # 127.0.0.1:11234 で待ち受け、Windows 側の http://127.0.0.1:1234 に渡す
#   PORT=11235 ruby script/lmstudio_relay.rb
#   ANLAGE_LLM=lmstudio ANLAGE_LLM_BASE_URL=http://127.0.0.1:11234/v1 ANLAGE_LLM_MODEL=<モデル> …
#
# 限界: 1 度に 1 つの要求だけ。まとめて受け取る応答だけ（stream は使わない）。Authorization のヘッダは渡さない
# （コマンドの引数にトークンを出さないため。LM Studio が API のトークンを求める設定のときは、使えない）。
require "json"
require "open3"
require "socket"
require "uri"

class LmstudioRelay
  BIND = "127.0.0.1".freeze
  DEFAULT_PORT = 11_234
  DEFAULT_TARGET = "http://127.0.0.1:1234".freeze
  DEFAULT_COMMAND = [ "/mnt/c/Windows/System32/curl.exe" ].freeze
  LOCAL_HOSTS = %w[127.0.0.1 localhost].freeze
  # curl の -w で、本文のあとに足させる行。状態の番号を、本文と分けて読む
  STATUS_MARK = "LMSTUDIO_RELAY_STATUS:".freeze
  # 手元のモデルの 1 回の応答を待つ上限（秒）。アダプタの待ち時間（300 秒）より長くしておく
  MAX_TIME = 600

  attr_reader :port

  def initialize(port: DEFAULT_PORT, target: DEFAULT_TARGET, command: DEFAULT_COMMAND)
    uri = URI(target)
    unless uri.scheme == "http" && LOCAL_HOSTS.include?(uri.host)
      raise ArgumentError, "中継の先は、同じ機械の中（127.0.0.1・localhost）だけです: #{target}"
    end

    @target = target.chomp("/")
    @command = command
    @server = TCPServer.new(BIND, port)
    @port = @server.addr[1]
  end

  def run
    loop do
      client = @server.accept
      begin
        handle(client)
      rescue IOError, SystemCallError
        nil
      ensure
        client.close unless client.closed?
      end
    end
  rescue IOError, SystemCallError
    nil # stop で閉じた
  end

  def stop = @server.close

  private

  def handle(client)
    head = +""
    head << client.readpartial(4096) until head.include?("\r\n\r\n")
    header, body = head.split("\r\n\r\n", 2)
    body = body.to_s
    length = header[/^content-length: (\d+)/i, 1].to_i
    body << client.readpartial(4096) while body.bytesize < length
    method, path, = header.lines.first.split

    status, reply = path.start_with?("/") ? forward(method, path, body) : failure(400, "パスが読めません")
    client.write("HTTP/1.1 #{status} X\r\nContent-Type: application/json\r\nContent-Length: #{reply.bytesize}\r\nConnection: close\r\n\r\n#{reply}")
  end

  # [状態の番号, 本文]
  def forward(method, path, body)
    args = [ "-sS", "--max-time", MAX_TIME.to_s, "-X", method, "-o", "-", "-w", "\n#{STATUS_MARK}%{http_code}" ]
    args += [ "-H", "Content-Type: application/json", "--data-binary", "@-" ] unless method == "GET"
    out, _err, result = Open3.capture3(*@command, *args, "#{@target}#{path}", stdin_data: body, binmode: true)
    return failure(502, "curl が失敗しました（終了の番号 #{result.exitstatus}）。LM Studio のサーバーが立っているかを確かめてください") unless result.success?

    reply, mark, status = out.rpartition("\n#{STATUS_MARK}")
    mark.empty? ? failure(502, "curl の出力が読めません") : [ status.to_i, reply ]
  end

  def failure(status, message) = [ status, JSON.generate(error: message) ]
end

if $PROGRAM_NAME == __FILE__
  relay = LmstudioRelay.new(port: Integer(ENV.fetch("PORT", LmstudioRelay::DEFAULT_PORT)))
  warn "中継: http://#{LmstudioRelay::BIND}:#{relay.port} → Windows 側の #{LmstudioRelay::DEFAULT_TARGET}（止めるのは Ctrl-C）"
  trap("INT") { exit }
  relay.run
end
