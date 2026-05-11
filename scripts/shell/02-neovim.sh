#!/usr/bin/env bash
# =============================================================================
# scripts/shell/02-neovim.sh — Neovim installation and configuration
# =============================================================================
#
# NEOVIM ANALYSIS FOR FEDORA 44:
#
# PACKAGE OPTIONS:
#   1. DNF (Fedora repos):
#      Fedora 44 ships Neovim 0.10.x in the standard repos.
#      Neovim 0.10 is stable, supports all modern LSP/treesitter features,
#      and is the version most plugins target. This is RECOMMENDED for stability.
#
#   2. COPR (neovim-nightly or similar):
#      Available but adds update churn. Only needed if you require Neovim 0.11+
#      features (e.g., the built-in LSP inlay hints, native snippet support).
#      COPR: @neovim/neovim (provides nightly builds)
#
#   3. AppImage / GitHub releases:
#      Portable but bypasses system updates. Not recommended on Fedora.
#
# VERDICT: Use Fedora repos (dnf install neovim). Fedora 44's Neovim is recent
# enough for LazyVim/AstroNvim/manual config. Install neovim-nightly COPR only
# if you need cutting-edge features.
#
# CLIPBOARD:
#   Wayland clipboard requires wl-clipboard (provides wl-copy/wl-paste).
#   Neovim detects wl-clipboard automatically on Wayland sessions.
#   Do NOT install xclip/xsel as primary clipboard — they require XWayland.
#   We install both for compatibility (XWayland sessions still exist).
#
# PLUGIN MANAGER:
#   lazy.nvim is the current standard. Fast, declarative, lazy-loaded.
#   We set up a minimal but functional config using lazy.nvim.
#
# INTEGRATIONS:
#   ripgrep: required by Telescope.nvim (live grep)
#   fd-find: required by Telescope.nvim (find files)
#   node.js + npm: required by many LSP servers (pyright, tsserver, etc.)
#   python3-pynvim: Python provider for Neovim plugins
#   python3-neovim: alias for pynvim (Fedora package name)
#   tree-sitter-cli: for compiling Treesitter grammars
#
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

source "${LIB_DIR}/helpers.sh"
source "${LIB_DIR}/pkg.sh"

log_section "Neovim"

REAL_USER="${SUDO_USER:-${USER}}"
REAL_HOME="$(real_home)"
NVIM_CONFIG_DIR="${REAL_HOME}/.config/nvim"

# =============================================================================
# 1. Install Neovim and dependencies
# =============================================================================
log_step "Installing Neovim and dependencies"

# python3-neovim is the correct Fedora RPM name (source package: python-neovim).
# python3-pynvim does NOT exist as a Fedora RPM — it caused your DNF5 error.
# python3-neovim provides the pynvim library and is needed for Python-based
# plugins and for :checkhealth to pass without Python provider warnings.
#
# wl-clipboard: primary clipboard tool for Wayland (wl-copy / wl-paste).
# xclip / xsel: XWayland fallbacks, valid RPMs, harmless to install alongside.
dnf_install \
  neovim \
  python3-neovim \
  wl-clipboard \
  xclip \
  xsel

# npm is needed for many LSP servers; nodejs/npm installed in devtools
# tree-sitter-cli can be installed via npm if needed

# =============================================================================
# 2. Optional: Neovim Nightly via COPR
# =============================================================================
log_step "Checking Neovim version preference"

if ! "${DRY_RUN}"; then
  NVIM_VERSION="$(nvim --version 2>/dev/null | head -1 | grep -oP 'v\K[\d.]+')"
  log_info "Installed Neovim version: ${NVIM_VERSION}"

  # Fedora 44 ships 0.10.x; offer nightly if user wants 0.11+
  NVIM_MAJOR="$(echo "${NVIM_VERSION}" | cut -d. -f1)"
  NVIM_MINOR="$(echo "${NVIM_VERSION}" | cut -d. -f2)"

  if [[ "${NVIM_MAJOR}" -eq 0 && "${NVIM_MINOR}" -lt 10 ]]; then
    log_warn "Neovim version ${NVIM_VERSION} is older than expected for Fedora 44"
    log_warn "Enabling COPR neovim nightly for a more recent version"
    dnf_copr_enable "@neovim/neovim"
    sudo "${DNF_CMD}" upgrade -y neovim
  fi
