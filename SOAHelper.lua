-- Author: Liu Peiqi
-- Create Date: 2020/05/11

-- 本文件虽然叫SOA，但不是为连续内存优化，而是使用SOA思路主要解决三个问题
-- 1. 数据结构中字段的访问性封装
-- 2. 减少实现访问性封装所产生的函数和创建的table
-- 3. 如果把业务数据看成关系型数据库的表，那么业务迭代修改多数会增减列数
--    SOA的方法很好的分割各个列以及反应相互列的依赖性，从而减小业务迭代的复杂性
-- 优化的依据是数据结构中字段的数量远远小于运行时创建的结构数量
-- 所以反转结构内外关系后便可以同时减少函数和table的构建
-- 把`Player(player_id).Prop.HP`变为`Player.Prop.HP.Get(player_id)`
-- 另一方面对于可见性实现方面不使用metatable的__index和__newindex
-- 是因为metatable不能独立的定义访问性，多数定义为readonly。
-- metatable另一问题是花费太多table来构建一个结构
-- 最后，极度不推荐使用本文件中的方法来实现不稳定键值的Struct或Map
-- 以及不推荐动态的实时不稳定多次构建Struct或Map
-- 原因是这样会使“减少构建产生的函数和table”这个设计目标失效

local function IgnoreOperate(...)
end

local LogError = IgnoreOperate

local SOAHelper = {}
function SOAHelper.SetLogError(log_error_function)
    LogError = log_error_function
end

function SOAHelper.StructGetSet(stored_table, struct_item_name)
    if stored_table[struct_item_name] ~= nil then
        LogError("[SOAHelper.StructGetSet] dumplicate struct item name \"%s\"!", struct_item_name)
    end
    local column = {}
    stored_table[struct_item_name] = column
    local Get = function(id)
        return column[id]
    end
    local Set = function(id, value)
        column[id] = value
    end
    return Get, Set
end

function SOAHelper.StructClear(stored_table, keys)
    if keys then
        return function(id)
            for _, key in pairs(keys) do
                local column = stored_table[key]
                if column then
                    column[id] = nil
                end
            end
        end
    else
        return function(id)
            for struct_item_name, column in pairs(stored_table) do
                column[id] = nil
            end
        end
    end
end

function SOAHelper.StructCopyToTable(stored_table, keys)
    if keys then
        return function(id, cache)
            local new_table = cache or {}
            for _, key in pairs(keys) do
                local column = stored_table[key]
                if column then
                    new_table[key] = column[id]
                end
            end
            return new_table
        end
    else
        return function(id, cache)
            local new_table = cache or {}
            for key, column in pairs(stored_table) do
                new_table[key] = column[id]
            end
            return new_table
        end
    end
end

function SOAHelper.StructGetSetTuple3(stored_table, key1, key2, key3)
    local col1, col2, col3 = {}, {}, {}
    stored_table[key1], stored_table[key2], stored_table[key3]
        = col1, col2, col3
    local Get = function(id)
        return col1[id], col2[id], col3[id]
    end
    local Set = function(id, v1, v2, v3)
        col1[id], col2[id], col3[id] = v1, v2, v3
    end
end

function SOAHelper.StructGetSetTuple4(stored_table, key1, key2, key3, key4)
    local col1, col2, col3, col4 = {}, {}, {}, {}
    stored_table[key1], stored_table[key2], stored_table[key3], stored_table[key4]
        = col1, col2, col3, col4
    local Get = function(id)
        return col1[id], col2[id], col3[id], col4[id]
    end
    local Set = function(id, v1, v2, v3, v4)
        col1[id], col2[id], col3[id], col4[id] = v1, v2, v3, v4
    end
end

function SOAHelper.StructWrap(stored_table, items_name)
    local facade = {}
    for _, name in pairs(items_name) do
        local Get, Set = SOAHelper.StructGetSet(stored_table, name)
        facade[name] = {Get = Get, Set = Set}
    end
    facade.CopyToTable = SOAHelper.StructCopyToTable(stored_table, items_name)
    facade.Clear = SOAHelper.StructClear(stored_table, items_name)
    return facade
