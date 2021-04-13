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

tmpdir = os.getenv("TMPDIR")
if not tmpdir then
  tmpdir = "/tmp"
end
tmpdir = tmpdir .. "/embedded_scripts"

function uboot_hook(image)
  -- image.skip will be set by swupdate if versions match
  exec("echo test error && false");
  if image.skip then
    return true, image
  end
  exec(tmpdir .. "/prepare_uboot.sh")
  return true, image
end

function os_hook(image)
  if image.skip then
    return true, image
  end
  exec(tmpdir .. "/prepare_os.sh")
  return true, image
end

function app_hook(image)
  if image.skip then
    return true, image
  end
  exec(tmpdir .. "/prepare_container.sh")
  return true, image
end

swupdate.trace("Embedded script loaded")
