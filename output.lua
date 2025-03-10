local output = {}

local screenWidth, screenHeight = love.window.getMode()
local outputFont = love.graphics.newFont(10)

function output.new(text, color)
  local obj = {
    text = love.graphics.newText(outputFont, text),
    width = nil,
    color = color,
    duration = 2
  }
  
  obj.width = obj.text:getWidth()
  return obj
end

function output.update(obj, dt)
  obj.duration = obj.duration - dt
end

function output.draw(objects)
  for i = 1, 32 do
    local obj = objects[i]
    
    if not obj then
      break
    end
    
    local posX = screenWidth - (obj.width + 6)
    local posY = screenHeight - (i * 12 + 8)
    
    love.graphics.setColor(obj.color)
    love.graphics.draw(obj.text, posX, posY)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

return output