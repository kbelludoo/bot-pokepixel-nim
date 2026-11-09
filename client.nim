import std/[asyncdispatch, httpclient, json, strutils, sysrand, random, times]
import checksums/sha2
import types

const
  DefaultApiBaseUrl = "https://pokepixel.nietore.com/api/v1"
  DefaultClientVersion = "2026.07.26-sync-guard-v1"
  DefaultUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

type
  GameClient* = ref object
    baseUrl*: string
    accessToken*: string
    signingKey*: string
    clientVersion*: string

proc toHexStr(s: openArray[byte]): string =
  result = ""
  for b in s:
    result.add(toHex(int(b), 2).toLowerAscii)

proc newUUID4*(): string =
  var bytes: array[16, byte]
  if not urandom(bytes):
    randomize()
    for i in 0 .. 15:
      bytes[i] = byte(rand(255))
  bytes[6] = (bytes[6] and 0x0F) or 0x40
  bytes[8] = (bytes[8] and 0x3F) or 0x80
  result = toHexStr(bytes[0..3]) & "-" &
           toHexStr(bytes[4..5]) & "-" &
           toHexStr(bytes[6..7]) & "-" &
           toHexStr(bytes[8..9]) & "-" &
           toHexStr(bytes[10..15])

proc sha256Hex(s: string): string =
  var hasher = initSha_256()
  hasher.update(s)
  result = $hasher.digest()

proc hmacSha256(key, data: string): string =
  var k = key
  if k.len > 64:
    var h = initSha_256()
    h.update(k)
    let d = h.digest()
    k = ""
    for b in d: k.add(b)
  if k.len < 64:
    k.add(repeat('\0', 64 - k.len))
  var oKeyPad = ""
  var iKeyPad = ""
  for i in 0 ..< 64:
    oKeyPad.add(chr(ord(k[i]) xor 0x5c))
    iKeyPad.add(chr(ord(k[i]) xor 0x36))
  var inner = initSha_256()
  inner.update(iKeyPad)
  inner.update(data)
  let innerDigest = inner.digest()
  var innerStr = ""
  for b in innerDigest: innerStr.add(b)
  var outer = initSha_256()
  outer.update(oKeyPad)
  outer.update(innerStr)
  result = $outer.digest()

proc newGameClient*(initialToken: string): GameClient =
  new(result)
  result.baseUrl = DefaultApiBaseUrl
  result.accessToken = initialToken
  result.signingKey = ""
  result.clientVersion = DefaultClientVersion

proc signRequest(self: GameClient, httpMethod, path: string, timestamp: int64, bodyStr: string): string =
  if self.signingKey.len == 0: return ""
  let digest = sha256Hex(bodyStr)
  var cleanPath = path
  let qIdx = path.find('?')
  if qIdx >= 0: cleanPath = path[0 ..< qIdx]
  let payload = httpMethod & "\n" & cleanPath & "\n" & $timestamp & "\n" & digest
  result = hmacSha256(self.signingKey, payload)

proc doRequest*(self: GameClient, httpMethod, endpoint: string, body: JsonNode = nil, idempotent: bool = false): Future[JsonNode] {.async.} =
  let client = newAsyncHttpClient()
  defer: client.close()

  var bodyStr = ""
  if body != nil:
    bodyStr = $body

  var headers = newHttpHeaders([
    ("Content-Type", "application/json"),
    ("X-PokeIdle-Client", "web"),
    ("X-PokeIdle-Client-Version", self.clientVersion),
    ("Accept", "application/json, text/plain, */*"),
    ("User-Agent", DefaultUserAgent)
  ])

  if self.accessToken.len > 0:
    headers.add("Authorization", "Bearer " & self.accessToken)

  if idempotent or httpMethod == "POST" or httpMethod == "PUT":
    headers.add("Idempotency-Key", newUUID4())

  if self.signingKey.len > 0 and self.accessToken.len > 0:
    let nowMs = (epochTime() * 1000).int64
    let sig = self.signRequest(httpMethod, endpoint, nowMs, bodyStr)
    if sig.len > 0:
      headers.add("X-PokeIdle-Timestamp", $nowMs)
      headers.add("X-PokeIdle-Signature", sig)

  client.headers = headers
  let url = self.baseUrl & endpoint

  var resp: AsyncResponse
  if httpMethod == "POST":
    resp = await client.post(url, bodyStr)
  elif httpMethod == "PUT":
    resp = await client.put(url, bodyStr)
  else:
    resp = await client.get(url)

  if resp.code == Http200 or resp.code == Http201:
    let respBody = await resp.body
    if respBody.len > 0:
      result = parseJson(respBody)
    else:
      result = newJObject()
  else:
    raise newException(IOError, "HTTP " & $resp.code & " em " & endpoint)

