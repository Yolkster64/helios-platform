"""Check component boundaries and the fixed, non-deploying command runner."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch, Mock

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location('helios_components', ROOT / 'scripts/bootstrap/components.py')
components = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = components
SPEC.loader.exec_module(components)


class ComponentPlanTests(unittest.TestCase):
    def test_fixed_parts_remain_in_one_repository(self):
        plan = components.list_parts(ROOT)
        self.assertEqual([part['id'] for part in plan['parts']], ['core', 'desktop', 'usb', 'cloud', 'fleet'])
        self.assertEqual(plan['repository'], 'Yolkster64/helios-platform')
        self.assertEqual(plan['sourcePolicy'], 'single-repository')
        self.assertFalse(plan['executed'])

    def test_schema_supports_builtin_validator(self):
        result = components.schema_validation.validate_file(ROOT / 'config/components.json',
            ROOT / 'config/schemas/components.schema.json', engine='builtin', repo_root=ROOT)
        self.assertTrue(result.valid, result.issues)

    def test_schema_rejects_command_injection_and_profile_swapping(self):
        manifest = json.loads((ROOT / 'config/components.json').read_text())
        schema = json.loads((ROOT / 'config/schemas/components.schema.json').read_text())
        for mutate in (
            lambda value: value['parts']['core'].update(command='rm -rf example'),
            lambda value: value['parts']['core'].update(testProfile='cloud'),
            lambda value: value['parts']['usb'].update(paths=['../../outside']),
            lambda value: value['parts'].update(arbitrary=value['parts']['core']),
        ):
            candidate = copy.deepcopy(manifest)
            mutate(candidate)
            issues, _ = components.schema_validation.validate_instance(candidate, schema, 'builtin')
            self.assertTrue(issues)

    def test_plan_never_launches_process_or_deployment(self):
        with patch.object(components.subprocess, 'Popen', side_effect=AssertionError('plan executed')), \
             patch.object(components.subprocess, 'run', side_effect=AssertionError('plan executed')):
            for name in components.PARTS:
                plan = components.plan_part(name, ROOT)
                self.assertFalse(plan['executed'])
                self.assertFalse(plan['deployment']['executed'])
                self.assertFalse(plan['deployment']['automaticApply'])

    def test_cloud_and_fleet_refer_to_protected_read_only_workflow_defaults(self):
        for name in ('cloud', 'fleet'):
            deploy = components.plan_part(name, ROOT)['deployment']
            self.assertEqual(deploy['workflow'], '.github/workflows/helios-deploy.yml')
            self.assertEqual(deploy['environment'], 'azure-dev')
            self.assertEqual(deploy['ref'], 'refs/heads/main')
            self.assertEqual(deploy['inputs'], {'what_if': True, 'deploy_confirmed': False})

    def test_usb_targets_portable_planner_not_legacy_repair_scripts(self):
        plan = components.plan_part('usb', ROOT)
        self.assertIn('src/ai/HELIOS.AIHub/Setup/UsbSetupPlanner.cs', plan['details']['artifacts'])
        command = plan['tests'][0]['argv']
        self.assertEqual(command[:2], ['dotnet', 'test'])
        self.assertIn('FullyQualifiedName~UsbSetup', command)
        self.assertFalse(any(argument.endswith('.ps1') for argument in command))

    def test_invalid_part_never_reaches_process_runner(self):
        with patch.object(components, '_execute', side_effect=AssertionError('invalid part executed')):
            for name in ('core;echo unsafe', '../cloud', '', ['core'], 'deploy'):
                with self.subTest(name=name), self.assertRaises(components.ComponentError):
                    components.test_part(name, ROOT)

    def test_tests_cannot_select_an_unreviewed_repository(self):
        with tempfile.TemporaryDirectory() as temporary, self.assertRaises(components.ComponentError):
            components.test_part('core', Path(temporary))

    def test_missing_usb_source_is_unavailable_instead_of_zero_tests(self):
        plan = components.plan_part('usb', ROOT)
        plan['missingPaths'] = ['src/ai/HELIOS.AIHub/Setup/UsbSetupPlanner.cs']
        with patch.object(components, 'plan_part', return_value=plan), patch.object(components, '_execute') as runner:
            result = components.test_part('usb', ROOT)
        self.assertEqual(result['status'], 'unavailable')
        self.assertFalse(result['executed'])
        runner.assert_not_called()

    @unittest.skipIf(sys.platform == 'win32', 'Linux host boundary applies to Linux')
    def test_desktop_on_linux_is_not_reported_as_passed(self):
        with patch.object(components, '_execute') as runner:
            result = components.test_part('desktop', ROOT)
        self.assertEqual(result['status'], 'unavailable')
        self.assertFalse(result['executed'])
        runner.assert_not_called()

    def test_first_failure_stops_the_component(self):
        with patch.object(components, '_execute', return_value={'name': 'first', 'status': 'failed', 'executed': True}) as runner:
            result = components.test_part('core', ROOT)
        self.assertEqual(result['status'], 'failed')
        self.assertEqual(runner.call_count, 1)

    def test_profiles_do_not_contain_deployment_or_shell_commands(self):
        allowed = {'dotnet', 'python', 'msbuild', 'bicep'}
        for steps in components.PROFILES.values():
            for step in steps:
                self.assertIn(step.argv[0], allowed)
                self.assertFalse(set(step.argv) & {'apply', 'deploy', 'create', '--apply', 'workflow', 'login', '-c '})
                self.assertGreater(step.timeout, 0)
                self.assertLessEqual(step.timeout, 1200)


class ComponentExecutionTests(unittest.TestCase):
    def test_missing_executable_is_explicit(self):
        with tempfile.TemporaryDirectory() as temporary, patch.object(components, '_executable', return_value=None):
            result = components._execute(components.PROFILES['usb'][0], ROOT, Path(temporary))
        self.assertEqual(result['status'], 'unavailable')
        self.assertFalse(result['executed'])

    def test_zero_test_dotnet_exit_zero_fails(self):
        process = Mock()
        process.wait.return_value = 0
        with tempfile.TemporaryDirectory() as temporary, \
             patch.object(components, '_executable', return_value='/safe/dotnet'), \
             patch.object(components.subprocess, 'Popen', return_value=process) as launch:
            result = components._execute(components.PROFILES['usb'][0], ROOT, Path(temporary))
        self.assertEqual(result['status'], 'failed')
        self.assertEqual(result['exitCode'], 0)
        self.assertFalse(launch.call_args.kwargs['shell'])
        self.assertEqual(launch.call_args.kwargs['stdin'], subprocess.DEVNULL)
        self.assertEqual(launch.call_args.kwargs['cwd'], ROOT)

    def test_trx_receipt_requires_positive_executed_pass_count_and_no_skips(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'result.trx'
            for total, executed, passed, failed, expected in [(0,0,0,0,False), (1,0,0,0,False),
                   (2,1,1,0,False), (1,1,0,1,False), (2,2,2,0,True)]:
                path.write_text(f'<TestRun><ResultSummary><Counters total="{total}" executed="{executed}" passed="{passed}" failed="{failed}"/></ResultSummary></TestRun>')
                self.assertEqual(components._trx_passed(path), expected)
            path.write_text('<not xml')
            self.assertFalse(components._trx_passed(path))

    def test_python_receipt_rejects_zero_tests_skips_and_errors(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'result.xml'
            for tests, failures, errors, skipped, expected in [(0,0,0,0,False), (1,0,0,0,True),
                                                             (1,1,0,0,False), (1,0,1,0,False), (1,0,0,1,False)]:
                path.write_text(f'<testsuites><testsuite tests="{tests}" failures="{failures}" errors="{errors}" skipped="{skipped}"/></testsuites>')
                self.assertEqual(components._junit_passed(path), expected)

    def test_timeout_reports_cleanup_outcome(self):
        process = Mock()
        process.wait.side_effect = subprocess.TimeoutExpired('fixed-test', 1)
        for cleaned, status in ((True, 'timeout'), (False, 'cleanup-failed')):
            with tempfile.TemporaryDirectory() as temporary, \
                 patch.object(components, '_executable', return_value='/safe/dotnet'), \
                 patch.object(components.subprocess, 'Popen', return_value=process), \
                 patch.object(components, '_stop', return_value=cleaned) as stop:
                result = components._execute(components.PROFILES['usb'][0], ROOT, Path(temporary))
            self.assertEqual(result['status'], status)
            stop.assert_called_once_with(process)

    def test_python_test_profile_executes_with_real_runner(self):
        # A tiny inert process exercises argv, cwd, exit propagation and reaping.
        step = components.Step('runner-contract', ('python', '-c', 'raise SystemExit(7)'), timeout=10)
        with tempfile.TemporaryDirectory() as temporary:
            result = components._execute(step, ROOT, Path(temporary))
        self.assertEqual(result['status'], 'failed')
        self.assertEqual(result['exitCode'], 7)

    def test_unittest_leaf_rejects_zero_tests_and_skips(self):
        for count, ran, skipped, expected in [(0, 0, [], 1), (1, 1, [('test', 'skipped')], 1), (1, 1, [], 0)]:
            suite = Mock()
            suite.countTestCases.return_value = count
            result = Mock(testsRun=ran, skipped=skipped)
            result.wasSuccessful.return_value = True
            with patch('unittest.defaultTestLoader.loadTestsFromName', return_value=suite), \
                 patch('unittest.TextTestRunner') as runner, patch('builtins.print'):
                runner.return_value.run.return_value = result
                self.assertEqual(components._run_unittest('identity-plan'), expected)
            if count == 0:
                runner.assert_not_called()

    def test_unittest_leaf_refuses_unknown_profiles(self):
        with patch('unittest.defaultTestLoader.loadTestsFromName') as load:
            self.assertEqual(components._run_unittest('os.system'), 2)
        load.assert_not_called()

    def test_main_reports_unavailable_as_nonzero(self):
        with patch.object(components, 'test_part', return_value={'status': 'unavailable', 'executed': False}), \
             patch('builtins.print'):
            self.assertNotEqual(components.main(['test', 'desktop']), 0)


if __name__ == '__main__':
    unittest.main()
