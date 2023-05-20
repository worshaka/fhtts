-- require('json')
-- require('fhlog')

-- A collection of Lua objects to capture game state

-- Utility functions

function shuffle(table)
    for i = #table, 2, -1 do
        local j = math.random(i)
        table[i], table[j] = table[j], table[i]
    end
end

function map(list, func)
    local result = {}
    for _, entry in ipairs(list) do
        table.insert(result, func(entry))
    end
    return result
end

function mapDictToList(dict, func)
    local result = {}
    for name, entry in pairs(dict) do
        table.insert(result, func(name, entry))
    end
    return result
end

function mapDict(dict, func)
    local result = {}
    for name, entry in pairs(dict) do
        result[name] = func(entry)
    end
    return result
end

function identity(e)
    return e
end

-- Card Class

Card = {}
Card.__index = Card
function Card.new(json)
    local self = setmetatable({}, Card)
    self.nr = json[1]
    self.shuffle = json[2]
    self.initiative = json[3]
    return self
end

function Card.newFromSave(save)
    -- Same constructor when loading from a save
    return Card.new(save)
end

function Card:save()
    return {
        self.number, self.shuffle, self.initiative
    }
end

-- Pile class

Pile = {}
Pile.__index = Pile
function Pile.new()
    local self = setmetatable({}, Pile)
    self.cards = {}
    return self
end

function Pile.newFromSave(save)
    local self = Pile.new()
    self.cards = map(save, Card.newFromSave)
    return self
end

function Pile:save()
    return map(self.cards, Card.save)
end

function Pile:addCard(card)
    table.insert(self.cards, card)
end

