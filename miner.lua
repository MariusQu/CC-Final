-- ============================================================
--                    MINER V8
-- ============================================================
--
-- CC:Tweaked 1.113.1
-- Minecraft 1.20.1
--
-- AUFBAU:
--
--       Abbaubereich
--             -->
--
-- [ KISTE ][ TURTLE ]
--
-- Die Turtle steht direkt vor der Kiste.
-- Die Turtle schaut vom Kistenplatz in den Abbaubereich.
--
-- ============================================================
--
-- BEFEHLE:
--
-- miner
-- miner new <breite> <tiefe> <hoehe> [fackelabstand]
-- miner resume
-- miner status
-- miner reset
--
-- Beispiel:
--
-- miner new 10 20 6 6
--
-- ============================================================


local VERSION = 8
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
    print("          MINER V8")
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
        fs.open(STATE_FILE, "w")

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
        fs.open(STATE_FILE, "r")

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
        textutils.unserialize(content)

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
            "Bitte einmal ausfuehren:"
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

        if item and item.name == name then

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

        if item and item.name == name then
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
-- 0 = +X / vorne
-- 1 = +Z / rechts
-- 2 = -X / hinten / Kiste
-- 3 = -Z / links
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

    if data.name == "minecraft:water" then
        return true
    end

    if data.name == "minecraft:lava" then
        return true
    end

    return false

end


local function collectFront()

    local slot =
        findItem("minecraft:bucket")

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
        findItem("minecraft:bucket")

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
        findItem("minecraft:bucket")

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
-- RAW BEWEGUNG
--
-- Diese Funktionen aktualisieren immer die gespeicherte
-- Position.
-- ============================================================

local function moveForwardRaw()

    while true do

        local ok, err =
            turtle.forward()

        if ok then

            if state.dir == 0 then
                state.x = state.x + 1

            elseif state.dir == 1 then
                state.z = state.z + 1

            elseif state.dir == 2 then
                state.x = state.x - 1

            elseif state.dir == 3 then
                state.z = state.z - 1
            end

            save()

            return true

        end


        -- Fluessigkeit?
        local hasBlock, data =
            turtle.inspect()

        if hasBlock and isFluid(data) then

            if not collectFront() then

                error(
                    "Fluessigkeit gefunden, aber kein "
                    .. "leerer Eimer vorhanden."
                )

            end

        elseif hasBlock then

            local dug, digErr =
                turtle.dig()

            if not dug then

                error(
                    "Bewegung blockiert: "
                    .. tostring(digErr)
                )

            end

        else

            -- Entity oder kurzfristige Blockierung.
            sleep(0.2)

        end

    end

end


local function moveUpRaw()

    while true do

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

        if hasBlock and isFluid(data) then

            if not collectUp() then

                error(
                    "Fluessigkeit ueber der Turtle, "
                    .. "aber kein Eimer vorhanden."
                )

            end

        elseif hasBlock then

            if not turtle.digUp() then

                error(
                    "Block ueber der Turtle kann "
                    .. "nicht entfernt werden."
                )

            end

        else

            sleep(0.2)

        end

    end

end


local function moveDownRaw()

    while true do

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

        if hasBlock and isFluid(data) then

            if not collectDown() then

                error(
                    "Fluessigkeit unter der Turtle, "
                    .. "aber kein Eimer vorhanden."
                )

            end

        elseif hasBlock then

            if not turtle.digDown() then

                error(
                    "Block unter der Turtle kann "
                    .. "nicht entfernt werden."
                )

            end

        else

            sleep(0.2)

        end

    end

end


-- ============================================================
-- RAW DIG
-- ============================================================

local function digFront()

    while true do

        local hasBlock, data =
            turtle.inspect()

        if not hasBlock then
            return true
        end


        if isFluid(data) then

            if collectFront() then

                return true

            end

            return false

        end


        local ok, err =
            turtle.dig()

        if not ok then

            error(
                "Kann Block vorne nicht abbauen: "
                .. tostring(err)
            )

        end

    end

