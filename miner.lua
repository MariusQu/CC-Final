-- ============================================================
-- MINER V7.1
-- CC:Tweaked 1.113.1
-- Minecraft 1.20.x
--
-- AUFBAU:
--
-- [KISTE] [TURTLE] ---> ABBAUBEREICH
--
-- Die Turtle steht direkt vor der Kiste.
-- Die Kiste ist HINTER der Turtle.
-- Beim Start schaut die Turtle vom Abbaubereich weg.
--
-- Beispiel:
--
--   KISTE | TURTLE | -> -> -> MINING
--
-- ============================================================
--
-- FUNKTIONEN
--
-- * 2 Block hohe Ebenen
-- * danach 2 Bloecke nach oben
-- * Fackeln NUR auf der ersten Ebene
-- * Fackeln werden HINTER der Turtle gesetzt
-- * Fackeln werden NICHT ausgeladen
-- * maximal 16 Fackeln werden behalten
-- * Eimer werden behalten
-- * Fuel wird automatisch nachgeladen
-- * Inventar wird automatisch ausgeladen
-- * Wasser/Lava werden mit Eimern aufgenommen
-- * Position und Richtung werden gespeichert
-- * Rueckkehr zur Kiste
-- * exakte Rueckkehr zum Arbeitsplatz
-- * Neustart nach Serverrestart moeglich
--
-- ============================================================


local VERSION = 71
local STATE_FILE = "miner_state"

local args = {...}
local command = args[1]


-- ============================================================
-- KONFIGURATION
-- ============================================================

local MIN_FUEL = 500
local FUEL_BUFFER = 100

local MIN_TORCHES = 4
local MAX_TORCHES = 16

local MIN_BUCKETS = 2
local MAX_BUCKETS = 4

local MIN_FREE_SLOTS = 2


-- ============================================================
-- STATE
-- ============================================================

local state = nil


-- ============================================================
-- HILFE
-- ============================================================

local function usage()

    print("")
    print("================================")
    print("          MINER V7.1")
    print("================================")
    print("")
    print("Neuer Auftrag:")
    print("")
    print("  miner new <breite> <tiefe> <hoehe> [fackelabstand]")
    print("")
    print("Beispiel:")
    print("")
    print("  miner new 5 5 4 6")
    print("")
    print("Status:")
    print("")
    print("  miner status")
    print("")
    print("Reset:")
    print("")
    print("  miner reset")
    print("")
end


-- ============================================================
-- SPEICHERN
-- ============================================================

local function save()

    local file, err = fs.open(STATE_FILE, "w")

    if not file then
        error(
            "Kann miner_state nicht speichern: "
            .. tostring(err)
        )
    end

    file.write(textutils.serialize(state))
    file.close()

end


-- ============================================================
-- LADEN
-- ============================================================

local function loadState()

    if not fs.exists(STATE_FILE) then
        return nil
    end

    local file, err = fs.open(STATE_FILE, "r")

    if not file then
        error(
            "Kann miner_state nicht lesen: "
            .. tostring(err)
        )
    end

    local content = file.readAll()
    file.close()

    local data = textutils.unserialize(content)

    if not data then
        error(
            "miner_state ist beschaedigt."
        )
    end

    if data.version ~= VERSION then

        print("")
        print("Alter miner_state gefunden.")
        print("")
        print("Bitte einmal ausfuehren:")
        print("")
        print("  miner reset")
        print("")
        print("Danach neuen Auftrag starten.")
        print("")

        return nil
    end

    return data

end


-- ============================================================
-- INVENTAR
-- ============================================================

local function countItem(name)

    local total = 0

    for slot = 1, 16 do

        local item =
            turtle.getItemDetail(slot)

        if item and item.name == name then
            total = total + item.count
        end

    end

    return total
end


local function findItem(name)

    for slot = 1, 16 do

        local item =
            turtle.getItemDetail(slot)

        if item and item.name == name then
            return slot
        end

    end

    return nil
end


local function freeSlots()

    local free = 0

    for slot = 1, 16 do

        if turtle.getItemCount(slot) == 0 then
            free = free + 1
        end

    end

    return free
end


-- ============================================================
-- POSITION
--
-- x = Entfernung in Richtung Abbaubereich
-- z = seitliche Position
-- y = Hoehe
--
-- dir:
-- 0 = vorne / +x
-- 1 = rechts / +z
-- 2 = hinten / -x
-- 3 = links / -z
-- ============================================================

