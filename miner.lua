-- ============================================================
-- MINER V7
-- CC:Tweaked 1.113.1
-- Minecraft 1.20.x
--
-- AUFBAU:
--
-- [KISTE] [TURTLE] ---> ABBAUBEREICH
--
-- Die Turtle schaut beim Start von der Kiste weg.
--
-- ============================================================
--
-- V7:
--
-- * 2 Block hohe Ebenen
-- * Fackeln NUR auf der untersten Ebene
-- * Fackeln hinter der Turtle
-- * Fackeln bleiben im Inventar
-- * max. 16 Fackeln werden nachgeladen
-- * Eimer bleiben im Inventar
-- * Beute wird ausgeladen
-- * Fuel wird nachgeladen
-- * Wasser/Lava werden aufgenommen
-- * Position + Richtung werden gespeichert
-- * exakte Rueckkehr zum Arbeitsplatz
-- * Serverrestart kann fortgesetzt werden
--
-- ============================================================


local VERSION = 7
local STATE_FILE = "miner_state"


-- ============================================================
-- KONFIGURATION
-- ============================================================

local MIN_FUEL = 1000
local FUEL_MARGIN = 100

local MIN_TORCHES = 4
local REFILL_TORCHES = 16

local MIN_BUCKETS = 2
local REFILL_BUCKETS = 4

local DEFAULT_TORCH_DISTANCE = 6

local MIN_FREE_SLOTS = 2


-- ============================================================
-- RICHTUNGEN
--
-- 0 = +X
-- 1 = +Z
-- 2 = -X
-- 3 = -Z
-- ============================================================


local state
local service


-- ============================================================
-- FEHLER
-- ============================================================

local function die(message)

    error(message, 0)

end


-- ============================================================
-- SPEICHERN
-- ============================================================

local function save()

    local file, err =
        fs.open(STATE_FILE, "w")


    if not file then

        die(
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
-- LADEN
-- ============================================================

local function loadState()

    if not fs.exists(STATE_FILE) then

        return nil

    end


    local file, err =
        fs.open(STATE_FILE, "r")


    if not file then

        die(
            "Kann miner_state nicht lesen: "
            .. tostring(err)
        )

    end


    local data =
        textutils.unserialize(
            file.readAll()
        )


    file.close()


    if not data then

        die(
            "miner_state ist beschaedigt."
        )

    end


    if data.version ~= VERSION then

        die(
            "Alter miner_state gefunden.\n\n"
            .. "Bitte einmal 'delete miner_state' "
            .. "ausfuehren und neuen Auftrag starten."
        )

    end


    return data

end


-- ============================================================
-- HILFE
-- ============================================================

local function usage()

    print("")
    print("==============================")
    print("          MINER V7")
    print("==============================")
    print("")

    print(
        "Neuer Auftrag:"
    )

    print(
        "miner new <breite> <tiefe> <hoehe> [fackeln]"
    )

    print("")

    print(
        "Beispiel:"
    )

    print(
        "miner new 5 5 10 6"
    )

    print("")

    print(
        "Status:"
    )

    print(
        "miner status"
    )

    print("")

    print(
        "Reset:"
    )

    print(
        "miner reset"
    )

    print("")

end


-- ============================================================
-- STATUS
-- ============================================================

if command == "status" then

    state = loadState()


    if not state then

        print("")
        print("Kein Auftrag gespeichert.")
        print("")

        return

    end


    local total =
        state.width
        * state.depth
        * state.layers


    print("")
    print("==============================")
    print("         MINER STATUS")
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
        "Ebene: "
        .. state.layer
        .. "/"
        .. state.layers
    )


    print(
        "Reihe: "
        .. state.row
        .. "/"
        .. state.depth
    )


    print(
        "Spalte: "
        .. state.col
        .. "/"
        .. state.width
    )


    print(
        "Fortschritt: "
        .. state.nextCell
        .. "/"
        .. total
    )


    print(
        "Phase: "
        .. tostring(state.phase)
    )


    print(
        "Fuel: "
        .. tostring(turtle.getFuelLevel())
    )


    print(
        "Fackeln: "
        .. tostring(
            state.torchCount or 0
        )
    )


    print("")
    print("==============================")
    print("")

    return