end


local function digAbove()

    local hasBlock, data =
        turtle.inspectUp()

    if not hasBlock then
        return true
    end


    if isFluid(data) then

        if collectUp() then
            return true
        end

        return false

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
        turtle.getFuelLevel() == "unlimited"
        or turtle.getFuelLevel() >= MIN_FUEL

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
        string.lower(data.name or "")


    if not string.find(
        name,
        "chest",
        1,
        true
    ) then

        error(
            "Vor der Turtle steht keine Kiste. "
            .. "Gefunden: "
            .. tostring(data.name)
        )

    end

end


-- ============================================================
-- KISTEN-PERIPHERAL
--
-- Wenn generic_peripherals aktiviert ist, kann V8 damit
-- gezielt Fackeln, Eimer und Fuel aus der Kiste holen.
--
-- Falls der Server dies nicht erlaubt, verwendet V8 die
-- normale turtle.suck()-Methode als Fallback.
-- ============================================================

local function getChestPeripheral()

    local chest =
        peripheral.wrap("front")

    if chest then

        if chest.list
        and chest.size
        and chest.pushItems then

            return chest

        end

    end

    return nil

end


local function findChestItem(chest, itemName)

    local items =
        chest.list()

    for slot, item in pairs(items) do

        if item.name == itemName then
            return slot
        end

    end

    return nil

end


local function findChestEmpty(chest)

    local items =
        chest.list()

    local size =
        chest.size()

    for slot = 1, size do

        if not items[slot] then
            return slot
        end

    end

    return nil

end


local function moveChestItemToSlotOne(
    chest,
    itemName
)

    local chestName =
        peripheral.getName(chest)


    local itemSlot =
        findChestItem(
            chest,
            itemName
        )


    if not itemSlot then
        return false
    end


    if itemSlot == 1 then
        return true
    end


    local list =
        chest.list()


    -- Slot 1 freimachen.
    if list[1] then

        local empty =
            findChestEmpty(chest)

        if not empty then

            return false

        end


        local moved =
            chest.pushItems(
                chestName,
                1,
                nil,
                empty
            )

        if moved <= 0 then
            return false
        end

    end


    -- Liste aktualisieren.
    itemSlot =
        findChestItem(
            chest,
            itemName
        )


    if not itemSlot then
        return false
    end


    if itemSlot == 1 then
        return true
    end


    local moved =
        chest.pushItems(
            chestName,
            itemSlot,
            nil,
            1
        )


    return moved > 0

end


-- ============================================================
-- SPEZIFISCHES ITEM AUS KISTE HOLEN
-- ============================================================

local function pullSpecific(
    itemName,
    amount
)

    if amount <= 0 then
        return 0
    end


    local chest =
        getChestPeripheral()


    -- ========================================================
    -- PERIPHERAL-METHODE
    -- ========================================================

    if chest then

        local remaining =
            amount


        while remaining > 0 do

            if not moveChestItemToSlotOne(
                chest,
                itemName
            ) then

                break

            end


            local slot =
                findEmptySlot()

            if not slot then
                break
            end


            turtle.select(slot)


            local before =
                turtle.getItemCount(slot)


            local wanted =
                math.min(
                    remaining,
                    64
                )


            local ok =
                turtle.suck(wanted)


            if not ok then
                break
            end


            local after =
                turtle.getItemCount(slot)


            local received =
                after - before


            if received <= 0 then
                break
            end


            remaining =
                remaining - received

        end


        turtle.select(1)


        return amount - remaining

    end


    -- ========================================================
    -- FALLBACK
    --
    -- Wenn generic_peripherals deaktiviert ist, versuchen
    -- wir normale suck()-Aufnahmen.
    --
    -- Dafür sollte die Versorgung in der Kiste möglichst
    -- weit vorne einsortiert sein.
    -- ========================================================

    local receivedTotal = 0
    local attempts = 0


    while receivedTotal < amount
    and attempts < 8 do

        attempts = attempts + 1


        local slot =
            findEmptySlot()

        if not slot then
            break
        end


        turtle.select(slot)


        local before =
            turtle.getItemCount(slot)


        if not turtle.suck(
            math.min(
                amount - receivedTotal,
                64
            )
        ) then

            break

        end


        local item =
            turtle.getItemDetail(slot)


        if item
        and item.name == itemName then

            receivedTotal =
                receivedTotal + item.count

        else

            -- Falsches Item wieder zurueck.
            if item then

                turtle.drop()

            end

        end

    end


    turtle.select(1)


    return receivedTotal