local function updateForward()

    if state.dir == 0 then
        state.x = state.x + 1

    elseif state.dir == 1 then
        state.z = state.z + 1

    elseif state.dir == 2 then
        state.x = state.x - 1

    elseif state.dir == 3 then
        state.z = state.z - 1
    end

end


local function turnRight()

    turtle.turnRight()

    state.dir =
        (state.dir + 1) % 4

    save()

end


local function turnLeft()

    turtle.turnLeft()

    state.dir =
        (state.dir + 3) % 4

    save()

end


local function face(direction)

    local diff =
        (direction - state.dir) % 4

    if diff == 1 then

        turnRight()

    elseif diff == 2 then

        turnRight()
        turnRight()

    elseif diff == 3 then

        turnLeft()

    end

end


-- ============================================================
-- FUEL
-- ============================================================

local function refuelInventory()

    if turtle.getFuelLevel() == "unlimited" then
        return
    end

    for slot = 1, 16 do

        local item =
            turtle.getItemDetail(slot)

        if item then

            if item.name == "minecraft:coal"
            or item.name == "minecraft:charcoal"
            or item.name == "minecraft:coal_block" then

                turtle.select(slot)

                turtle.refuel()

            end

        end

    end

    turtle.select(1)

end


local function refuelEnough()

    if turtle.getFuelLevel() == "unlimited" then
        return
    end

    refuelInventory()

    if turtle.getFuelLevel() >= MIN_FUEL then
        return
    end

    -- Der eigentliche Kisten-Service wird weiter unten
    -- durch service() erledigt.
end


-- ============================================================
-- FLUESSIGKEITEN
-- ============================================================

local function isFluid(data)

    if not data then
        return false
    end

    if not data.name then
        return false
    end

    return
        data.name == "minecraft:water"
        or
        data.name == "minecraft:lava"

end


local function getBucket()

    local slot =
        findItem("minecraft:bucket")

    if not slot then
        return nil
    end

    return slot
end


local function collectFront()

    local slot = getBucket()

    if not slot then
        return false
    end

    local old =
        turtle.getSelectedSlot()

    turtle.select(slot)

    local ok =
        turtle.place()

    turtle.select(old)

    return ok
end


local function collectUp()

    local slot = getBucket()

    if not slot then
        return false
    end

    local old =
        turtle.getSelectedSlot()

    turtle.select(slot)

    local ok =
        turtle.placeUp()

    turtle.select(old)

    return ok
end


local function collectDown()

    local slot = getBucket()

    if not slot then
        return false
    end

    local old =
        turtle.getSelectedSlot()

    turtle.select(slot)

    local ok =
        turtle.placeDown()

    turtle.select(old)

    return ok
end


-- ============================================================
-- KISTE
-- ============================================================

local function checkChest()

    local ok, data =
        turtle.inspect()

    if not ok then

        error(
            "Hinter der Turtle wurde keine Kiste gefunden."
        )

    end

    local name =
        string.lower(data.name or "")

    if not string.find(name, "chest", 1, true) then

        error(
            "Hinter der Turtle steht keine Kiste."
        )

    end

end


-- ============================================================
-- SERVICE:
--
-- Turtle geht zur Startposition.
-- Dort steht die Kiste HINTER ihr.
-- ============================================================

local function goHome()

    -- y
    while state.y > 0 do

        if turtle.down() then
            state.y = state.y - 1
            save()
        else

            local ok, data =
                turtle.inspectDown()

            if ok and isFluid(data) then

                if not collectDown() then
                    error("Fluessigkeit unter der Turtle.")
                end

            else

                turtle.digDown()

            end
        end

    end


    -- x
    if state.x > 0 then

        face(2)

        while state.x > 0 do

            if turtle.forward() then

                state.x =
                    state.x - 1

                save()

            else

                local ok, data =
                    turtle.inspect()

                if ok and isFluid(data) then

                    if not collectFront() then
                        error("Fluessigkeit auf dem Rueckweg.")
                    end

                else

                    turtle.dig()

                end

            end

        end

    elseif state.x < 0 then

        face(0)

        while state.x < 0 do

            if turtle.forward() then

                state.x =
                    state.x + 1

                save()

            else

                turtle.dig()

            end

        end

    end


    -- z
    if state.z > 0 then

        face(3)

        while state.z > 0 do

            if turtle.forward() then

                state.z =
                    state.z - 1

                save()

            else

                turtle.dig()

            end

        end

    elseif state.z < 0 then

        face(1)

        while state.z < 0 do

            if turtle.forward() then

                state.z =
                    state.z + 1

                save()

            else

                turtle.dig()

            end

        end

    end