function Pile:drawCard()
    local cards = self.cards
    if #cards > 0 then
        local card = cards[#cards]
        table.remove(cards, #cards)
        return card
    else
        return nil
    end
end

function Pile:shuffle()
    shuffle(self.cards)
end

function Pile:shouldShuffle()
    for _, card in ipairs(self.cards) do
        if card.shuffle then
            return true
        end
    end
    return false
end

function Pile:moveCardsTo(otherPile)
    for _, card in ipairs(self.cards) do
        otherPile:addCard(card)
    end
    self.cards = {}
end

-- Deck

Deck = {}
Deck.__index = Deck

function Deck.new(json)
    local self = setmetatable({}, Deck)
    self.drawPile = Pile.new()
    self.discardPile = Pile.new()

    if json ~= nil then
        for _, cardJson in ipairs(json) do
            self:addCard(Card.new(cardJson))
        end
    end
    self.drawPile:shuffle()
    return self
end

function Deck.newFromSave(save)
    local self = setmetatable({}, Deck)
    self.drawPile = Pile.newFromSave(save.draw)
    self.discardPile = Pile.newFromSave(save.discard)
    return self
end

function Deck:save()
    return {
        draw = self.drawPile:save(),
        discard = self.discardPile:save()
    }
end

function Deck:addCard(card)
    self.drawPile:addCard(card)
end

function Deck:draw()
    local card = self.drawPile:drawCard()
    if card ~= nil then
        self.discardPile:addCard(card)
    end
    return card
end

function Deck:shouldShuffle()
    return self.discardPile:shouldShuffle()
end

function Deck:shuffle()
    self.discardPile:moveCardsTo(self.drawPile)
    self.drawPile:shuffle()
end

function Deck:shuffleIfNeeded()
    self.currentCard = nil
    if self:shouldShuffle() then
        self:shuffle()
    end
end

-- Formula class
Formula = {}
Formula.__index = Formula

function Formula.new(str)
    local self = setmetatable({}, Formula)
    self:parse(str)    
    return self
end

function Formula:parse(str)
    -- fhlog(INFO, "Formula", "parsing %s", str)
    local operators = { "/", "x" }
    local foundOperator = false
    for _, operator in ipairs(operators) do
        local idx = string.find(str, operator)
        if idx and not foundOperator then
            self.operator = operator
            self.left = Formula.new(string.sub(str, 1, idx - 1))
            self.right = Formula.new(string.sub(str, idx + 1))
            foundOperator = true
        end
    end
    if not foundOperator then
        self.value = str
    end
end

function Formula:eval(nbCharacters)
    if self.value ~= nil then
        if self.value == "C" then
            return nbCharacters
        else
            return tonumber(self.value)
        end
    else
        if self.operator == "/" then
            return self.left:eval(nbCharacters) / self.right:eval(nbCharacters)
        elseif self.operator == "x" then
            return self.left:eval(nbCharacters) * self.right:eval(nbCharacters)
        end
    end
    return 0
end

-- MonsterInstance class

MonsterInstance = {}
MonsterInstance.__index = MonsterInstance

function MonsterInstance.new(monster, nr, level, type)
    local self = setmetatable({}, MonsterInstance)
    self.monster = monster
    self.level = level
    self.type = type or "normal"
    self.nr = nr
    self.conditions = {}
    self:updateBaseStats()
    return self
end

function MonsterInstance:updateBaseStats()
    local damage = (self.maxHp or 0) - (self.hp or 0)
    local monsterLevel = self.monster.levels[self.level + 1][self.type]
    -- Fix boss hps dependent on "C"
    local nbCharacters = self.monster.gameState:nbCharacters()
    local maxHp = monsterLevel.hp:eval(nbCharacters)
    self.hp = maxHp - damage
    self.maxHp = maxHp
    self.baseShield = monsterLevel.baseShield or 0
    self.baseRetaliate = monsterLevel.baseRetaliate or 0
    self.basePierce = monsterLevel.basePierce or 0
    self.immunities = map(monsterLevel.immunities or {}, identity)
    self.applyConditions = map(monsterLevel.conditions or {}, identity)
end

function MonsterInstance.newFromSave(monster, level, save)
    local self = setmetatable({}, MonsterInstance)
    self.monster = monster
    self.level = level
    self.hp = save.hp
    self.maxHp = save.maxHp
    self.nr = save.nr
    self.type = save.type
    self.conditions = save.conditions
    self:updateBaseStats()
    return self
end

function MonsterInstance:save()
    return {
        type = self.type,
        nr = self.nr,
        hp = self.hp,
        maxHp = self.maxHp,
        conditions = self.conditions,
    }
end

function MonsterInstance:switchType()
    if self.type == "normal" then
        self.type = "elite"
    elseif self.type == "elite" then
        self.type = "normal"
    end
    self:updateBaseStats()
end

function MonsterInstance:changeHp(amount)
    self.hp = self.hp + amount
    if self.hp <= 0 then
        -- death, free up this instance
        self.monster:removeInstance(self)
    elseif self.hp > self.maxHp then
        self.hp = self.maxHp
    end
end

function MonsterInstance:toggleCondition(condition)
    local current = self.conditions[condition] or false
    if not current then
        -- check immunities
        for _, immunity in ipairs(self.immunities) do
            if immunity == condition then
                broadcastToAll(self.monster.name .. " is immune to " .. condition)
                return
            end
        end
    end
    self.conditions[condition] = not current or nil
end

function MonsterInstance:setLevel(level)
    self.level = level
    self:updateBaseStats()
end

function MonsterInstance:toState()
    return {
        type = self.type,
        standeeNr = self.nr,
        health = self.hp,
        maxHealth = self.maxHp,
        baseShield = self.baseShield,
        baseRetaliate = self.baseRetaliate,
        basePierce = self.basePierce,
        conditions = mapDictToList(self.conditions, function(k, v) return ConditionMapping[k] end),
        level = self.level,
    }
end

MonsterLevelType = {}
MonsterLevelType.__index = MonsterLevelType
function MonsterLevelType.new(json)
    local self = setmetatable({}, MonsterLevelType)
    self.hp = Formula.new(json.hp)
    self.shield = json.shield or 0
    self.retaliate = json.retaliate or 0
    self.immunities = json.immunities or {}
    self.conditions = json.conditions or {}
    return self
end

MonsterLevel = {}
MonsterLevel.__index = MonsterLevel

function MonsterLevel.new(json)
    local self = setmetatable({}, MonsterLevel)
    if json.normal then
        self.normal = MonsterLevelType.new(json.normal)
    else
        self.normal = {}
    end
    if json.elite then
        self.elite = MonsterLevelType.new(json.elite)
    else
        self.elite = {}
    end
    if json.boss then
        self.boss = MonsterLevelType.new(json.boss)
    else
        self.boss = {}
    end
    return self
end

Monster = {}
Monster.__index = Monster

function Monster.new(gameState, json)
    local remainingStandees = {}
    for i = 1, json.maxInstances do
        table.insert(remainingStandees, i)
    end
    shuffle(remainingStandees)
    local self = setmetatable({}, Monster)
    self.gameState = gameState
    self.name = json.name
    self.internal = json.internal
    self.deck = gameState.decks[json.deck]
    self.instances = {}
    self.remainingStandees = remainingStandees
    self.isBoss = json.isBoss
    self.level = gameState.level
    self.levels = map(json.levels, MonsterLevel.new)
    self.turnState = 0
    return self
end

function Monster.newFromSave(gameState, json, save)
    local self = setmetatable({}, Monster)
    self.gameState = gameState
    self.name = save.name
    self.internal = save.internal
    self.levels = map(json.levels, MonsterLevel.new)
    self.deck = gameState.decks[json.deck]
    self.instances = map(save.instances,
        function(e) return MonsterInstance.newFromSave(self, save.level, e) end)
    self.remainingStandees = map(save.remainingStandees, identity)
    self.isBoss = save.isBoss
    self.level = save.level
    self.initiative = save.initiative
    self.currentCard = save.currentCard ~= nil and Card.newFromSave(save.currentCard) or nil
    self.turnState = save.turnState
    return self
end

function Monster:save()
    return {
        name = self.name,
        internal = self.internal,
        instances = map(self.instances, MonsterInstance.save),
        remainingStandees = map(self.remainingStandees, identity),
        isBoss = self.isBoss,
        level = self.level,
        initiative = self.initiative,
        currentCard = self.currentCard ~= nil and self.currentCard:save() or nil,
        turnState = self.turnState
    }
end

function Monster:newInstance(type)
    local standees = self.remainingStandees
    if #standees > 0 then
        local nr = standees[#standees]
        table.remove(standees, #standees)
        local instance = MonsterInstance.new(self, nr, self.level, type)
        table.insert(self.instances, instance)
        return instance
    else
        return nil
    end
end

function Monster:removeInstance(instance)
    for i = #self.instances, 1, -1 do
        if self.instances[i] == instance then
            local nr = instance.nr
            table.insert(self.remainingStandees, nr)
            shuffle(self.remainingStandees)
            table.remove(self.instances, i)
        end
    end
end

function Monster:findInstance(nr)
    for _, instance in ipairs(self.instances) do
        if instance.nr == nr or (instance.type == "boss" and nr == 0) then
            return instance
        end
    end
    return nil
end

function Monster:startRound()
    if #self.instances > 0 then
        self.currentCard = self.deck:draw()
        if self.currentCard == nil then
            fhlog(ERROR, "GameState", "Monster type %s drew no card", self.name)
        end
        self.initiative = self.currentCard.initiative
    end
end

function Monster:endRound()
    self.currentCard = nil
    self.initiative = 100
    self.deck:shuffleIfNeeded()
end

function Monster:setLevel(level)
    self.level = level
    for _, instance in ipairs(self.instances) do
        instance:setLevel(level)
    end
end

function Monster:toState()
    local result = {
        id = self.internal,
        name = self.name,
        turnState = self.turnState,
        level = self.level,
        monsterInstances = map(self.instances, MonsterInstance.toState)
    }
    if self.currentCard ~= nil then
        result.currentCard = self.currentCard.nr
        result.initiative = self.currentCard.initiative
    else
        result.currentCard = 0
        result.initiative = 100
    end
    return result
end

Summon = {}
Summon.__index = Summon
function Summon.new(character, model, nr)
    local self = setmetatable({}, Summon)
    self.character = character
    self.name = model.name
    self.nr = nr
    self.maxHp = model.hp
    self.hp = model.hp
    self.conditions = {}
    return self
end

function Summon.newFromSave(character, save)
    local self = setmetatable({}, Summon)
    self.character = character
    self.name = save.name
    self.nr = save.nr
    self.maxHp = save.maxHp
    self.hp = save.hp
    self.conditions = map(save.conditions, identity)
    return self
end

function Summon.save()
    return {
        name = self.name,
        nr = self.nr,
        hp = self.hp,
        maxHp = self.maxHp,
        conditions = map(self.conditions, identity)
    }
end

function Summon:changeHp(amount)
    self.hp = self.hp + amount
    if self.hp <= 0 then
        self.character:removeSummon(self.name, self.nr)
    end
end

function Summon:toggleCondition(condition)
    local current = self.conditions[condition] or false    
    self.conditions[condition] = not current or nil
end

function Summon:toState()
    return {
        name = self.name,
        standeeNr = self.nr,
        health = self.hp,
        maxHealth = self.maxHp,
    }
end

Character = {}
Character.__index = Character

function Character.new(json)
    local self = setmetatable({}, Character)
    self.name = json.name
    self.hps = json.hps
    self.level = 1
    self.summons = json.summons or {}
    self.activeSummons = {}
    self.turnState = 0
    self.conditions = {}
    self:reset()
    return self
end

function Character.newFromSave(json, save)
    local self = setmetatable({}, Character)
    self.name = save.name
    self.hps = json.hps
    self.level = save.level
    self.initiative = save.initiative
    self.hp = save.hp
    self.maxHp = save.maxHp
    self.xp = save.xp
    self.summons = json.summons
    self.activeSummons = map(save.summons, function(summon) return Summon.newFromSave(self, summon) end)
    self.turnState = save.turnState
    self.conditions = save.conditions
    return self
end

function Character:save()
    return {
        name = self.name,
        level = self.level,
        initiative = self.initiative,
        hp = self.hp,
        maxHp = self.maxHp,
        xp = self.xp,
        summons = map(self.activeSummons, Summon.save),
        turnState = self.turnState,
        conditions = self.conditions,
    }
end

function Character:reset()
    self.initiative = 0
    self.hp = self.hps[self.level]
    self.maxHp = self.hps[self.level]
    self.xp = 0
end

function Character:addSummon(name)
    local summonModel = self:findSummonModel(name)
    if summonModel ~= nil then
        -- Count currently active summons of the name
        local alreadySpawned = 0
        for _, summon in ipairs(self.activeSummons) do
            if summon.name == name then
                alreadySpawned = alreadySpawned + 1
            end
        end

        if alreadySpawned < summonModel.maxInstances then
            local summon = Summon.new(self, summonModel, alreadySpawned + 1)
            table.insert(self.activeSummons, summon)
            return summon
        end
    end
end

function Character:startRound(initiative)
    self.initiative = initiative
end

function Character:endRound()
    self.initiative = 0
end

function Character:changeHp(amount)
    self.hp = self.hp + amount
    if self.hp < 0 then
        self.hp = 0
    end
end

function Character:changeXp(amount)
    self.xp = self.xp + amount
    if self.xp < 0 then
        self.xp = 0
    end
end

function Character:changeLevel(amount)
    self.level = amount
    self.hp = self.hps[self.level]
    self.maxHp = self.hps[self.level]
end

function Character:toggleCondition(condition)
    local current = self.conditions[condition] or false
    self.conditions[condition] = not current or nil
end

function Character:removeSummon(name, nr)
    local activeSummons = self.activeSummons
    for i = #activeSummons, 1, -1 do
        if activeSummons[i].name == name and activeSummons[i].nr == nr then
            table.remove(activeSummons, i)
        end
    end
end

function Character:findSummonModel(name)
    for _, summon in ipairs(self.summons) do
        if summon.name == name then
            return summon
        end
    end
end

function Character:toState()
    return {
        id = self.name,
        turnState = self.turnState,
        initiative = self.initiative,
        characterState = {
            health = self.hp,
            maxHealth = self.maxHp,
            level = self.level,
            xp = self.xp,
            summonList = map(self.summons, Summon.toState),
            conditions = mapDictToList(self.conditions, function(k,v) return ConditionMapping[k] end)
        }
    }
end

GameState = {}
GameState.__index = GameState

function GameState.new(gameData)
    ensureConditionsMappings()
    local self = setmetatable({}, GameState)
    self.gameData = gameData
    self.characters = {}
    self.monsters = {}
    self.round = 1
    self.roundState = 0
    self.level = 0
    self.decks = {}
    self.elements = { fire = 0, ice = 0, air = 0, earth = 0, light = 0, dark = 0 }
    return self
end

function GameState.newFromSave(gameData, save)
    ensureConditionsMappings()
    local self = setmetatable({}, GameState)
    self.gameData = gameData
    self.round = save.round
    self.roundState = save.roundState
    self.level = save.level
    self.elements = mapDict(save.elements, identity)
    self.decks = mapDict(save.decks, Deck.newFromSave)
    self.characters = mapDict(save.characters,
        function(e) return Character.newFromSave(gameData.characters[e.name], e) end)
    self.monsters = mapDict(save.monsters, function(e)
        local monsterData = gameData.monsters[e.internal]
        return Monster.newFromSave(self, monsterData, e)
    end)
    return self
end

function GameState:save()
    -- Save pretty much everything, except for gameData
    return {
        characters = mapDict(self.characters, Character.save),
        monsters = mapDict(self.monsters, Monster.save),
        round = self.round,
        roundState = self.roundState,
        level = self.level,
        decks = mapDict(self.decks, Deck.save),
        elements = mapDict(self.elements, identity)
    }
end

function GameState:addCharacter(name)
    fhlog(DEBUG, "GameState", "Adding character %s", name)
    local characterModel = self.gameData.characters[name]
    if characterModel ~= nil then
        self.characters[name] = Character.new(characterModel)
    end
end

function GameState:removeCharacter(name)
    fhlog(DEBUG, "GameState", "Removing character %s", name)
    self.characters[name] = nil
end

function GameState:addMonster(name, boss)
    boss = boss or false
    local monsterData = self.gameData.monsters[name]
    if monsterData ~= nil then
        local deck = self:ensureDeck(monsterData.deck)
        if deck ~= nil then
            local monster = Monster.new(self, monsterData)
            self.monsters[monster.name] = monster
        else
            fhlog(ERROR, "GameState", "Could not find deck for %s (%s)", name, monsterData.deck)
        end
    end
end

function GameState:ensureDeck(name)
    if self.decks[name] ~= nil then
        return self.decks[name]
    end
    local deckModel = self.gameData.decks[name]
    if deckModel ~= nil then
        local deck = Deck.new(deckModel.cards)
        self.decks[name] = deck
        return deck
    end
    return nil
end

function GameState:setLevel(level)
    self.level = level
    -- Also change all existing monsters
    for _, monster in pairs(self.monsters) do
        monster:setLevel(level)
    end
end

function GameState:newMonsterInstance(name, type)
    fhlog(DEBUG, "GameState", "Adding new monster instance of %s (%s)", name, type)
    local monster = self.monsters[name]
    if monster ~= nil then
        local instance = monster:newInstance(type)
        if instance ~= nil then
            fhlog(DEBUG, "GameState", "Got instance : %s", instance.nr)
        else
            fhlog(DEBUG, "GameState", "No instance created")
        end
        if self.roundState == 1 and monster.currentCard == nil then
            monster:startRound()
        end
        return instance
    end
end

function GameState:change(what, name, nr, amount)
    fhlog(DEBUG, "GameState", "Change %s on %s (%s) by %s", what, name, nr or "", amount)
    local target = self:findTarget(name, nr)
    if target ~= nil then
        if what == "hp" then
            target:changeHp(amount)
        elseif what == "xp" then
            target:changeXp(amount)
        elseif what == "level" then
            target:changeLevel(amount)
        end
    end
end

function GameState:startRound(characterInitiatives)
    if self.roundState ~= 0 then
        fhlog(WARNING, "GameState", "Round is already started")
        return
    end
    for name, character in pairs(self.characters) do
        character:startRound(tonumber(characterInitiatives[name]) or 99)
    end
    for _, monster in pairs(self.monsters) do
        monster:startRound()
    end
    self.roundState = 1
end

function GameState:endRound()
    if self.roundState ~= 1 then
        fhlog(WARNING, "GameState", "Round isn't started")
        return
    end
    for _, character in pairs(self.characters) do
        character:endRound()
    end
    for _, monster in pairs(self.monsters) do
        monster:endRound()
    end
    for name, value in pairs(self.elements) do
        value = value - 1
        if value < 0 then value = 0 end
        self.elements[name] = value
    end
    self.round = self.round + 1
    self.roundState = 0
end

function GameState:infuse(element, half)
    half = half or false
    self.elements[element] = half and 1 or 2
end

function GameState:nbCharacters()
    local nbCharacters = #(self.characters)
    if nbCharacters < 2 then return 2 end
    if nbCharacters > 4 then return 4 end
    return nbCharacters
end

function GameState:findTarget(name, nr)
    -- Monsters
    local monster = self.monsters[name]
    if monster ~= nil then
        return monster:findInstance(nr)
    end

    -- Characters
    local character = self.characters[name]
    if character ~= nil then
        return character
    end

    -- Summons
    for _, character in pairs(self.characters) do
        for _, summon in pairs(character.activeSummons) do
            if summon.name == name and summon.nr == nr then
                return summon
            end
        end
    end

    -- NPCs ???
end

function GameState:reset()
    self.monsters = {}
    for _, character in ipairs(self.characters) do
        character:reset()
    end
    self.round = 1
    self.roundState = 0
    self.decks = {}
end

function GameState:prepareScenario(name)
    self:reset()
    local scenario = self.gameData['scenarios'][name]
    if scenario ~= nil then
        for _, monsterName in ipairs(scenario.monsters or {}) do
            self:addMonster(monsterName)
        end
        return true
    end
    return false
end

function GameState:endScenario()
    self:reset()
end

function GameState:updateGameData(gameData)
    self.gameData = gameData
end

function GameState:toggleCondition(condition, name, nr)
    fhlog(DEBUG, "GameState", "Toggling %s on %s(%s)", condition, name, nr or "")
    local target = self:findTarget(name, nr)
    if target ~= nil then
        target:toggleCondition(condition)
    end
end

function GameState:switchMonster(name, nr)
    fhlog(DEBUG, "GameState", "Switching %s(%s)'s type", name, nr or "")
    local target = self:findTarget(name, nr)
    if target ~= nil then
        target:switchType()
    end
end

function GameState:toState()
    local currentList = {}
    for name, character in pairs(self.characters) do
        table.insert(currentList, character:toState())
    end
    for name, monster in pairs(self.monsters) do
        table.insert(currentList, monster:toState())
    end
    table.sort(currentList, function(a, b) return (a.initiative or 0) < (b.initiative or 0) end)
    local result = {
        version = 100,
        level = self.level,
        round = self.round,
        roundState = self.roundState,
        currentList = currentList,
        elements = self.elements,
    }
    fhlog(INFO, "GameState", "Returning state : %s", result)
    -- fhlog(INFO, "GameState", "%s", self:save())
    return result
end

ConditionMapping = {}
function ensureConditionsMappings()
    for i, condition in ipairs(conditionsOrder) do
        ConditionMapping[condition] = i - 1
    end
end