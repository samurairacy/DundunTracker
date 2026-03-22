-- LibDataBroker-1.1
-- Provides a data-object registry for minimap/display plugins.
-- Public Domain.

assert(LibStub, "LibDataBroker-1.1 requires LibStub")

local lib, oldminor = LibStub:NewLibrary("LibDataBroker-1.1", 4)
if not lib then return end

lib.attributestorage = lib.attributestorage or {}
lib.namestorage      = lib.namestorage or {}
lib.domt = lib.domt or {
    __index = function(self, attribute)
        return lib.attributestorage[self] and lib.attributestorage[self][attribute]
    end,
    __newindex = function(self, attribute, value)
        lib.attributestorage[self] = lib.attributestorage[self] or {}
        lib.attributestorage[self][attribute] = value
        local name = lib.namestorage[self]
        if lib.callbacks then
            lib.callbacks:Fire("LibDataBroker_AttributeChanged", name, attribute, value, self)
        end
    end,
}

function lib:NewDataObject(name, dataobj)
    if self.namestorage[name] then
        error(('Duplicate data object: "%s"'):format(name))
    end
    dataobj = dataobj or {}
    setmetatable(dataobj, self.domt)
    self.namestorage[dataobj] = name
    self.namestorage[name]    = dataobj
    return dataobj
end

function lib:GetDataObjectByName(name)
    return self.namestorage[name]
end

function lib:GetNameByDataObject(dataobj)
    return self.namestorage[dataobj]
end

function lib:pairs()
    local iter = pairs(self.namestorage)
    return function()
        local key, value = iter()
        while key do
            if type(key) == "string" then return key, value end
            key, value = iter()
        end
    end
end