end


-- ============================================================
-- RESET
-- ============================================================

if command == "reset" then

    if fs.exists(STATE_FILE) then

        fs.delete(STATE_FILE)

        print(
            "miner_state wurde geloescht."
        )

    else

        print(
            "Kein miner_state vorhanden."
        )

    end


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
        tonumber(args[5])
        or DEFAULT_TORCH_DISTANCE


    if not width
    or not depth
    or not height then

        usage()

        return

    end


    if width < 1
    or depth < 1
    or height < 1 then

        die(
            "Breite, Tiefe und Hoehe muessen mindestens 1 sein."
        )

    end


    if torchDistance < 0 then

        torchDistance = 0

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

        torchDistance =
            torchDistance,

        x = 0,

        y = 0,

        z = 0,

        dir = 0,

        layer = 1,

        row = 1,

        col = 1,

        nextCell = 1,

        torchCounter = 0,

        torchCount = 0,

        phase = "mining",

        returnTarget = nil

    }


    save()


    print("")
    print("==============================")
    print("       NEUER MINER V7")
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
    print("Aufbau:")
    print("")
    print("[KISTE] [TURTLE] ---> ABBAUBEREICH")
    print("")
    print("Die Turtle muss von der Kiste wegschauen.")
    print("")

end


-- ============================================================
-- STATE LADEN
-- ============================================================

if not state then

    state = loadState()


    if not state then

        usage()

        return

    end

end


-- ============================================================
-- INVENTAR
-- ============================================================

local function freeSlots()

    local free = 0


    for slot = 1, 16 do

        if turtle.getItemCount(slot) == 0 then

            free = free + 1

        end

    end


    return free

end


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


-- ============================================================
-- DREHEN
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
-- POSITION VORWAERTS
-- ============================================================

local function updateForward()

    if state.dir == 0 then

        state.x =
            state.x + 1


    elseif state.dir == 1 then

        state.z =
            state.z + 1


    elseif state.dir == 2 then

        state.x =
            state.x - 1


    elseif state.dir == 3 then

        state.z =
            state.z - 1

    end

end


-- ============================================================
-- FUEL
-- ============================================================

local function fuel()

    return turtle.getFuelLevel()

end


local function distanceHome()

    return
        math.abs(state.x)
        + math.abs(state.y)
        + math.abs(state.z)

end


local function refuelFromInventory()

    if fuel() == "unlimited" then

        return

    end


    for slot = 1, 16 do

        local item =
            turtle.getItemDetail(slot)


        if item then

            if item.name ==
                "minecraft:coal"
            or item.name ==
                "minecraft:charcoal"
            or item.name ==
                "minecraft:coal_block" then

                turtle.select(slot)


                while turtle.refuel(1) do
                end

            end

        end

    end


    turtle.select(1)

end


local function ensureFuel()

    if fuel() == "unlimited" then

        return

    end


    local needed =
        distanceHome()
        + MIN_FUEL
        + FUEL_MARGIN


    if fuel() < needed then

        service()

    end

end


-- ============================================================
-- FLUESSIGKEIT
-- ============================================================

local function isFluid(data)

    if not data
    or not data.name then

        return false

    end


    local name =
        string.lower(data.name)


    return
        name == "minecraft:water"
        or
        name == "minecraft:lava"

end


local function collectFront()

    local slot =
        findItem(
            "minecraft:bucket"
        )


    if not slot then

        service()


        slot =
            findItem(
                "minecraft:bucket"
            )

    end


    if not slot then

        die(
            "Kein leerer Eimer vorhanden."
        )

    end


    local old =
        turtle.getSelectedSlot()


    turtle.select(slot)


    turtle.place()


    turtle.select(old)

end


