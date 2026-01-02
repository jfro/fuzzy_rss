export const FolderTree = {
  mounted() {
    const userId = this.el.dataset.userId
    const storageKey = `fuzzy_rss_expanded_folders_${userId}`

    // Read expanded folders from localStorage on mount
    const stored = localStorage.getItem(storageKey)
    const folderIds = stored ? JSON.parse(stored) : []

    // Send to server to initialize the expanded state
    this.pushEvent("init_expanded_folders", { folder_ids: folderIds })

    // Listen for changes from server and update localStorage
    this.handleEvent("expanded-folders-changed", ({ folder_ids }) => {
      localStorage.setItem(storageKey, JSON.stringify(folder_ids))
    })
  }
}
