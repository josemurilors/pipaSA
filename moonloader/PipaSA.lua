script_name("PipaSA")
script_author("pipaSA")
script_description("Batalha de pipas (corte de linha) inspirada em CS Diamantes Pipas")

-- Teclas configuraveis em moonloader/config/PipaSA.ini (G = entrar de carona no GTA, por isso desafiar e U)
local ini = { keys = { launch = "K", give = "Y", pull = "H", whip = "J", challenge = "U" } }
pcall(function()
    local inicfg = require "inicfg"
    ini = inicfg.load(ini, "PipaSA.ini")
    inicfg.save(ini, "PipaSA.ini")
end)
local function vk(c) return tostring(c):upper():byte() end
local KEY = { launch = vk(ini.keys.launch), give = vk(ini.keys.give), pull = vk(ini.keys.pull), whip = vk(ini.keys.whip),
              challenge = vk(ini.keys.challenge), left = 0x25, right = 0x27 }
local CFG = {
    kite_models = { 19100, 19101, 19102, 19103 },
    dmg_base = 7.0,        -- HP/s de dano quando as linhas se cruzam (antes dos multiplicadores)
    line_res = 1.0,        -- resistencia da linha do CJ (ver _mod_resistenciaLinha no jogo original)
    wind_factor = { 0.6, 1.0, 1.4 }, -- vento 1 / 15 / 20 do original -> brisa / moderado / forte
    challenge_r = 15, contact = 2.2, -- m: distancia p/ desafiar; raio de contato das linhas
    reward = 500, points = 25,
    spawn_r = 45, despawn_r = 80, respawn_s = 240, -- spawn curto: a colisao do chao so existe perto do jogador
    info_r = 70, -- m: ate onde as informacoes aparecem
}
-- shortcut: coordenadas aproximadas de LS; calibrar in-game (campos/lajes de periferia) e ajustar. Z e corrigido pelo chao.
local SPOTS = {
    { "Ganton",         2290, -1720, 14, 1 }, { "Idlewood",   1990, -1740, 14, 1 },
    { "Jefferson",      2130, -1190, 24, 1 }, { "Los Flores", 2650, -1290, 24, 2 },
    { "Glen Park",      1960, -1230, 20, 1 }, { "El Corona",  1830, -2110, 13, 2 },
    { "Willowfield",    2420, -1930, 13, 2 }, { "Playa del Seville", 2760, -2020, 13, 3 },
    { "Mirante Leste",  2670,  -996, 85, 3 },
}
local BLIP_SPRITE = 56 -- radar_light: textura trocada pelo icone da pipa (modloader/zz_PipaSA_HUD/models/hud.txd)
local SKINS = { 14, 20, 22, 28, 29, 30 }
local SKINS_F = { 9, 10, 11, 12, 13, 31 }
-- animacoes do proprio GTA SA (sem IFP novo): { bloco, nome }
local ANIM = {
    sit = { "BEACH", "ParkSit_M_loop" }, sitw = { "BEACH", "ParkSit_W_loop" },
    sitg = { "BEACH", "SitnWait_loop_W" }, look = { "ON_LOOKERS", "lkup_loop" },
    talkA = { "GANGS", "prtial_gngtlkA" }, talkB = { "GANGS", "prtial_gngtlkB" }, cheer = { "ON_LOOKERS", "wave_loop" },
}
-- cenas ao redor de cada spot (dx, dy em metros a partir do spot; rumo em graus, 0 = norte).
-- props: { modelo, dx, dy, dz, rumo } | atores: sit/sitw (no banco, rumo), sitg (no chao), talk (fx, fy = para quem olha), kite (solitario)
-- shortcut: o "rumo" do banco/ator sentado depende da frente do modelo; calibrar in-game se ficarem de costas.
local function own(name, extra)
    local a = { "PIPASA", name, fb = ANIM.look }
    for k, v in pairs(extra or {}) do a[k] = v end
    return a