local function collectUp()

    local slot =
        findItem(
            "minecraft:bucket"
        )


    if not slot then

        service()


        slot =
            findItem(
                "minecraft:bucket"
            )

    end


    if not slot then

        die(
            "Kein leerer Eimer vorhanden."
        )

    end


    local old =
        turtle.getSelectedSlot()


    turtle.select(slot)


    turtle.placeUp()


    turtle.select(old)

end


local function collectDown()

    local slot =
        findItem(
            "minecraft:bucket"
        )


    if not slot then

        service()


        slot =
            findItem(
                "minecraft:bucket"
            )

    end


    if not slot then

        die(
            "Kein leerer Eimer vorhanden."
        )

    end


    local old =
        turtle.getSelectedSlot()


    turtle.select(slot)


    turtle.placeDown()


    turtle.select(old)

end


-- ============================================================
-- VORWAERTS
-- ============================================================

local function forward()

    ensureFuel()


    while true do

        if turtle.forward() then

            updateForward()

            save()

            return

        end


        local ok, data =
            turtle.inspect()


        if ok and isFluid(data) then

            collectFront()

        else

            if freeSlots()
                < MIN_FREE_SLOTS then

                service()

            end


            if not turtle.dig() then

                turtle.attack()

                sleep(0.1)

            end

        end


        sleep(0.05)

    end

end


-- ============================================================
-- HOCH
-- ============================================================

local function up()

    ensureFuel()


    while true do

        if turtle.up() then

            state.y =
                state.y + 1


            save()


            return

        end


        local ok, data =
            turtle.inspectUp()


        if ok and isFluid(data) then

            collectUp()

        else

            if freeSlots()
                < MIN_FREE_SLOTS then

                service()

            end


            if not turtle.digUp() then

                turtle.attackUp()

                sleep(0.1)

            end

        end


        sleep(0.05)

    end

end


-- ============================================================
-- RUNTER
-- ============================================================

local function down()

    ensureFuel()


    while true do

        if turtle.down() then

            state.y =
                state.y - 1


            save()


            return

        end


        local ok, data =
            turtle.inspectDown()


        if ok and isFluid(data) then

            collectDown()

        else

            if freeSlots()
                < MIN_FREE_SLOTS then

                service()

            end


            if not turtle.digDown() then

                turtle.attackDown()

                sleep(0.1)

            end

        end


        sleep(0.05)

    end

end


-- ============================================================
-- ZU POSITION
-- ============================================================

local function goTo(targetX, targetY, targetZ)

    -- Y zuerst.
    while state.y < targetY do

        up()

    end


    while state.y > targetY do

        down()

    end


    -- X.
    if state.x < targetX then

        face(0)


        while state.x < targetX do

            forward()

        end

    elseif state.x > targetX then

        face(2)


        while state.x > targetX do

            forward()

        end

    end


    -- Z.
    if state.z < targetZ then

        face(1)


        while state.z < targetZ do

            forward()

        end

    elseif state.z > targetZ then

        face(3)


        while state.z > targetZ do

            forward()

        end

    end

end


-- ============================================================
-- KISTE PRUEFEN
-- ============================================================

