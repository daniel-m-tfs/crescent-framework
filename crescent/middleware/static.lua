-- crescent/middleware/static.lua
-- Middleware para servir arquivos estáticos

local M = {}

-- Cria middleware para servir arquivos estáticos
-- @param public_dir: Diretório de arquivos públicos (padrão: "public")
function M.create(public_dir)
    public_dir = public_dir or "public"
    
    return function(ctx, next)
        -- Verifica se é uma requisição GET ou HEAD
        if ctx.method ~= "GET" and ctx.method ~= "HEAD" then
            return next()
        end
        
        local req_path = ctx.path
        
        -- Remove a barra inicial se existir
        req_path = req_path:gsub("^/", "")
        
        -- Constrói o caminho do arquivo com separador correto
        local file_path = public_dir .. "/" .. req_path
        
        -- Tenta abrir o arquivo em modo binário
        local file = io.open(file_path, "rb")
        if not file then
            return next() -- Arquivo não encontrado, passa para próxima rota
        end
        
        local content = file:read("*all")
        file:close()
        
        if not content then
            return next()
        end
        
        -- Determina o content-type baseado na extensão
        local content_type = M.get_content_type(file_path)
        
        -- Envia headers
        ctx.res:setHeader("Content-Type", content_type)
        ctx.res:setHeader("Content-Length", tostring(#content))
        ctx.res:setHeader("Cache-Control", "public, max-age=3600")
        
        -- Marca como finalizado ANTES de enviar
        ctx.res.finished = true
        
        -- Para requisições HEAD, apenas envia headers
        if ctx.method == "HEAD" then
            ctx.res:writeHead(200)
            ctx.res:finish()
        else
            -- Para GET, envia o conteúdo
            ctx.res:writeHead(200)
            ctx.res:finish(content)
        end
        
        -- Retorna false para parar a cadeia de middlewares
        return false
    end
end

-- Retorna o content-type baseado na extensão do arquivo
function M.get_content_type(file_path)
    local ext = file_path:match("%.([^.]+)$") or ""
    ext = ext:lower()
    
    local types = {
        css = "text/css",
        js = "application/javascript",
        json = "application/json",
        html = "text/html",
        htm = "text/html",
        png = "image/png",
        jpg = "image/jpeg",
        jpeg = "image/jpeg",
        gif = "image/gif",
        svg = "image/svg+xml",
        ico = "image/x-icon",
        txt = "text/plain",
        pdf = "application/pdf",
        woff = "font/woff",
        woff2 = "font/woff2",
        ttf = "font/ttf",
        eot = "application/vnd.ms-fontobject"
    }
    
    return types[ext] or "application/octet-stream"
end

return M