end


-- ============================================================
-- ZUR POSITION
-- ============================================================

local function goTo(x, y, z)

    -- Hoehe
    while state.y < y do

        if turtle.up() then

            state.y =
                state.y + 1

            save()

        else

            local ok, data =
                turtle.inspectUp()

            if ok and isFluid(data) then

                collectUp()

            else

                turtle.digUp()

            end

        end

    end


    while state.y > y do

        if turtle.down() then

            state.y =
                state.y - 1

            save()

        else

            local ok, data =
                turtle.inspectDown()

            if ok and isFluid(data) then

                collectDown()

            else

                turtle.digDown()

            end

        end

    end


    -- X
    if state.x < x then

        face(0)

        while state.x < x do

            if turtle.forward() then

                state.x =
                    state.x + 1

                save()

            else

                turtle.dig()

            end

        end

    elseif state.x > x then

        face(2)

        while state.x > x do

            if turtle.forward() then

                state.x =
                    state.x - 1

                save()

            else

                turtle.dig()

            end

        end

    end


    -- Z
    if state.z < z then

        face(1)

        while state.z < z do

            if turtle.forward() then

                state.z =
                    state.z + 1

                save()

            else

                turtle.dig()

            end

        end

    elseif state.z > z then

        face(3)

        while state.z > z do

            if turtle.forward() then

                state.z =
                    state.z - 1

                save()

            else

                turtle.dig()

            end

        end

    end

end


-- ============================================================
-- AUS KISTE HOLEN
--
-- Turtle steht so, dass die Kiste VOR ihr ist.
-- ============================================================

local function suckItem(names, amount)

    for _, wanted in ipairs(names) do

        local old =
            turtle.getSelectedSlot()

        for slot = 1, 16 do

            local item =
                turtle.getItemDetail(slot)

            if not item then

                turtle.select(slot)

                local ok =
                    turtle.suck(amount)

                turtle.select(old)

                if ok then
                    return true
                end

            end

        end

    end

    return false
end


-- ============================================================
-- SERVICE
-- ============================================================

local function service()

    print("")
    print("------------------------------")
    print("Zur Kiste...")
    print("------------------------------")


    -- Aktuelle Position speichern.
    state.returnX = state.x
    state.returnY = state.y
    state.returnZ = state.z
    state.returnDir = state.dir
    state.phase = "service"

    save()


    -- Nach Hause.
    goHome()


    -- Kiste ist HINTER der Turtle.
    -- Wir drehen uns zur Kiste.
    face(2)


    checkChest()


    -- ========================================================
    -- ALLES AUSLADEN
    --
    -- NICHT:
    -- * Fackeln
    -- * Eimer
    -- * Fuel
    -- ========================================================

    for slot = 1, 16 do

        local item =
            turtle.getItemDetail(slot)

        if item then

            local keep = false

            if item.name == "minecraft:torch" then
                keep = true
            end

            if item.name == "minecraft:bucket" then
                keep = true
            end

            if item.name == "minecraft:coal"
            or item.name == "minecraft:charcoal"
            or item.name == "minecraft:coal_block" then

                keep = true
            end


            if not keep then

                turtle.select(slot)
                turtle.drop()

            end

        end

    end


    -- ========================================================
    -- FACKELN
    -- ========================================================

    local torches =
        countItem("minecraft:torch")


    if torches < MIN_TORCHES then

        turtle.select(1)

        turtle.suck(
            MAX_TORCHES - torches
        )

    end


    -- ========================================================
    -- EIMER
    -- ========================================================

    local buckets =
        countItem("minecraft:bucket")


    if buckets < MIN_BUCKETS then

        turtle.select(1)

        turtle.suck(
            MAX_BUCKETS - buckets
        )

    end


    -- ========================================================
    -- FUEL
    -- ========================================================

    if turtle.getFuelLevel() ~= "unlimited"
    and turtle.getFuelLevel() < MIN_FUEL then

        for i = 1, 16 do

            turtle.select(i)

            local item =
                turtle.getItemDetail(i)

            if item then

                if item.name == "minecraft:coal"
                or item.name == "minecraft:charcoal"
                or item.name == "minecraft:coal_block" then

                    turtle.refuel()

                end

            end

        end

    end


    turtle.select(1)


    -- ========================================================
    -- ZUR ARBEIT
    -- ========================================================

    print("Rueckkehr zum Arbeitsplatz...")


    goTo(
        state.returnX,
        state.returnY,
        state.returnZ
    )


    face(state.returnDir)


    state.x = state.returnX
    state.y = state.returnY
    state.z = state.returnZ
    state.dir = state.returnDir

    state.returnX = nil
    state.returnY = nil
    state.returnZ = nil
    state.returnDir = nil

    state.phase = "mining"

    save()


    print("Arbeitsplatz erreicht.")
    print("")

