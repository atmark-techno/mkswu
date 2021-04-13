require("swupdate")

-- lua cannot read and write to a process,
-- so we need two helpers.. exec_pipe is blind to any message
-- it prints, that will go straight to swupdate's stdout/stderr :/
function exec_pipe(cmd, data)
  local f = assert(io.popen(cmd, 'w'))
  assert(f:write(data))
  assert(f:close())
end

function exec(cmd)
  -- likewise, we lose stdout/stderr distinction here...
  -- print everything as error if command failed, otherwise just trace.
  local f = assert(io.popen(cmd .. ' 2>&1', 'r'))
  local s = assert(f:read('*a'))
  local rc = f:close()
  if rc then
    for line in s:gmatch('[^\r\n]+') do
      swupdate.trace(line)
    end
  else
    for line in s:gmatch('[^\r\n]+') do
      swupdate.error(line)
    end
  end
  assert(rc)
end
