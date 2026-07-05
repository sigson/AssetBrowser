# Asset Browser (Godot 3 plugin)

<img src="https://raw.githubusercontent.com/sigson/AssetBrowser/refs/heads/godot3/addons/asset_browser/icon.png" alt="Preview 0" width="100"/>

A Godot 3 editor addon — a Unity-like dockable project browser with tabbed views, fast search, resource-type filtering, tags, favorites, and flexible performance settings.

## Preview
How plugin looks like:
<table>
  <tr>
    <td><img src="https://raw.githubusercontent.com/sigson/AssetBrowser/refs/heads/godot3/addons/asset_browser/img/screen1.png" alt="Preview 1" width="300"/></td>
    <td><img src="https://raw.githubusercontent.com/sigson/AssetBrowser/refs/heads/godot3/addons/asset_browser/img/screen2.png" alt="Preview 2" width="300"/></td>
    <td><img src="https://raw.githubusercontent.com/sigson/AssetBrowser/refs/heads/godot3/addons/asset_browser/img/screen3.png" alt="Preview 3" width="300"/></td>
  </tr>
</table>

## Installation

1. Copy the `addons/asset_browser` folder into your project.
2. In Godot: **Project → Project Settings → Plugins** → enable **Asset Browser**.
3. By default the panel opens in the editor's left dock (configurable, see below).

## Key Features

### Placement and tabs
- The panel can be opened **in a dock**, **in the bottom panel**, or **in both at once** (two independent windows sharing the same data layer) — configurable via the `config.tres` resource (`open_in_dock`, `open_in_bottom_panel`, dock slot, bottom panel title).
- Support for **multiple tabs** within a single host: opening a new tab, duplicating the current one, closing a tab.
- Tab state (current directory, navigation history, view mode, preview zoom) persists across editor sessions.

### Navigation
- A project folder tree (hierarchy) on the left, a file list/grid on the right (layout mode is configurable).
- **Back / Forward / Up** buttons with directory navigation history.
- **Breadcrumbs** with line wrapping and the ability to type a path manually.
- **Favorite folders**: add/remove via the tree's context menu, quick access to them.
- Lazy (on-demand) and incremental folder-tree building — avoids recomputing the whole tree on every change.

### File viewing
- Two display modes: **list** and **tile grid** with previews.
- **Virtualization** of the list/grid — only visible items are rendered, keeping things smooth on large projects.
- Adjustable **preview zoom** via a slider in the status bar.
- Previews are generated in per-frame batches with a time budget so the editor doesn't stall.
- A custom preview generator for **TileSet** — builds a collage from atlas tile thumbnails.
- Two preview caching modes: **engine_lazy** (no dedicated cache, relies on the engine) and **full_memory** (in-memory cache with TTL and periodic sweeping).

### Search
- A search field with debounce and **asynchronous**, frame-by-frame traversal — doesn't block the UI on large projects.
- **Regex** search support for file names.
- **Content search** inside files (text and text-based `.tres` resources), with a limit on the amount of data read and a required opt-in confirmation for project-wide content search, preventing accidental scanning of the entire disk.
- Toggle search scope: **current folder** or **the whole project**.
- Result count limit, with status-bar indicators for truncated results / blocked content search.
- **Tag filtering** as part of the search query.

### Resource type filter
- A modal dialog for selecting resource types, showing a tree of the `Resource` class hierarchy (built from `ClassDB`, including user script resources as a separate `CustomResource` branch).
- **Tri-state** checkboxes (unchecked / partial / fully checked) with "installer-style" logic — selecting a parent selects its entire subtree.
- Search/filter for types inside the dialog.

### File operations
Available via the context menu and toolbar:
- Create: **folder, text file, material, scene, resource**.
- **Rename**, **duplicate**, **delete** (with confirmation) files and folders.
- **Copy / Cut / Paste** via the plugin's internal clipboard.
- **Copy path**, **show in OS file manager**, **open containing folder**.
- **Open in external editor** / open for editing directly in Godot.
- **Drag & drop** for files and folders (moving into another directory, accepting files dropped from the OS/engine).
- Renaming, copying, and deleting automatically carries over/removes the associated `.import` sidecar files.
- Sort the file list by column (name, type, size, etc.), ascending/descending.

