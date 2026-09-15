-- ============================================================
--                       MINER V10
-- ============================================================
--
-- CC:Tweaked
--
-- Befehle:
--
--   miner new <breite> <tiefe> <hoehe> [fackelabstand]
--   miner resume
--   miner status
--   miner reset
--
-- Beispiel:
--
--   miner new 10 20 6 6
--
-- Aufbau:
--
--   [ KISTE ][ TURTLE ] ---> Abbaugebiet
--
-- Die Turtle steht zu Beginn direkt vor der Kiste
-- und schaut in den Abbaubereich.
--
-- ============================================================


local VERSION = 10
local STATE_FILE = "miner_state"


local args = {...}
local command = args[1]


-- ============================================================
-- KONFIGURATION
-- ============================================================

local MIN_FUEL = 500
local FUEL_BUFFER = 150

local MAX_TORCHES = 16
local MIN_TORCHES = 4

local MAX_BUCKETS = 4
local MIN_BUCKETS = 2

local MIN_FREE_SLOTS = 2


-- ============================================================
-- STATE
-- ============================================================

local state = nil
local servicing = false


-- ============================================================
-- HILFE
-- ============================================================

local function usage()

    print("")
    print("==============================")
    print("          MINER V10")
    print("==============================")
    print("")

    print("Neuer Auftrag:")
    print("")
    print(" miner new <breite> <tiefe> <hoehe> [fackeln]")
    print("")

    print("Beispiel:")
    print("")
    print(" miner new 10 20 6 6")
    print("")

    print("Fortsetzen:")
    print("")
    print(" miner resume")
    print("")

    print("Status:")
    print("")
    print(" miner status")
    print("")

    print("Reset:")
    print("")
    print(" miner reset")
    print("")

end


-- ============================================================
-- STATE SPEICHERN
-- ============================================================

local function save()

    if not state then
        return
    end

    local file, err =
        fs.open(
            STATE_FILE,
            "w"
        )

    if not file then
        error(
            "Kann miner_state nicht speichern: "
            .. tostring(err)
        )
    end

    file.write(
        textutils.serialize(state)
    )

    file.close()

end


-- ============================================================
-- STATE LADEN
-- ============================================================

local function loadState()

    if not fs.exists(STATE_FILE) then
        return nil
    end

    local file, err =
        fs.open(
            STATE_FILE,
            "r"
        )

    if not file then
        error(
            "Kann miner_state nicht lesen: "
            .. tostring(err)
        )
    end

    local content =
        file.readAll()

    file.close()

    local data =
        textutils.unserialize(
            content
        )

    if not data then
        error(
            "miner_state ist beschaedigt."
        )
    end

    if data.version ~= VERSION then

        print("")
        print(
            "Alter miner_state gefunden."
        )
        print("")
        print(
            "Bitte ausfuehren:"
        )
        print("")
        print(" miner reset")
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

        if item
        and item.name == name then

            total =
                total + item.count

        end

    end

    return total

end


local function findItem(name)

    for slot = 1, 16 do

        local item =
            turtle.getItemDetail(slot)

        if item
        and item.name == name then

            return slot

        end

    end

    return nil

end


local function findEmptySlot()

    for slot = 1, 16 do

        if turtle.getItemCount(slot) == 0 then
            return slot
        end

    end

    return nil

end


local function freeSlots()

    local count = 0

    for slot = 1, 16 do

        if turtle.getItemCount(slot) == 0 then
            count = count + 1
        end

    end

    return count

end


local function isKeepItem(name)

    if name == "minecraft:torch" then
        return true
    end

    if name == "minecraft:bucket" then
        return true
    end

    if name == "minecraft:coal" then
        return true
    end

    if name == "minecraft:charcoal" then
        return true
    end

    return false

end


-- ============================================================
-- RICHTUNGEN
--
-- 0 = +X
-- 1 = +Z
-- 2 = -X
-- 3 = -Z
-- ============================================================

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

    local difference =
        (direction - state.dir) % 4

    if difference == 1 then

        turnRight()

    elseif difference == 2 then

        turnRight()
        turnRight()

    elseif difference == 3 then

        turnLeft()

    end

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


local function collectFront()

    local slot =
        findItem(
            "minecraft:bucket"
        )

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

    local slot =
        findItem(
            "minecraft:bucket"
        )

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

    local slot =
        findItem(
            "minecraft:bucket"
        )

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
-- FUEL
-- ============================================================