end

function SOAHelper.MapGetSet(stored_table, name)
    -- map 这里结构本身是Struct的一层嵌套结构
    -- 那为什么不直接使用Struct嵌套呢
    -- 原因是想区分两者的适用场景，Map引用与虽然也是有限个Key但却是配置的
    -- Key在含义上是作为参数的
    -- 而Struct嵌套（StructNested）的Key是编写时确定的，Key的含义是字段
    -- StructNested实现: `local hp = Player.Prop.HP.Get(id)`
    -- 使用Map实现的取值操作，键值为任意类型
    -- `local hp = Player.GetProp(id, "HP")`
    -- 或 `local hp = Player.GetProp(id, config.prop_type.hp.id)`
    local column = {}
    stored_table[name] = column
    local Get = function(id, key)
        local map = column[key]
        return map and map[id]
    end
    local Set = function(id, key, value)
        local map = column[key]
        if map == nil then
            map = {}
            column[key] = map
        end
        map[id] = value
    end
    local CopyToTable = SOAHelper.StructCopyToTable(column)
    local Clear = SOAHelper.StructClear(column)
    return Get, Set, CopyToTable, Clear
end

function SOAHelper.MapNextWrap(stored_table, name)
    if name ~= nil then
        stored_table = stored_table[name]
    end
    local new_next = function(id, key)
        while true do
            local key, column = next(stored_table, key)
            if key == nil then
                return nil
            end
            local value = column[id]
            if value ~= nil then
                return key, value
            end
        end
        return nil -- never used!
    end-- inner function end
    return new_next
end

function SOAHelper.StructNestedWrap(stored_table, name, keys)
    -- 或使用结构的嵌套方式，键值为字符串类型`local hp = Player.Prop.HP.Get(id)`
    -- 或键值为数字类型`local hp = Player.Prop[Enum.PROP.HP].Get(id)`
    local column = {}
    stored_table[name] = column
    local facade = {}
    for _, key in pairs(keys) do
        local Get, Set = SOAHelper.StructGetSet(column, key)
        facade[key] = {Get = Get, Set = Set}
    end
    facade.CopyToTable = SOAHelper.StructCopyToTable(column)
    facade.Clear = SOAHelper.StructClear(column)
    return facade
end

function SOAHelper.RangeGenerater(default_capacity, range_start, range_end, id_start)
    default_capacity = default_capacity or 256
    local next_range_index = range_start or 1
    local next_id = id_start or 1
    local GetRange = function(capacity)
        local range_index = next_range_index
        capacity = capacity or default_capacity
        next_range_index = next_range_index + capacity
        if range_end and next_range_index > range_end then
            LogError("[SOAHelper.GetRange] Out of range[%s:%s], now index:%s!",
                range_start, range_end, next_range_index)
        end
        local id = next_id
        next_id = next_id + 1
        return range_index, capacity, id
    end
end

local function InRange(x, left, right)
    return x >= left and x <= right
end

local function CopyByRange(CopyFunction, left_from, left_to, right_iter)
    if left_from == right_iter then
        return
    end
    if InRange(right_iter, left_from, left_to) then
        -- copy from back to front
        right_iter = right_iter + left_to - left_from
        for left_iter = left_to, left_from, -1 do
            CopyFunction(left_iter, right_iter)
            right_iter = right_iter - 1
        end
    else
        -- copy from front to back
        for left_iter = left_from, left_to do
            CopyFunction(left_iter, right_iter)
            right_iter = right_iter + 1
        end
    end
end

