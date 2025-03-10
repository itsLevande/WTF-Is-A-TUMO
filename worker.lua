local blobReader = require("moonblob.BlobReader")
local blobWriter = require("moonblob.BlobWriter")

local love = require("love")

local processChannel = love.thread.getChannel("processFile")
local resultChannel = love.thread.getChannel("results")

local objHeaderComment  = "#.obj created by WTF Is A TUMO ???"
local objHeader         = "\no %s"

local verticeLine       = "\nv %f %f %f"
local lineLine          = "\nl %d %d"
local triangleLine      = "\nf %d %d %d"
local quadLine          = "\nf %d %d %d %d"

local lineFormat        = string.rep("LLL", 2)
local triangleFormat    = string.rep("LLL", 3)
local quadFormat        = string.rep("LLL", 4)

function convertToTumo(file, modelName)
  local succ, err = file:open("r")
    
  if err then
    return { status = "Error", message = string.format("Failed to open file : %s", modelName) }
  end
  
  --print(string.format("Starting conversion of %s to a .tumo", modelName))
  
  local verticesWriter = blobWriter(">")
  local totalVertices = 0
  
  local faceWriter = blobWriter(">")
  local totalFaces = 0
  
  local edgeWriter = blobWriter(">")
  local totalEdges = 0
  
  for line in file:lines() do
    local lineMarker = line:sub(1, 1)
    
    if lineMarker == "v" then
      local x, y, z = line:match("v%s+([-%d%.]+)%s+([-%d%.]+)%s+([-%d%.]+)")
      
      if not (x and y and z) then
        return { status = "Error", message = string.format("Detected an Invalid vertice within %s", modelName) }
      end
      
      totalVertices = totalVertices + 1
      verticesWriter:pack("fff", x + 0, y + 0, z + 0)
      
    elseif lineMarker == "f" then
      local v1, v2, v3, v4 = line:match("f%s+(%d+)%s+(%d+)%s+(%d+)%s*(%d*)")
      
      if not (v1 and v2 and v3) then
        return { status = "Error", message = string.format("Detected an Invalid face within %s", modelName) }
      end
      
      local vertsInFace = -1
      
      if v4 ~= "" then -- quad
        vertsInFace = 4
        
      elseif v3 ~= "" then -- tri
        vertsInFace = 3
      end
      
      if vertsInFace == -1 then
        return { status = "Error", message = string.format("Detected an Invalid face within %s", modelName) }
      end
      
      faceWriter:pack("L", vertsInFace)
      
      if vertsInFace == 3 then
        faceWriter:pack("LLLLLLLLL", v1 - 1, 0, 0, v2 - 1, 0, 0, v3 - 1, 0, 0)
        
        edgeWriter:pack("LL", v1 - 1, v2 - 1)
        edgeWriter:pack("LL", v2 - 1, v3 - 1)
        edgeWriter:pack("LL", v3 - 1, v1 - 1)
        
      elseif vertsInFace == 4 then
        faceWriter:pack("LLLLLLLLLLLL", v1 - 1, 0, 0, v2 - 1, 0, 0, v3 - 1, 0, 0, v4 - 1, 0, 0)
        
        edgeWriter:pack("LL", v1 - 1, v2 - 1)
        edgeWriter:pack("LL", v2 - 1, v3 - 1)
        edgeWriter:pack("LL", v3 - 1, v4 - 1)
        edgeWriter:pack("LL", v4 - 1, v1 - 1) 
      end
      
      totalFaces = totalFaces + 1
      totalEdges = totalEdges + vertsInFace
      
    elseif lineMarker == "l" then
      local v1, v2 = line:match("l%s+(%d+)%s+(%d+)")
      
      if not (v1 and v2) then
        return { status = "Error", message = string.format("Detected an Invalid line within %s", modelName) }
      end  
      
      faceWriter:pack("L", 2)
      faceWriter:pack("LLLLLL", v1 - 1, 0, 0, v2 - 1, 0, 0)
      
      edgeWriter:pack("LL", v1 - 1, v2 - 1)
      
      totalFaces = totalFaces + 1
      totalEdges = totalEdges + 1
    end
  end
  
  if totalVertices == 0 or totalFaces == 0 or totalEdges == 0 then
    return { status = "Error", message = string.format("%s is not a valid model", modelName) }
  end
  
  local tumoWriter = blobWriter(">")
  tumoWriter:pack("LL", 1, 0)
  
  tumoWriter:pack("L", totalVertices)
  tumoWriter:raw(verticesWriter:tostring())
  
  -- some bounding box stuff / constants that crash the game when no set correctly
  tumoWriter:pack("ffffffffLLlL", 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, -1, totalFaces * 6)
  
  tumoWriter:pack("L", totalFaces)
  tumoWriter:raw(faceWriter:tostring())
  
  tumoWriter:pack("L", totalEdges)
  tumoWriter:raw(edgeWriter:tostring())
  
  tumoWriter:pack("L", 0)
  
  local tumoFile = love.filesystem.newFile(modelName .. ".tumo")
  tumoFile:open("w")
  
  tumoFile:write(tumoWriter:tostring())
  tumoFile:close()
  
  return { status = "Completed", message = string.format("Completed converting %s to a .tumo", modelName) }