end


-- ============================================================
-- BEWEGUNG VORWAERTS
-- ============================================================

local function forward()

    if turtle.getFuelLevel() ~= "unlimited"
    and turtle.getFuelLevel() < FUEL_BUFFER then

        service()

    end


    while true do

        if turtle.forward() then

            updateForward()
            save()

            return true

        end


        local ok, data =
            turtle.inspect()

        if ok and isFluid(data) then

            if not collectFront() then

                service()

            end

        else

            turtle.dig()

        end


        sleep(0.1)

    end

end


-- ============================================================
-- HOCH
-- ============================================================

local function up()

    while true do

        if turtle.up() then

            state.y =
                state.y + 1

            save()

            return true

        end


        local ok, data =
            turtle.inspectUp()

        if ok and isFluid(data) then

            if not collectUp() then
                service()
            end

        else

            turtle.digUp()

        end


        sleep(0.1)

    end

end


-- ============================================================
-- RUNTER
-- ============================================================

local function down()

    while true do

        if turtle.down() then

            state.y =
                state.y - 1

            save()

            return true

        end


        local ok, data =
            turtle.inspectDown()

        if ok and isFluid(data) then

            if not collectDown() then
                service()
            end

        else

            turtle.digDown()

        end


        sleep(0.1)

    end

end


-- ============================================================
-- FACKEL
--
-- NUR AUF DER ERSTEN 2-BLOCK-EBENE.
--
-- Also:
--
-- Y = 0 oder Y = 1 -> Fackeln
-- Y >= 2             -> keine Fackeln
--
-- Die Fackel wird HINTER der Turtle platziert.
-- ============================================================

local function torch()

    if state.torchDistance <= 0 then
        return
    end


    if state.y >= 2 then
        return
    end


    state.torchCounter =
        state.torchCounter + 1


    if state.torchCounter <
        state.torchDistance then

        save()
        return
    end


    local slot =
        findItem("minecraft:torch")


    if not slot then

        service()

        slot =
            findItem("minecraft:torch")

    end


    if not slot then

        error(
            "Keine Fackeln vorhanden."
        )

    end


    local oldSlot =
        turtle.getSelectedSlot()

    local oldDir =
        state.dir


    -- Hinter uns.
    face(
        (oldDir + 2) % 4
    )


    turtle.select(slot)


    -- Erst direkt hinter uns setzen.
    local placed =
        turtle.place()


    -- Wieder nach vorne.
    face(oldDir)


    turtle.select(oldSlot)


    if placed then

        state.torchCounter = 0

    else

        -- Falls direkt hinter der Turtle
        -- kein Platz ist, versuchen wir
        -- NICHT irgendwo anders eine Fackel
        -- zu setzen.
        --
        -- Dadurch bleiben die Fackeln wirklich
        -- an der Rueckwand.

    end


    save()

end


-- ============================================================
-- EINEN BLOCK VOR DER TURTLE ABBAUEN
-- ============================================================

local function digFront()

    local ok, data =
        turtle.inspect()


    if ok then

        if isFluid(data) then

            if not collectFront() then
                service()
            end

        else

            turtle.dig()

        end

    end

end


-- ============================================================
-- BLOCK OBEN ABBauen
-- ============================================================

local function digAbove()

    if state.y + 1 >= state.height then
        return
    end


    local ok, data =
        turtle.inspectUp()


    if ok then

        if isFluid(data) then

            if not collectUp() then
                service()
            end

        else

            turtle.digUp()

        end

    end