local function CopyWithGap(CopyFunction,
                            left_from, left_to, right_iter, gap_index, gap_count)
    -- left[1, 2, 3, 4, 5]
    --              ^
    --    gap_index=4, gap_count=2
    -- right[1, 2, 3, nil, nil, 4, 5]
    --       front      gap     back
    if gap_index then
        local copy_count = gap_index - 1
        if copy_count > 0 then -- front
            local copy_to = left_from + copy_count - 1
            CopyByRange(CopyFunction, left_from, copy_to, right_iter)
            left_from = left_from + copy_count
            right_iter = right_iter + copy_count
        end
        -- gap
        if gap_count then
            right_iter = right_iter + gap_count
        else
            right_iter = right_iter + 1
        end
    end
    -- back
    CopyByRange(CopyFunction, left_from, left_to, right_iter)
end

local function RangeClear(array, from, to)
    for index = from, to do
        array[index] = nil
    end
end

local function RangeStructClear(struct_stored, items_name, from, to)
    for _, name in pairs(items_name) do
        RangeClear(struct_stored[name], from, to)
    end
end

local function StructClear(struct_stored, items_name, index)
    for _, name in pairs(items_name) do
        struct_stored[name][index] = nil
    end
end

local function RangeCheck(start, finish, index, tag)
    if not InRange(index, start, finish) then
        LogError("[SOAHelper.%s] Out of range[%s, %s] => %s!",
            tag, start, finish, index)
        return false
    end
    return true
end

-- AOSOA: 通过增加间接性引用来控制数组类型的成员的可见性和减少数组table构建
-- facade = {
--     New = func(capacity) => id,
--     Delete = func(id),
--     Length = func(id) => length
--     PushBackSlot = func(id),
--     RemoveAt = func(id, index),
--     RemoveAllIf = func(id, Predicate) => removed count
--     [ITEM NAME](optional) = {GetByIndex = func(id, index) => value,
--                    SetByIndex = func(id, index, value)}
-- }

-- eg. --[[Declare]]
-- eg. local stored_table = {}
-- eg. SOAHelper.AOSOAWrapBegin(stored_table, SOAHelper.RangeGenerater())
-- eg. SOAHelper.AOSOAWrapItemGetSetByIndex(stored_table, "BuffID", true)
-- eg. SOAHelper.AOSOAWrapItemGetSetByIndex(stored_table, "UID", true)
-- eg. SOAHelper.AOSOAWrapItemGetSetByIndex(stored_table, "Remain", true)
-- eg. SOAHelper.AOSOAWrapItemGetSetByIndex(stored_table, "Duration", true)
-- eg. GetBuffLayerByIndex, SetBuffLayerByIndex
--         = SOAHelper.AOSOAWrapItemGetSetByIndex(stored_table, "Layer", false)
-- eg. local buffs = SOAHelper.AOSOAWrapEnd(stored_table)

-- eg. --[[on entity enter world]]
-- eg. local entity_buffs = buffs.New()

-- eg. --[[in some gameplay file!]]
-- eg. for i = 1, buffs.Length(entity_buffs) do
-- eg.     local buff_id = buffs.BuffID.GetByIndex(entity_buffs, i)
-- eg.     --[[do somethings]]
-- eg.     local layer = GetBuffLayerByIndex(entity_buffs, i)
-- eg.     SetBuffLayerByIndex(entity_buffs, i, layer + 1)
-- eg. end
-- eg. buffs.RemoveAt(entity_buffs, 1)
-- eg. buffs.PushBackSlot(entity_buffs)
-- eg. buffs.UID.SetByIndex(entity_buffs, buffs.Length(entity_buffs), uid)

-- eg. --[[on entity leave world]]
-- eg. buffs.Delete(entity_buffs)

local array_infos = {}
function SOAHelper.AOSOAWrapBegin(struct_stored, GetRange)
    local array_info = {start = {}, size = {}, capacity = {},
        GetRange = GetRange, items_name = {}, count = 0, facade = {}}
    array_infos[struct_stored] = array_info
end