end


-- ============================================================
-- KISTE: INVENTAR ABLADEN
-- ============================================================

local function unload()

    for slot = 1, 16 do

        local item =
            turtle.getItemDetail(slot)

        if item then

            if not isKeepItem(
                item.name
            ) then

                turtle.select(slot)

                turtle.drop()

            end

        end

    end


    turtle.select(1)

end


-- ============================================================
-- KISTE: FACKELN
-- ============================================================

local function refillTorches()

    local current =
        countItem(
            "minecraft:torch"
        )


    if current >= MAX_TORCHES then
        return
    end


    local need =
        MAX_TORCHES - current


    local got =
        pullSpecific(
            "minecraft:torch",
            need
        )


    if current + got < MIN_TORCHES then

        error(
            "Zu wenige Fackeln in der Kiste. "
            .. "Mindestens "
            .. MIN_TORCHES
            .. " benoetigt."
        )

    end

end


-- ============================================================
-- KISTE: EIMER
-- ============================================================

local function refillBuckets()

    local current =
        countItem(
            "minecraft:bucket"
        )


    if current >= MAX_BUCKETS then
        return
    end


    local need =
        MAX_BUCKETS - current


    local got =
        pullSpecific(
            "minecraft:bucket",
            need
        )


    if current + got < MIN_BUCKETS then

        error(
            "Zu wenige leere Eimer in der Kiste. "
            .. "Mindestens "
            .. MIN_BUCKETS
            .. " benoetigt."
        )

    end

end


-- ============================================================
-- KISTE: FUEL
-- ============================================================

local function refillFuel()

    if turtle.getFuelLevel()
        == "unlimited" then

        return

    end


    refuelInventory()


    if turtle.getFuelLevel()
        >= MIN_FUEL then

        return

    end


    -- Erst Kohle versuchen.
    local need =
        16


    pullSpecific(
        "minecraft:coal",
        need
    )


    refuelInventory()


    -- Dann Holzkohle.
    if turtle.getFuelLevel()
        < MIN_FUEL then

        pullSpecific(
            "minecraft:charcoal",
            16
        )

        refuelInventory()

    end


    if turtle.getFuelLevel()
        < MIN_FUEL then

        error(
            "Nicht genug Fuel in der Kiste."
        )

    end

end


-- ============================================================
-- ZUR STARTPOSITION
-- ============================================================

local function goHome()

    -- Y zuerst.
    while state.y > 0 do
        moveDownRaw()
    end


    -- X zurueck auf 0.
    if state.x > 0 then

        face(2)

        while state.x > 0 do
            moveForwardRaw()
        end

    elseif state.x < 0 then

        face(0)

        while state.x < 0 do
            moveForwardRaw()
        end

    end


    -- Z zurueck auf 0.
    if state.z > 0 then

        face(3)

        while state.z > 0 do
            moveForwardRaw()
        end

    elseif state.z < 0 then

        face(1)

        while state.z < 0 do
            moveForwardRaw()
        end

    end


    save()

end


-- ============================================================
-- ZU EINER POSITION
-- ============================================================

