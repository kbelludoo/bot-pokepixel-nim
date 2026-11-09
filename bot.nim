import std/[asyncdispatch, json, strformat, strutils, times, uri]
import ws
import types, client, stealth

type
  BotInstance* = ref object
    config*: AccountConfig
    client*: GameClient
    ws*: WebSocket
    isConnected*: bool
    level*: int
    hp*: int
    maxHp*: int
    mana*: int
    maxMana*: int
    gold*: int64
    kills*: int64
    expPerHour*: float
    status*: string
    currentArea*: string
    startTime*: float
    startExp*: int64
    currentExp*: int64
    isHunting*: bool
    currentMapId*: int
    currentZoneId*: string
    zones*: seq[Zone]
    leaderName*: string
    leaderLevel*: int
    circuitState*: string
    logs*: seq[string]
    running*: bool

proc newBotInstance*(config: AccountConfig): BotInstance =
  new(result)
  result.config = config
  result.client = newGameClient(config.credentials.token)
  result.level = 1
  result.hp = 100
  result.maxHp = 100
  result.mana = 0
  result.maxMana = 0
  result.gold = 0
  result.kills = 0
  result.expPerHour = 0.0
  result.status = "Iniciando..."
  result.currentArea = config.settings.huntTarget
  result.startTime = epochTime()
  result.startExp = 0
  result.currentExp = 0
  result.isHunting = false
  result.currentMapId = 0
  result.currentZoneId = ""
  result.zones = @[]
  result.leaderName = ""
  result.leaderLevel = 1
  result.circuitState = "CLOSED (Operação Normal)"
  result.logs = @[]
  result.running = false
  result.isConnected = false

proc addLog*(self: BotInstance, msg: string) =
  let now = now().format("HH:mm:ss")
  let formatted = fmt"[{now}] {msg}"
  echo formatted
  if self.logs.len >= 25:
    self.logs.delete(0)
  self.logs.add(formatted)

proc sendWs*(self: BotInstance, msg: string): Future[bool] {.async.} =
  if self.ws == nil or not self.isConnected: return false
  try:
    await self.ws.send(msg)
    result = true
  except CatchableError:
    self.isConnected = false
    result = false

proc triggerHunt*(self: BotInstance) {.async.} =
  var targetZoneId = "auto"
  var targetZoneName = "Charmander"

  let target = self.config.settings.huntTarget
  if target == "auto" or target.len == 0:
    for z in self.zones:
      if z.recommendedLevel <= self.level:
        targetZoneId = z.id
        targetZoneName = z.name
        break
  else:
    for z in self.zones:
      if z.id == target:
        targetZoneId = z.id
        targetZoneName = z.name
        break

  if self.zones.len > 0 and targetZoneId == "auto":
    targetZoneId = self.zones[0].id
    targetZoneName = self.zones[0].name

  self.addLog(fmt"Preparando entrada na zona: {targetZoneName}...")

  try:
    let alloc = await self.client.prepareHunt(targetZoneId)
    let enterMsg = %*{
      "type": "huntsim.enter",
      "data": {
        "map_id": alloc.mapId,
        "zone_id": alloc.zoneId
      }
    }
    discard await self.sendWs($enterMsg)
    self.isHunting = true
    self.status = "hunting"
    self.currentArea = targetZoneName
    self.currentMapId = alloc.mapId
    self.currentZoneId = alloc.zoneId
    self.addLog(fmt"⚔️ Caçada ativa no mapa {alloc.mapId} ({targetZoneName})!")
  except CatchableError as e:
    self.addLog(fmt"Erro ao preparar caçada em {targetZoneName}: {e.msg}")

proc handleWsMessage*(self: BotInstance, text: string) {.async.} =
  try:
    let node = parseJson(text)
    let msgType = node{"type"}.getStr("")
    let data = node{"data"}

    case msgType
    of "connection.ready":
      self.addLog("⚡ [WS] Servidor autorizou conexão (connection.ready).")
      self.status = "hunting"
      self.isHunting = true
    of "combat.started":
      self.status = "hunting"
      self.isHunting = true
    of "loot.received", "hunt.kill_reward":
      let g = if data != nil: data{"gold"}.getBiggestInt(0) else: 0
      let exp = if data != nil: data{"exp"}.getBiggestInt(0) else: 0
      inc self.kills
      self.gold += g
      self.currentExp += exp
      self.status = "hunting"
    of "level.up", "trainer.level_up":
      let lvl = if data != nil: data{"level"}.getInt(0) else: 0
      let maxHpVal = if data != nil: data{"max_hp"}.getInt(0) else: 0
      if lvl > 0: self.level = lvl
      if maxHpVal > 0:
        self.maxHp = maxHpVal
        self.hp = maxHpVal
      self.addLog(fmt"🎉 PARABÉNS! SUBIU PARA O NÍVEL {self.level}!")
    of "combat.player_defeated":
      self.addLog("⚠️ Pokémon líder foi derrotado em combate! Ativando protocolo de recuperação...")
      discard await self.client.healTeam()
    of "capture.success":
      let name = if data != nil: data{"name"}.getStr("Pokémon") else: "Pokémon"
      let isShiny = if data != nil: data{"is_shiny"}.getBool(false) else: false
      if isShiny:
        self.addLog(fmt"🌟 CAPTURA SHINY INCRÍVEL: {name}!")
      else:
        self.addLog(fmt"🎯 Pokémon capturado com sucesso: {name}")
    of "hunt.stopped":
      self.isHunting = false
    else:
      discard
  except CatchableError:
    discard