### Tags and favorites
- Assign arbitrary **tags** to files/folders, stored separately from the project (`user://asset_browser/tags.cfg`).
- A list of **favorite folders** for quick access (`user://asset_browser/favorites.cfg`).

### Auto-refresh
- Tracks project filesystem changes via `EditorFileSystem` signals (create/delete/rename, reimport) — the tree and file lists update automatically.
- Three polling modes: **event-only**, **event + periodic polling**, **polling-only** — with configurable frequency and coalescing of rapid changes.

### Lifecycle control (killswitch)
- Ability to **suspend** the plugin in one or both panels (e.g., to save resources) without unloading the addon itself, and **resume** it later.
- Option to persist the "suspended" state across editor restarts.
- A **restart** button for the plugin without toggling it off/on in the plugin list.

### Settings and performance profiles
A dedicated settings dialog grouped into sections: filesystem scanning, folder tree, file list, search, previews, lifecycle, layout/spacing. Comes with ready-made **profiles**:
- **Low CPU / Low RAM** — minimal load (lazy preview cache, fewer items per frame).
- **Balanced** — sensible default values.
- **Responsive** — maximum responsiveness (full in-memory preview cache, more items per frame, no grid virtualization).

Settings are stored in `settings.cfg` inside the addon folder and applied on the fly without an editor restart.

## Project structure

```
addons/asset_browser/
├── asset_browser_plugin.gd     # EditorPlugin entry point
├── asset_browser_config.gd     # panel placement config (.tres, editable in the Inspector)
├── config.tres
├── settings.cfg                # user performance/appearance settings
├── plugin.cfg
├── shared/                     # shared services and data models
│   ├── shared.gd                    # dependency container (DI)
│   ├── asset_database.gd            # EditorFileSystem wrapper, change tracking
│   ├── asset_node.gd                # file/folder node model
│   ├── settings_model.gd            # settings.cfg read/write, profiles
│   ├── thumbnail_service.gd         # preview generation and caching
│   ├── tile_set_preview_generator.gd# custom TileSet preview generator
│   ├── tag_store.gd                 # tag storage
│   ├── favorites_model.gd           # favorite folders
│   ├── clipboard_model.gd           # clipboard (copy/cut)
│   ├── lifecycle_controller.gd      # plugin suspend/resume/restart
│   └── i_thumbnail_provider.gd      # thumbnail provider interface
├── ops/                         # business logic
│   ├── file_ops.gd                  # file operations (create/rename/copy/move/delete)
│   ├── search_engine.gd             # search engine (by name/content, regex)
│   ├── search_state.gd              # search bar state
│   ├── resource_type_graph.gd       # Resource type hierarchy graph
│   └── type_selection_model.gd      # tri-state type selection model
└── ui/                          # visual components
    ├── tab_host.gd                  # tab host, dock/bottom panel
    ├── browser_view.gd              # layout of a single browser tab
    ├── browser_tab_state.gd         # per-tab state (navigation history, etc.)
    ├── hierarchy_pane.gd            # folder tree
    ├── file_view.gd                 # file list/grid
    ├── file_tile.gd                 # a single tile in the grid
    ├── toolbar.gd                   # toolbar (navigation, create, search, sort)
    ├── search_bar.gd                # search bar with toggles (regex/content/scope)
    ├── breadcrumbs.gd                # path breadcrumbs
    ├── status_bar.gd                 # status bar (count, zoom, notifications)
    ├── type_selector_dialog.gd       # resource type selector dialog
    ├── settings_dialog.gd            # settings and profiles dialog
    └── flow_container.gd             # wrapping container (used for breadcrumbs)
```

## Requirements
- Godot Engine **3.3+**.
- Editor-only (`@tool`); it is not bundled into exported game builds.