local function goTo(
    targetX,
    targetY,
    targetZ
)

    -- --------------------------------------------------------
    -- Y
    -- --------------------------------------------------------

    while state.y < targetY do
        moveUpRaw()
    end


    while state.y > targetY do
        moveDownRaw()
    end


    -- --------------------------------------------------------
    -- X
    -- --------------------------------------------------------

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


    -- --------------------------------------------------------
    -- Z
    -- --------------------------------------------------------

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


    save()

end


-- ============================================================
-- SERVICE
--
-- Kiste:
--
-- [KISTE] [TURTLE] -> Mine
--
-- ============================================================

local function service()

    if servicing then
        return
    end


    servicing = true


    print("")
    print("------------------------------")
    print("Inventar/Fuel Service")
    print("------------------------------")


    -- Aktuelle Position merken.
    state.returnX = state.x
    state.returnY = state.y
    state.returnZ = state.z
    state.returnDir = state.dir

    state.phase = "service"

    save()


    -- Zur Kiste.
    goHome()


    -- Turtle schaut jetzt +X.
    -- Kiste ist hinter ihr.
    face(2)


    checkChest()


    -- Beute abladen.
    unload()


    -- Fuel / Eimer / Fackeln.
    refillFuel()
    refillBuckets()
    refillTorches()


    turtle.select(1)


    -- Arbeitsplatz wiederherstellen.
    print("Rueckkehr zum Arbeitsplatz...")


    goTo(
        state.returnX,
        state.returnY,
        state.returnZ
    )


    face(
        state.returnDir
    )


    state.x =
        state.returnX

    state.y =
        state.returnY

    state.z =
        state.returnZ

    state.dir =
        state.returnDir


    state.returnX = nil
    state.returnY = nil
    state.returnZ = nil
    state.returnDir = nil


    state.phase = "mining"

    save()


    print("Arbeitsplatz erreicht.")
    print("")


    servicing = false

end


-- ============================================================
-- FUEL CHECK
-- ============================================================

local function fuelCheck()

    if turtle.getFuelLevel()
        == "unlimited" then

        return

    end


    refuelInventory()


    if turtle.getFuelLevel()
        < FUEL_BUFFER then

        service()

    end

end


-- ============================================================
-- INVENTAR CHECK
-- ============================================================

local function inventoryCheck()

    if freeSlots()
        <= MIN_FREE_SLOTS then

        service()

    end

end


-- ============================================================
-- FACKEL HINTER DER TURTLE
--
-- Die Fackel wird auf dem Boden des Blocks hinter der
-- Turtle platziert.
--
-- Nur Layer 1!
--
-- Dadurch gibt es ab Layer 2 KEINE Fackeln mehr.
-- ============================================================

local function torchBehind()

    -- Nur erste Ebene.
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


    local slot =
        findItem(
            "minecraft:torch"
        )


    if not slot then

        service()

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


    -- Bei der ersten Position einer Reihe
    -- waere "hinter der Turtle" ausserhalb
    -- des Raumes.
    --
    -- Dort setzen wir keine Fackel.
    if state.currentCol == 1
    and state.currentRow % 2 == 1 then

        state.torchCounter = 0

        save()

        return

    end


    local oldSlot =
        turtle.getSelectedSlot()

    local oldDir =
        state.dir


    -- 180 Grad drehen.
    turnRight()
    turnRight()


    -- Einen Block zurueck.
    moveForwardRaw()


    turtle.select(slot)


    -- Fackel auf den Boden setzen.
    turtle.placeDown()


    -- Zurueck zum aktuellen Block.
    face(oldDir)

    moveForwardRaw()


    turtle.select(oldSlot)


    state.torchCounter = 0

    save()

end


-- ============================================================
-- EINE ABBauPOSITION
-- ============================================================

