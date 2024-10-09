import std/posix
import chronos
from ./request import SpoeRequest

const
  MAX_FRAME_SIZE* = 16380
  SPOP_VERSION* = "2.0"
  SPOP_CAPABILITIES* = "pipelining"
  SPOE_FRAME_FLAG_FIN* = 0x00000001
  SPOE_FRAME_FLAG_ABORT* = 0x00000002

type
  SpoeFrameError* = enum
    ERROR_NONE = 0
    ERROR_IO
    ERROR_TOUT
    ERROR_TOO_BIG
    ERROR_INVALID
    ERROR_NO_VSN
    ERROR_NO_FRAME_SIZE
    ERROR_NO_CAP
    ERROR_BAD_VSN
    ERROR_BAD_FRAME_SIZE
    ERROR_FRAG_NOT_SUPPORTED
    ERROR_INTERLACED_FRAMES
    ERROR_FRAMEID_NOTFOUND
    ERROR_RES
    ERROR_UNKNOWN = 99

  SpoeHandler* = proc(req: SpoeRequest) {.gcsafe.}

  SpoeAgent* = ref object
    maxConn*: int
    address*: string
    maxFrameSize*: uint32
    pipelining*: bool
    done*: Future[void]
    handler*: SpoeHandler
    nextClientId*: int
