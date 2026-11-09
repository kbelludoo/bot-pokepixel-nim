import std/[asyncdispatch, asynchttpserver, json, strformat, times]
import types, bot

type
  WebServer* = ref object
    bots*: seq[BotInstance]
    port*: int
    startTime*: float

proc newWebServer*(bots: seq[BotInstance], port: int): WebServer =
  new(result)
  result.bots = bots
  result.port = port
  result.startTime = epochTime()

proc start*(self: WebServer) {.async.} =
  var server = newAsyncHttpServer()
  let port = self.port
  let bots = self.bots
  let startT = self.startTime

  proc cb(req: Request) {.async.} =
    if req.url.path == "/api/status":
      let elapsed = (epochTime() - startT).int64
      let hours = elapsed div 3600
      let mins = (elapsed mod 3600) div 60
      let secs = elapsed mod 60
      let uptimeStr = fmt"{hours}h{mins}m{secs}s"

      var accArray = newJArray()
      for b in bots:
        let dto = b.toDto()
        var logsArr = newJArray()
        for l in dto.logs:
          logsArr.add(%l)

        accArray.add(%*{
          "id": dto.id,
          "name": dto.name,
          "level": dto.level,
          "vocation": dto.vocation,
          "hp": dto.hp,
          "maxHp": dto.maxHp,
          "mana": dto.mana,
          "maxMana": dto.maxMana,
          "gold": dto.gold,
          "kills": dto.kills,
          "expPerHour": dto.expPerHour,
          "status": dto.status,
          "currentArea": dto.currentArea,
          "durationSec": dto.durationSec,
          "logs": logsArr,
          "updatedAt": dto.updatedAt,
          "extra": {
            "bestiaryFocus": dto.extra.bestiaryFocus,
            "circuitState": dto.extra.circuitState,
            "cooldownSec": dto.extra.cooldownSec,
            "leaderLevel": dto.extra.leaderLevel,
            "leaderName": dto.extra.leaderName
          }
        })

      let payload = %*{
        "accounts": accArray,
        "goroutines": 0,
        "ramAllocMB": 1.50,
        "ramSysMB": 3.80,
        "uptime": uptimeStr
      }

      let headers = newHttpHeaders([
        ("Content-Type", "application/json"),
        ("Access-Control-Allow-Origin", "*")
      ])
      await req.respond(Http200, $payload, headers)
    else:
      let html = "<h1>PokePixel Nim Multi-Bot Engine Online</h1><p>Visite /api/status para telemetria.</p>"
      await req.respond(Http200, html, newHttpHeaders([("Content-Type", "text/html; charset=utf-8")]))

  server.listen(Port(port))
  echo "[Dashboard] Servidor HTTP de telemetria ativo na porta ", port
  while true:
    if server.shouldAcceptRequest():
      await server.acceptRequest(cb)
    else:
      await sleepAsync(10)