end
ANIM.fly, ANIM.pull, ANIM.give = own("kite_fly_loop"), own("kite_pull"), own("kite_give")
ANIM.whip, ANIM.cheer2, ANIM.lose = own("kite_whip", { once = true }), own("kite_cheer"), own("kite_lose")
local REEL_MODEL = 19107 -- carretel preso a mao
local PED_KITE_ANIMS = { own("kite_ped_a", { hand = 24 }), own("kite_ped_b", { hand = 34 }), own("kite_ped_c", { hand = 24 }) }
local TAIL_MODELS = { 19104, 19105, 19106, 19104, 19105 } -- lacos da rabiola (ondulam por script)
local SCENES = {
    ["Mirante Leste"] = {
        props = { { 1280, 3, 0, 0, 90 }, { 1280, -3, 6, 0, 270 }, { 1256, 6, -4, 0, 180 }, { 1594, -7, -3, 0, 0 },
                  { 1640, 8, 6, 0.03, 20 }, { 1255, 12, 3, 0, 200 }, { 1221, -9, 6, 0, 30 } },
        actors = { { "sit", 3, 0, 90 }, { "sitw", 3, 1.2, 90 }, { "sit", -3, 6, 270 }, { "sitg", 8, 6.8, 20 },
                   { "talk", -7, -1.5, -7, -4.5 }, { "talk", -7, -4.5, -7, -1.5 },
                   { "kite", 14, 12 }, { "kite", -14, 10 }, { "kite", 0, -16 } },
    },
    DEFAULT = {
        props = { { 1280, 4, 0, 0, 90 }, { 1594, -5, 4, 0, 0 } },
        actors = { { "sit", 4, 0, 90 }, { "talk", -5, 2.4, -5, 5.6 }, { "talk", -5, 5.6, -5, 2.4 }, { "kite", 9, -7 } },
    },
}
local SAVE = getWorkingDirectory() .. "\\config\\PipaSA.txt"

local font, sw, sh
local points = 0
local wind = { ang = 0, level = 2, next = 0 }
local mine, battle, spots = nil, nil, {}
local cjForce

local function rank() return points >= 300 and "Ouro" or points >= 100 and "Prata" or "Bronze" end
local function rad(d) return d * math.pi / 180 end
local function clamp(v, a, b) return v < a and a or v > b and b or v end

local function loadPoints()
    local f = io.open(SAVE, "r"); if not f then return end
    points = tonumber(f:read("*a")) or 0; f:close()
end
local function savePoints()
    local f = io.open(SAVE, "w"); if f then f:write(points); f:close() end
end

-- distancia minima entre dois segmentos 3D (Ericson, Real-Time Collision Detection)
local function segDist(p1, q1, p2, q2)
    local function sub(a, b) return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
    local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
    local d1, d2, r = sub(q1, p1), sub(q2, p2), sub(p1, p2)
    local a, e, f = dot(d1, d1), dot(d2, d2), dot(d2, r)
    local s, t
    local c = dot(d1, r)
    local b = dot(d1, d2)
    local den = a * e - b * b
    s = den > 1e-6 and clamp((b * f - c * e) / den, 0, 1) or 0
    t = (b * s + f) / e
    if t < 0 then t, s = 0, clamp(-c / a, 0, 1) elseif t > 1 then t, s = 1, clamp((b - c) / a, 0, 1) end
    local dx = (p1[1] + d1[1] * s) - (p2[1] + d2[1] * t)
    local dy = (p1[2] + d1[2] * s) - (p2[2] + d2[2] * t)
    local dz = (p1[3] + d1[3] * s) - (p2[3] + d2[3] * t)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local ffi = require "ffi"
pcall(ffi.cdef, "typedef struct { float x; float y; float z; } PipaV3;")
local boneFn
local function bonePos(ped, bone)
    if not boneFn then
        local ok, fn = pcall(ffi.cast, "void (__thiscall *)(void*, PipaV3*, unsigned int, bool)", 0x5E01C0)
        if not ok then return nil end
        boneFn = fn
    end
    local ptr = getCharPointer(ped)
    if not ptr or ptr == 0 then return nil end
    local v = ffi.new("PipaV3[1]")
    if not pcall(boneFn, ffi.cast("void*", ptr), v, bone, true) then return nil end
    return v[0].x, v[0].y, v[0].z
end

-- direcao para onde a camera olha: yaw (rad, mundo) e inclinacao (graus, + = para cima)
local function camAim()
    local cx, cy, cz = getActiveCameraCoordinates()
    local tx, ty, tz = getActiveCameraPointAt()
    local dx, dy = tx - cx, ty - cy
    return math.atan2(dy, dx), math.deg(math.atan2(tz - cz, math.sqrt(dx * dx + dy * dy)))
end