proc readerLoop*(self: BotInstance) {.async.} =
  while self.running and self.isConnected:
    try:
      let msg = await self.ws.receiveStrPacket()
      if msg.len > 0:
        await self.handleWsMessage(msg)
      else:
        break
    except CatchableError as e:
      self.addLog("Erro no stream do WebSocket: " & e.msg)
      break
  self.isConnected = false
  self.isHunting = false
  self.status = "Reconectando..."

proc pingLoop*(self: BotInstance) {.async.} =
  while self.running:
    await sleepAsync(20000)
    if self.isConnected:
      let nowMs = (epochTime() * 1000).int64
      let ping = %*{
        "type": "ping",
        "data": {
          "client_time": nowMs,
          "foreground": true
        }
      }
      discard await self.sendWs($ping)

proc huntLoop*(self: BotInstance) {.async.} =
  while self.running:
    let jitterDelay = applyJitter(5000, 0.20)
    await sleepAsync(jitterDelay)
    if self.config.settings.autoHunt and self.isConnected and not self.isHunting:
      if self.status != "Autenticando..." and self.status != "Falha no Login":
        await self.triggerHunt()

proc healLoop*(self: BotInstance) {.async.} =
  while self.running:
    let jitterDelay = applyJitter(10000, 0.20)
    await sleepAsync(jitterDelay)
    if self.config.settings.autoHeal and self.maxHp > 0:
      let pct = (self.hp.float / self.maxHp.float) * 100.0
      if pct < self.config.settings.hpThreshold.float:
        self.addLog("❤️ HP baixo detectado! Enviando ordem de cura da equipe...")
        if await self.client.healTeam():
          self.hp = self.maxHp
          self.addLog("✨ Equipe curada com sucesso!")

proc dailyLoop*(self: BotInstance) {.async.} =
  while self.running:
    let dailyDelay = applyJitter(900000, 0.15) # ~15 minutos
    await sleepAsync(dailyDelay)
    if self.config.settings.autoDaily:
      self.addLog("🎁 Coletando recompensas diárias, missões e stamina com pacing humano...")
      discard await self.client.claimDailyLogin()
      await pacingDelay(300, 600)
      discard await self.client.claimAllQuests()
      await pacingDelay(300, 600)
      discard await self.client.claimAllBattlepass()
      await pacingDelay(300, 600)
      discard await self.client.claimAllSpeciesGoals()
      await pacingDelay(300, 600)
      discard await self.client.claimAllMail()
      await pacingDelay(300, 600)
      discard await self.client.resolveStamina()

    if self.config.settings.autoProfessions:
      await pacingDelay(400, 700)
      discard await self.client.collectMiningRewards(0)
      await pacingDelay(400, 700)
      discard await self.client.collectFarmRewards(0)

proc metricsLoop*(self: BotInstance) {.async.} =
  while self.running:
    await sleepAsync(10000)
    let elapsed = epochTime() - self.startTime
    if elapsed > 10.0:
      let gainedExp = max(0, self.currentExp - self.startExp).float
      self.expPerHour = (gainedExp / elapsed) * 3600.0

