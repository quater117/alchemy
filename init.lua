-- idea: explore button + require lot of essence to 'discover' certain items: sapling, iron, copper, tin, gold, mese, diamond, mithril

-- ALCHEMY by rnd (2017)
--         by quater (2023)

-- combine ingredients into new outputs


alchemy = {};

dofile(core.get_modpath('alchemy') .. '/items.lua')


-- returns change in greedy way
local get_change = function(essence0)
  local essences = alchemy.essence;
  local quantities = {};
  for i = 4, 1, -1 do
    local item = essences[i][1];
    local essence = essences[i][2];
    quantities[item] = math.floor(essence0 / essence);
    essence0 = essence0 - quantities[item] * essence;
  end
  return quantities
end


-- Try to 'make' of the first found material of 'in' using essences in 'out'.
local lab_unite = function(pos)
  local meta = core.get_meta(pos);
  local inv = meta:get_inventory();
  local stack;
  for i = 1, 4 do
    local items = inv:get_stack('in', i);
    stack = stack or items;
    if stack:is_empty() then
      stack = items;
    elseif not items:is_empty() and stack:get_name() ~= items:get_name() then
      return
    end
  end
  if stack:is_empty() then
    return
  end
  local item = stack:get_name();
  local essence = 0;
  -- Get essence 'out'.
  for i = 1, 4 do
    local stack = inv:get_stack('out', i);
    if not stack:is_empty() then
      local item = stack:get_name();
      local count = stack:get_count();
      if alchemy.essence_values[item] then
        essence = essence + alchemy.essence_values[item] * count;
      else
        return
      end
    end
  end
  -- Compute cost.
  local cost = alchemy.items[item];
  if not cost then return end
  -- Adjust cost depending on upgrades
  local x = 0;
  if inv:get_stack('upgrade', 1):get_name() == 'alchemy:essence_upgrade' then
    x = math.min(inv:get_stack('upgrade', 1):get_count() / 100, 1);
  end
  -- local multiplier = function(x) return 0.2 + 4.8 / (1 + 5 * x) end
  local multiplier = function(x) return 5 / (-4 * x * x + 8 * x + 1) end
  cost = cost * math.max(1, multiplier(x));
  -- Compute quantity of output.
  local quantity = math.floor(essence / cost);
  if quantity < 1 then return end
  -- Fill inventory.
  essence = essence - cost * quantity;
  for i = 1, 4 do
    local stack = inv:get_stack('in', i);
    if stack:is_empty() then
      local size = math.min(quantity, 65535);
      inv:set_stack('in', i, ItemStack(item .. ' ' .. size));
      quantity = quantity - size;
    elseif stack:get_name() == item then
      quantity = quantity + stack:get_count();
      local size = math.min(quantity, 65535);
      inv:set_stack('in', i, ItemStack(item .. ' ' .. size));
      quantity = quantity - size;
    end
    if quantity == 0 then
      break
    end
  end
  -- Left essence.
  essence = essence + cost * quantity;
  -- Compute essence.
  local quantities = get_change(essence);
  local i = 1;
  for item, quantity in pairs(quantities) do
    if quantity > 0 then
      inv:set_stack('out', i, ItemStack(item .. ' ' .. quantity));
      i = i + 1;
    end
  end
  while i <= 4 do
    inv:set_stack('out', i, ItemStack(''));
    i = i + 1;
  end
end