fi

# =============================================================================
# 3. LSP and tooling dependencies
# =============================================================================
log_step "Installing LSP and Neovim tooling dependencies"

# Python LSP server (pyright via npm is faster; python-lsp-server via dnf)
dnf_install python3-lsp-server || true  # Optional; pyright via Mason is better

# Lua LSP (for Neovim config files — lua-language-server not in Fedora repos)
# We use Mason.nvim to install lua-language-server from within Neovim

# Formatters via dnf
dnf_install \
  shfmt \
  stylua 2>/dev/null || true  # stylua may not be in all Fedora versions

# stylua via cargo if not available as RPM
if ! has_cmd stylua; then
  log_step "Installing stylua via cargo"
  if ! "${DRY_RUN}"; then
    sudo -u "${REAL_USER}" cargo install stylua 2>/dev/null || \
      log_warn "stylua cargo install failed — install manually: cargo install stylua"
  fi
fi

# =============================================================================
# 4. Write Neovim configuration (lazy.nvim based)
# =============================================================================
log_step "Writing Neovim configuration"

if ! "${DRY_RUN}"; then
  sudo -u "${REAL_USER}" mkdir -p "${NVIM_CONFIG_DIR}/lua"
fi

# ── init.lua ──────────────────────────────────────────────────────────────────
if [[ -f "${NVIM_CONFIG_DIR}/init.lua" ]] && ! grep -q "fedora-workstation-setup" "${NVIM_CONFIG_DIR}/init.lua" 2>/dev/null; then
  NVIM_BACKUP="${NVIM_CONFIG_DIR}.bak.$(date +%Y%m%d%H%M%S)"
  log_warn "Existing Neovim config found — backing up to ${NVIM_BACKUP}"
  if ! "${DRY_RUN}"; then
    sudo -u "${REAL_USER}" cp -r "${NVIM_CONFIG_DIR}" "${NVIM_BACKUP}"
  fi
fi

if "${DRY_RUN}"; then
  log_dry "Would write Neovim configuration to ${NVIM_CONFIG_DIR}"
else

sudo -u "${REAL_USER}" tee "${NVIM_CONFIG_DIR}/init.lua" > /dev/null <<'INIT_EOF'
-- =============================================================================
-- Neovim Configuration — Fedora Developer Workstation
-- fedora-workstation-setup
-- Plugin manager: lazy.nvim
-- =============================================================================

-- ── Bootstrap lazy.nvim ───────────────────────────────────────────────────────
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- ── Load modules ──────────────────────────────────────────────────────────────
require("config.options")
require("config.keymaps")
require("config.plugins")
INIT_EOF

# ── options.lua ───────────────────────────────────────────────────────────────
sudo -u "${REAL_USER}" tee "${NVIM_CONFIG_DIR}/lua/config/options.lua" > /dev/null <<'OPTIONS_EOF'
-- =============================================================================
-- Editor Options
-- =============================================================================
local opt = vim.opt

-- Line numbers
opt.number = true
opt.relativenumber = true

-- Indentation
opt.tabstop = 2
opt.shiftwidth = 2
opt.expandtab = true
opt.smartindent = true
opt.autoindent = true

-- Search
opt.hlsearch = true
opt.incsearch = true
opt.ignorecase = true
opt.smartcase = true

-- Appearance
opt.termguicolors = true
opt.signcolumn = "yes"
opt.cursorline = true
opt.wrap = false
opt.scrolloff = 8
opt.sidescrolloff = 8
opt.colorcolumn = "120"
opt.splitbelow = true
opt.splitright = true