local function refuelInventory()

    if turtle.getFuelLevel() == "unlimited" then
        return true
    end

    local old =
        turtle.getSelectedSlot()

    for slot = 1, 16 do

        local item =
            turtle.getItemDetail(slot)

        if item then

            if item.name == "minecraft:coal"
            or item.name == "minecraft:charcoal" then

                turtle.select(slot)
                turtle.refuel()

            end

        end

    end

    turtle.select(old)

    return
        turtle.getFuelLevel()
        >= MIN_FUEL

end


local function fuelCheck()

    if turtle.getFuelLevel() == "unlimited" then
        return
    end

    if turtle.getFuelLevel()
        >= MIN_FUEL then

        return

    end

    if refuelInventory() then
        return
    end

    error(
        "Zu wenig Fuel. "
        .. "Bitte Kohle/Charcoal nachfuellen."
    )

end


-- ============================================================
-- KISTE
-- ============================================================

local function checkChest()

    local ok, data =
        turtle.inspect()

    if not ok then

        error(
            "Vor der Turtle wurde keine Kiste gefunden."
        )

    end

    local name =
        string.lower(
            data.name or ""
        )

    if not string.find(
        name,
        "chest",
        1,
        true
    ) then

        error(
            "Vor der Turtle steht keine Kiste."
        )

    end

end


-- ============================================================
-- INVENTAR ABLADEN
-- ============================================================

local function unload()

    for slot = 1, 16 do

        local item =
            turtle.getItemDetail(slot)

        if item
        and not isKeepItem(item.name) then

            turtle.select(slot)

            turtle.drop()

        end

    end

    turtle.select(1)

end


-- ============================================================
-- ITEM AUS KISTE HOLEN
-- ============================================================

local function pullItem(
    name,
    amount
)

    local received = 0

    while received < amount do

        local slot =
            findEmptySlot()

        if not slot then
            break
        end

        turtle.select(slot)

        local before =
            turtle.getItemCount(slot)

        local ok =
            turtle.suck(
                math.min(
                    amount - received,
                    64
                )
            )

        if not ok then
            break
        end

        local item =
            turtle.getItemDetail(slot)

        if not item then
            break
        end

        if item.name ~= name then

            turtle.drop()

            break

        end

        local after =
            turtle.getItemCount(slot)

        received =
            received + (
                after - before
            )

    end

    turtle.select(1)

    return received

end


-- ============================================================
-- SERVICE
--
-- Turtle dreht sich zur Kiste zurueck.
-- Sie befindet sich waehrend des Services immer am Startpunkt.
-- ============================================================

local function service()

    if servicing then
        return
    end

    servicing = true

    -- Zurueck zur Startposition.
    -- Wir benutzen die gespeicherte absolute Position.
    --
    -- Die Funktion goTo() wird weiter unten definiert.
    --
    -- Lua erlaubt den Aufruf hier erst nachdem die Funktion
    -- existiert; deshalb wird service() weiter unten
    -- neu referenziert.
    servicing = false

end


-- ============================================================
-- BEWEGUNG
-- ============================================================

local function moveForwardRaw()

    while true do

        fuelCheck()

        local ok =
            turtle.forward()

        if ok then

            if state.dir == 0 then
                state.x =
                    state.x + 1

            elseif state.dir == 1 then
                state.z =
                    state.z + 1

            elseif state.dir == 2 then
                state.x =
                    state.x - 1

            else
                state.z =
                    state.z - 1
            end

            save()

            return true

        end


        local hasBlock, data =
            turtle.inspect()

        if hasBlock
        and isFluid(data) then

            if not collectFront() then

                error(
                    "Fluessigkeit vorne, "
                    .. "aber kein Eimer vorhanden."
                )

            end

        elseif hasBlock then

            local dug, err =
                turtle.dig()

            if not dug then

                error(
                    "Bewegung blockiert: "
                    .. tostring(err)
                )

            end

        else

            sleep(0.2)

        end

    end

end


local function moveUpRaw()

    while true do

        fuelCheck()

        local ok =
            turtle.up()

        if ok then

            state.y =
                state.y + 1

            save()

            return true

        end


        local hasBlock, data =
            turtle.inspectUp()

        if hasBlock
        and isFluid(data) then

            if not collectUp() then

                error(
                    "Fluessigkeit ueber der Turtle."
                )

            end

        elseif hasBlock then

            if not turtle.digUp() then

                error(
                    "Block ueber der Turtle "
                    .. "kann nicht entfernt werden."
                )

            end

        else

            sleep(0.2)

        end

    end

end


