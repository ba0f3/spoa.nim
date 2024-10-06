import std/[streams, unittest]
import spoa/utils

#[
Test cases borrowed from https://github.com/negasus/haproxy-spoe-go/blob/25800f6e0406cd070088ec919f94577549407813/varint/varint_test.go
]#

proc testEncode(n: uint64, expectResult: string) =
  var buf: array[10, uint8]
  assert encodeVarint(buf, n) == expectResult.len
  for i in 0..<expectResult.len:
    assert buf[i] == cast[uint8](expectResult[i])

proc testDecode(data: string, expectValue: uint64, expectBytesCount: int) =
  var
    value: uint64
    ret = newStringStream(data).decodeVarint(value)
  assert ret == expectBytesCount
  assert value == expectValue

suite "varint tests":
  test "encode varint":
    var buf: array[10, uint8]

    testEncode(239, "\xEF")
    testEncode(240, "\xF0\x00")
    testEncode(241, "\xF1\x00")
    testEncode(256, "\xF0\x01")
    testEncode(2287, "\xFF\x7F")
    testEncode(2289, "\xF1\x80\x00")

  test "decode varint":
    testDecode("\xF0", 0, -1)
    testDecode("\xEF", 239, 1)
    testDecode("\xF1\x00", 241, 2)
    testDecode("\xF0\x01", 256, 2)
    testDecode("\xFF\x7F", 2287, 2)
    testDecode("\xF1\x80\x00", 2289, 3)



