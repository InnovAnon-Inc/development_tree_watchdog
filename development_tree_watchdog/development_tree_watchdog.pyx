# development_tree_watchdog
# handles -march= / -mtune= architecture-specific distribution

# TODO create git repo if not exists (local & upstream)   

import time
import os
import sys
from watchdog.observers import Observer
from watchdog.events import PatternMatchingEventHandler
import httpx
import subprocess

# Config
WATCH_PATH = "/mnt/host_src"
CLONER_URL = os.getenv("CLONER_URL", "http://python_project_cloner.innovanon.com:9323/clone")
DEBOUNCE_SECONDS = 5

class RepoUpdateHandler(PatternMatchingEventHandler):
    def __init__(self):
        super().__init__(ignore_patterns=[f"*/.git/*", "*/__pycache__/*"], ignore_directories=True)
        self.last_triggered = {}

    def is_ignored_by_git(self, path):
        """Returns True if the specific file path is ignored by the repo's .gitignore."""
        repo_root = self.find_repo_root(path)
        if not repo_root:
            return False
        
        # git check-ignore returns 0 if the file is ignored, 1 if it is not.
        cmd = ["git", "check-ignore", "-q", path]
        result = subprocess.run(cmd, cwd=repo_root, env={"HOME": "/tmp"})
        return result.returncode == 0

    def on_modified(self, event):
        if self.is_ignored_by_git(event.src_path):
            return
        repo_root = self.find_repo_root(event.src_path)
        if repo_root:
            now = time.time()
            # Prevent rapid-fire triggers
            if now - self.last_triggered.get(repo_root, 0) > DEBOUNCE_SECONDS:
                print(f"✨ Change detected in {repo_root}")
                self.process_update(repo_root)
                self.last_triggered[repo_root] = now

    def find_repo_root(self, path):
        """Walks up from the changed file to find the .git directory."""
        current = os.path.dirname(path)
        while current != WATCH_PATH and current != "/":
            if os.path.exists(os.path.join(current, ".git")):
                return current
            current = os.path.dirname(current)
        return None

    def process_update(self, repo_path):
        env = os.environ.copy()
        env["HOME"] = "/tmp"

        # Check if there are real changes (excluding ignored files)
        status = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=repo_path, capture_output=True, text=True, env=env
        ).stdout
        if not status:
            return

        subprocess.run(["git", "config", "--global", "safe.directory", repo_path],)
        subprocess.run(["git", "config", "--global", "--add", "safe.directory", repo_path],)
        subprocess.run(["git", "config", "--global", "user.email", "InnovAnon-Inc@gmx.com"],)
        subprocess.run(["git", "config", "--global", "user.name", "lmaddox"],)

        # 1. Git Commit & Push
        # We assume the container has the correct SSH keys/git config
        subprocess.run(["git", "add", "."], cwd=repo_path)
        subprocess.run(["git", "commit", "-m", "chore: auto-sync from watcher"], cwd=repo_path)
        subprocess.run(["git", "push"], cwd=repo_path)

        # 2. Notify Cloner
        # We need the remote URL to tell the Cloner where to pull from
        remote_url = subprocess.check_output(
            ["git", "config", "--get", "remote.origin.url"], 
            cwd=repo_path, text=True
        ).strip()

        # FIXME development_tree_watchdog  | httpx.ConnectError: [Errno 111] Connection refused
        with httpx.Client(timeout=httpx.Timeout(9000.0, read=None)) as client:
            client.post(CLONER_URL, json={"repo_url": remote_url})

def main():
    watch_path = os.getenv("WATCH_PATH", "/mnt/host_src")

    if not os.path.exists(watch_path):
        print(f"❌ Error: Watch path '{watch_path}' does not exist.")
        sys.exit(1)

    print(f"👁️  Chimera Source Watcher starting on: {watch_path}")

    event_handler = RepoUpdateHandler()
    observer = Observer()
    observer.schedule(event_handler, watch_path, recursive=True)

    observer.start()
    try:
        # This loop keeps the container alive
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()

    observer.join()