local function newKite(owner, model, len, hand)
    if not isModelAvailable(model) then model = 1318 end -- modelo da pipa nao registrado pelo modloader: usa a seta do jogo
    requestModel(model); loadAllModelsNow()
    local x, y, z = getCharCoordinates(owner)
    local ok, o = pcall(createObject, model, x, y, z + 3)
    if not ok then -- modelo customizado falhou (sem COL/DFF invalido): usa a seta do jogo para o mod nao morrer
        print("PipaSA: createObject falhou para o modelo " .. model .. ": " .. tostring(o))
        requestModel(1318); loadAllModelsNow()
        o = createObject(1318, x, y, z + 3)
    end
    setObjectCollision(o, false)
    local tail = {}
    for _, m in ipairs(TAIL_MODELS) do
        if isModelAvailable(m) then
            requestModel(m); loadAllModelsNow()
            local okt, to = pcall(createObject, m, x, y, z + 3)
            if okt then setObjectCollision(to, false); tail[#tail + 1] = to end
        end
    end
    local reel
    if isModelAvailable(REEL_MODEL) then
        requestModel(REEL_MODEL); loadAllModelsNow()
        local okr, ro = pcall(createObject, REEL_MODEL, x, y, z + 1)
        if okr then setObjectCollision(ro, false); reel = ro end
    end
    return { reel = reel, hand = hand or 24, tail = tail, hist = {}, owner = owner, obj = o, len = len or 25, hp = 100, pos = { x, y, z + 3 }, steer = 0,
             whipUntil = 0, whipReady = 0, act = 0, cut = false, fallT = 0, phase = math.random() * 6 }
end

local function destroyKite(k)
    if not k then return end
    for _, o in ipairs(k.tail or {}) do deleteObject(o) end
    k.tail = nil
    if k.reel then deleteObject(k.reel); k.reel = nil end
    if k.obj then deleteObject(k.obj); k.obj = nil end
end

-- historico da posicao: cada laco repete o caminho da pipa com atraso (+ ondulacao lateral), dando o efeito de rabiola
local function updateTail(k, now, head)
    if not k.tail then return end
    local h = k.hist
    h[#h + 1] = { now, k.pos[1], k.pos[2], k.pos[3] }
    while #h > 2 and h[2][1] < now - 1.5 do table.remove(h, 1) end
    local px, py = -math.sin(wind.ang), math.cos(wind.ang)
    for i, o in ipairs(k.tail) do
        local tt, s = now - 0.09 * i, h[1]
        for j = #h, 1, -1 do if h[j][1] <= tt then s = h[j]; break end end
        local w = math.sin(now * 5.5 - i * 1.1 + k.phase) * (0.08 + 0.06 * i)
        setObjectCoordinates(o, s[2] + px * w, s[3] + py * w, s[4] - 0.75 - 0.38 * i)
        setObjectRotation(o, 0, w * 90, head)
    end
end

local function anchor(k)
    if k.reel and doesCharExist(k.owner) then
        local gt = getGameTimer()
        if k.aT ~= gt then -- uma vez por quadro: posiciona o carretel na mao e usa-o como ponto de partida da linha
            k.aT = gt
            local x, y, z = bonePos(k.owner, k.hand)
            if x then
                local hd = getCharHeading(k.owner)
                local r = math.rad(hd)
                x, y, z = x - math.sin(r) * 0.07, y + math.cos(r) * 0.07, z - 0.03
                k.aPos = { x, y, z }
                setObjectCoordinates(k.reel, x, y, z)
                setObjectRotation(k.reel, 0, 0, hd)
            end
        end
        if k.aPos then return k.aPos end
    end
    local x, y, z = getCharCoordinates(k.owner)
    return { x, y, z + 1.0 }
end

-- onde a pipa quer ficar: segue o vento, ou o centro da arena durante a batalha
local function updateKite(k, dt, now, aim)
    if k.cut then
        k.fallT = k.fallT + dt
        local p = k.pos
        p[1] = p[1] + math.cos(wind.ang) * 3 * dt; p[2] = p[2] + math.sin(wind.ang) * 3 * dt
        p[3] = p[3] - (3 + 4 * k.fallT) * dt
        local gz = getGroundZFor3dCoord(p[1], p[2], p[3] + 2)
        if (gz ~= 0 and p[3] <= gz + 0.2) or k.fallT > 8 then destroyKite(k); return false end
    else
        local a = anchor(k)
        if k.held then -- na mao do dono ate ele soltar linha
            local hd = rad(getCharHeading(k.owner))
            k.pos[1], k.pos[2], k.pos[3] = a[1] - math.sin(hd) * 0.1, a[2] + math.cos(hd) * 0.1, a[3] + 0.45
        else
            local el = rad(35 + 15 * wind.level)
            local dx, dy = math.cos(wind.ang), math.sin(wind.ang)
            if k.cy then -- pipa do CJ: segue a direcao da camera (como a mira), com elevacao limitada para nunca ir ao chao
                el = rad(clamp(k.ce + 6, 18, 70)) -- elevacao = inclinacao da camera (+6 graus); minimo 18 evita o chao, maximo 70 evita o zenite
                dx, dy = math.cos(k.cy), math.sin(k.cy)
            end
            local h = math.sqrt(math.max(k.len * k.len * (1 - math.sin(el) ^ 2), 1))
            if aim then
                local vx, vy = aim[1] - a[1], aim[2] - a[2]
                local m = math.sqrt(vx * vx + vy * vy)
                if m > 0.1 then
                    local bearing = math.atan2(vy, vx)
                    if k.cy then -- em batalha a camera so mexe a pipa dentro de um cone de 35 graus em torno do rival
                        local diff = (k.cy - bearing + math.pi) % (2 * math.pi) - math.pi
                        bearing = bearing + clamp(diff, -0.6, 0.6)
                    end
                    dx, dy = math.cos(bearing), math.sin(bearing)
                end
                h = math.min(h, m + 2)
            end
            local lat = k.steer * 8
            local sway = math.sin(now * 1.7 + k.phase) * 1.2
            local tx = a[1] + dx * h - dy * (lat + sway)
            local ty = a[2] + dy * h + dx * (lat + sway)
            local tz = a[3] + k.len * math.sin(el) + math.sin(now * 2.3 + k.phase) * 0.6
            local f = clamp(dt * 2.5, 0, 1)
            k.pos[1] = k.pos[1] + (tx - k.pos[1]) * f
            k.pos[2] = k.pos[2] + (ty - k.pos[2]) * f
            k.pos[3] = k.pos[3] + (tz - k.pos[3]) * f
        end
    end
    if k.cy or k.held then
        local sc = k.held and 0.35 or clamp(0.35 + (k.len - 2.5) / 12, 0.35, 1)
        if not k.sc or math.abs(sc - k.sc) > 0.02 then
            k.sc = sc
            setObjectScale(k.obj, sc)
            for _, o in ipairs(k.tail or {}) do setObjectScale(o, sc) end
        end
    end
    local p = k.pos
    setObjectCoordinates(k.obj, p[1], p[2], p[3])
    local a = anchor(k)
    local head = math.deg(math.atan2(a[2] - p[2], a[1] - p[1])) - 90
    setObjectRotation(k.obj, -20, 0, head)
    updateTail(k, now, head)
    return true
end

local function drawLine3(a, b, w, col)
    local ok1, x1, y1 = convert3DCoordsToScreen(a[1], a[2], a[3])
    local ok2, x2, y2 = convert3DCoordsToScreen(b[1], b[2], b[3])
    if ok1 and ok2 then renderDrawLine(x1, y1, x2, y2, w, col) end
end

local function drawKiteLine(k, col)
    if k.cut or not k.obj then return end
    local a, p, n = anchor(k), k.pos, 18
    local dist = math.sqrt((p[1] - a[1]) ^ 2 + (p[2] - a[2]) ^ 2 + (p[3] - a[3]) ^ 2)
    local sag = math.sqrt(math.max(k.len - dist, 0)) * 1.2
    local pts = { a }
    for i = 1, n do
        local t = i / n
        pts[#pts + 1] = { a[1] + (p[1] - a[1]) * t, a[2] + (p[2] - a[2]) * t, a[3] + (p[3] - a[3]) * t - sag * 4 * t * (1 - t) }
    end
    -- engrossa com a proximidade da camera (min 3, max 6 px) e brilha ao longo da linha
    local cx, cy, cz = getActiveCameraCoordinates()
    local cd = math.sqrt((a[1] - cx) ^ 2 + (a[2] - cy) ^ 2 + (a[3] - cz) ^ 2)
    local w = clamp(70 / math.max(cd, 1), 3, 6)
    for i = 2, #pts do
        drawLine3(pts[i - 1], pts[i], w + 3, 0xB0000000)
    end
    local t = os.clock()
    for i = 2, #pts do
        local glint = (math.sin(t * 6 - i * 0.7) > 0.8) and 0xFFFFFFFF or (col or 0xFFFFFFFF)
        drawLine3(pts[i - 1], pts[i], w, glint)
    end
end

local function bar(x, y, w, frac, col, label)
    renderDrawBox(x - 1, y - 1, w + 2, 14, 0xFF000000)
    renderDrawBox(x, y, w * clamp(frac, 0, 1), 12, col)
    renderFontDrawText(font, label, x + 4, y - 2, 0xFFFFFFFF)
end

local function txt(x, y, s, col) renderFontDrawText(font, s, x, y, col or 0xFFFFFFFF) end
local function label3d(p, s, col)
    local ok, x, y = convert3DCoordsToScreen(p[1], p[2], p[3])
    if ok then txt(x - 6 * #s / 2, y, s, col) end
end

-- informacoes na tela: so aparecem perto dos eventos ou depois de digitar "pipa" (dicas usam a caixa de ajuda padrao do GTA)
local function drawHud(now, info)
    if not info and not battle then return end
    local flying = mine and not mine.cut
    txt(20, sh * 0.45, ("Vento: %s  |  Rank: %s (%d pts)"):format(({ "brisa", "moderado", "forte" })[wind.level], rank(), points))
    if flying then
        txt(20, sh * 0.45 + 18, ("Linha: %d m"):format(mine.len), 0xFFB0E0FF)
        local bw = 220
        bar(sw / 2 - bw - 20, 40, bw, mine.hp / 100, 0xFF3CB43C, ("Sua linha  %d"):format(math.max(mine.hp, 0)))
        if battle then
            local rk = battle.spot.kite
            bar(sw / 2 + 20, 40, bw, rk.hp / 100, 0xFFDC3C3C, ("Linha de %s  %d"):format(battle.spot.name, math.max(rk.hp, 0)))
            label3d(rk.pos, "RIVAL", 0xFFFF6666); label3d(mine.pos, "VOCE", 0xFF66CCFF)
            if battle.touch and now - battle.touch < 0.2 then txt(sw / 2 - 50, 64, "LINHAS SE CORTANDO!", 0xFFFFD700) end
        end
    end
    for _, s in ipairs(spots) do
        if s.ped and s.kite and not s.kite.cut and not (battle and battle.spot == s) then
            local x, y, z = getCharCoordinates(s.ped)
            label3d({ x, y, z + 1.2 }, s.name, 0xFFFFFFFF)
        end
    end
end

local function showControls()
    local k = ini.keys
    printHelpString(("~y~PIPA~w~: ~y~%s~w~ pega a pipa na mao. Segure ~y~%s~w~ para soltar linha (ela sobe) e ~y~%s~w~ para recolher. ~y~%s~w~ da um chicote.~n~"
        .. "A pipa segue a direcao da camera. ~y~%s~w~ desafia um jogador: cruze sua linha na dele e corte primeiro!~n~Digite ~y~PIPA~w~ para rever esta ajuda."):format(
        k.launch:upper(), k.give:upper(), k.pull:upper(), k.whip:upper(), k.challenge:upper()))
end

local function groundZ(x, y, zref)
    for _, up in ipairs({ 6, 25 }) do
        local gz = getGroundZFor3dCoord(x, y, zref + up) -- devolve so a altura; 0 = colisao nao carregada
        if gz ~= 0 and math.abs(gz - zref) < 12 then return gz end
    end
end

local function loadAnim(block)
    if hasAnimationLoaded(block) then return true end
    requestAnimation(block)
    local t = os.clock()
    while not hasAnimationLoaded(block) and os.clock() - t < 2 do wait(0) end
    return hasAnimationLoaded(block)
end

local function playAnim(ped, a)
    if not loadAnim(a[1]) then
        if a.fb then return playAnim(ped, a.fb) end
        print("PipaSA: bloco de animacao nao carregou: " .. a[1]); return
    end
    local ok, err = pcall(taskPlayAnim, ped, a[2], a[1], 4.0, not a.once, false, false, false, -1)
    if not ok then print("PipaSA: taskPlayAnim " .. a[2] .. ": " .. tostring(err)) end
end

local function headingTo(x1, y1, x2, y2) return math.deg(math.atan2(y2 - y1, x2 - x1)) - 90 end

local function makePed(s, dx, dy, heading, female)
    local pool = female and SKINS_F or SKINS
    local skin = pool[math.random(#pool)]
    requestModel(skin); loadAllModelsNow()
    local x, y = s.x + dx, s.y + dy
    local p = createChar(4, skin, x, y, (groundZ(x, y, s.gz) or s.gz) + 1)
    setCharHeading(p, heading)
    setCharStayInSamePlace(p, true)
    return p
end

local function spawnScene(s)
    local sc = SCENES[s.name] or SCENES.DEFAULT
    s.props, s.amb = {}, {}
    for _, p in ipairs(sc.props) do
        requestModel(p[1]); loadAllModelsNow()
        local x, y = s.x + p[2], s.y + p[3]
        local o = createObject(p[1], x, y, (groundZ(x, y, s.gz) or s.gz) + p[4])
        setObjectHeading(o, p[5])
        s.props[#s.props + 1] = o
    end
    for _, a in ipairs(sc.actors) do
        local kind, amb = a[1], { kind = a[1], next = 0 }
        if kind == "sit" or kind == "sitw" then
            amb.ped = makePed(s, a[2], a[3], a[4], kind == "sitw"); amb.anim = ANIM[kind]
        elseif kind == "sitg" then
            amb.ped = makePed(s, a[2], a[3], a[4], true); amb.anim = ANIM.sitg
        elseif kind == "talk" then
            amb.ped = makePed(s, a[2], a[3], headingTo(a[2], a[3], a[4], a[5]), math.random() < 0.3)
            amb.anim = math.random() < 0.5 and ANIM.talkA or ANIM.talkB
        elseif kind == "kite" then
            amb.ped = makePed(s, a[2], a[3], math.random(360), false); amb.anim = PED_KITE_ANIMS[math.random(#PED_KITE_ANIMS)]
            amb.kite = newKite(amb.ped, CFG.kite_models[math.random(#CFG.kite_models)], 28 + math.random(20), amb.anim.hand)
            amb.kite.steer = (math.random() - 0.5) * 1.6
        end
        if amb.ped then playAnim(amb.ped, amb.anim); s.amb[#s.amb + 1] = amb end
    end
end

local function despawnScene(s)
    for _, a in ipairs(s.amb or {}) do
        destroyKite(a.kite); if a.ped then deleteChar(a.ped) end
    end
    for _, o in ipairs(s.props or {}) do deleteObject(o) end
    s.amb, s.props = nil, nil
end

local function spawnSpot(s, now)
    s.gz = groundZ(s.x, s.y, select(3, getCharCoordinates(PLAYER_PED)))
    if not s.gz then s.retry = now + 1; return end -- colisao ainda nao carregou: tenta de novo
    local z = s.gz
    local skin = SKINS[math.random(#SKINS)]
    requestModel(skin); loadAllModelsNow()
    s.ped = createChar(4, skin, s.x, s.y, z + 1)
    s.anim = PED_KITE_ANIMS[math.random(#PED_KITE_ANIMS)]
    setCharStayInSamePlace(s.ped, true); playAnim(s.ped, s.anim)
    local k = newKite(s.ped, CFG.kite_models[math.random(#CFG.kite_models)], 22 + math.random(10), s.anim.hand)
    k.steer = (math.random() - 0.5) * 1.2
    k.phase = math.random() * 6
    s.kite = k
    spawnScene(s)
end

local function despawnSpot(s)
    despawnScene(s)
    if s.kite then destroyKite(s.kite); s.kite = nil end
    if s.ped then deleteChar(s.ped); s.ped = nil end
end

local function endBattle(won)
    local s = battle.spot
    if won then
        points = points + CFG.points; savePoints(); addScore(PLAYER_HANDLE, CFG.reward)
        printStringNow(("~g~PIPA CORTADA! +$%d  +%d pts  (%s)"):format(CFG.reward, CFG.points, rank()), 4000)
        s.kite.cut = true; s.cd = os.clock() + CFG.respawn_s
        cjForce = { a = ANIM.cheer2, t = os.clock() + 2.5 }
    else
        printStringNow("~r~CORTARAM SUA PIPA!", 3000)
        mine.cut = true
        cjForce = { a = ANIM.lose, t = os.clock() + 2.5 }
    end
    battle = nil
end

function main()
    while not isPlayerPlaying(PLAYER_HANDLE) do wait(500) end
    math.randomseed(os.time())
    font = renderCreateFont("Arial", 11, 5)
    sw, sh = getScreenResolution()
    for _, v in ipairs(SPOTS) do
        local s = { name = v[1], x = v[2], y = v[3], z = v[4], diff = v[5], cd = 0 }
        s.blip = addSpriteBlipForCoord(s.x, s.y, s.z, BLIP_SPRITE)
        spots[#spots + 1] = s
    end
    loadPoints()
    local last = os.clock()
    local cjCur, cjCheck, stuckSince = nil, 0, nil
    local idleSince, typed, infoUntil, wasInfo, ctrlCool, lastWant = nil, "", 0, false, 0, nil

    while true do
        wait(0)
        local now = os.clock()
        local dt = math.min(now - last, 0.1); last = now

        if now > wind.next then
            wind.level = math.random(3); wind.ang = rad(math.random(360)); wind.next = now + 60 + math.random(40)
        end

        local px, py, pz = getCharCoordinates(PLAYER_PED)
        local inCar = isCharInAnyCar(PLAYER_PED)

        if wasKeyPressed(KEY.launch) then
            if mine and not mine.cut then destroyKite(mine); mine = nil; battle = nil
            elseif not inCar then
                mine = newKite(PLAYER_PED, CFG.kite_models[1], 2.5, 24); mine.held = true
                printStringNow(("~y~Pipa na mao. ~w~Segure ~y~%s~w~ para soltar linha e ela sobe"):format(ini.keys.give:upper()), 4000)
            end
        end
        if mine and (inCar or isCharDead(PLAYER_PED)) then destroyKite(mine); mine = nil; battle = nil end

        -- spots: streaming dos NPCs
        local nearest, nd, nearAny, nearAnyD
        for _, s in ipairs(spots) do
            local d = math.sqrt((px - s.x) ^ 2 + (py - s.y) ^ 2)
            if d < 140 and now > (s.req or 0) then s.req = now + 2; requestCollision(s.x, s.y) end
            if not s.ped and d < CFG.spawn_r and now > s.cd and now > (s.retry or 0) then spawnSpot(s, now)
            elseif s.ped and (d > CFG.despawn_r or isCharDead(s.ped)) and not (battle and battle.spot == s) then despawnSpot(s) end
            if s.ped and s.kite and not s.kite.cut then
                local pd = math.sqrt((px - s.x) ^ 2 + (py - s.y) ^ 2)
                if pd < CFG.challenge_r and (not nd or pd < nd) then nearest, nd = s, pd end
            end
            local d2 = math.sqrt((px - s.x) ^ 2 + (py - s.y) ^ 2)
            if not nearAny or d2 < nearAnyD then nearAny, nearAnyD = s, d2 end
        end
        for _, s in ipairs(spots) do
            if s.kite and s.kite.cut and not updateKite(s.kite, dt, now) then s.kite = nil end
            if s.ped and not s.kite and now > s.cd then despawnSpot(s) end
        end

        -- controles
        if mine and not mine.cut then
            local pull = isKeyDown(KEY.pull)
            local give = isKeyDown(KEY.give)
            if mine.held then
                if give then mine.held = false; mine.len = 3 end -- so sobe depois de soltar linha
            else
                if give then mine.len = math.min(mine.len + 8 * dt, 70) end
                if pull then
                    mine.len = math.max(mine.len - 8 * dt, 2.5)
                    if mine.len <= 2.6 then mine.held = true end -- recolheu tudo: volta para a mao
                end
            end
            mine.act = ((pull or give) and not mine.held) and 1 or 0
            if wasKeyPressed(KEY.whip) and now > mine.whipReady then
                mine.whipUntil, mine.whipReady = now + 1.2, now + 6
                printStringNow("~y~CHICOTE!", 800)
            end
        end
        if nearest and not battle and not inCar and wasKeyPressed(KEY.challenge) then
            if not mine then mine = newKite(PLAYER_PED, CFG.kite_models[1], 2.5, 24) end
            if not mine.cut then
                mine.held = false; mine.len = math.max(mine.len, 25)
                battle = { spot = nearest, ai = now + 1 }
                printStringNow("~r~BATALHA! ~w~cruze sua linha na do rival e corte primeiro!", 4000)
            end
        end

        -- infos: perto dos eventos ou ao digitar "pipa"
        for k = 0x41, 0x5A do
            if wasKeyPressed(k) then typed = (typed .. string.char(k)):sub(-4) end
        end
        if typed == "PIPA" then typed = ""; infoUntil = now + 25; showControls() end
        local info = (nearAnyD and nearAnyD < CFG.info_r) or now < infoUntil
        if info and not wasInfo and now > ctrlCool then ctrlCool = now + 120; showControls() end
        wasInfo = info
        local want = nearest and not battle and nearest or nil
        if want ~= lastWant then
            lastWant = want
            if want then printHelpString(("Pressione ~y~%s~w~ para desafiar o jogador de %s para uma batalha de pipas."):format(ini.keys.challenge:upper(), want.name)) end
        end

        -- IA do rival
        if battle then
            local rk, d = battle.spot.kite, battle.spot.diff
            if now > battle.ai then
                battle.ai = now + 0.5 + math.random() * 1.5
                rk.act = math.random() < 0.35 + 0.15 * d and 1 or 0
                if mine and not mine.cut and math.random() < 0.3 + 0.2 * d then
                    rk.steer = clamp(rk.steer + (math.random() - 0.5) * 0.6, -1, 1)
                end
                if now > rk.whipReady and math.random() < 0.1 * d then rk.whipUntil, rk.whipReady = now + 1.2, now + 8 end
            end
            if not mine or mine.cut then battle = nil
            elseif not battle.spot.ped or isCharDead(battle.spot.ped) then battle = nil end
        end

        -- atualiza pipas
        local aim
        if mine and not mine.cut then
            mine.cy, mine.ce = camAim()
            if battle then
                local a, b = anchor(mine), anchor(battle.spot.kite)
                aim = { (a[1] + b[1]) / 2, (a[2] + b[2]) / 2 }
            end
            updateKite(mine, dt, now, aim)
        elseif mine and mine.cut and not updateKite(mine, dt, now) then mine = nil end
        for _, s in ipairs(spots) do
            if s.kite and not s.kite.cut then
                updateKite(s.kite, dt, now, battle and battle.spot == s and aim or nil)
                if s.ped and doesCharExist(s.ped) then
                    setCharHeading(s.ped, math.deg(math.atan2(s.kite.pos[2] - s.y, s.kite.pos[1] - s.x)) - 90)
                end
            end
        end

        -- cenas ambientes: pipas solitarias, mantem animacoes vivas
        for _, sp in ipairs(spots) do
            for _, a in ipairs(sp.amb or {}) do
                if a.kite then updateKite(a.kite, dt, now) end
                if now > a.next and a.ped and doesCharExist(a.ped) and not isCharDead(a.ped) then
                    a.next = now + 3
                    if a.kite then
                        local ax, ay = getCharCoordinates(a.ped)
                        setCharHeading(a.ped, headingTo(ax, ay, a.kite.pos[1], a.kite.pos[2]))
                    end
                    if not isCharPlayingAnim(a.ped, a.anim[2]) then playAnim(a.ped, a.anim) end
                end
            end
        end

        -- CJ: animacao conforme a acao. Segurando a pipa usa a de carregar caixa (anda normalmente); as demais so parado,
        -- e qualquer entrada de movimento (WASD/analogico) cancela a animacao para o CJ nunca ficar travado
        local spd = getCharSpeed(PLAYER_PED)
        local mx, my = getPositionOfAnalogueSticks(0)
        local moving = math.abs(mx) > 8 or math.abs(my) > 8
        local want
        if (mine or cjForce) and not inCar and not isCharDead(PLAYER_PED) then
            if cjForce and now < cjForce.t and not moving then want = cjForce.a
            elseif mine and not mine.cut then
                if mine.held then want = nil -- na mao: sem animacao (a de carregar caixa ficou ruim)
                elseif not moving then
                    if now < mine.whipUntil then want = ANIM.whip
                    elseif isKeyDown(KEY.pull) then want = ANIM.pull
                    elseif isKeyDown(KEY.give) then want = ANIM.give
                    elseif spd < 0.05 then
                        idleSince = idleSince or now
                        if now - idleSince > 1 then want = ANIM.fly end
                    end
                end
            end
        end
        if moving or spd >= 0.05 then idleSince = nil end
        -- rede de seguranca: stick/WASD pressionado mas o CJ nao anda (animacao prendendo): solta a animacao
        if moving and spd < 0.1 then stuckSince = stuckSince or now else stuckSince = nil end
        if stuckSince and now - stuckSince > 0.4 then want = nil end
        if want and (want ~= cjCur or (now > cjCheck and not isCharPlayingAnim(PLAYER_PED, cjCur[2]) and not want.once)) then
            playAnim(PLAYER_PED, want); cjCur = want
        elseif not want and cjCur then
            clearCharTasks(PLAYER_PED); cjCur = nil
        end
        cjCheck = now + 1

        -- o corpo do CJ acompanha a pipa: vira suavemente para ela enquanto ele esta parado
        if mine and not mine.cut and not mine.held and not moving and spd < 0.3 and not inCar and not isCharDead(PLAYER_PED) then
            local dx, dy = mine.pos[1] - px, mine.pos[2] - py
            if dx * dx + dy * dy > 4 then
                local target = math.deg(math.atan2(dy, dx)) - 90
                local hd = getCharHeading(PLAYER_PED)
                setCharHeading(PLAYER_PED, hd + ((target - hd + 180) % 360 - 180) * clamp(dt * 6, 0, 1))
            end
        end

        -- dano
        if battle and mine and not mine.cut then
            local rk = battle.spot.kite
            local a1, a2 = anchor(mine), anchor(rk)
            if segDist(a1, mine.pos, a2, rk.pos) < CFG.contact then
                local wf = CFG.wind_factor[wind.level]
                local function saw(k) return 0.35 + 0.9 * k.act + (now < k.whipUntil and 2.5 or 0) end
                rk.hp = rk.hp - CFG.dmg_base * saw(mine) * wf / (1 + 0.15 * battle.spot.diff) * dt
                mine.hp = mine.hp - CFG.dmg_base * saw(rk) * wf * (0.8 + 0.2 * battle.spot.diff) / CFG.line_res * dt
                battle.touch = now
            end
            if rk.hp <= 0 then endBattle(true) elseif mine.hp <= 0 then endBattle(false) end
        end

        -- render
        if mine then drawKiteLine(mine, 0xFF66E0FF) end
        for _, sp in ipairs(spots) do
            for _, a in ipairs(sp.amb or {}) do if a.kite then drawKiteLine(a.kite, 0xFFFFFFFF) end end
        end
        for _, s in ipairs(spots) do
            if s.kite then drawKiteLine(s.kite, battle and battle.spot == s and 0xFFFF6666 or 0xFFFFFFFF) end
        end
        drawHud(now, info)
    end
end

function onScriptTerminate(s)
    if s ~= thisScript() then return end
    destroyKite(mine)
    for _, sp in ipairs(spots) do despawnSpot(sp); if sp.blip then removeBlip(sp.blip) end end
end
