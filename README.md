# bot-pokepixel-nim ⚡

Automação autônoma nativa para **PokePixel** reescrita 100% em **Nim 2.2** com modelo de gerenciamento de memória ORC (`--mm:orc`), zero overhead de Garbage Collector e ultra-baixo consumo de memória RAM.

## 🚀 Destaques da Arquitetura Nim
- **100% Paridade de Heurística e Métricas**: Compatível com as métricas JSON de telemetria expostas na porta padrão (`3015`) sob `/api/status`.
- **Motor Anti-Detecção com Pacing e Jitter Orgânico**: Variação randômica de $\pm 20\%$ nos intervalos de caça e ações para evitar assinaturas temporais determinísticas.
- **Operação 24/7 Contínua sem Pausas Forçadas**: Otimizado para jogabilidade de idle contínua.
- **Assinatura Criptográfica HMAC-SHA256**: Suporte integral a autenticação por handoff, login e requisições com assinatura HMAC e idempotência.
- **Conexão Real-Time WebSocket**: Conexão com canal em tempo real para sincronização autoritativa de caçadas, capturas e combate.
- **Consumo de Memória Extremamente Reduzido**: Binário estático e compacto compilado via Zig toolchain.

## 📦 Compilação
```bash
nim c --os:linux --cpu:amd64 --gcc.exe:zigcc-linux-gnu.bat --gcc.linkerexe:zigcc-linux-gnu.bat -d:ssl -d:release -o:bot-pokepixel-linux-nim main.nim
```

## ⚙️ Configuração
Copie `accounts.example.json` para `accounts.json` e insira suas credenciais:
```json
[
  {
    "id": "acc-1",
    "name": "Treinador Principal",
    "enabled": true,
    "credentials": {
      "token": "seu-bearer-token",
      "email": "user@exemplo.com",
      "password": "senha-segura",
      "handoffCode": ""
    },
    "settings": {
      "huntTarget": "auto",
      "autoHunt": true,
      "autoHeal": true,
      "autoCapture": true,
      "autoDaily": true,
      "autoProfessions": true
    }
  }
]
```
