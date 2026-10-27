# Engenharia reversa do CS Diamantes Pipas

Este mod é uma **reimplementação inspirada** no jogo Unity *CS Diamantes Pipas* (batalha de pipas com corte de linha). Nenhum asset do jogo foi copiado: modelos, ícone, animações e código foram feitos do zero.

## O que foi analisado

- **Alvo:** `CS Diamantes Pipas.exe` (Unity IL2CPP: `GameAssembly.dll` + `il2cpp_data/Metadata/global-metadata.dat`), com Photon (rede/chat) e Vivox (voz).
- **Método:** leitura estática dos nomes de classes, campos e métodos em `global-metadata.dat`. **Não** foram lidos corpos de métodos nem observada a execução, então tudo abaixo é **inferência pelos nomes**.

## Mecânicas inferidas

| Mecânica | Nomes encontrados | O que o mod faz |
| --- | --- | --- |
| Linha com vida | `LinhaHP`, `LINHA_DMG_BASE`, `_mod_resistenciaLinha` | cada pipa tem 100 de vida de linha; dano base por segundo e resistência configuráveis |
| Corte | `Cortar`, `corteBool`, `CortadoCaida`, `kite_hilo_cortado` | linha sem vida corta a pipa, que cai com o vento |
| Controle da linha | `AlarguePipas`, `KitePuxar`, `KiteDescarregar(Rapido)` | `Y` dá linha, `H` puxa |
| Chicote | `RabiolaChicote`, `botonChicoteRabiola` | `J`: dano 2,5x por ~1 s, recarga de 6 s |
| Vento | `_vel_vento1`, `_vel_vento15`, `_vel_vento20` | 3 níveis (brisa, moderado, forte) mudando a cada 60–100 s |
| Bots | `BOT_Kite`, `bot_respawn`, `_iaBOT_atraerKite` | rivais com IA simples por temporizador |
| Ranking | `_ranked_bronze`, `_ranked_plata`, `_ranked_oro` | Bronze, Prata (100 pts), Ouro (300 pts), salvo em arquivo |

Ficaram **de fora**: loja de diamantes, anúncios, anti-hack, chat e voz online, lobby e matchmaking.

## Como reproduzir a leitura

Extraia os identificadores de `global-metadata.dat` (strings ASCII) e filtre por termos como `corte`, `linha`, `rabiola`, `vento`, `Kite`. Para ir além (corpo dos métodos), recupere símbolos com Il2CppDumper e abra `GameAssembly.dll` em um desmontador.
