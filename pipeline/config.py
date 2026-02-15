import yaml
import re
from typing import Any, Dict

class Config:
    """
    Loads a YAML configuration file and expands placeholders like {{ var.name }}.
    Placeholders can use dot notation to reference nested keys.
    """

    def __init__(self, config_path: str):
        with open(config_path, 'r') as f:
            self.data = yaml.safe_load(f)
        self._expand_placeholders(self.data)

    def _expand_placeholders(self, obj: Any, context: Dict = None) -> Any:
        """
        Recursively traverse the configuration and replace {{ key }} with the
        corresponding value from the context (the config itself).
        """
        if context is None:
            context = self.data

        if isinstance(obj, dict):
            for k, v in obj.items():
                obj[k] = self._expand_placeholders(v, context)
        elif isinstance(obj, list):
            for i, v in enumerate(obj):
                obj[i] = self._expand_placeholders(v, context)
        elif isinstance(obj, str):
            # Match {{ ... }} with optional whitespace and allow dotted keys
            def replacer(match):
                key_path = match.group(1).strip()
                parts = key_path.split('.')
                value = context
                for part in parts:
                    if isinstance(value, dict) and part in value:
                        value = value[part]
                    else:
                        # If the key is not found, return the original placeholder
                        return match.group(0)
                return str(value)
            # Replace all placeholders
            obj = re.sub(r'{{\s*([\w\.]+)\s*}}', replacer, obj)
        return obj

    def get(self, *keys, default=None):
        """
        Retrieve a value from the config using a sequence of keys.
        Example: config.get('step2', 'out_dir')
        """
        val = self.data
        for k in keys:
            if isinstance(val, dict) and k in val:
                val = val[k]
            else:
                return default
        return val