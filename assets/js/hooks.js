export const FolderTree = {
  mounted() {
    const userId = this.el.dataset.userId
    this.handleEvent("update_expanded_folders_cookie", ({ folder_ids }) => {
      const d = new Date();
      d.setTime(d.getTime() + (365 * 24 * 60 * 60 * 1000)); // 1 year
      const expires = "expires=" + d.toUTCString();
      const cookieName = userId ? `expanded_folders_${userId}` : "expanded_folders";
      document.cookie = cookieName + "=" + encodeURIComponent(JSON.stringify(folder_ids)) + ";" + expires + ";path=/";
    })
  }
}

export const ScrollReset = {
  mounted() {
    this.el.scrollTop = 0;
  },
  updated() {
    this.el.scrollTop = 0;
  }
}
