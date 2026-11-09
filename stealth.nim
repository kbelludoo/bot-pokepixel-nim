import std/[asyncdispatch, random]

randomize()

proc applyJitter*(baseMs: int, pct: float = 0.20): int =
  let delta = (baseMs.float * pct).int
  if delta <= 0: return baseMs
  let offset = rand(-delta .. delta)
  result = max(50, baseMs + offset)

proc pacingDelay*(minMs: int = 300, maxMs: int = 600): Future[void] {.async.} =
  let delayMs = rand(minMs .. maxMs)
  await sleepAsync(delayMs)