local function checkChest()

    local ok, data =
        turtle.inspect()


    if not ok then

        die(
            "Keine Kiste hinter der Turtle gefunden.\n\n"
            .. "[KISTE] [TURTLE] ---> MINING"
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

        die(
            "Hinter der Turtle steht keine Kiste."
        )

    end

end


-- ============================================================
-- KISTE
-- ============================================================

local function getChest()

    local chest =
        peripheral.wrap("front")


    if not chest then

        die(
            "Die Kiste konnte nicht als Inventar erkannt werden."
        )

    end


    if not chest.list
    or not chest.size
    or not chest.pushItems then

        die(
            "Die Kiste stellt keine Inventar-Funktionen bereit."
        )

    end


    return chest

end


-- ============================================================
-- ENTLADEN
--
-- Fackeln und leere Eimer bleiben in der Turtle.
-- ============================================================

local function unload(chest)

    print("Inventar wird entladen...")


    for slot = 1, 16 do

        local item =
            turtle.getItemDetail(slot)


        if item then

            local keep = false


            if item.name ==
                "minecraft:torch" then

                keep = true

            end


            if item.name ==
                "minecraft:bucket" then

                keep = true

            end


            if not keep then

                turtle.select(slot)


                turtle.drop()

            end

        end

    end


    turtle.select(1)


    state.torchCount =
        countItem("minecraft:torch")


    save()

end


-- ============================================================
-- KISTE DURCHSUCHEN
-- ============================================================

local function chestFind(chest, wanted)

    local items =
        chest.list()


    for slot, item in pairs(items) do

        for _, name in ipairs(wanted) do

            if item.name == name then

                return slot

            end

        end

    end


    return nil

end


-- ============================================================
-- AUS KISTE HOLEN
-- ============================================================

local function take(chest, wanted, amount)

    local source =
        chestFind(
            chest,
            wanted
        )


    if not source then

        return false

    end


    local target = nil


    for slot = 1, 16 do

        local item =
            turtle.getItemDetail(slot)


        if not item then

            target = slot

            break

        end


        if turtle.getItemSpace(slot) > 0 then

            for _, name in ipairs(wanted) do

                if item.name == name then

                    target = slot

                    break

                end

            end

        end


        if target then

            break

        end

    end


    if not target then

        return false

    end


    local old =
        turtle.getSelectedSlot()


    turtle.select(target)


    local result =
        turtle.suck(amount)


    turtle.select(old)


    return result

end


-- ============================================================
-- FUEL NACHFUELLEN
-- ============================================================

local function refillFuel(chest)

    if fuel() == "unlimited" then

        return

    end


    refuelFromInventory()


    if fuel() >= MIN_FUEL then

        return

    end


    print("Fuel wird nachgeladen...")


    while fuel() < MIN_FUEL do

        local got =
            take(
                chest,
                {
                    "minecraft:coal",
                    "minecraft:charcoal",
                    "minecraft:coal_block"
                },
                64
            )


        if not got then

            break

        end


        refuelFromInventory()

    end


    if fuel() < MIN_FUEL then

        die(
            "Nicht genug Fuel in der Kiste."
        )

    end

end


-- ============================================================
-- FACKELN NACHLADEN
-- ============================================================

local function refillTorches(chest)

    if state.torchDistance <= 0 then

        return

    end


    local current =
        countItem("minecraft:torch")


    state.torchCount =
        current


    save()


    if current >= MIN_TORCHES then

        return

    end


    print(
        "Nur "
        .. current
        .. " Fackeln vorhanden."
    )


    print(
        "Fackeln werden nachgeladen..."
    )


    local amount =
        REFILL_TORCHES - current


    if amount <= 0 then

        return

    end


    take(
        chest,
        {
            "minecraft:torch"
        },
        amount
    )


    state.torchCount =
        countItem("minecraft:torch")


    save()


    if state.torchCount < MIN_TORCHES then

        die(
            "Zu wenige Fackeln in der Kiste."
        )

    end

end


-- ============================================================
-- EIMER NACHLADEN
-- ============================================================

local function refillBuckets(chest)

    local current =
        countItem(
            "minecraft:bucket"
        )


    if current >= MIN_BUCKETS then

        return

    end


    print(
        "Leere Eimer werden nachgeladen..."
    )


    local amount =
        REFILL_BUCKETS - current


    take(
        chest,
        {
            "minecraft:bucket"
        },
        amount
    )


    if countItem("minecraft:bucket")
        < MIN_BUCKETS then

        die(
            "Zu wenige leere Eimer in der Kiste."
        )

    end

end


-- ============================================================
-- SERVICE
-- ============================================================

service = function()

    -- --------------------------------------------------------
    -- ARBEITSPLATZ SPEICHERN
    -- --------------------------------------------------------

    if state.phase == "mining" then

        state.returnTarget = {

            x = state.x,

            y = state.y,

            z = state.z,

            dir = state.dir

        }


        state.phase = "service"


        save()

    end


    local target =
        state.returnTarget


    if not target then

        die(
            "Kein Rueckkehrziel gespeichert."
        )

    end


    print("")
    print("==============================")
    print("         ZUR KISTE")
    print("==============================")
    print("")


    -- --------------------------------------------------------
    -- ZUR STARTPOSITION
    -- --------------------------------------------------------

    goTo(
        0,
        0,
        0
    )


    -- --------------------------------------------------------
    -- KISTE LIEGT BEI -X
    -- --------------------------------------------------------

    face(2)


    checkChest()


    local chest =
        getChest()


    -- --------------------------------------------------------
    -- BEUTE ENTLADEN
    -- --------------------------------------------------------

    unload(chest)


    -- --------------------------------------------------------
    -- VORRAETE
    -- --------------------------------------------------------

    refillFuel(chest)

    refillTorches(chest)

    refillBuckets(chest)


    -- --------------------------------------------------------
    -- ZURUECK IN RICHTUNG MINING
    -- --------------------------------------------------------

    face(0)


    -- --------------------------------------------------------
    -- EXAKT ZUM ARBEITSPLATZ
    -- --------------------------------------------------------

    goTo(
        target.x,
        target.y,
        target.z
    )


    -- Urspruengliche Blickrichtung wiederherstellen.
    face(target.dir)


    state.returnTarget = nil

    state.phase = "mining"


    save()


    print("")
    print("Zurueck am gespeicherten Arbeitsplatz.")
    print("")

end


-- ============================================================
-- FACKEL SETZEN
--
-- NUR AUF DER UNTERSTEN EBENE!
--
-- Die Turtle setzt sie hinter sich.
-- ============================================================

local function placeTorch()

    -- Keine Fackeln gewuenscht.
    if state.torchDistance <= 0 then

        return

    end


    -- ========================================================
    -- WICHTIG:
    --
    -- Sobald Y > 0 ist, werden KEINE Fackeln mehr gesetzt.
    --
    -- Da die erste Ebene Y=0/1 ist, bleiben Fackeln
    -- auch auf Y=1 noch erlaubt.
    --
    -- Ab der naechsten 2-Block-Ebene Y>=2:
    -- keine Fackeln.
    -- ========================================================

    if state.y >= 2 then

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

        die(
            "Keine Fackeln vorhanden."
        )

    end


    local oldSlot =
        turtle.getSelectedSlot()


    local oldDir =
        state.dir


    turtle.select(slot)


    -- --------------------------------------------------------
    -- Hinter uns drehen.
    -- --------------------------------------------------------

    face(
        (oldDir + 2) % 4
    )


    -- --------------------------------------------------------
    -- Fackel an die Wand hinter uns.
    -- --------------------------------------------------------

    local placed =
        turtle.place()


    -- --------------------------------------------------------
    -- Wieder nach vorne.
    -- --------------------------------------------------------

    face(oldDir)


    turtle.select(oldSlot)


    if placed then

        state.torchCounter = 0

    end


    state.torchCount =
        countItem("minecraft:torch")


    save()

end


-- ============================================================
-- EINE ZELLE ABBAUEN
-- ============================================================

local function mineCell()

    -- --------------------------------------------------------
    -- Block vor uns.
    -- --------------------------------------------------------

    local ok, data =
        turtle.inspect()


    if ok then

        if isFluid(data) then

            collectFront()

        else

            if freeSlots()
                < MIN_FREE_SLOTS then

                service()

            end


            turtle.dig()

        end

    end


    -- --------------------------------------------------------
    -- Block ueber uns.
    --
    -- Nur wenn dieser innerhalb des Raumes liegt.
    -- --------------------------------------------------------

    if state.y + 1 < state.height then

        local upOk, upData =
            turtle.inspectUp()


        if upOk then

            if isFluid(upData) then

                collectUp()

            else

                if freeSlots()
                    < MIN_FREE_SLOTS then

                    service()

                end


                turtle.digUp()

            end

        end

    end


    -- --------------------------------------------------------
    -- Fackel nur auf Ebene 1.
    -- --------------------------------------------------------

    placeTorch()


    save()

end


-- ============================================================
-- ZELLPOSITION
-- ============================================================

local function cellPosition(index)

    local width =
        state.width


    local depth =
        state.depth


    local perLayer =
        width * depth


    local layer =
        math.floor(
            (index - 1) / perLayer
        ) + 1


    local inside =
        (index - 1) % perLayer


    local row =
        math.floor(
            inside / width
        ) + 1


    local col =
        (inside % width
        ) + 1


    local x


    if row % 2 == 1 then

        x =
            col - 1

    else

        x =
            width - col

    end


    local z =
        row - 1


    local y =
        (layer - 1) * 2


    return x, y, z

end


-- ============================================================
-- FERTIG
-- ============================================================

local function finish()

    state.phase = "final"


    save()


    print("")
    print("==============================")
    print("        MINING FERTIG")
    print("==============================")
    print("")


    goTo(
        0,
        0,
        0
    )


    face(2)


    checkChest()


    local chest =
        getChest()


    unload(chest)


    face(0)


    state.phase = "finished"


    save()


    print("")
    print("==============================")
    print("           FERTIG")
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

end


-- ============================================================
-- WIEDERHERSTELLUNG SERVICE
-- ============================================================

local function resumeService()

    print("")
    print(
        "Unterbrochener Kistenbesuch gefunden."
    )
    print("")


    service()

end


-- ============================================================
-- WIEDERHERSTELLUNG FINAL
-- ============================================================

local function resumeFinal()

    print("")
    print(
        "Unterbrochene Rueckkehr gefunden."
    )
    print("")


    goTo(
        0,
        0,
        0
    )


    face(2)


    checkChest()


    local chest =
        getChest()


    unload(chest)


    face(0)


    state.phase = "finished"


    save()


    print(
        "Auftrag abgeschlossen."
    )

end


-- ============================================================
-- HAUPTPROGRAMM
-- ============================================================

print("")
print("==============================")
print("          MINER V7")
print("==============================")
print("")


-- Auftrag bereits fertig.
if state.phase == "finished" then

    print(
        "Dieser Auftrag ist bereits fertig."
    )


    print("")
    print(
        "Neuer Auftrag:"
    )


    print(
        "miner new <breite> <tiefe> <hoehe> [fackeln]"
    )


    return

end


-- Service fortsetzen.
if state.phase == "service" then

    resumeService()

    return

end


-- Finale Rueckkehr fortsetzen.
if state.phase == "final" then

    resumeFinal()

    return

end


-- ============================================================
-- MINING
-- ============================================================

local total =
    state.width
    * state.depth
    * state.layers


while state.nextCell <= total do

    local index =
        state.nextCell


    local x, y, z =
        cellPosition(index)


    state.layer =
        math.floor(y / 2) + 1


    state.row =
        z + 1


    state.col =
        x + 1


    save()


    print(
        "Zelle "
        .. index
        .. "/"
        .. total
        .. "  "
        .. x
        .. ","
        .. y
        .. ","
        .. z
    )


    -- --------------------------------------------------------
    -- Zur Zielposition.
    -- --------------------------------------------------------

    goTo(
        x,
        y,
        z
    )


    -- --------------------------------------------------------
    -- Zelle abbauen.
    -- --------------------------------------------------------

    mineCell()


    -- --------------------------------------------------------
    -- Zelle erledigt.
    -- --------------------------------------------------------

    state.nextCell =
        state.nextCell + 1


    save()


    -- --------------------------------------------------------
    -- Wenn diese Ebene fertig ist und noch eine weitere
    -- existiert, geht die Turtle exakt 2 Bloecke hoch.
    --
    -- Die naechste Zelle wird danach automatisch bei Y+2
    -- angefahren.
    -- --------------------------------------------------------

    sleep(0.05)

end


-- ============================================================
-- FERTIG
-- ============================================================

finish()