-- Clipboard — auto-detect Wayland (wl-clipboard) or X11
-- unnamedplus syncs Neovim yank/paste with system clipboard
opt.clipboard = "unnamedplus"

-- Files
opt.undofile = true
opt.swapfile = false
opt.backup = false
opt.updatetime = 250
opt.timeoutlen = 400

-- Completion
opt.completeopt = "menu,menuone,noselect"
opt.pumheight = 10

-- Folding (using treesitter)
opt.foldmethod = "expr"
opt.foldexpr = "nvim_treesitter#foldexpr()"
opt.foldlevel = 99  -- Open all folds by default

-- Whitespace
opt.list = true
opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }

-- Neovim providers
vim.g.python3_host_prog = vim.fn.exepath("python3")
vim.g.loaded_perl_provider = 0    -- Disable Perl provider (not needed)
vim.g.loaded_ruby_provider = 0    -- Disable Ruby provider (not needed)
OPTIONS_EOF

# ── keymaps.lua ───────────────────────────────────────────────────────────────
sudo -u "${REAL_USER}" tee "${NVIM_CONFIG_DIR}/lua/config/keymaps.lua" > /dev/null <<'KEYMAPS_EOF'
-- =============================================================================
-- Key Mappings
-- =============================================================================
local map = vim.keymap.set

-- Leader key
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- ── Normal mode ───────────────────────────────────────────────────────────────

-- Clear search highlight
map("n", "<Esc>", "<cmd>nohlsearch<CR>")

-- Window navigation
map("n", "<C-h>", "<C-w>h", { desc = "Move to left window" })
map("n", "<C-j>", "<C-w>j", { desc = "Move to lower window" })
map("n", "<C-k>", "<C-w>k", { desc = "Move to upper window" })
map("n", "<C-l>", "<C-w>l", { desc = "Move to right window" })

-- Resize windows
map("n", "<C-Up>",    "<cmd>resize +2<CR>")
map("n", "<C-Down>",  "<cmd>resize -2<CR>")
map("n", "<C-Left>",  "<cmd>vertical resize -2<CR>")
map("n", "<C-Right>", "<cmd>vertical resize +2<CR>")

-- Buffer navigation
map("n", "<S-h>", "<cmd>bprevious<CR>", { desc = "Previous buffer" })
map("n", "<S-l>", "<cmd>bnext<CR>",     { desc = "Next buffer" })
map("n", "<leader>bd", "<cmd>bdelete<CR>", { desc = "Delete buffer" })

-- File tree
map("n", "<leader>e", "<cmd>Neotree toggle<CR>", { desc = "File Explorer" })
map("n", "<leader>o", "<cmd>Neotree focus<CR>",  { desc = "Focus Explorer" })

-- Telescope
map("n", "<leader>ff", "<cmd>Telescope find_files<CR>",   { desc = "Find files" })
map("n", "<leader>fg", "<cmd>Telescope live_grep<CR>",    { desc = "Live grep" })
map("n", "<leader>fb", "<cmd>Telescope buffers<CR>",      { desc = "Find buffers" })
map("n", "<leader>fh", "<cmd>Telescope help_tags<CR>",    { desc = "Help tags" })
map("n", "<leader>fr", "<cmd>Telescope oldfiles<CR>",     { desc = "Recent files" })
map("n", "<leader>fc", "<cmd>Telescope commands<CR>",     { desc = "Commands" })
map("n", "<leader>fk", "<cmd>Telescope keymaps<CR>",      { desc = "Keymaps" })
map("n", "<leader>fs", "<cmd>Telescope git_status<CR>",   { desc = "Git status" })