end


-- ============================================================
-- INVENTAR PRUEFEN
-- ============================================================

local function inventoryCheck()

    if freeSlots() <= MIN_FREE_SLOTS then

        service()

    end

end


-- ============================================================
-- EINE POSITION ABBauen
-- ============================================================

local function minePosition()

    inventoryCheck()

    digFront()

    digAbove()

    torch()

    save()

end


-- ============================================================
-- REIHE ABBauen
--
-- Wir stehen am Anfang der Reihe.
--
-- Fuer jeden Block:
--
-- 1. Block vorne abbauen
-- 2. Block oben abbauen
-- 3. Fackel setzen
-- 4. zur naechsten Position laufen
--
-- Dadurch wird wirklich die komplette Reihe abgebaut.
-- ============================================================

local function mineRow(row, reverse)

    if reverse then

        face(2)

    else

        face(0)

    end


    for col = 1, state.width do

        state.currentRow = row
        state.currentCol = col

        save()


        minePosition()


        -- Nicht hinter den Raum laufen.
        if col < state.width then

            forward()

        end

    end

end


-- ============================================================
-- ZUR NAECHSTEN REIHE
-- ============================================================

local function nextRow(reverse)

    if reverse then

        -- Wir schauen nach hinten.
        -- Rechts drehen bringt uns seitlich.
        turnLeft()

        forward()

        turnLeft()

    else

        -- Wir schauen nach vorne.
        turnRight()

        forward()

        turnRight()

    end

    save()

end


-- ============================================================
-- EINEN KOMPLETTEN 2-BLOCK-LAYER ABBauen
-- ============================================================

local function mineLayer(layer)

    state.layer = layer
    state.currentRow = 1
    state.currentCol = 1

    save()


    for row = 1, state.depth do

        local reverse =
            (row % 2 == 0)


        mineRow(
            row,
            reverse
        )


        if row < state.depth then

            nextRow(reverse)

        end

    end

end


-- ============================================================
-- STATUS
-- ============================================================

local function status()

    state = loadState()


    if not state then

        print("")
        print("Kein Auftrag gespeichert.")
        print("")

        return
    end


    print("")
    print("==============================")
    print("          STATUS")
    print("==============================")
    print("")

    print(
        "Raum: "
        .. state.width
        .. " x "
        .. state.depth
        .. " x "
        .. state.height
    )

    print(
        "Position: "
        .. state.x
        .. ", "
        .. state.y
        .. ", "
        .. state.z
    )

    print(
        "Richtung: "
        .. state.dir
    )

    print(
        "Ebene: "
        .. state.layer
        .. "/"
        .. state.layers
    )

    print(
        "Reihe: "
        .. state.currentRow
        .. "/"
        .. state.depth
    )

    print(
        "Spalte: "
        .. state.currentCol
        .. "/"
        .. state.width
    )

    print(
        "Fackeln: "
        .. countItem("minecraft:torch")
    )

    print(
        "Eimer: "
        .. countItem("minecraft:bucket")
    )

    print(
        "Fuel: "
        .. tostring(turtle.getFuelLevel())
    )

    print(
        "Phase: "
        .. tostring(state.phase)
    )

    print("")

end


-- ============================================================
-- RESET
-- ============================================================

if command == "reset" then

    if fs.exists(STATE_FILE) then

        fs.delete(STATE_FILE)

        print("")
        print("miner_state wurde geloescht.")
        print("")

    else

        print("")
        print("Kein miner_state vorhanden.")
        print("")

    end

    return

end


-- ============================================================
-- STATUS
-- ============================================================

if command == "status" then

    status()

    return

end


-- ============================================================
-- NEUER AUFTRAG
-- ============================================================

