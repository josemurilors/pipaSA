# Animações (IFP) e como foram feitas

O DragonFF 1.0.0 importa/exporta modelos (`.dff`, `.txd`, `.col`), mas **não** animações. Por isso o projeto tem o próprio leitor e escritor de IFP ANP3 e um gerador que usa o Blender só para posar e conferir.

## Pipeline

1. `tools/ifp.py` lê e escreve IFP ANP3 (validado: regravar o `ped.ifp` do jogo mantém tamanho e quadros).
2. `tools/blender_kite_anims.py` (rodado no Blender em modo background):
   - importa `work/player.dff` (esqueleto do CJ, extraído do seu `models/gta3.img`) com o DragonFF;
   - parte da pose `IDLE_stance` do `anim/ped.ifp` e aplica deltas (graus, Euler XYZ) por osso;
   - converte para o formato do IFP (`q_ifp = repouso_local @ base_blender`) e grava `pipasa.ifp` (bloco `PIPASA`);
   - renderiza um esqueleto posado para conferir e imprime medidas (distância entre as mãos, posição da cabeça e do queixo).

## Convenções medidas no esqueleto do CJ

| Ossos | Eixo | Efeito |
| --- | --- | --- |
| braços e coxas | Z negativo | flexiona para frente |
| braços e coxas | Z positivo | estende para trás |
| coluna, pescoço e cabeça | Z positivo | inclina/baixa para a frente |
| coluna, pescoço e cabeça | Z negativo | inclina para trás / olha para cima |
| braço direito (id 22) | Y positivo | afasta do corpo; no esquerdo (id 32) é Y negativo |
| braços | X | torção |

Dois erros do projeto vieram de inverter essas convenções (pose de "oração" com as mãos coladas e CJ olhando para baixo), por isso o gerador imprime as medidas.

## Animações geradas

`kite_fly_loop`, `kite_pull`, `kite_give`, `kite_whip`, `kite_cheer`, `kite_lose` (CJ) e `kite_ped_a`, `kite_ped_b`, `kite_ped_c` (pedestres soltando pipa). O IFP é importado pelo Mod Loader como bloco de animação `PIPASA`.

## Regerar

```bash
# Blender com o add-on DragonFF; PIPASA_GAME = pasta do GTA SA
blender -b --factory-startup --python tools/blender_kite_anims.py -- "<pasta do projeto>" "<pasta de previews>"
```