local function moveDownRaw()

    while true do

        fuelCheck()

        local ok =
            turtle.down()

        if ok then

            state.y =
                state.y - 1

            save()

            return true

        end


        local hasBlock, data =
            turtle.inspectDown()

        if hasBlock
        and isFluid(data) then

            if not collectDown() then

                error(
                    "Fluessigkeit unter der Turtle."
                )

            end

        elseif hasBlock then

            if not turtle.digDown() then

                error(
                    "Block unter der Turtle "
                    .. "kann nicht entfernt werden."
                )

            end

        else

            sleep(0.2)

        end

    end

end


-- ============================================================
-- DIG
-- ============================================================

local function digFront()

    local hasBlock, data =
        turtle.inspect()

    if not hasBlock then
        return true
    end

    if isFluid(data) then
        return collectFront()
    end

    local ok, err =
        turtle.dig()

    if not ok then

        error(
            "Kann Block vorne nicht abbauen: "
            .. tostring(err)
        )

    end

    return true

end


local function digAbove()

    local hasBlock, data =
        turtle.inspectUp()

    if not hasBlock then
        return true
    end

    if isFluid(data) then
        return collectUp()
    end

    local ok, err =
        turtle.digUp()

    if not ok then

        error(
            "Kann Block oben nicht abbauen: "
            .. tostring(err)
        )

    end

    return true

end


-- ============================================================
-- ZIELPOSITION
-- ============================================================

local function goTo(
    targetX,
    targetY,
    targetZ
)

    while state.y < targetY do
        moveUpRaw()
    end

    while state.y > targetY do
        moveDownRaw()
    end


    -- X zuerst.
    if state.x < targetX then

        face(0)

        while state.x < targetX do
            moveForwardRaw()
        end

    elseif state.x > targetX then

        face(2)

        while state.x > targetX do
            moveForwardRaw()
        end

    end


    -- Z.
    if state.z < targetZ then

        face(1)

        while state.z < targetZ do
            moveForwardRaw()
        end

    elseif state.z > targetZ then

        face(3)

        while state.z > targetZ do
            moveForwardRaw()
        end

    end

end


-- ============================================================
-- STARTPUNKT
-- ============================================================

local function goHome()

    goTo(
        0,
        0,
        0
    )

    face(0)

end


-- ============================================================
-- SERVICE
-- ============================================================

local function performService()

    if servicing then
        return
    end

    servicing = true

    local oldX =
        state.x

    local oldY =
        state.y

    local oldZ =
        state.z

    local oldDir =
        state.dir


    -- Startposition.
    goHome()


    checkChest()


    -- Abbau abladen.
    unload()


    -- Fuel holen.
    if turtle.getFuelLevel()
        ~= "unlimited" then

        if turtle.getFuelLevel()
            < MIN_FUEL + FUEL_BUFFER then

            pullItem(
                "minecraft:coal",
                16
            )

            pullItem(
                "minecraft:charcoal",
                16
            )

            refuelInventory()

        end

    end


    -- Fackeln auffuellen.
    local torches =
        countItem(
            "minecraft:torch"
        )

    if torches < MAX_TORCHES then

        pullItem(
            "minecraft:torch",
            MAX_TORCHES - torches
        )

    end


    -- Eimer auffuellen.
    local buckets =
        countItem(
            "minecraft:bucket"
        )

    if buckets < MAX_BUCKETS then

        pullItem(
            "minecraft:bucket",
            MAX_BUCKETS - buckets
        )

    end


    -- Zur alten Position.
    goTo(
        oldX,
        oldY,
        oldZ
    )

    face(oldDir)

    servicing = false

    save()

end


-- ============================================================
-- INVENTAR-CHECK
-- ============================================================

local function inventoryCheck()

    if freeSlots()
        >= MIN_FREE_SLOTS then

        return

    end

    performService()

end


-- ============================================================
-- FUEL CHECK MIT SERVICE
-- ============================================================

local function fuelCheckService()

    if turtle.getFuelLevel()
        == "unlimited" then

        return

    end

    if turtle.getFuelLevel()
        >= MIN_FUEL then

        return

    end

    performService()

    if turtle.getFuelLevel()
        < MIN_FUEL then

        error(
            "Nach Service immer noch zu wenig Fuel."
        )

    end

end


-- ============================================================
-- FACKELN
--
-- WICHTIG:
--
-- Nur Layer 1.
--
-- Der Zaehler bezieht sich auf die bearbeiteten Positionen.
--
-- Die Fackel wird hinter der Turtle platziert.
-- Die Turtle veraendert dadurch ihre logische Richtung NICHT.
-- ============================================================

