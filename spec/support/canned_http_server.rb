require "socket"

# LLM のアダプタの spec が使う、開発機の中（127.0.0.1）だけに立つサーバー。1 回の要求を受けて、決まった応答を返す。
# 外は呼ばない。受けた要求（最初の行、ヘッダ、本文）を requests にためる。ブロックに渡すのは、サーバーの元の URL（末尾に / なし）
module CannedHttpServer
  def serve(status: 200, body: "{}", delay: 0, path: "")
    server = TCPServer.new("127.0.0.1", 0)
    requests = []
    thread = Thread.new do
      client = server.accept
      head = +""
      head << client.readpartial(4096) until head.include?("\r\n\r\n")
      header, rest = head.split("\r\n\r\n", 2)
      length = header[/content-length: (\d+)/i, 1].to_i
      rest << client.readpartial(4096) while rest.bytesize < length
      requests << { line: header.lines.first.strip, header: header, body: JSON.parse(rest.force_encoding("UTF-8")) }
      sleep delay
      client.write("HTTP/1.1 #{status} X\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
      client.close
    rescue IOError, SystemCallError
      nil
    end
    yield "http://127.0.0.1:#{server.addr[1]}#{path}", requests
  ensure
    thread&.join(2)
    server&.close
  end

  # だれも聞いていない、開発機の中のポート
  def closed_port
    TCPServer.open("127.0.0.1", 0) { |server| server.addr[1] }
  end
end