function SOAHelper.AOSOAWrapItemGetSetByIndex(struct_stored, item_name, insert_to_facade)
    local array_info = array_infos[struct_stored]
    local index = array_info.count + 1
    array_info.count = index
    array_info.items_name[index] = item_name
    if struct_stored[item_name] then
        LogError("[SOAHelper.AOSOAWrapItem] dumplicate struct item name \"%s\"!", item_name)
    end
    struct_stored[item_name] = {}
    local GetByIndex = function(array_id, index)
        local start = array_info.start[array_id]
        local size = array_info.size[array_id]
        if not RangeCheck(1, size, index, "GetByIndex") then return end
        local iter = start + index - 1
        return struct_stored[item_name][iter]
    end
    local SetByIndex = function(array_id, index, value)
        local start = array_info.start[array_id]
        local size = array_info.size[array_id]
        if not RangeCheck(1, size, index, "SetByIndex") then return end
        local iter = start + index - 1
        struct_stored[item_name][iter] = value
    end

    local facade = array_info.facade
    if insert_to_facade then
        facade[item_name] = {GetByIndex = GetByIndex, SetByIndex = SetByIndex}
    end
    return GetByIndex, SetByIndex
end

function SOAHelper.AOSOAWrapItemTuple3GetSetByIndex(struct_stored, item_name, tuple_names, insert_to_facade)
    local array_info = array_infos[struct_stored]
    local index = array_info.count + 1
    array_info.count = index
    array_info.items_name[index] = item_name
    for _, tuple_name in pairs(tuple_names) do
        if struct_stored[tuple_name] then
            LogError("[SOAHelper.AOSOAWrapItemTuple3] dumplicate tuple3 item name \"%s\"!", tuple_name)
        end
        struct_stored[tuple_name] = {}
    end
    local key1, key2, key3 = tuple_names[1], tuple_names[2], tuple_names[3]
    local GetByIndex = function(array_id, index)
        local start = array_info.start[array_id]
        local size = array_info.size[array_id]
        if not RangeCheck(1, size, index, "GetByIndex Tuple3") then return end
        local iter = start + index - 1
        return struct_stored[key1][iter], struct_stored[key2][iter], struct_stored[key3][iter]
    end
    local SetByIndex = function(array_id, index, v1, v2, v3)
        local start = array_info.start[array_id]
        local size = array_info.size[array_id]
        if not RangeCheck(1, size, index, "GetByIndex Tuple3") then return end
        local iter = start + index - 1
        struct_stored[key1][iter] = v1
        struct_stored[key2][iter] = v2
        struct_stored[key3][iter] = v3
    end

    local facade = array_info.facade
    if insert_to_facade then
        facade[item_name] = {GetByIndex = GetByIndex, SetByIndex = SetByIndex}
    end
end