end

function convertToObj(file, modelName)
  local succ, err = file:open("r")
  
  if err then
    return { status = "Error", message = string.format("Failed to open file : %s", modelName) }
  end
  
  --print(string.format("Starting conversion of %s to a .obj", modelName))

  local outputBuffer = { objHeaderComment, string.format(objHeader, modelName) }
  local outputIndex = 3
  
  local contents, size = file:read()
  file:close()
  
  local reader = blobReader(contents, ">", size)
  reader:skip(8)
  
  -- skip header stuff, since it can technically be incorrect
  -- but have a valid model in the file ???
  --[[
  if reader:u32() ~= 1 then
    return { status = "Error", message = string.format("Invalid header version within %s", modelName) }
  end
  
  if reader:u32() ~= 0 then
    return { status = "Error", message = string.format("Invalid header unknown within %s", modelName) }
  end
  ]]
  
  local totalVertices = reader:u32()

  if totalVertices <= 0 then
    return { status = "Error", message = string.format("Detected an Invalid amount of vertices within %s", modelName) } 
  end
  
  for i = 1, totalVertices do
    outputBuffer[outputIndex] = string.format(verticeLine, reader:unpack("fff"))
    outputIndex = outputIndex + 1
  end
  
  reader:skip(48)
  
  -- skip past some bounding box stuff (not relevant to gameplay)
  -- as well as other constants (they can be invalid i guess ?)
  --[[
  if reader:u32() ~= 1 or reader:u32() ~= 0 or reader:s32() ~= -1 then
    return { status = "Error", message = string.format("Constants are invalid within %s", modelName) }
  end
  
  reader:skip(4)
  ]]
  
  local totalFaces = reader:u32()
  
  if totalFaces <= 0 then
    return { status = "Error", message = string.format("Detected an Invalid amount of faces within %s", modelName) }
  end
  
  for i = 1, totalFaces do
    local vertCount = reader:u32()
    
    if vertCount <= 0 then
      return { status = "Error", message = string.format("Detected an Empty Face within %s", modelName) }
      
    elseif vertCount == 2 then
      local v1, _, _, v2 = reader:unpack(lineFormat)
      outputBuffer[outputIndex] = string.format(lineLine, v1 + 1, v2 + 1)
    
    elseif vertCount == 3 then
      local v1, _, _, v2, _, _, v3 = reader:unpack(triangleFormat)
      outputBuffer[outputIndex] = string.format(triangleLine, v1 + 1, v2 + 1, v3 + 1)
        
    elseif vertCount == 4 then
      local v1, _, _, v2, _, _, v3, _, _, v4 = reader:unpack(quadFormat)
      outputBuffer[outputIndex] = string.format(quadLine, v1 + 1, v2 + 1, v3 + 1, v4 + 1)

    elseif vertCount > 4 then
      return { status = "Error", message = string.format("Detected an NGON within %s", modelName) }
    end
    
    outputIndex = outputIndex + 1
  end
  
  local objFile = love.filesystem.newFile(string.format("%s.obj", modelName))
  
  objFile:open("w")
  objFile:write(table.concat(outputBuffer))
  objFile:close()
  
  return { status = "Completed", message = string.format("Completed converting %s to a .obj", modelName) }
end

function processFile(file)
  local filePath = file:getFilename()
  local path,name,extension = splitFilePath(filePath)
  
  if extension == "tumo" then
    return convertToObj(file, name)
    
  elseif extension == "obj" then
    return convertToTumo(file, name)
  end
  
  return { status = "Error", message = string.format("%s is not a valid .tumo or .obj file", name) }
end

-- i have no idea how this works, actually
function splitFilePath(filePath)
  return filePath:match("^(.-)([^\\/]-)%.([^\\/%.]-)%.?$")
end

while true do
  local task = processChannel:demand()

  if task and task.file then
    local result = processFile(task.file)
    resultChannel:push(result)
  end
end