if command == "new" then

    local width =
        tonumber(args[2])

    local depth =
        tonumber(args[3])

    local height =
        tonumber(args[4])

    local torchDistance =
        tonumber(args[5]) or 6


    if not width
    or not depth
    or not height then

        usage()
        return

    end


    if width < 1
    or depth < 1
    or height < 1 then

        print("")
        print("Alle Werte muessen mindestens 1 sein.")
        print("")

        return

    end


    if fs.exists(STATE_FILE) then

        fs.delete(STATE_FILE)

    end


    local layers =
        math.ceil(height / 2)


    state = {

        version = VERSION,

        width = width,
        depth = depth,
        height = height,

        layers = layers,

        layer = 1,
        currentRow = 1,
        currentCol = 1,

        torchDistance =
            torchDistance,

        torchCounter = 0,

        x = 0,
        y = 0,
        z = 0,

        -- Startausrichtung:
        -- 0 = vom Kistenplatz in den Abbaubereich
        dir = 0,

        phase = "mining"

    }


    save()


    print("")
    print("==============================")
    print("       MINER V7.1 START")
    print("==============================")
    print("")

    print(
        "Raum: "
        .. width
        .. " x "
        .. depth
        .. " x "
        .. height
    )

    print(
        "Ebenen: "
        .. layers
    )

    print(
        "Fackelabstand: "
        .. torchDistance
    )

    print("")

    print(
        "Starte Abbau..."
    )

    print("")


else

    -- Kein Befehl.
    usage()

    return

end


-- ============================================================
-- MINING STARTEN
-- ============================================================

-- ============================================================
-- WICHTIG:
--
-- Die Turtle steht beim Start mit der Kiste hinter sich.
--
-- Die gespeicherte Richtung 0 ist:
-- vorne = Abbaubereich
--
-- Falls die Turtle beim Start noch zur Kiste schaut,
-- drehen wir sie 180 Grad.
--
-- Deshalb:
--
-- [KISTE] [TURTLE] ---> MINING
--
-- Turtle muss mit dem Ruecken zur Kiste stehen.
-- ============================================================


state.phase = "mining"

save()


-- ============================================================
-- LAYER
-- ============================================================

for layer = state.layer, state.layers do

    state.layer = layer

    save()


    print("")
    print(
        "================================"
    )

    print(
        "Ebene "
        .. layer
        .. "/"
        .. state.layers
    )

    print(
        "================================"
    )

    print("")


    -- --------------------------------------------------------
    -- Jeder Layer ist 2 Bloecke hoch.
    --
    -- Layer 1:
    -- Y=0 + Y=1
    --
    -- Layer 2:
    -- Y=2 + Y=3
    --
    -- usw.
    -- --------------------------------------------------------

    local targetY =
        (layer - 1) * 2


    -- Zur richtigen Hoehe.
    goTo(
        state.x,
        targetY,
        state.z
    )


    -- --------------------------------------------------------
    -- Layer abbauen.
    -- --------------------------------------------------------

    mineLayer(layer)


    -- --------------------------------------------------------
    -- Noch eine Ebene?
    -- --------------------------------------------------------

    if layer < state.layers then

        print("")
        print(
            "Naechste Ebene: 2 Bloecke nach oben."
        )
        print("")


        -- Zum Ausgangspunkt dieses Layers
        -- zurueckkehren.
        --
        -- Damit die naechste Ebene wieder
        -- sauber serpentin abgebaut wird.
        goTo(
            0,
            targetY,
            0
        )


        -- 2 Bloecke hoch.
        up()
        up()


        -- Wieder Richtung Abbaubereich.
        face(0)


        state.layer =
            layer + 1

        state.currentRow = 1
        state.currentCol = 1

        save()

    end

end


-- ============================================================
-- FERTIG
-- ============================================================

print("")
print("==============================")
print("        MINING FERTIG")
print("==============================")
print("")


state.phase = "finished"

save()


-- Zurueck zur Kiste.
goHome()


-- Kiste anschauen.
face(2)


checkChest()


-- Beute ausladen.
for slot = 1, 16 do

    local item =
        turtle.getItemDetail(slot)

    if item then

        local keep = false

        if item.name == "minecraft:torch" then
            keep = true
        end

        if item.name == "minecraft:bucket" then
            keep = true
        end

        if item.name == "minecraft:coal"
        or item.name == "minecraft:charcoal"
        or item.name == "minecraft:coal_block" then

            keep = true

        end


        if not keep then

            turtle.select(slot)
            turtle.drop()

        end

    end

end


turtle.select(1)


print("")
print("==============================")
print("          FERTIG")
print("==============================")
print("")

print(
    "Fackeln behalten: "
    .. countItem("minecraft:torch")
)

print(
    "Eimer behalten: "
    .. countItem("minecraft:bucket")
)

print("")