local lab_split = function(pos) -- break down materials in 'in'
  local meta = core.get_meta(pos);
  local inv = meta:get_inventory();
  local essence = 0;
  -- Get essence 'in'.
  for i = 1, 4 do
    local stack = inv:get_stack('in', i);
    if not stack:is_empty() then
      local item = stack:get_name();
      if alchemy.items[item] then
        essence = essence + alchemy.items[item] * stack:get_count();
      else
        return
      end
    end
  end
  -- require 1 energy to break 250 essence
  local fuel_cost = math.floor(essence / 250);
  -- Get essence 'out'.
  for i = 1, 4 do
    local stack = inv:get_stack('out', i);
    if not stack:is_empty() then
      local item = stack:get_name();
      local count = stack:get_count();
      if alchemy.essence_values[item] then
        essence = essence + alchemy.essence_values[item] * count;
      else
        return
      end
    end
  end
  -- Check
  if fuel_cost < 1 then fuel_cost = 1 end
  local fuel_stack = ItemStack('alchemy:essence_energy ' .. fuel_cost);
  if not inv:contains_item('fuel', fuel_stack) then
    local text = 'not enough energy, need ' .. fuel_cost .. ' cells.';
    meta:set_string('infotext', text);
    local text = core.formspec_escape(text);
    local form =
      'size[5.5,5]'
      .. 'textarea[0.,0;6.1,6;alchemy_help;ALCHEMY;' .. text .. ']';
    core.show_formspec(meta:get_string('owner'), 'alchemy_help', form);
    return
  else
    inv:remove_item('fuel', fuel_stack);
    meta:set_string('infotext', '');
  end
  -- Clear 'in'.
  for i = 1, 4 do
    inv:set_stack('in', i, ItemStack(''));
  end
  -- Compute essence.
  local quantities = get_change(essence);
  local i = 1;
  for item, quantity in pairs(quantities) do
    if quantity > 0 then
      inv:set_stack('out', i, ItemStack(item .. ' ' .. quantity));
      i = i + 1;
    end
  end
  while i <= 4 do
    inv:set_stack('out', i, ItemStack(''));
    i = i + 1;
  end
end


core.register_abm({ -- very slowly create energy
  nodenames = { 'alchemy:lab' },
  neighbors = {},
  interval = 30,
  chance = 1,
  action = function(pos, node, active_object_count, active_object_count_wider)
    local meta = core.get_meta(pos);
    local inv = meta:get_inventory();
    local upgrade = 0;
    if inv:get_stack('upgrade', 1):get_name() == 'alchemy:essence_upgrade' then
      upgrade = inv:get_stack('upgrade', 1):get_count();
    end
    local count = 1 + upgrade;
    local stack = ItemStack('alchemy:essence_energy ' .. count);
    inv:add_item('fuel', stack);
  end
});


local lab_update_meta = function(pos)
    local meta = core.get_meta(pos);
    local spos = pos.x .. ',' .. pos.y .. ',' .. pos.z;
    local form =
      'size[8,6.75]'
      .. 'button[0,2.25;2.,0.75;split;BREAK]'
      .. 'button[3,2.25;2.,0.75;unite;MAKE]'
      .. 'button[6,2.25;2.,0.75;fuel;FUEL]'
      .. 'label[0,-0.2.;MATERIAL]'
      .. 'list[nodemeta:' .. spos .. ';in;0,0.25;2,2;]'
      .. 'label[3,-0.2.;ESSENCE]'
      .. 'list[nodemeta:' .. spos .. ';out;3,0.25;2,2;]'
      .. 'image[2,0.;1,1;gui_furnace_arrow_bg.png^[transformR270]'
      .. 'image[2,1.;1,1;gui_furnace_arrow_bg.png^[transformR90]'
      .. 'label[6,-0.2.;UPGRADE]'
      .. 'list[nodemeta:' .. spos .. ';upgrade;6,0.25;1,1;]'
      .. 'button[6.,1.25;2,1;upgrade;'.. core.colorize('red', 'HELP') .. ']'
      .. 'list[current_player;main;0,3;8,4;]'
      .. 'listring[current_player;main]'
      .. 'listring[context;out]'
      .. 'listring[current_player;main]'
      .. 'listring[context;in]'
      .. 'listring[current_player;main]'
      .. 'listring[context;upgrade]'
      .. 'listring[current_player;main]';
    meta:set_string('formspec', form);
end

local allow_metadata_inventory_put = function(pos, listname, index, stack, player)
  if core.is_protected(pos, player:get_player_name()) then
    return 0
  end
  if listname == 'out' then
    if alchemy.essence_values[stack:get_name()] then
      return stack:get_count()
    else
      return 0
    end
  elseif listname == 'upgrade' then
    if stack:get_name() == 'alchemy:essence_upgrade' then
      return stack:get_count()
    else
      return 0
    end
  elseif listname == 'in' then
    if alchemy.items[stack:get_name()] then
      return stack:get_count()
    else
      return 0
    end
  else
    return stack:get_count()
  end
