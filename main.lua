local output = require("output")

local screenWidth = 800
local screenHeight = 600

local workers = {}
local activeThreads = 0
local maxThreads = 16

local activePath = nil

local processChannel = love.thread.getChannel("processFile")
local resultChannel = love.thread.getChannel("results")

local processQueue = {}
local queueSize = 0

local resultMessages = {}
local resultSize = 0

local completedColor = { 1, 1, 0.60, 1 }
local errorColor = { 1, 0.60, 0.60, 1 }

local headerFont = love.graphics.newFont(32)
local headerText = love.graphics.newText(headerFont, "WTF Is A TUMO?")

local subHeaderFont = love.graphics.newFont(16)
local subHeaderText = love.graphics.newText(subHeaderFont, "Drag a file/directory into the window to begin")
local subHeaderText2 = love.graphics.newText(subHeaderFont, "(Files will be output to %appdata%\\WTF Is A TUMO\\ for windows users)")

function love.load(args)
  love.window.setMode(screenWidth, screenHeight)
  love.window.setTitle("WTF Is A TUMO?")
  
  if love.filesystem.isFused() then
    local path = love.filesystem.getSourceBaseDirectory()
    local success = love.filesystem.mount(path, "WTF Is A TUMO", true)
    
    if not success then
      print("NOT mounted, reading/writing files may NOT be possible")
    end
  end
  
  for i = 1, maxThreads do
    local worker = love.thread.newThread("worker.lua")
    worker:start()
    
    workers[i] = worker
  end
end

function love.draw()
  love.graphics.setColor(1, 1, 1, 1)
  
  love.graphics.print(string.format("Active Threads : %d.", activeThreads), 6, screenHeight - 32)
  love.graphics.print(string.format("Currently processing %d files.", queueSize), 6, screenHeight - 20)
  
  love.graphics.draw(headerText, screenWidth / 2 - headerText:getWidth() / 2, 32)
  love.graphics.draw(subHeaderText, screenWidth / 2 - subHeaderText:getWidth() / 2, 72)
  love.graphics.draw(subHeaderText2, screenWidth / 2 - subHeaderText2:getWidth() / 2, 96)
  
  output.draw(resultMessages)
end

function love.update(dt)
  while activeThreads < maxThreads and queueSize > 0 do
    local task = table.remove(processQueue, 1)
    local file, err
    
    -- file within mounted directory
    if type(task) == "string" then
      file, err = love.filesystem.newFile(task, "r")
      
    else -- file that was manually dropped (hopefully)
      file = task
    end
    
    if file and processChannel:push( { file = file }) then
      activeThreads = activeThreads + 1
      queueSize = queueSize - 1
      
    else
      queueSize = queueSize - 1
      
      table.insert(resultMessages, 1, output.new(string.format("Error opening file : %s", task), errorColor))
      resultSize = resultSize + 1
    end
  end
  
  local result = resultChannel:pop()
  local t = love.timer.getTime()
  
  while result do
    activeThreads = activeThreads - 1
    
    if result.message then
      local color = completedColor
      
      if result.status == "Error" then
        color = errorColor
      end
      
      table.insert(resultMessages, 1, output.new(result.message, color))
      resultSize = resultSize + 1
    end
    
    result = resultChannel:pop()
  end
  
  for i = resultSize, 1, -1 do
    local result = resultMessages[i]
    output.update(result, dt)
    
    if result.duration <= 0 then
      table.remove(resultMessages, i)
      resultSize = resultSize - 1
    end
  end
  
  if activePath and activeThreads == 0 and queueSize == 0 then
    love.filesystem.unmount(activePath)
    activePath = nil
  end
end

function processFile(filePath)
  table.insert(processQueue, filePath)
  queueSize = queueSize + 1
end

function processPath(path)
  if love.filesystem.getInfo(path, "directory") then
    local items = love.filesystem.getDirectoryItems(path)
    
    for _,v in pairs (items) do
      local fullPath = string.format("%s/%s", path, v)
      
      if love.filesystem.getInfo(fullPath, "file") then
        processFile(fullPath)
        
      elseif love.filesystem.getInfo(fullPath, "directory") then
        processPath(fullPath)
      end
    end
    
  elseif love.filesystem.getInfo(path, "file") then
    processFile(love.filesystem.newFile(fullPath))
  end
end

function love.filedropped(file)
  processFile(file)
end

function love.directorydropped(path)
  if activePath then
    return
  end
  
  local succ, err = love.filesystem.mount(path, "PROCESS_MODELS")
  
  if err then
    table.insert(resultMessages, 1, output.new(string.format("Failed to mount directory : %s", path), errorColor))
    resultSize = resultSize + 1
    return
  end
  
  activePath = path
  processPath("PROCESS_MODELS")
end

function love.threaderror(thread, errorstr)
  for i = 1, maxThreads do
    if workers[i] == thread then
      local worker = love.thread.newThread("worker.lua")
      worker:start()
      
      workers[i] = worker
      activeThreads = activeThreads - 1
      break
    end
  end
end

-- i have no idea how this works, actually
function splitFilePath(filePath)
  return filePath:match("^(.-)([^\\/]-)%.([^\\/%.]-)%.?$")
end