-- LSP
map("n", "gd",         vim.lsp.buf.definition,         { desc = "Go to definition" })
map("n", "gD",         vim.lsp.buf.declaration,        { desc = "Go to declaration" })
map("n", "gr",         "<cmd>Telescope lsp_references<CR>", { desc = "References" })
map("n", "gi",         vim.lsp.buf.implementation,     { desc = "Go to implementation" })
map("n", "K",          vim.lsp.buf.hover,              { desc = "Hover docs" })
map("n", "<leader>ca", vim.lsp.buf.code_action,        { desc = "Code actions" })
map("n", "<leader>rn", vim.lsp.buf.rename,             { desc = "Rename symbol" })
map("n", "<leader>lf", function() vim.lsp.buf.format({ async = true }) end, { desc = "Format" })
map("n", "[d",         vim.diagnostic.goto_prev,       { desc = "Previous diagnostic" })
map("n", "]d",         vim.diagnostic.goto_next,       { desc = "Next diagnostic" })
map("n", "<leader>ld", vim.diagnostic.open_float,      { desc = "Show diagnostic" })

-- Git (Gitsigns)
map("n", "<leader>gs", "<cmd>Gitsigns stage_hunk<CR>",     { desc = "Stage hunk" })
map("n", "<leader>gr", "<cmd>Gitsigns reset_hunk<CR>",     { desc = "Reset hunk" })
map("n", "<leader>gp", "<cmd>Gitsigns preview_hunk<CR>",   { desc = "Preview hunk" })
map("n", "<leader>gb", "<cmd>Gitsigns blame_line<CR>",     { desc = "Blame line" })
map("n", "]h",         "<cmd>Gitsigns next_hunk<CR>",      { desc = "Next hunk" })
map("n", "[h",         "<cmd>Gitsigns prev_hunk<CR>",      { desc = "Previous hunk" })

-- Toggleterm
map("n", "<C-t>", "<cmd>ToggleTerm<CR>", { desc = "Toggle terminal" })
map("t", "<C-t>", "<cmd>ToggleTerm<CR>", { desc = "Toggle terminal" })
map("t", "<Esc>", [[<C-\><C-n>]],        { desc = "Exit terminal mode" })

-- ── Visual mode ───────────────────────────────────────────────────────────────
-- Indent and stay in visual mode
map("v", "<", "<gv")
map("v", ">", ">gv")

-- Move selected lines
map("v", "<A-j>", ":m .+1<CR>==")
map("v", "<A-k>", ":m .-2<CR>==")
KEYMAPS_EOF