local function minePosition()

    inventoryCheck()
    fuelCheck()


    -- Block vorne.
    digFront()


    -- Block darueber.
    --
    -- Nur wenn die aktuelle Turtle-Ebene
    -- noch innerhalb der gewuenschten Raumhoehe liegt.
    if state.y + 1 < state.height then

        digAbove()

    end


    -- --------------------------------------------------------
    -- Erst in den abgebauten Block laufen.
    --
    -- Dadurch ist die Turtle immer innerhalb des
    -- vorgesehenen Bereichs.
    -- --------------------------------------------------------

    moveForwardRaw()


    -- Fackel hinter der Turtle.
    torchBehind()


    save()

end


-- ============================================================
-- REIHENRICHTUNG
-- ============================================================

local function rowDirection(row)

    if row % 2 == 1 then
        return 0
    else
        return 2
    end

end


-- ============================================================
-- REIHENWECHSEL
--
-- WICHTIG:
--
-- Der seitliche Wechsel passiert IMMER innerhalb des
-- definierten Raums.
--
-- KEIN Schachbrettmuster.
-- KEINE Wand wird fuer den Reihenwechsel angefasst.
-- ============================================================

local function nextRow(row)

    if row >= state.depth then
        return
    end


    -- Beide Reihen liegen auf +Z.
    face(1)


    moveForwardRaw()


    -- Richtung der naechsten Reihe.
    face(
        rowDirection(
            row + 1
        )
    )


    state.currentRow =
        row + 1

    state.currentCol = 1

    save()

end


-- ============================================================
-- EINEN LAYER ABBauen
-- ============================================================

local function mineLayer(layer)

    state.layer = layer

    -- --------------------------------------------------------
    -- Startposition des Layers.
    --
    -- Jeder Layer beginnt bei:
    --
    -- x = 0
    -- z = 0
    --
    -- und der passenden Hoehe.
    -- --------------------------------------------------------

    local targetY =
        (layer - 1) * 2


    goTo(
        0,
        targetY,
        0
    )


    -- Erste Reihe beginnt immer bei +X.
    face(0)


    local startRow = 1
    local startCol = 1


    -- Falls ein Serverrestart mitten in diesem Layer
    -- passiert ist, ab gespeicherter Position fortsetzen.
    if state.currentLayer == layer then

        startRow =
            state.currentRow or 1

        startCol =
            state.currentCol or 1

    else

        state.currentLayer = layer
        state.currentRow = 1
        state.currentCol = 1

        save()

    end


    for row = startRow, state.depth do

        state.currentRow = row

        -- Richtung der Reihe.
        face(
            rowDirection(row)
        )


        local firstCol = 1

        if row == startRow then
            firstCol = startCol
        end


        for col = firstCol, state.width do

            state.currentRow = row
            state.currentCol = col

            save()


            -- Position abbauen.
            minePosition()


            -- ------------------------------------------------
            -- Nach dem Vorwaertslauf befindet sich die Turtle
            -- bereits beim naechsten Rasterpunkt.
            --
            -- Deshalb speichern wir die naechste Spalte.
            -- ------------------------------------------------

            state.currentCol =
                col + 1

            save()

        end


        -- ----------------------------------------------------
        -- Reihe fertig.
        --
        -- Wenn noch eine Reihe folgt:
        -- einen Block seitlich +Z.
        -- ----------------------------------------------------

        if row < state.depth then

            state.currentRow =
                row + 1

            state.currentCol = 1

            nextRow(row)

        end

    end


    state.currentLayer =
        layer + 1

    state.currentRow = 1
    state.currentCol = 1

    save()

end


-- ============================================================
-- STATUS
-- ============================================================