end


core.register_node('alchemy:lab', {
  description = 'Alchemy laboratory',
  tiles = {
    'default_steel_block.png',
    'default_steel_block.png',
    'alchemy_lab.png',
    'alchemy_lab.png',
    'alchemy_lab.png',
    'alchemy_lab.png'
  },
  groups = { cracky = 3, mesecon_effector_on = 1 },
  sounds = default.node_sound_wood_defaults(),

  can_dig = function(pos, player)
    local meta = core.get_meta(pos);
    local inv = meta:get_inventory();
    return inv:is_empty('in') and inv:is_empty('out') and inv:is_empty('upgrade');
  end,

  after_place_node = function(pos, placer)
    local meta = core.get_meta(pos);
    meta:set_string(
      'infotext', 'Alchemy: To operate it insert materials or essences.'
    );
    meta:set_string('owner', placer:get_player_name());
    local inv = meta:get_inventory();
    inv:set_size('in', 4);
    inv:set_size('out', 4); -- dusts here
    inv:set_size('upgrade', 1);
    inv:set_size('fuel', 32);
  end,

  on_rightclick = function(pos, node, player, itemstack, pointed_thing)
    if core.is_protected(pos, player:get_player_name()) then
      return
    end
    lab_update_meta(pos);
  end,

  allow_metadata_inventory_put = allow_metadata_inventory_put,

  allow_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, count, player)
    local meta = core.get_meta(pos);
    local inv = meta:get_inventory();
    local stack = inv:get_stack(from_list, from_index);
    return allow_metadata_inventory_put(pos, to_list, to_index, stack, player)
  end,

  allow_metadata_inventory_take = function(pos, listname, index, stack, player)
    if core.is_protected(pos, player:get_player_name()) then
      return 0
    end
    return stack:get_count()
  end,

  mesecons = { effector = {
    action_on = function(pos, node, ttl)
      if type(ttl) ~= 'number' then ttl = 1 end
      if ttl < 0 then return end -- machines_TTL prevents infinite recursion
      local meta = core.get_meta(pos);
      if meta:get_int('mode') == 2 then
        lab_unite(pos)
      else
        lab_split(pos)
      end
    end
    }
  },

  on_receive_fields = function(pos, formname, fields, sender)
    if core.is_protected(pos, sender:get_player_name()) then return end
    local meta = core.get_meta(pos);

    if fields.unite then
      lab_unite(pos);
      meta:set_int('mode', 2);
      return
    end

    if fields.split then
      lab_split(pos);
      meta:set_int('mode', 1);
      return
    end

    if fields.fuel then
      local meta = core.get_meta(pos);
      local spos = pos.x .. ',' .. pos.y .. ',' .. pos.z;
      local form =
        'size[8,8.25]'
        .. 'label[0,-0.2;INSERT ENERGY ESSENCE AS FUEL]'
        .. 'list[nodemeta:' .. spos .. ';fuel;0,0.25;8,4;]'
        .. 'list[current_player;main;0,4.5;8,4;]'
        .. 'listring[context;fuel]'
        .. 'listring[current_player;main]'
        .. 'listring[context;fuel]';
      core.show_formspec(sender:get_player_name(), 'alchemy_fuel', form);
      return
    end

    if fields.upgrade then
      local text =
        core.colorize('yellow', '1.BREAK') .. '\n'
          .. 'Place items in left window (MATERIALS) and use \'break\' to transmute them into essences.\n\n'
          .. core.colorize('yellow', '2.MADE') .. '\n'
          .. 'Place essences in right window (ESSENCES), place item to be created in left window (1st position) and use \'make\'.\n\n'
          .. core.colorize('red', '3.DISCOVER') .. '\n'
          .. 'if you insert enough essence you can discover new materials.\n\n'
          .. 'Make process will be more effective if you place upgrade essences in upgrade window. cost factor is 0.2 + 4.8/(1 + 0.05*upgrade)\n\n'
          .. 'To break materials you need 1 energy essence for every 250 essence. Energy essence is produced at rate (1+upgrade) by alchemy lab every 1/2 minute\n\n'
          .. 'There are 4 kinds of essences: low (1), medium (50), high(2500) and upgrade(125000).'

      local text = core.formspec_escape(text);
      local meta = core.get_meta(pos);
      local level = meta:get_int('level'); -- discovery level
      local discovery = alchemy.discoveries[level] or alchemy.discoveries[0];
      local red =
        core.colorize(
          'red',
          'DISCOVER ' .. level .. ' : '
            .. discovery.item .. ' (cost ' .. discovery.cost .. ')'
        );
      local form =
        'size[5.5,5]'
        .. 'textarea[0.,0;6.1,5.5;alchemy_help;ALCHEMY HELP;' .. text .. ']'
        .. 'button_exit[0,4.75;5.5,0.75;discover;' .. red ..']';
      core.show_formspec(
        sender:get_player_name(),
        'alchemy_help:' .. core.pos_to_string(pos),
        form
      );
      return
    end
  end,
});