# ── plugins.lua ───────────────────────────────────────────────────────────────
sudo -u "${REAL_USER}" tee "${NVIM_CONFIG_DIR}/lua/config/plugins.lua" > /dev/null <<'PLUGINS_EOF'
-- =============================================================================
-- Plugin Definitions (lazy.nvim)
-- =============================================================================
require("lazy").setup({

  -- ── Colorscheme ─────────────────────────────────────────────────────────────
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    config = function()
      require("catppuccin").setup({ flavour = "mocha" })
      vim.cmd.colorscheme("catppuccin")
    end,
  },

  -- ── Status line ─────────────────────────────────────────────────────────────
  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("lualine").setup({
        options = { theme = "catppuccin" },
        sections = {
          lualine_c = { { "filename", path = 1 } },
          lualine_x = { "encoding", "fileformat", "filetype" },
        },
      })
    end,
  },

  -- ── File explorer ────────────────────────────────────────────────────────────
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
      "MunifTanjim/nui.nvim",
    },
    config = function()
      require("neo-tree").setup({
        window = { width = 30 },
        filesystem = {
          filtered_items = { hide_dotfiles = false },
        },
      })
    end,
  },

  -- ── Fuzzy finder (Telescope) ─────────────────────────────────────────────────
  -- Requires: ripgrep (rg), fd
  {
    "nvim-telescope/telescope.nvim",
    tag = "0.1.8",
    dependencies = {
      "nvim-lua/plenary.nvim",
      { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
    },
    config = function()
      local telescope = require("telescope")
      telescope.setup({
        defaults = {
          file_ignore_patterns = { "node_modules", ".git/" },
          vimgrep_arguments = {
            "rg", "--color=never", "--no-heading",
            "--with-filename", "--line-number",
            "--column", "--smart-case", "--hidden",
          },
        },
        pickers = {
          find_files = { find_command = { "fd", "--type", "f", "--hidden", "--exclude", ".git" } },
        },
      })
      telescope.load_extension("fzf")
    end,
  },

  -- ── Treesitter ────────────────────────────────────────────────────────────────
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter.configs").setup({
        ensure_installed = {
          "bash", "c", "cpp", "go", "lua", "python", "rust",
          "typescript", "javascript", "json", "yaml", "toml",
          "dockerfile", "terraform", "hcl", "markdown", "vim",
          "regex", "query",
        },
        highlight = { enable = true },
        indent = { enable = true },
        incremental_selection = { enable = true },
      })
    end,
  },

  -- ── LSP ───────────────────────────────────────────────────────────────────────
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "williamboman/mason.nvim",
      "williamboman/mason-lspconfig.nvim",
      "hrsh7th/cmp-nvim-lsp",
    },
    config = function()
      require("mason").setup()
      require("mason-lspconfig").setup({
        ensure_installed = {
          "lua_ls",        -- Lua (Neovim config)
          "pyright",       -- Python
          "gopls",         -- Go
          "rust_analyzer", -- Rust
          "bashls",        -- Bash
          "dockerls",      -- Dockerfile
          "yamlls",        -- YAML (k8s manifests)
          "jsonls",        -- JSON
          "terraformls",   -- Terraform/HCL
        },
        automatic_installation = true,
      })

      local lspconfig = require("lspconfig")
      local caps = require("cmp_nvim_lsp").default_capabilities()

      -- Configure each installed server
      require("mason-lspconfig").setup_handlers({
        function(server_name)
          lspconfig[server_name].setup({ capabilities = caps })
        end,
        ["lua_ls"] = function()
          lspconfig.lua_ls.setup({
            capabilities = caps,
            settings = {
              Lua = {
                diagnostics = { globals = { "vim" } },
                workspace = { library = vim.api.nvim_get_runtime_file("", true) },
                telemetry = { enable = false },
              },
            },
          })
        end,
      })

      -- Diagnostic display
      vim.diagnostic.config({
        virtual_text = { prefix = "●" },
        signs = true,
        update_in_insert = false,
        severity_sort = true,
        float = { border = "rounded" },
      })
    end,
  },

  -- ── Completion ────────────────────────────────────────────────────────────────
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "hrsh7th/cmp-cmdline",
      "L3MON4D3/LuaSnip",
      "saadparwaiz1/cmp_luasnip",
      "rafamadriz/friendly-snippets",
    },
    config = function()
      local cmp = require("cmp")
      local luasnip = require("luasnip")
      require("luasnip.loaders.from_vscode").lazy_load()

      cmp.setup({
        snippet = { expand = function(args) luasnip.lsp_expand(args.body) end },
        mapping = cmp.mapping.preset.insert({
          ["<C-b>"]   = cmp.mapping.scroll_docs(-4),
          ["<C-f>"]   = cmp.mapping.scroll_docs(4),
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<C-e>"]   = cmp.mapping.abort(),
          ["<CR>"]    = cmp.mapping.confirm({ select = false }),
          ["<Tab>"]   = cmp.mapping(function(fallback)
            if cmp.visible() then cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then luasnip.expand_or_jump()
            else fallback() end
          end, { "i", "s" }),
          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then luasnip.jump(-1)
            else fallback() end
          end, { "i", "s" }),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" },
          { name = "buffer",  keyword_length = 3 },
          { name = "path" },
        }),
        formatting = {
          format = function(entry, item)
            local source_labels = {
              nvim_lsp = "[LSP]", luasnip = "[Snip]",
              buffer = "[Buf]", path = "[Path]",
            }
            item.menu = source_labels[entry.source.name] or ""
            return item
          end,
        },
        window = {
          completion = cmp.config.window.bordered(),
          documentation = cmp.config.window.bordered(),
        },
      })
    end,
  },

  -- ── Formatting ────────────────────────────────────────────────────────────────
  {
    "stevearc/conform.nvim",
    config = function()
      require("conform").setup({
        formatters_by_ft = {
          lua        = { "stylua" },
          python     = { "ruff_format", "black" },
          go         = { "gofmt" },
          rust       = { "rustfmt" },
          sh         = { "shfmt" },
          bash       = { "shfmt" },
          json       = { "prettier" },
          yaml       = { "prettier" },
          markdown   = { "prettier" },
          javascript = { "prettier" },
          typescript = { "prettier" },
        },
        format_on_save = {
          timeout_ms = 500,
          lsp_fallback = true,
        },
      })
    end,
  },

  -- ── Git integration ───────────────────────────────────────────────────────────
  {
    "lewis6991/gitsigns.nvim",
    config = function()
      require("gitsigns").setup({
        signs = {
          add    = { text = "▎" },
          change = { text = "▎" },
          delete = { text = "" },
        },
        current_line_blame = false,  -- Toggle with <leader>gb
      })
    end,
  },

  {
    "tpope/vim-fugitive",
    cmd = { "Git", "G", "Gdiff", "Gblame" },
  },

  -- ── Terminal ──────────────────────────────────────────────────────────────────
  {
    "akinsho/toggleterm.nvim",
    version = "*",
    config = function()
      require("toggleterm").setup({
        size = 15,
        direction = "horizontal",
        shell = vim.o.shell,
      })
    end,
  },

  -- ── Quality of life ───────────────────────────────────────────────────────────
  { "numToStr/Comment.nvim",      config = true },
  { "windwp/nvim-autopairs",      config = true },
  { "kylechui/nvim-surround",     version = "*", config = true },
  { "folke/which-key.nvim",       config = true },
  { "lukas-reineke/indent-blankline.nvim", main = "ibl", config = true },
  { "RRethy/vim-illuminate" },
  { "folke/todo-comments.nvim",   dependencies = { "nvim-lua/plenary.nvim" }, config = true },
  { "stevearc/dressing.nvim",     config = true },

  -- ── Buffers ───────────────────────────────────────────────────────────────────
  {
    "akinsho/bufferline.nvim",
    version = "*",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("bufferline").setup({ options = { diagnostics = "nvim_lsp" } })
    end,
  },

  -- ── Noice (better UI for messages, cmdline, popupmenu) ───────────────────────
  {
    "folke/noice.nvim",
    event = "VeryLazy",
    dependencies = { "MunifTanjim/nui.nvim", "rcarriga/nvim-notify" },
    config = function()
      require("noice").setup({
        lsp = {
          override = {
            ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
            ["vim.lsp.util.stylize_markdown"] = true,
            ["cmp.entry.get_documentation"] = true,
          },
        },
        presets = { bottom_search = true, command_palette = true, long_message_to_split = true },
      })
    end,
  },

}, {
  -- lazy.nvim options
  performance = {
    rtp = {
      -- Disable some built-in plugins we replace with better alternatives
      disabled_plugins = {
        "gzip", "matchit", "matchparen", "netrw", "netrwPlugin",
        "tarPlugin", "tohtml", "tutor", "zipPlugin",
      },
    },
  },
  ui = { border = "rounded" },
  checker = { enabled = true, notify = false },  -- Auto-check for plugin updates
})
PLUGINS_EOF

sudo -u "${REAL_USER}" mkdir -p "${NVIM_CONFIG_DIR}/lua/config"

fi # end DRY_RUN check

log_success "Neovim configuration written to ${NVIM_CONFIG_DIR}"
log_info "First launch will auto-install all plugins via lazy.nvim"
log_info "Mason will install LSP servers on first open of relevant filetypes"
log_warn "Run 'nvim' and wait for lazy.nvim to complete installation"
log_warn "Then run ':MasonInstall lua-language-server pyright gopls rust-analyzer bashls' if needed"
