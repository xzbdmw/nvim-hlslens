local M = {}

local cmd = vim.cmd
local api = vim.api
local fn = vim.fn

local bufs

local function setup()
    bufs = {cnt = 0}
end

local function find_hls_qfnr()
    for i = 1, fn.getqflist({nr = '$'}).nr do
        local context = fn.getqflist({nr = i, context = 0}).context
        if type(context) == 'table' and context.hlslens then
            return i
        end
    end
    return 0
end

local function valid_pat(pat)
    if pat == '' then
        return false
    end
    for g in pat:gmatch('.?/') do
        if g ~= [[\/]] then
            return false
        end
    end
    return true
end

function M.hit_cache(bufnr, pattern, n_idx, nr_idx)
    local c = bufs[bufnr]
    return c and pattern == c.pattern and n_idx == c.n_idx and nr_idx == c.nr_idx and
               vim.v.searchforward == c.sfw
end

function M.update_cache(bufnr, pattern, n_idx, nr_idx)
    local c = bufs[bufnr]
    c.pattern, c.n_idx, c.nr_idx, c.sfw = pattern, n_idx, nr_idx, vim.v.searchforward
end

function M.build(bufnr, pattern)
    bufnr = bufnr or api.nvim_get_current_buf()

    -- fast and simple way to prevent memory leaking :)
    if bufs.cnt > 5 then
        bufs = {cnt = 0}
    end

    local c = bufs[bufnr] or {}

    if c.changedtick == api.nvim_buf_get_changedtick(bufnr) and c.pattern == pattern then
        return c.plist
    elseif not valid_pat(pattern) or vim.bo.bt == 'quickfix' then
        -- vim.bo.bt is not cheap
        return {}
    end

    local tf
    if fn.expand('%') == '' then
        tf = fn.tempname()
        cmd('f ' .. tf)
    end

    if vim.o.smartcase then
        local pattern_chars = pattern:gsub('\\.', '')
        if pattern_chars:lower(pattern) ~= pattern_chars then
            pattern = '\\C' .. pattern
        end
    end

    local qf_list_nr = fn.getqflist({nr = 0}).nr
    local hls_list_nr = find_hls_qfnr()
    local offset_nr = qf_list_nr - hls_list_nr
    local err_prefix = 'sil noa'
    local grep_cmd
    if hls_list_nr == 0 then
        grep_cmd = 'vimgrep'
    else
        if offset_nr > 0 then
            cmd(string.format('%s col %d', err_prefix, offset_nr))
        elseif offset_nr < 0 then
            cmd(string.format('%s cnew %d', err_prefix, -offset_nr))
        end
        cmd([[noau call setqflist([], 'r')]])
        grep_cmd = 'vimgrepadd'
    end

    local ok, msg = pcall(cmd, string.format('%s %s /%s/gj %%', err_prefix, grep_cmd, pattern))
    if not ok then
        if msg:match('^Vim%(%a+%):E682') then
            ok = pcall(cmd, string.format('%s %s /\\V%s/gj %%', err_prefix, grep_cmd, pattern))
        end
    end

    local plist = {}
    -- don't waste the memory :)
    if fn.getqflist({size = 0}).size <= 10000 then
        plist = ok and vim.tbl_map(function(item)
            return {item.lnum, item.col}
        end, fn.getqflist()) or {}
    end

    fn.setqflist({}, 'r', {context = {hlslens = true}, title = 'hlslens pattern = ' .. pattern})

    if qf_list_nr ~= 0 then
        local qf_info = fn.getqflist({nr = 0, winid = 0})
        local now_nr = qf_info.nr
        if qf_info.winid ~= 0 then
            err_prefix = 'sil'
        end
        offset_nr = now_nr - qf_list_nr
        if offset_nr > 0 then
            cmd(string.format('%s col %d', err_prefix, offset_nr))
        elseif offset_nr < 0 then
            cmd(string.format('%s cnew %d', err_prefix, -offset_nr))
        elseif offset_nr == 0 and now_nr == 10 then
            cmd(string.format('%s col', err_prefix))
        end
    end

    if tf and tf ~= '' then
        cmd('sil 0f')
        cmd('bw! ' .. tf)
    end

    c = {plist = plist, changedtick = api.nvim_buf_get_changedtick(bufnr), pattern = pattern}
    if not bufs[bufnr] then
        bufs.cnt = bufs.cnt + 1
    end
    bufs[bufnr] = c
    return plist
end

function M.clear()
    bufs = {cnt = 0}
end

setup()

return M
