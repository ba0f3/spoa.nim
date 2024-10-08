import std/unittest
import pkg/chronos
import spoa/utils

#[
Test cases borrowed from https://github.com/negasus/haproxy-spoe-go/blob/25800f6e0406cd070088ec919f94577549407813/varint/varint_test.go
]#

proc testEncode(n: uint64, expectResult: string) =
  var buf: array[10, uint8]
  assert encodeVarint(buf, n) == expectResult.len
  for i in 0..<expectResult.len:
    assert buf[i] == cast[uint8](expectResult[i])

proc testDecode(data: string, expectValue: uint64, expectBytesCount: int) {.async.} =
  proc serveClient(server: StreamServer, transp: StreamTransport) {.async: (raises: []).} =
    try:
      var wstream = newAsyncStreamWriter(transp)
      await wstream.write(data)
      await wstream.finish()
      await wstream.closeWait()
      await transp.closeWait()
      server.stop()
      server.close()
    except CatchableError as exc:
      raiseAssert exc.msg

  var
    value: uint64
    bytesRead: uint64
    ret: int

  var server = createStreamServer(initTAddress("127.0.0.1:0"), serveClient, {ReuseAddr})
  server.start()
  var transp = await connect(server.localAddress())
  var rstream = newAsyncStreamReader(transp)
  ret = await rstream.decodeVarint(addr value, addr bytesRead)
  await rstream.closeWait()
  await transp.closeWait()
  await server.join()

  assert ret == expectBytesCount
  assert value == expectValue

suite "varint tests":
  test "encode varint":

    #var buf: array[10, uint8]
    #discard encodeVarint(buf, 16380)
    #echo buf

    testEncode(239, "\xEF")
    testEncode(240, "\xF0\x00")
    testEncode(241, "\xF1\x00")
    testEncode(256, "\xF0\x01")
    testEncode(2287, "\xFF\x7F")
    testEncode(2289, "\xF1\x80\x00")

  test "decode varint":
    waitFor testDecode("\xF0", 0, -1)
    waitFor testDecode("\xEF", 239, 1)
    waitFor testDecode("\xF1\x00", 241, 2)
    waitFor testDecode("\xF0\x01", 256, 2)
    waitFor testDecode("\xFF\x7F", 2287, 2)
    waitFor testDecode("\xF1\x80\x00", 2289, 3)



