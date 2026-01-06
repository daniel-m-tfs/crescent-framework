# Crescent Framework - Website Documentation

Website oficial do **Crescent Framework**, um framework web moderno em Lua de alta performance.

## 📁 Estrutura

```
site/
├── index.html          # Página principal
├── docs.html           # Documentação completa
├── styles.css          # Estilos globais + animações
├── docs.css            # Estilos específicos da documentação
├── script.js           # JavaScript da página principal
├── docs.js             # JavaScript da documentação
├── sitemap.xml         # Mapa do site para SEO
├── robots.txt          # Instruções para crawlers
└── crescent-logo-semfundo.png  # Logo do framework
```

## 🎨 Features

### Design
- **Netflix-Style Hero**: Layout em grid com logo animada e starfield
- **Animações CSS**: Estrelas piscando, estrelas cadentes, logo flutuante
- **Ícones Lucide**: SVG responsivos com efeitos de hover
- **Syntax Highlighting**: Prism.js com tema Tomorrow Night
- **Responsive**: Layout adaptável para mobile e desktop

### Animações
- **Stars Background**: 3 camadas de estrelas com efeito twinkle
- **Shooting Stars**: Meteoros diagonais com movimento suave
- **Logo Float**: Logo flutua suavemente com drop-shadow glow
- **Icon Hover**: Ícones aumentam e brilham no hover

## 🔍 SEO Optimization

### Meta Tags Implementadas

#### Keywords Principais
- `framework web lua`
- `lua web framework`
- `lua web`
- `crescent framework`
- `crescent lua`
- `lua orm`
- `luvit framework`
- `lua rest api`

#### Tags de SEO
- **Title**: Otimizado com keywords principais
- **Description**: Descrição clara e objetiva (155-160 caracteres)
- **Keywords**: Lista completa de termos relevantes
- **Canonical URL**: Previne conteúdo duplicado
- **Language**: Português e Inglês
- **Author**: Crescent Framework Team

#### Open Graph (Facebook/LinkedIn)
- `og:type`: website
- `og:title`: Título otimizado
- `og:description`: Descrição atrativa
- `og:image`: Logo do framework
- `og:url`: URL canônica

#### Twitter Cards
- `twitter:card`: summary_large_image
- `twitter:title`: Título otimizado
- `twitter:description`: Descrição concisa
- `twitter:image`: Logo do framework

#### Schema.org JSON-LD
```json
{
  "@type": "SoftwareApplication",
  "name": "Crescent Framework",
  "applicationCategory": "DeveloperApplication",
  "programmingLanguage": "Lua",
  "keywords": "framework web lua, lua web framework, lua web, crescent lua, luvit, luajit"
}
```

### Arquivos de SEO

#### sitemap.xml
- Lista todas as páginas do site
- Define prioridades e frequência de atualização
- Facilita indexação pelos search engines

#### robots.txt
- Permite acesso de todos os crawlers
- Define Sitemap location
- Crawl-delay configurado para politeness

## 🚀 Deploy

### GitHub Pages
```bash
# Configure o GitHub Pages para apontar para a pasta /site
# Settings > Pages > Source: main branch / site folder
```

### Netlify
```bash
# Build command: (não necessário)
# Publish directory: site
```

### Vercel
```bash
# Framework Preset: Other
# Root Directory: site
```

## 📊 Performance

- **CSS Animations**: Hardware-accelerated (GPU)
- **SVG Icons**: Inline para performance
- **Prism.js**: CDN com cache
- **Images**: Logo PNG otimizada
- **Lazy Loading**: Implementado para imagens futuras

## 🎯 Browser Support

- Chrome/Edge: ✅ Full support
- Firefox: ✅ Full support
- Safari: ✅ Full support
- Mobile browsers: ✅ Responsive

## 📝 Manutenção

### Atualizar Keywords
Edite as meta tags no `<head>` de `index.html` e `docs.html`:
```html
<meta name="keywords" content="seus, novos, keywords">
```

### Atualizar Sitemap
Edite `sitemap.xml` sempre que adicionar novas páginas:
```xml
<url>
    <loc>https://crescentframework.dev/nova-pagina.html</loc>
    <lastmod>2026-01-06</lastmod>
    <priority>0.8</priority>
</url>
```

### Verificar SEO
Use ferramentas como:
- Google Search Console
- Bing Webmaster Tools
- SEO analyzers (Lighthouse, GTmetrix)

## 🔗 Links Úteis

- [Google Search Console](https://search.google.com/search-console)
- [Bing Webmaster Tools](https://www.bing.com/webmasters)
- [Schema.org](https://schema.org/)
- [Open Graph Protocol](https://ogp.me/)
- [Lucide Icons](https://lucide.dev/)
- [Prism.js](https://prismjs.com/)

## 📄 Licença

MIT License - Veja LICENSE no diretório raiz do projeto.
