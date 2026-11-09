import std/[asyncdispatch, json, os, strutils, strformat]
import types, bot, dashboard

const DefaultAccountsExample = staticRead("accounts.example.json")

proc main() =
  echo "================================================================================"
  echo "       ⚡ POKEPIXEL NATIVE NIM MULTI-BOT ENGINE (ULTRA-LEVE & ZERO-GC) ⚡       "
  echo "================================================================================"

  let configPath = "accounts.json"
  var content = ""
  if fileExists(configPath):
    content = readFile(configPath)
  else:
    echo "⚠️ Arquivo accounts.json não encontrado. Criando template padrão..."
    writeFile(configPath, DefaultAccountsExample)
    content = DefaultAccountsExample

  let rootJson = parseJson(content)
  var allConfigs: seq[AccountConfig] = @[]
  if rootJson.kind == JArray:
    for item in rootJson:
      allConfigs.add(parseAccountConfig(item))

  let targetAcc = getEnv("ACCOUNT", "")
  var activeConfigs: seq[AccountConfig] = @[]
  for cfg in allConfigs:
    if not cfg.enabled and cfg.id != targetAcc:
      continue
    if targetAcc.len > 0 and cfg.id != targetAcc:
      continue
    activeConfigs.add(cfg)

  if activeConfigs.len == 0:
    echo "⚠️ Nenhuma conta com 'enabled: true' encontrada em accounts.json."

  var bots: seq[BotInstance] = @[]
  for cfg in activeConfigs:
    echo fmt"Iniciando bot em runtime Nim nativo: {cfg.name} ({cfg.id})"
    let b = newBotInstance(cfg)
    asyncCheck b.run()
    bots.add(b)

  var port = 3015
  let portEnv = getEnv("PORT", "3015")
  try:
    port = parseInt(portEnv)
  except ValueError:
    port = 3015

  let webServer = newWebServer(bots, port)
  asyncCheck webServer.start()

  echo fmt"🌐 [Web Server] PokePixel Nim API ativa em http://0.0.0.0:{port}"
  runForever()

when isMainModule:
  main()
