import json
from pathlib import Path
import tempfile
import unittest
from scripts.validation import validate_config_schemas as validator

ROOT = Path(__file__).resolve().parents[3]
MANIFEST = ROOT / 'config/control-project.json'
SCHEMA = ROOT / 'config/schemas/control-project.schema.json'


class ControlProjectTests(unittest.TestCase):
    def validate(self, mutate=None):
        data = json.loads(MANIFEST.read_text())
        if mutate: mutate(data)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'project.json'
            path.write_text(json.dumps(data))
            return validator.validate_file(path, SCHEMA, engine='builtin', repo_root=ROOT)

    def test_current_project_is_valid(self):
        self.assertTrue(self.validate().valid)

    def test_all_policy_bypasses_are_rejected(self):
        for name in json.loads(MANIFEST.read_text())['policy']:
            with self.subTest(name=name):
                self.assertFalse(self.validate(lambda d: d['policy'].__setitem__(name, True)).valid)

    def test_credentials_are_only_environment_references(self):
        self.assertFalse(self.validate(lambda d: d['integrations']['linear'].__setitem__('apiKeyEnv', 'secret-value')).valid)
        self.assertFalse(self.validate(lambda d: d['integrations']['github'].__setitem__('token', 'secret')).valid)

    def test_private_link_cannot_carry_credentials(self):
        for url in ['http://example.com/x', 'https://user:pass@example.com/x', 'https://example.com/x?token=s', 'https://example.com/x#secret']:
            with self.subTest(url=url):
                self.assertFalse(self.validate(lambda d: d['integrations']['linear'].__setitem__('projectUrl', url)).valid)

    def test_identity_and_contract_paths_cannot_drift(self):
        for key,value in [('projectId','another-project'),('repository','other/repo'),('routingConfig','../../secret')]:
            with self.subTest(key=key):
                self.assertFalse(self.validate(lambda d: d.__setitem__(key,value)).valid)

    def test_required_surfaces_and_steps_are_preserved(self):
        self.assertFalse(self.validate(lambda d: d['integrations'].pop('slack')).valid)
        self.assertFalse(self.validate(lambda d: d['steps'].reverse()).valid)


if __name__ == '__main__': unittest.main()