proc login*(self: GameClient, email, pass: string): Future[bool] {.async.} =
  let payload = %*{
    "login": email,
    "password": pass,
    "captcha_token": ""
  }
  let res = await self.doRequest("POST", "/auth/login", payload)
  let at = res{"access_token"}.getStr("")
  let key = res{"client_signing_key"}.getStr("")
  if at.len > 0:
    self.accessToken = at
    if key.len > 0: self.signingKey = key
    result = true

proc exchangeHandoff*(self: GameClient, code: string): Future[bool] {.async.} =
  let payload = %*{"code": code}
  let res = await self.doRequest("POST", "/auth/handoff/exchange", payload)
  let at = res{"access_token"}.getStr("")
  let key = res{"client_signing_key"}.getStr("")
  if at.len > 0:
    self.accessToken = at
    if key.len > 0: self.signingKey = key
    result = true

proc getMe*(self: GameClient): Future[JsonNode] {.async.} =
  result = await self.doRequest("GET", "/trainer/me")

proc getCreatures*(self: GameClient, location: string = ""): Future[seq[Creature]] {.async.} =
  let endpoint = if location.len > 0: "/creatures?location=" & location else: "/creatures"
  let val = await self.doRequest("GET", endpoint)
  var arr = val
  if val.hasKey("data"): arr = val["data"]
  elif val.hasKey("creatures"): arr = val["creatures"]

  result = @[]
  if arr.kind == JArray:
    for c in arr:
      result.add(Creature(
        id: c{"id"}.getStr(""),
        speciesId: c{"species_id"}.getStr(""),
        name: c{"name"}.getStr("Pokémon"),
        level: c{"level"}.getInt(1),
        hp: c{"hp"}.getInt(100),
        maxHp: c{"max_hp"}.getInt(100),
        isLeader: c{"is_leader"}.getBool(false),
        isShiny: c{"is_shiny"}.getBool(false)
      ))

proc getZones*(self: GameClient): Future[seq[Zone]] {.async.} =
  let val = await self.doRequest("GET", "/zones")
  var arr = val
  if val.hasKey("data"): arr = val["data"]
  elif val.hasKey("zones"): arr = val["zones"]

  result = @[]
  if arr.kind == JArray:
    for z in arr:
      result.add(Zone(
        id: z{"id"}.getStr(""),
        name: z{"name"}.getStr(""),
        recommendedLevel: z{"recommended_level"}.getInt(1),
        minLevel: z{"min_level"}.getInt(1),
        maxLevel: z{"max_level"}.getInt(100),
        mapId: z{"map_id"}.getInt(0)
      ))

proc prepareHunt*(self: GameClient, zoneId: string): Future[tuple[mapId: int, zoneId: string]] {.async.} =
  let payload = %*{"zone_id": zoneId}
  let res = await self.doRequest("POST", "/hunts/prepare", payload, idempotent = true)
  let alloc = res{"allocation"}
  if alloc != nil:
    result.mapId = alloc{"map_id"}.getInt(0)
    result.zoneId = alloc{"zone_id"}.getStr(zoneId)

proc healTeam*(self: GameClient): Future[bool] {.async.} =
  try:
    discard await self.doRequest("POST", "/team/heal", %*{})
    result = true
  except CatchableError: result = false

proc claimDailyLogin*(self: GameClient): Future[bool] {.async.} =
  try:
    discard await self.doRequest("POST", "/daily-login/claim", %*{}, idempotent = true)
    result = true
  except CatchableError: result = false

proc claimAllQuests*(self: GameClient): Future[bool] {.async.} =
  try:
    discard await self.doRequest("POST", "/quests/claim-all", %*{}, idempotent = true)
    result = true
  except CatchableError: result = false

proc claimAllSpeciesGoals*(self: GameClient): Future[bool] {.async.} =
  try:
    discard await self.doRequest("POST", "/species-goals/claim-all", %*{}, idempotent = true)
    result = true
  except CatchableError: result = false

proc claimAllBattlepass*(self: GameClient): Future[bool] {.async.} =
  try:
    discard await self.doRequest("POST", "/battlepass/claim-all", %*{}, idempotent = true)
    result = true
  except CatchableError: result = false

proc claimAllMail*(self: GameClient): Future[bool] {.async.} =
  try:
    discard await self.doRequest("POST", "/mail/claim-all", %*{}, idempotent = true)
    result = true
  except CatchableError: result = false

proc resolveStamina*(self: GameClient): Future[bool] {.async.} =
  try:
    discard await self.doRequest("POST", "/stamina/resolve", %*{})
    result = true
  except CatchableError: result = false

proc collectMiningRewards*(self: GameClient, slot: int = 0): Future[bool] {.async.} =
  try:
    discard await self.doRequest("POST", "/professions/mining/rewards/collect", %*{"slot_index": slot}, idempotent = true)
    result = true
  except CatchableError: result = false

proc collectFarmRewards*(self: GameClient, slot: int = 0): Future[bool] {.async.} =
  try:
    discard await self.doRequest("POST", "/professions/farming/rewards/collect", %*{"slot_index": slot}, idempotent = true)
    result = true
  except CatchableError: result = false
