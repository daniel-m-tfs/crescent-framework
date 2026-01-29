-- crescent/utils/components.lua
-- Utilitário para renderizar componentes reutilizáveis em etlua

local etlua = require("crescent.utils.etlua")
local path = require("crescent.utils.path")

local M = {}

-- Cache de componentes compilados para melhor performance
local component_cache = {}

-- Renderiza um componente com dados
-- @param component_path: Caminho relativo ao diretório views (ex: "components/button")
-- @param data: Tabela com dados a passar para o componente
-- @return: HTML renderizado ou nil em caso de erro
function M.render(component_path, data)
    local file_path = "views/" .. component_path .. ".etlua"
    
    -- Tenta encontrar o arquivo
    local file = io.open(file_path, "r")
    if not file then
        return nil, "Component not found: " .. file_path
    end
    file:close()
    
    -- Renderiza o componente
    local html, err = etlua.render_file(file_path, data or {})
    
    if not html then
        return nil, "Error rendering component " .. component_path .. ": " .. (err or "unknown")
    end
    
    return html
end

-- Renderiza múltiplos componentes em sequência
-- @param components: Array de tabelas {path, data}
-- @return: Todos os HTMLs concatenados
function M.render_all(components)
    local results = {}
    for i, component in ipairs(components or {}) do
        local html, err = M.render(component.path, component.data)
        if html then
            table.insert(results, html)
        else
            table.insert(results, "<!-- Error: " .. (err or "unknown") .. " -->")
        end
    end
    return table.concat(results, "\n")
end

-- Helper para usar em controllers
-- Adiciona método include_component ao contexto
function M.setup_context(ctx)
    function ctx:include_component(component_path, data)
        local html, err = M.render(component_path, data or {})
        if not html then
            return "<!-- Error: " .. (err or "component not found") .. " -->"
        end
        return html
    end
    
    -- Versão para passar como função anônima
    function ctx:component(component_path, data)
        return self:include_component(component_path, data)
    end
end

return M