local function torchBehind()

    if state.layer ~= 1 then
        return
    end

    if state.torchDistance <= 0 then
        return
    end


    state.torchCounter =
        state.torchCounter + 1


    if state.torchCounter
        < state.torchDistance then

        save()

        return

    end


    -- Erste Position der ersten Reihe:
    -- hinter der Turtle ist ausserhalb des Bereichs.
    if state.currentCol == 1
    and state.currentRow % 2 == 1 then

        state.torchCounter = 0

        save()

        return

    end


    local slot =
        findItem(
            "minecraft:torch"
        )


    if not slot then

        performService()

        slot =
            findItem(
                "minecraft:torch"
            )

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


    -- 180 Grad drehen.
    face(
        (oldDir + 2) % 4
    )


    -- Einen Block zurueck.
    moveForwardRaw()


    turtle.select(slot)


    local placed, placeErr =
        turtle.placeDown()


    turtle.select(oldSlot)


    -- Zurueck auf die Arbeitsposition.
    face(oldDir)

    moveForwardRaw()


    if not placed then

        error(
            "Fackel konnte nicht gesetzt werden: "
            .. tostring(placeErr)
        )

    end


    state.torchCounter = 0

    save()

end


-- ============================================================
-- EINZELNE MINING-POSITION
--
-- GANZ WICHTIG:
--
-- 1. Frontblock abbauen
-- 2. oberen Block abbauen
-- 3. in den Frontblock fahren
-- 4. Fackel behandeln
--
-- Diese Reihenfolge bleibt auch beim letzten Block einer
-- Reihe identisch.
--
-- Dadurch wird der obere Block NICHT uebersprungen.
-- ============================================================

local function minePosition()

    inventoryCheck()
    fuelCheckService()


    -- Frontblock.
    digFront()


    -- Oberer Block.
    if state.y + 1
        < state.height then

        digAbove()

    end


    -- In den gerade abgebauten Block.
    moveForwardRaw()


    -- Fackel.
    torchBehind()


    save()

end


-- ============================================================
-- REIHENRICHTUNG
-- ============================================================

local function rowDirection(row)

    if row % 2 == 1 then
        return 0
    end

    return 2

end


-- ============================================================
-- NAECHSTE REIHE
--
-- Die Turtle steht nach minePosition() bereits auf dem letzten
-- Block der aktuellen Reihe.
--
-- Genau hier war der alte Fehler besonders kritisch.
--
-- Wir drehen zuerst, gehen EINEN Block seitlich und drehen
-- danach wieder in die neue Reihenrichtung.
-- ============================================================

local function nextRow(row)

    if row % 2 == 1 then

        -- Aktuelle Richtung +X.
        -- Neue Reihe geht zurueck nach -X.
        --
        -- Ein Schritt +Z.
        turnRight()

        moveForwardRaw()

        turnRight()

    else

        -- Aktuelle Richtung -X.
        -- Neue Reihe geht wieder nach +X.
        --
        -- Ein Schritt +Z.
        turnLeft()

        moveForwardRaw()

        turnLeft()

    end


    state.currentRow =
        row + 1

    state.currentCol = 1

    save()

end


-- ============================================================
-- LAYER
-- ============================================================

local function mineLayer(layer)

    state.layer =
        layer


    -- Zwei Hoehen pro Layer.
    local targetY =
        (layer - 1) * 2


    goTo(
        0,
        targetY,
        0
    )


    -- Startausrichtung.
    face(0)


    local startRow = 1
    local startCol = 1


    -- ========================================================
    -- RESUME
    -- ========================================================

    if state.currentLayer == layer then

        startRow =
            state.currentRow or 1

        startCol =
            state.currentCol or 1

    else

        state.currentLayer =
            layer

        state.currentRow = 1
        state.currentCol = 1

        save()

    end


    -- ========================================================
    -- REIHEN
    -- ========================================================

    for row = startRow, state.depth do

        state.currentRow =
            row


        face(
            rowDirection(row)
        )


        local firstCol = 1

        if row == startRow then

            firstCol =
                startCol

        end


        -- ====================================================
        -- SPALTEN
        -- ====================================================

        for col = firstCol, state.width do

            state.currentRow =
                row

            state.currentCol =
                col

            save()


            -- ==================================================
            -- DIE POSITION
            -- ==================================================

            minePosition()


            -- ==================================================
            -- NUR WENN ES EINE WEITERE SPALTE GIBT:
            --
            -- minePosition() hat uns bereits auf die aktuelle
            -- Position gebracht.
            --
            -- Wir muessen also nur noch einen Schritt in der
            -- aktuellen Reihenrichtung machen.
            --
            -- Beim letzten Block NICHT.
            -- ==================================================

            if col < state.width then

                state.currentCol =
                    col + 1

                save()

            end

        end


        -- ====================================================
        -- REIHENWECHSEL
        -- ====================================================

        if row < state.depth then

            nextRow(row)

        end

    end


    -- ========================================================
    -- LAYER FERTIG
    -- ========================================================

    state.currentLayer =
        layer + 1

    state.currentRow = 1
    state.currentCol = 1

    save()

