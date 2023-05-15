-- define essences and their values
alchemy.essence = {
  { "alchemy:essence_low", 1 },
  { "alchemy:essence_medium", 50 },
  { "alchemy:essence_high", 2500 },
  { "alchemy:essence_upgrade", 125000 }
}; -- values of low, medium, high, upgrade essences

alchemy.essence_values = {};
for i = 1, #alchemy.essence do
  alchemy.essence_values[alchemy.essence[i][1]] = alchemy.essence[i][2];
end

alchemy.fixed = {
  ['alchemy:essence_energy'] = 0.05,

  ['default:cobble'] = 1,
  ['default:stone'] = 1,
  ['default:gravel'] = 1,

  ['default:sand'] = 2,
  ['default:desert_sand'] = 2,
  ['default:silver_sand'] = 2,

  ['default:dirt'] = 3,
  ['default:wood'] = 4,
  ['default:tree'] = 16,
  ['default:coal_lump'] = 15,

  ['default:obsidian'] = 450,

  ['default:steel_ingot'] = 150,
  ['default:tin_ingot'] = 150,
  ['default:copper_ingot'] = 150,
  ['default:bronze_ingot'] = 150,
  ['moreores:silver_ingot'] = 313,
  ['default:gold_ingot'] = 625,
  ['default:mese_crystal'] = 1250,
  ['default:diamond'] = 2500,
  ['moreores:mithril_ingot'] = 5000,
};

-- https://stackoverflow.com/a/26367080
local copy;
copy = function(obj, seen)
  if type(obj) ~= 'table' then return obj end
  if seen and seen[obj] then return seen[obj] end
  local s = seen or {}
  local res = setmetatable({}, getmetatable(obj))
  s[obj] = res
  for k, v in pairs(obj) do res[copy(k, s)] = copy(v, s) end
  return res
end

local cycles;
cycles = function(graph, target, vertex, paths, path, seen)
  local vertex = vertex or target;
  local paths = paths or {};
  local path = path or {};
  local seen = seen or {};
  table.insert(path, vertex);
  if seen[vertex] then
    if vertex == target then
      table.insert(paths, copy(path));
    end
  else
    seen[vertex] = true;
    for _, vertex in ipairs(graph[vertex]) do
      cycles(graph, target, vertex, paths, path, seen);
    end
    seen[vertex] = nil;
  end
  table.remove(path);
  return paths
end

local forward = function(recipes, iessences)
  local jessences = copy(iessences);
  for _, recipe in ipairs(recipes) do
    local output = ItemStack(recipe.output);
    local item = output:get_name();
    local quantity = output:get_count();
    local essence = 0;
    for _, item in pairs(recipe.items) do
      essence = essence + iessences[item];
    end
    jessences[item] = math.min(jessences[item], essence / quantity);
  end
  return jessences
end

local dif = function(iessences, jessences)
  local same = true;
  for item, essence in pairs(iessences) do
    if jessences[item] ~= essence then
      same = false;
      break
    end
  end
  return not same
end