function SOAHelper.AOSOAWrapEnd(struct_stored)
    local array_info = array_infos[struct_stored]
    array_infos[struct_stored] = nil -- close meta info
    local GetRange = array_info.GetRange
    local items_name = array_info.items_name
    local facade = array_info.facade
    array_info.GetRange = nil
    array_info.items_name = nil
    array_info.facade = nil

    facade.New = function(capacity)
        local index, capacity, array_id = GetRange(capacity)
        array_info.start[array_id] = index
        array_info.size[array_id] = 0
        array_info.capacity[array_id] = capacity
        return array_id
    end

    facade.Delete = function(array_id)
        local size = array_info.size[array_id]
        if not size then
            LogError("[SOAHelper.AOSOAWrap.Delete] Delete a not existed array[%s]!", array_id)
            return
        end
        local from = array_info.start[array_id]
        local to = from + size - 1
        RangeStructClear(struct_stored, items_name, from, to)
        array_info.start[array_id] = nil
        array_info.size[array_id] = nil
        array_info.capacity[array_id] = nil
    end

    facade.Length = function(array_id)
        return array_info.size[array_id]
    end

    local InternalCopy = function(left_struct_id, right_struct_id)
        for _, name in pairs(items_name) do
            local column = struct_stored[name]
            column[right_struct_id] = column[left_struct_id]
        end
    end

    local Resize = function(array_id, new_capacity, gap_index, gap_count)
        if gap_count == nil then
            gap_count = 1
        end
        local size = array_info.size[array_id]
        if not size then
            LogError("[SOAHelper.AOSOAWrap.Resize] Resize a not existed array[%s]!", array_id)
            return
        end
        local right_index, new_capacity, new_id = GetRange(new_capacity)
        local left_index = array_info.start[array_id]
        CopyWithGap(InternalCopy, left_index, left_index + size - 1,
                    right_index, gap_index, gap_count)
        
        RangeStructClear(struct_stored, items_name, left_index, left_index + size - 1)

        array_info.start[array_id] = right_index
        array_info.size[array_id] = size + gap_count
        array_info.capacity[array_id] = new_capacity
    end

    local InsertSlotAt = function(array_id, index)
        local start = array_info.start[array_id]
        local size = array_info.size[array_id]
        local capacity = array_info.capacity[array_id]
        if index <= 0 then
            LogError("[SOAHelper.AOSOAWrap.InsertSlotAt]Not support reversed index[%s]!", index)
            return
        end
        if index > (size + 1) then
            LogError("[SOAHelper.AOSOAWrap.InsertSlotAt]Insert index[%s] out of range[1, %s]!",
                index, size)
        elseif index > size then -- push back
            if size == capacity then
                Resize(array_id, capacity * 2)
            else
                array_info.size[array_id] = size + 1
            end
        else -- insert
            if size == capacity then
                Resize(array_id, capacity * 2, index)
            else
                local left_from = start + index - 1
                local left_to = start + size - 1
                local right_iter = left_from + 1
                CopyByRange(InternalCopy, left_from, left_to, right_iter)
                array_info.size[array_id] = size + 1
                StructClear(struct_stored, items_name, left_from)
            end
        end
    end

    facade.PushBackSlot = function(array_id)
        local size = array_info.size[array_id]
        local capacity = array_info.capacity[array_id]
        if size == capacity then
            Resize(array_id, capacity * 2)
        else
            array_info.size[array_id] = size + 1
        end
    end

    facade.RemoveAt = function(array_id, index)
        local start = array_info.start[array_id]
        local size = array_info.size[array_id]
        if index == nil then
            index = size
        elseif not InRange(index, 1, size) then
            LogError("[SOAHelper.AOSOAWrap.RemoveAt] out of range[1, %s] < %s!"
                    , size, index)
            return
        end
        local left_from = start + index
        local left_to = start + size - 1
        if index ~= size then
            local right_iter = left_from - 1
            CopyByRange(InternalCopy, left_from, left_to, right_iter)
        end
        StructClear(struct_stored, items_name, left_to)
        array_info.size[array_id] = size - 1
    end

    facade.RemoveAllIf = function(array_id, Predicate)
        local start = array_info.start[array_id]
        local size = array_info.size[array_id]
        local from, to = start, start + size - 1
        local iter = from
        local remove_count = 0
        for index = from, to do
            if Predicate(index) then
                remove_count = remove_count + 1
            else
                if iter ~= index then
                    InternalCopy(index, iter)
                end
                iter = iter + 1
            end
        end
        return remove_count
    end

    return facade
end

function SOAHelper.StructRefGet(LeftGet, RightGet)
    return function(id)
        local ref_id = LeftGet(id)
        return RightGet(ref_id)
    end
end

function SOAHelper.ArrayRefStructGet(StructGet, GetByIndex)
    return function(id, index)
        local ref_id = StructGet(id)
        return GetByIndex(ref_id, index)
    end
end

function SOAHelper.ArrayRefStructSet(StructGet, SetByIndex)
    return function(id, index, ...)
        local ref_id = StructGet(id)
        SetByIndex(ref_id, index, ...)
    end
end

function SOAHelper.ArrayFacadeNextWrap(LengthFunction, GetByIndexFunction)
    return function(id, index)
        if index == nil then
            index = 0
        end
        index = index + 1
        local length = LengthFunction()
        if index > length then
            return nil
        end
        return index, GetByIndexFunction(id, index)
    end
end

return SOAHelper