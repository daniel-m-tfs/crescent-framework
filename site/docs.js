// Docs specific JavaScript

// Active nav link highlighting based on scroll position
const sections = document.querySelectorAll('.doc-section[id]');
const navLinks = document.querySelectorAll('.docs-nav a[href^="#"]');

function highlightNavigation() {
    const scrollY = window.pageYOffset;
    
    sections.forEach(section => {
        const sectionHeight = section.offsetHeight;
        const sectionTop = section.offsetTop - 150;
        const sectionId = section.getAttribute('id');
        
        if (scrollY > sectionTop && scrollY <= sectionTop + sectionHeight) {
            navLinks.forEach(link => {
                link.classList.remove('active');
                if (link.getAttribute('href') === `#${sectionId}`) {
                    link.classList.add('active');
                }
            });
        }
    });
}

window.addEventListener('scroll', highlightNavigation);
highlightNavigation();

// Smooth scroll for sidebar links
document.querySelectorAll('.docs-nav a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
        e.preventDefault();
        const target = document.querySelector(this.getAttribute('href'));
        if (target) {
            target.scrollIntoView({
                behavior: 'smooth',
                block: 'start'
            });
        }
    });
});

// Copy code functionality
document.querySelectorAll('.code-block').forEach(block => {
    block.style.position = 'relative';
    
    const copyButton = document.createElement('button');
    copyButton.innerHTML = '📋 Copy';
    copyButton.className = 'copy-button';
    copyButton.style.cssText = `
        position: absolute;
        top: 1rem;
        right: 1rem;
        background: rgba(99, 102, 241, 0.8);
        color: white;
        border: none;
        padding: 0.5rem 1rem;
        border-radius: 0.375rem;
        cursor: pointer;
        font-size: 0.875rem;
        font-weight: 500;
        opacity: 0;
        transition: all 0.2s;
        z-index: 10;
    `;
    
    block.appendChild(copyButton);
    
    block.addEventListener('mouseenter', () => {
        copyButton.style.opacity = '1';
    });
    
    block.addEventListener('mouseleave', () => {
        if (!copyButton.classList.contains('copied')) {
            copyButton.style.opacity = '0';
        }
    });
    
    copyButton.addEventListener('click', async (e) => {
        e.stopPropagation();
        const code = block.querySelector('code').textContent;
        
        try {
            await navigator.clipboard.writeText(code);
            copyButton.innerHTML = '✅ Copied!';
            copyButton.style.background = 'rgba(34, 197, 94, 0.8)';
            copyButton.classList.add('copied');
            
            setTimeout(() => {
                copyButton.innerHTML = '📋 Copy';
                copyButton.style.background = 'rgba(99, 102, 241, 0.8)';
                copyButton.classList.remove('copied');
                copyButton.style.opacity = '0';
            }, 2000);
        } catch (err) {
            console.error('Failed to copy:', err);
        }
    });
});

// Mobile menu toggle (if needed)
const createMobileMenu = () => {
    if (window.innerWidth <= 1024) {
        const sidebar = document.querySelector('.docs-sidebar');
        const toggleBtn = document.createElement('button');
        toggleBtn.innerHTML = '📚 Menu';
        toggleBtn.style.cssText = `
            position: fixed;
            bottom: 2rem;
            right: 2rem;
            background: var(--gradient);
            color: white;
            border: none;
            padding: 1rem 1.5rem;
            border-radius: 2rem;
            cursor: pointer;
            font-weight: 600;
            box-shadow: 0 4px 20px rgba(99, 102, 241, 0.4);
            z-index: 1000;
        `;
        
        toggleBtn.addEventListener('click', () => {
            sidebar.style.display = sidebar.style.display === 'none' ? 'block' : 'none';
        });
        
        document.body.appendChild(toggleBtn);
    }
};

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    highlightNavigation();
    
    // Fade in sections on scroll
    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.style.opacity = '1';
                entry.target.style.transform = 'translateY(0)';
            }
        });
    }, {
        threshold: 0.1,
        rootMargin: '0px 0px -100px 0px'
    });

    document.querySelectorAll('.doc-section').forEach(section => {
        section.style.opacity = '0';
        section.style.transform = 'translateY(20px)';
        section.style.transition = 'all 0.6s ease-out';
        observer.observe(section);
    });
});

// Search functionality (basic)
const addSearch = () => {
    const searchBox = document.createElement('div');
    searchBox.innerHTML = `
        <input type="search" placeholder="Buscar na documentação..." style="
            width: 100%;
            padding: 0.75rem 1rem;
            background: var(--bg-light);
            border: 1px solid rgba(255, 255, 255, 0.1);
            border-radius: 0.5rem;
            color: var(--text);
            font-size: 0.9rem;
            margin-bottom: 1rem;
        ">
    `;
    
    const sidebar = document.querySelector('.docs-sidebar');
    if (sidebar) {
        sidebar.insertBefore(searchBox, sidebar.firstChild);
        
        const input = searchBox.querySelector('input');
        input.addEventListener('input', (e) => {
            const searchTerm = e.target.value.toLowerCase();
            const sections = document.querySelectorAll('.nav-section');
            
            sections.forEach(section => {
                const links = section.querySelectorAll('a');
                let hasVisibleLinks = false;
                
                links.forEach(link => {
                    const text = link.textContent.toLowerCase();
                    if (text.includes(searchTerm)) {
                        link.style.display = 'block';
                        hasVisibleLinks = true;
                    } else {
                        link.style.display = searchTerm ? 'none' : 'block';
                    }
                });
                
                section.style.display = hasVisibleLinks || !searchTerm ? 'block' : 'none';
            });
        });
    }
};

addSearch();

// Keyboard shortcuts
document.addEventListener('keydown', (e) => {
    // Ctrl/Cmd + K to focus search
    if ((e.ctrlKey || e.metaKey) && e.key === 'k') {
        e.preventDefault();
        const searchInput = document.querySelector('.docs-sidebar input[type="search"]');
        if (searchInput) {
            searchInput.focus();
        }
    }
});

// Add table of contents for long sections
const addTableOfContents = () => {
    const content = document.querySelector('.docs-content');
    const headings = content.querySelectorAll('h2[id], h3[id]');
    
    if (headings.length > 5) {
        const toc = document.createElement('div');
        toc.className = 'table-of-contents';
        toc.style.cssText = `
            position: sticky;
            top: 100px;
            background: var(--bg-light);
            border: 1px solid rgba(255, 255, 255, 0.1);
            border-radius: 0.75rem;
            padding: 1.5rem;
            margin-bottom: 2rem;
        `;
        
        let tocHTML = '<h3 style="margin-top: 0; font-size: 1rem; color: var(--text-dim);">On This Page</h3><ul style="list-style: none; padding: 0;">';
        
        headings.forEach(heading => {
            const level = heading.tagName === 'H2' ? 0 : 1;
            const indent = level * 1;
            tocHTML += `
                <li style="margin-bottom: 0.5rem; padding-left: ${indent}rem;">
                    <a href="#${heading.id}" style="
                        color: var(--text-dim);
                        text-decoration: none;
                        font-size: 0.875rem;
                        transition: color 0.2s;
                    ">${heading.textContent}</a>
                </li>
            `;
        });
        
        tocHTML += '</ul>';
        toc.innerHTML = tocHTML;
        
        const firstSection = content.querySelector('.doc-section');
        if (firstSection) {
            firstSection.insertBefore(toc, firstSection.querySelector('h2'));
        }
    }
};

// Uncomment to enable ToC
// addTableOfContents();