local function showStatus()

    state =
        loadState()


    if not state then

        print("")
        print("Kein Auftrag gespeichert.")
        print("")

        return

    end


    print("")
    print("==============================")
    print("          MINER V8")
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
        "Layer: "
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
        "Freie Slots: "
        .. freeSlots()
    )

    print(
        "Fuel: "
        .. tostring(
            turtle.getFuelLevel()
        )
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
        print(
            "miner_state wurde geloescht."
        )
        print("")

    else

        print("")
        print(
            "Kein miner_state vorhanden."
        )
        print("")

    end

    return

end


-- ============================================================
-- STATUS
-- ============================================================

if command == "status" then

    showStatus()

    return

end


-- ============================================================
-- RESUME
-- ============================================================

if command == "resume" then

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


    if state.phase == "finished" then

        print("")
        print(
            "Der letzte Auftrag ist bereits fertig."
        )
        print("")

        return

    end


    print("")
    print("==============================")
    print("       MINER V8 RESUME")
    print("==============================")
    print("")

    print(
        "Position: "
        .. state.x
        .. ", "
        .. state.y
        .. ", "
        .. state.z
    )

    print("")

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


    width =
        math.floor(width)

    depth =
        math.floor(depth)

    height =
        math.floor(height)

    torchDistance =
        math.floor(torchDistance)


    if width < 1
    or depth < 1
    or height < 1 then

        print("")
        print(
            "Breite, Tiefe und Hoehe muessen "
            .. "mindestens 1 sein."
        )
        print("")

        return

    end


    if torchDistance < 0 then
        torchDistance = 0
    end


    if fs.exists(STATE_FILE) then
        fs.delete(STATE_FILE)
    end


    state = {

        version = VERSION,

        width = width,
        depth = depth,
        height = height,

        layers =
            math.ceil(
                height / 2
            ),

        layer = 1,
        currentLayer = 1,

        currentRow = 1,
        currentCol = 1,

        torchDistance =
            torchDistance,

        torchCounter = 0,

        x = 0,
        y = 0,
        z = 0,

        -- 0 = Richtung Abbaubereich.
        dir = 0,

        phase = "mining"

    }


    save()


    print("")
    print("==============================")
    print("       MINER V8 START")
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
        "Layer: "
        .. state.layers
    )

    print(
        "Fackelabstand: "
        .. torchDistance
    )

    print("")

end


-- ============================================================
-- KEIN NEUER AUFTRAG?
-- ============================================================

if not state then

    usage()

    return

end


-- ============================================================
-- MINING
-- ============================================================

local ok, err =
    pcall(function()

        state.phase = "mining"

        save()


        -- ----------------------------------------------------
        -- Jeden Layer abarbeiten.
        -- ----------------------------------------------------

        local firstLayer =
            state.currentLayer or 1


        for layer = firstLayer,
            state.layers do

            print("")
            print("==============================")
            print(
                "Layer "
                .. layer
                .. "/"
                .. state.layers
            )
            print("==============================")
            print("")


            state.layer = layer
            save()


            mineLayer(layer)

        end


        -- ----------------------------------------------------
        -- Fertig.
        -- ----------------------------------------------------

        state.phase = "finished"

        save()


        print("")
        print("==============================")
        print("       MINING FERTIG")
        print("==============================")
        print("")


        -- ----------------------------------------------------
        -- Zur Kiste.
        -- ----------------------------------------------------

        goHome()


        face(2)

        checkChest()


        -- Beute abladen.
        unload()


        turtle.select(1)


        print(
            "Inventar abgeladen."
        )

        print(
            "Fackeln behalten: "
            .. countItem(
                "minecraft:torch"
            )
        )

        print(
            "Eimer behalten: "
            .. countItem(
                "minecraft:bucket"
            )
        )

        print("")
        print(
            "Auftrag erfolgreich beendet."
        )
        print("")


    end)


-- ============================================================
-- FEHLERBEHANDLUNG
-- ============================================================

if not ok then

    print("")
    print("==============================")
    print("          FEHLER")
    print("==============================")
    print("")

    print(
        tostring(err)
    )

    print("")

    print(
        "Die Position wurde gespeichert."
    )

    print(
        "Nach Behebung des Problems:"
    )

    print("")

    print(" miner status")
    print(" miner resume")

    print("")

end