-- define item values for BREAK process
alchemy.settings = function()
  local length = function(tab)
    local count = 0;
    for _, _ in pairs(tab) do
      count = count + 1;
    end
    return count
  end
  local fixed = copy(alchemy.fixed);
  for item, essence in pairs(alchemy.essence_values) do
    fixed[item] = essence;
  end
  -- All recipes without alias and group.
  -- FIXME: handle group, alias.
  local aliases = core.registered_aliases;
  local output_recipes = {};
  local recipes = {};
  local items = {};
  local inputs = {};
  local outputs = {};
  local roots = {};
  local inerts = {};
  do
    local _inputs = {};
    local _outputs = {};
    local _inerts = {};
    for item, _ in pairs(core.registered_items) do
      if #item ~= 0 and not aliases[item] then
        -- output_recipes[item] = core.get_all_craft_recipes(item) or {};
        local item_recipes = core.get_all_craft_recipes(item) or {};
        local i = 1;
        while i <= #item_recipes do
          local remove = false;
          for _, item in pairs(item_recipes[i].items) do
            if item:match('group:') then
              remove = true;
              break
            end
          end
          if remove then
            item_recipes[i] = item_recipes[#item_recipes];
            item_recipes[#item_recipes] = nil;
          else
            i = i + 1;
          end
        end
        if length(item_recipes) > 0 then
          _outputs[item] = true;
        end
        output_recipes[item] = item_recipes;
        for _, recipe in ipairs(item_recipes) do
          table.insert(recipes, recipe);
          for _, item in pairs(recipe.items) do
            _inputs[item] = true;
          end
        end
        table.insert(items, item);
      end
    end
    -- outputs
    for item, _ in pairs(_outputs) do
      table.insert(outputs, item);
    end
    -- inputs
    for item, _ in pairs(_inputs) do
      table.insert(inputs, item);
    end
    -- roots & output_recipes & inerts
    for _, item in ipairs(items) do
      if _inputs[item] and not _outputs[item] then
        table.insert(roots, item);
      end
      if not _inputs[item] and not _outputs[item] then
        table.insert(inerts, item);
        output_recipes[item] = nil;
      end
    end
    -- items
    local i = 1;
    while i <= #items do
      if not _inputs[items[i]] and not _outputs[items[i]] then
        items[i] = items[#items];
        items[#items] = nil;
      else
        i = i + 1;
      end
    end
  end
  --[[
  -- Information
  do
    print('items: ' .. #items);
    print(dump(items));
    print('outputs: ' .. #outputs);
    print(dump(outputs));
    print('roots: ' .. #roots);
    print(dump(roots));
    print('inerts: ' .. #inerts);
    -- print(dump(inerts));
    print('inputs: ' .. #inputs);
    print(dump(inputs));
    print('recipes: ' .. #recipes);
    print(dump(recipes));
  end
  --]]
  local initial = math.huge;
  local iessences = {};
  for _, item in ipairs(items) do
    iessences[item] = initial;
  end
  for item, essence in pairs(fixed) do
    iessences[item] = essence;
  end
  local loop = math.pow(2, 10);
  for l = 1, loop do
    local epsilon;
    local jessences = forward(recipes, iessences);
    for item, essence in pairs(jessences) do
      if essence < 0.05 then
        jessences[item] = 0;
      end
      if jessences[item] < math.huge
        and math.abs(math.floor(jessences[item]) - jessences[item]) < 1e-6
      then
        jessences[item] = math.floor(jessences[item]);
      end
    end
    if not dif(jessences, iessences) then
      break
    end
    iessences = jessences;
  end
  -- Validate
  for _, recipe in ipairs(recipes) do
    local output = ItemStack(recipe.output);
    local essence = 0;
    for _, item in pairs(recipe.items) do
      essence = essence + iessences[item];
    end
    -- print(dump(recipe));
    -- print('recipe: ' .. essence / output:get_count());
    -- print('output: ' .. iessences[output:get_name()]);
    if essence >= 0.05 then
      assert(iessences[output:get_name()] <= essence / output:get_count() + 0.025);
    end
  end
  local zeros = {};
  local initials = {};
  for item, essence in pairs(iessences) do
    if essence == 0 or essence < 0.05 then
      iessences[item] = nil;
      table.insert(zeros, item);
    elseif essence >= initial and not fixed[item] then
      iessences[item] = nil;
      table.insert(initials, item);
    end
  end
  local roots = {};
  for item, essence in pairs(iessences) do
    if essence == initial then
      table.insert(roots, item);
    end
  end
  -- print('zeros: ' .. length(zeros));
  -- print(dump(zeros));
  -- print('initials: ' .. length(initials));
  -- print(dump(initials));
  -- print('roots: ' .. length(roots));
  -- print(dump(roots));
  -- print('essences: ' .. length(iessences));
  -- print(dump(iessences));
  alchemy.items = iessences;
end

-- discovery levels: sequence of items player can discover and cost to do so
alchemy.discoveries = {
  [0] = { item = "default:sapling", cost = 10 },
  [1] = { item = "default:cobble", cost = 250 },
  [2] = { item = "default:papyrus", cost = 300 },
  [3] = { item = "default:sand 2", cost = 500 },
  [4] = { item = "bucket:bucket_water", cost = 1000 },
  [5] = { item = "default:coal_lump", cost = 1250 },
  [6] = { item = "default:iron_lump", cost = 1500 },
  [7] = { item = "default:pine_needles 6", cost = 2000 },
  [8] = { item = "default:copper_lump", cost = 2500 },
  [9] = { item = "default:tin_lump", cost = 3000 },
  [10] = { item = "default:gold_lump", cost = 3500 },
  [11] = { item = "default:mese_crystal", cost = 6250 },
  [12] = { item = "default:diamond", cost = 10000 },
  [13] = { item = "default:obsidian", cost = 15000 },
  [14] = { item = "moreores:mithril_ingot", cost = 20000 },
}
