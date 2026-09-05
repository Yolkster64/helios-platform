import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('repository_health', Path(__file__).resolve().parents[1] / 'repository-health.py')
health = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(health)


class RepositoryHealthTests(unittest.TestCase):
    def test_success_is_scoped_to_repository(self):
        report = health.summarize({name: {'result': 'success'} for name in health.EXPECTED_JOBS})
        self.assertTrue(report['repositoryChecksPassed'])
        for key in ('runtimeVerified', 'deploymentVerified', 'providersVerified', 'connectorDeliveryVerified'):
            self.assertFalse(report[key])
        self.assertNotIn('OPERATIONAL', health.render(report))
        self.assertNotIn('$(date)', health.render(report))

    def test_every_incomplete_job_blocks_success(self):
        for name in health.EXPECTED_JOBS:
            for state in ('failure', 'cancelled', 'skipped', 'pending', None):
                with self.subTest(name=name, state=state):
                    needs = {key: {'result': 'success'} for key in health.EXPECTED_JOBS}
                    needs[name] = {'result': state}
                    self.assertFalse(health.summarize(needs)['repositoryChecksPassed'])

    def test_missing_or_malformed_needs_cannot_pass(self):
        for needs in ({}, None, [], {'health-check': {'result': 'success'}}):
            self.assertFalse(health.summarize(needs)['repositoryChecksPassed'])

    def test_inventory_requires_actual_files_and_json_objects(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.assertFalse(health.inventory(root)['ready'])
            for name in health.REQUIRED_FILES:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('{}' if path.suffix == '.json' else 'source', encoding='utf-8')
            self.assertTrue(health.inventory(root)['ready'])
            (root / 'config/aihub.json').write_text('[]', encoding='utf-8')
            self.assertFalse(health.inventory(root)['ready'])


if __name__ == '__main__':
    unittest.main()