end


-- ============================================================
-- GESAMTEN AUFTRAG AUSFUEHREN
-- ============================================================

local function runMining()

    local layers =
        math.ceil(
            state.height / 2
        )


    while state.currentLayer
        <= layers do

        mineLayer(
            state.currentLayer
        )

    end


    -- Zur Kiste.
    goHome()


    checkChest()


    unload()


    print("")
    print("==============================")
    print("       MINING FERTIG")
    print("==============================")
    print("")

end


-- ============================================================
-- STATUS
-- ============================================================

local function showStatus()

    if not state then

        print("")
        print("Kein aktiver Auftrag.")
        print("")

        return

    end


    print("")
    print("==============================")
    print("          MINER STATUS")
    print("==============================")
    print("")

    print(
        "Groesse: "
        .. state.width
        .. " x "
        .. state.depth
        .. " x "
        .. state.height
    )

    print(
        "Layer: "
        .. state.currentLayer
    )

    print(
        "Reihe: "
        .. state.currentRow
    )

    print(
        "Spalte: "
        .. state.currentCol
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
        "Fuel: "
        .. tostring(
            turtle.getFuelLevel()
        )
    )

    print(
        "Fackeln: "
        .. countItem(
            "minecraft:torch"
        )
    )

    print("")

end


-- ============================================================
-- RESET
-- ============================================================

local function reset()

    if fs.exists(STATE_FILE) then

        fs.delete(
            STATE_FILE
        )

    end

    print("")
    print(
        "Miner State wurde geloescht."
    )
    print("")

end


-- ============================================================
-- NEUEN AUFTRAG
-- ============================================================

local function newJob()

    local width =
        tonumber(args[2])

    local depth =
        tonumber(args[3])

    local height =
        tonumber(args[4])

    local torchDistance =
        tonumber(args[5])


    if not width
    or not depth
    or not height then

        usage()

        return

    end


    if width < 1
    or depth < 1
    or height < 1 then

        error(
            "Breite, Tiefe und Hoehe muessen >= 1 sein."
        )

    end


    if torchDistance == nil then

        torchDistance = 6

    end


    if torchDistance < 0 then
        torchDistance = 0
    end


    -- ========================================================
    -- Startposition:
    --
    -- x=0
    -- y=0
    -- z=0
    --
    -- Richtung +X.
    -- ========================================================

    state = {

        version = VERSION,

        width = width,
        depth = depth,
        height = height,

        torchDistance =
            torchDistance,

        torchCounter = 0,

        x = 0,
        y = 0,
        z = 0,

        dir = 0,

        layer = 1,

        currentLayer = 1,
        currentRow = 1,
        currentCol = 1

    }


    save()


    print("")
    print("==============================")
    print("       NEUER AUFTRAG")
    print("==============================")
    print("")

    print(
        "Groesse: "
        .. width
        .. " x "
        .. depth
        .. " x "
        .. height
    )

    print(
        "Fackelabstand: "
        .. torchDistance
    )

    print("")


    checkChest()

    fuelCheckService()

    inventoryCheck()


    runMining()

end


-- ============================================================
-- RESUME
-- ============================================================

local function resume()

    state =
        loadState()


    if not state then

        print("")
        print(
            "Kein gueltiger Auftrag vorhanden."
        )
        print("")

        return

    end


    print("")
    print("==============================")
    print("        MINER RESUME")
    print("==============================")
    print("")

    print(
        "Layer: "
        .. state.currentLayer
    )

    print(
        "Reihe: "
        .. state.currentRow
    )

    print(
        "Spalte: "
        .. state.currentCol
    )

    print("")


    fuelCheckService()

    inventoryCheck()

    runMining()

end


-- ============================================================
-- START
-- ============================================================

if command == "new" then

    newJob()

elseif command == "resume" then

    resume()

elseif command == "status" then

    state =
        loadState()

    showStatus()

elseif command == "reset" then

    reset()

elseif command == nil then

    usage()

else

    usage()

end

