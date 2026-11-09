import std/[json, options]

type
  GameCredentials* = object
    email*: string
    password*: string
    token*: string
    handoffCode*: string
    sessionCookie*: string

  GameSettings* = object
    huntTarget*: string
    autoHunt*: bool
    autoHeal*: bool
    hpThreshold*: int
    autoCapture*: bool
    autoCaptureShiny*: bool
    autoSell*: bool
    autoExtract*: bool
    autoDaily*: bool
    autoProfessions*: bool
    autoBreeding*: bool
    bestiaryFocus*: bool
    stealthMode*: bool

  AccountConfig* = object
    id*: string
    name*: string
    enabled*: bool
    bindIP*: string
    credentials*: GameCredentials
    settings*: GameSettings

  Zone* = object
    id*: string
    name*: string
    recommendedLevel*: int
    minLevel*: int
    maxLevel*: int
    mapId*: int

  Creature* = object
    id*: string
    speciesId*: string
    name*: string
    level*: int
    hp*: int
    maxHp*: int
    isLeader*: bool
    isShiny*: bool

  ExtraStatusDto* = object
    bestiaryFocus*: bool
    circuitState*: string
    cooldownSec*: int64
    leaderLevel*: int
    leaderName*: string

  AccountStatusDto* = object
    id*: string
    name*: string
    level*: int
    vocation*: string
    hp*: int
    maxHp*: int
    mana*: int
    maxMana*: int
    gold*: int64
    kills*: int64
    expPerHour*: float
    status*: string
    currentArea*: string
    durationSec*: int64
    logs*: seq[string]
    updatedAt*: int64
    extra*: ExtraStatusDto

proc parseCredentials(node: JsonNode): GameCredentials =
  if node != nil:
    result.email = node{"email"}.getStr("")
    result.password = node{"password"}.getStr("")
    result.token = node{"token"}.getStr("")
    result.handoffCode = node{"handoffCode"}.getStr("")
    result.sessionCookie = node{"sessionCookie"}.getStr("")

proc parseSettings(node: JsonNode): GameSettings =
  result.huntTarget = "auto"
  result.autoHunt = true
  result.autoHeal = true
  result.hpThreshold = 40
  result.autoCapture = true
  result.autoCaptureShiny = true
  result.autoSell = true
  result.autoExtract = true
  result.autoDaily = true
  result.autoProfessions = true
  result.autoBreeding = true
  result.bestiaryFocus = false
  result.stealthMode = true

  if node != nil:
    if node.hasKey("huntTarget"): result.huntTarget = node["huntTarget"].getStr("auto")
    elif node.hasKey("hunt_target"): result.huntTarget = node["hunt_target"].getStr("auto")

    if node.hasKey("autoHunt"): result.autoHunt = node["autoHunt"].getBool(true)
    if node.hasKey("autoHeal"): result.autoHeal = node["autoHeal"].getBool(true)
    if node.hasKey("hpThreshold"): result.hpThreshold = node["hpThreshold"].getInt(40)
    if node.hasKey("autoCapture"): result.autoCapture = node["autoCapture"].getBool(true)
    if node.hasKey("autoCaptureShiny"): result.autoCaptureShiny = node["autoCaptureShiny"].getBool(true)
    if node.hasKey("autoSell"): result.autoSell = node["autoSell"].getBool(true)
    if node.hasKey("autoExtract"): result.autoExtract = node["autoExtract"].getBool(true)
    if node.hasKey("autoDaily"): result.autoDaily = node["autoDaily"].getBool(true)
    if node.hasKey("autoProfessions"): result.autoProfessions = node["autoProfessions"].getBool(true)
    if node.hasKey("autoBreeding"): result.autoBreeding = node["autoBreeding"].getBool(true)
    if node.hasKey("bestiaryFocus"): result.bestiaryFocus = node["bestiaryFocus"].getBool(false)
    if node.hasKey("stealthMode"): result.stealthMode = node["stealthMode"].getBool(true)

proc parseAccountConfig*(node: JsonNode): AccountConfig =
  result.id = node{"id"}.getStr("")
  result.name = node{"name"}.getStr(result.id)
  result.enabled = node{"enabled"}.getBool(true)
  result.bindIP = node{"bindIP"}.getStr("")
  result.credentials = parseCredentials(node{"credentials"})
  result.settings = parseSettings(node{"settings"})