proc init*(self: BotInstance) {.async.} =
  self.status = "Autenticando..."
  self.currentArea = self.config.settings.huntTarget
  self.addLog("Inicializando cliente PokePixel Nim...")

  # 1. Autenticação
  var token = self.client.accessToken
  if token.len == 0:
    if self.config.credentials.handoffCode.len > 0:
      self.addLog(fmt"Trocando código de handoff ({self.config.credentials.handoffCode}) por sessão...")
      try:
        if await self.client.exchangeHandoff(self.config.credentials.handoffCode):
          self.addLog("Token de sessão obtido com sucesso via Handoff!")
          token = self.client.accessToken
      except CatchableError: discard

    if token.len == 0 and self.config.credentials.email.len > 0 and self.config.credentials.password.len > 0:
      self.addLog(fmt"Efetuando login para {self.config.credentials.email}...")
      try:
        if await self.client.login(self.config.credentials.email, self.config.credentials.password):
          self.addLog("Login realizado com sucesso! Token de acesso recebido.")
          token = self.client.accessToken
        else:
          self.status = "Falha no Login"
          self.addLog("Falha ao autenticar.")
      except CatchableError as e:
        self.status = "Falha no Login"
        self.addLog(fmt"Falha ao autenticar: {e.msg}")
  else:
    self.addLog("Utilizando Bearer Token pré-configurado.")

  # 2. Carregar Me
  try:
    let trNode = await self.client.getMe()
    let tr = trNode{"trainer"}
    if tr != nil:
      self.level = tr{"level"}.getInt(1)
      self.gold = tr{"gold"}.getBiggestInt(0)
      self.startExp = tr{"exp"}.getBiggestInt(0)
      self.currentExp = self.startExp
      let name = tr{"name"}.getStr("Treinador")
      self.addLog(fmt"Treinador conectado: {name} (Nível {self.level} | Ouro: {self.gold})")
  except CatchableError: discard

  # 3. Carregar Equipe e Criaturas
  try:
    let creatures = await self.client.getCreatures("team")
    for c in creatures:
      if c.isLeader or creatures.len == 1:
        self.hp = c.hp
        self.maxHp = c.maxHp
        self.leaderName = c.name
        self.leaderLevel = c.level
        self.addLog(fmt"Líder da equipe carregado: {c.name} (Lv. {c.level} | HP: {c.hp}/{c.maxHp})")
        break
  except CatchableError: discard

  # 4. Carregar Zonas
  try:
    self.zones = await self.client.getZones()
    self.addLog(fmt"Catálogo carregado: {self.zones.len} zonas de caça disponíveis.")
  except CatchableError: discard

  if self.status != "Falha no Login":
    self.status = "Pronto"

proc run*(self: BotInstance) {.async.} =
  self.running = true
  await self.init()

  asyncCheck self.pingLoop()
  asyncCheck self.huntLoop()
  asyncCheck self.healLoop()
  asyncCheck self.dailyLoop()
  asyncCheck self.metricsLoop()

  var backoffMs = 3000
  while self.running:
    let token = self.client.accessToken
    if token.len == 0:
      await sleepAsync(backoffMs)
      continue

    let wsUrl = fmt"wss://pokepixel.nietore.com/api/v1/ws?token={encodeUrl(token)}"
    self.addLog("Conectando ao canal em tempo real WebSocket...")

    try:
      self.ws = await newWebSocket(wsUrl)
      self.isConnected = true
      backoffMs = 3000
      self.addLog("WebSocket conectado com sucesso! Sessão autoritativa iniciada.")

      # Resume inicial
      let resume = %*{
        "type": "hunt.resume",
        "data": { "last_seq": 0 }
      }
      discard await self.sendWs($resume)

      await self.readerLoop()
    except CatchableError as e:
      self.addLog(fmt"Falha na conexão do WebSocket: {e.msg}")

    self.status = "Reconectando..."
    self.isHunting = false
    self.addLog(fmt"Tentando reautenticar em {(backoffMs div 1000)}s...")
    await sleepAsync(backoffMs)

    if self.config.credentials.email.len > 0 and self.config.credentials.password.len > 0:
      try:
        if await self.client.login(self.config.credentials.email, self.config.credentials.password):
          self.addLog("Reautenticação HTTP bem-sucedida!")
      except CatchableError as e:
        self.addLog(fmt"Reautenticação HTTP pendente ({e.msg}).")
        if backoffMs < 45000:
          backoffMs += 5000

proc toDto*(self: BotInstance): AccountStatusDto =
  let elapsed = (epochTime() - self.startTime).int64
  let displayName = if self.config.settings.stealthMode:
                      fmt"Treinador #{self.config.id}"
                    else:
                      self.config.name

  result = AccountStatusDto(
    id: self.config.id,
    name: displayName,
    level: self.level,
    vocation: "Treinador",
    hp: self.hp,
    maxHp: self.maxHp,
    mana: self.mana,
    maxMana: self.maxMana,
    gold: self.gold,
    kills: self.kills,
    expPerHour: self.expPerHour,
    status: self.status,
    currentArea: self.currentArea,
    durationSec: elapsed,
    logs: self.logs,
    updatedAt: (epochTime() * 1000).int64,
    extra: ExtraStatusDto(
      bestiaryFocus: self.config.settings.bestiaryFocus,
      circuitState: self.circuitState,
      cooldownSec: 0,
      leaderLevel: self.leaderLevel,
      leaderName: self.leaderName
    )
  )