core.register_on_player_receive_fields(
  function(player, formname, fields)
    local fname = 'alchemy_help:';
    if string.sub(formname, 1, string.len(fname)) ~= fname then return end
    if fields.discover then
      local pos = core.string_to_pos(string.sub(formname, string.len(fname) + 1));
      local meta = core.get_meta(pos);
      local level = meta:get_int('level') or 0; -- discovery level
      local discovery = alchemy.discoveries[level] or alchemy.discoveries[0];
      local cost = discovery.cost;
      local inv = meta:get_inventory();
      -- Get essence 'out'.
      local essence = 0;
      for i = 1, 4 do
        local stack = inv:get_stack('out', i);
        if not stack:is_empty() then
          local item = stack:get_name();
          local count = stack:get_count();
          if alchemy.essence_values[item] then
            essence = essence + alchemy.essence_values[item] * count;
          else
            return
          end
        end
      end

      local item = discovery.item;

      if essence < cost then
        core.chat_send_player(
          player:get_player_name(),
          '#ALCHEMY: you need at least '
            .. cost
            .. ' essence, you have only '
            .. essence
        );
        return
      end
      essence = essence - cost;
      inv:add_item('in', ItemStack(item));
      level = level + 1;
      if alchemy.discoveries[level] then
        meta:set_int('level', level);
        core.chat_send_player(
          player:get_player_name(),
          '#ALCHEMY: successfuly discovered ' .. item .. '!'
        );
      end
      -- Compute essence.
      local quantities = get_change(essence);
      local i = 1;
      for item, quantity in pairs(quantities) do
        if quantity > 0 then
          inv:set_stack('out', i, ItemStack(item .. ' ' .. quantity));
          i = i + 1;
        end
      end
      while i <= 4 do
        inv:set_stack('out', i, ItemStack(''));
        i = i + 1;
      end
      return
    end
  end
);


core.register_craft({
  output = 'alchemy:lab',
  recipe = {
    { 'default:steel_ingot', 'default:goldblock', 'default:steel_ingot' },
    { 'default:steel_ingot', 'default:diamondblock', 'default:steel_ingot' },
    { 'default:steel_ingot', 'default:steel_ingot', 'default:steel_ingot' },
  }
});


-- ESSENCES

core.register_craftitem('alchemy:essence_low', {
  description = 'Low essence',
  inventory_image = 'alchemy_essence_low.png',
  stack_max = 64000,
});

core.register_craftitem('alchemy:essence_medium', {
  description = 'Medium essence',
  inventory_image = 'alchemy_essence_medium.png',
  stack_max = 64000,
});

core.register_craftitem('alchemy:essence_high', {
  description = 'High essence',
  inventory_image = 'alchemy_essence_high.png',
  stack_max = 64000,
});

core.register_craftitem('alchemy:essence_upgrade', {
  description = 'Upgrade essence',
  inventory_image = 'alchemy_essence_upgrade.png',
  stack_max = 64000,
});

core.register_craftitem('alchemy:essence_energy', {
  description = 'energy essence',
  inventory_image = 'energy_essence.png',
  stack_max = 64000,
});

core.register_on_mods_loaded(alchemy.settings);

print('[MOD] alchemy loaded.');
