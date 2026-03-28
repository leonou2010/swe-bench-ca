"""Minimal registry shim for swe-agent tools running via docker exec.

Replaces the swerex-provided registry module with a simple JSON file-backed store.
"""

import json
import os

_ENV_FILE = "/root/.swe-agent-env"


class _Registry:
    def __init__(self):
        self._data = {}
        self._load()

    def _load(self):
        if os.path.exists(_ENV_FILE):
            try:
                with open(_ENV_FILE) as f:
                    self._data = json.load(f)
            except (json.JSONDecodeError, IOError):
                self._data = {}

    def _save(self):
        with open(_ENV_FILE, "w") as f:
            json.dump(self._data, f)

    def get(self, key, default=None):
        self._load()
        return self._data.get(key, default)

    def __getitem__(self, key):
        self._load()
        return self._data[key]

    def __setitem__(self, key, value):
        self._load()
        self._data[key] = value
        self._save()

    def __contains__(self, key):
        self._load()
        return key in self._data


registry = _Registry()
