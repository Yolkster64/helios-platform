#!/usr/bin/env python3
"""List, plan or test six HELIOS parts in this reviewed checkout. Never deploy."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
from typing import NamedTuple
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts/validation'))
import validate_config_schemas as schema_validation

PARTS = ('core', 'desktop', 'gui', 'usb', 'cloud', 'fleet')
GUI_PIECES = ('home', 'aihub', 'fabric', 'usb', 'themes')


class ComponentError(ValueError):
    pass


class Step(NamedTuple):
    name: str
    argv: tuple[str, ...]
    timeout: int = 300
    platform: str = 'any'
    result: str = 'exit-code'


DOTNET = ('dotnet', 'test', 'tests/HELIOS.AIHub.Tests', '-c', 'Release',
          '-m:1', '-nr:false', '-p:UseSharedCompilation=false')
# These are reviewed source commands. Config metadata cannot add arguments,
# replace an executable or supply a working directory.
PROFILES = {
    'core': (
        Step('core-dotnet', DOTNET + ('--filter', 'FullyQualifiedName!~.Fleet.&FullyQualifiedName!~UsbSetup'), 900, result='trx'),
        Step('core-python', ('python', '-m', 'pytest', 'src/ai/python/tests/test_boundary.py',
             'src/ai/python/tests/test_engines.py', 'src/ai/python/tests/test_analysis.py',
             'src/ai/python/tests/test_textwork.py', 'src/ai/python/tests/test_package_init.py', '-q'), result='junit'),
    ),
    'desktop': (
        Step('desktop-contract', ('python', 'scripts/validation/validate_yolkster_cutover.py')),
        Step('desktop-build', ('msbuild', 'src/gui/HELIOS.Shell.sln', '/restore',
                              '/p:Configuration=Release', '/p:Platform=x64', '/m:1', '/nr:false',
                              '/p:UseSharedCompilation=false'), 1200, 'windows'),
    ),
    'gui': (
        Step('gui-contract', ('python', 'scripts/validation/validate_yolkster_cutover.py')),
        Step('gui-native-build', ('msbuild', 'src/gui/HELIOS.Shell.sln', '/restore',
                                 '/p:Configuration=Release', '/p:Platform=x64', '/m:1', '/nr:false',
                                 '/p:UseSharedCompilation=false'), 1200, 'windows'),
    ),
    'usb': (Step('usb-planner', DOTNET + ('--filter', 'FullyQualifiedName~UsbSetup'), 900, result='trx'),),
    'cloud': (
        Step('identity-plan', ('python', 'scripts/bootstrap/components.py', '_unittest', 'identity-plan')),
        Step('oidc-targets', ('python', 'scripts/bootstrap/components.py', '_unittest', 'oidc-targets')),
        Step('bicep-template', ('bicep', 'build', 'infra/main.bicep', '--no-restore'), result='bicep'),
        Step('bicep-parameters', ('bicep', 'build-params', 'infra/main.bicepparam', '--no-restore'), result='bicep'),
    ),
    'fleet': (
        Step('fleet-dotnet', DOTNET + ('--filter', 'FullyQualifiedName~Fleet'), 900, result='trx'),
        Step('fleet-python', ('python', '-m', 'pytest', 'src/ai/python/tests/test_fleet_worker.py',
                             'src/ai/python/tests/test_fleet_learning.py', '-q'), result='junit'),
    ),
}


def _load(root: Path) -> dict:
    root = root.resolve()
    manifest = root / 'config/components.json'
    schema = root / 'config/schemas/components.schema.json'
    if not manifest.is_file() or manifest.stat().st_size > 32768:
        raise ComponentError('Component map is missing or exceeds the size limit.')
    try:
        result = schema_validation.validate_file(manifest, schema, engine='builtin', repo_root=root)
        if not result.valid:
            raise ComponentError('Component map does not match its schema.')
        data = json.loads(manifest.read_text(encoding='utf-8'))
        # Check this immutable code contract too; editing the schema cannot route a
        # different profile to a component or change the set of allowed parts.
        if set(data['parts']) != set(PARTS):
            raise ComponentError('Component map must contain exactly the six supported parts.')
        for name, part in data['parts'].items():
            if part['testProfile'] != name:
                raise ComponentError('Component map test profile differs from the fixed runner.')
            records = [part]
            if name == 'gui':
                if set(part.get('pieces', {})) != set(GUI_PIECES):
                    raise ComponentError('GUI must contain exactly the supported edit pieces.')
                records.extend(part['pieces'].values())
            elif 'pieces' in part:
                raise ComponentError('Only GUI supports piece selectors.')
            for record in records:
                for path in [path for field in ('paths', 'artifacts', 'workflows') for path in record.get(field, [])]:
                    candidate = Path(path)
                    if candidate.is_absolute() or '..' in candidate.parts or not (root / candidate).resolve().is_relative_to(root):
                        raise ComponentError('Component paths must stay inside the repository.')
        return data
    except (OSError, KeyError, TypeError, json.JSONDecodeError, schema_validation.SchemaError) as error:
        raise ComponentError('Component map or schema could not be read safely.') from error


def _name(name: str) -> str:
    if not isinstance(name, str) or name.lower() not in PARTS:
        raise ComponentError('Choose one part: core, desktop, gui, usb, cloud or fleet.')
    return name.lower()


def _piece(name: str, piece: str | None) -> str | None:
    if piece is None:
        return None
    if name != 'gui' or not isinstance(piece, str):
        raise ComponentError('Piece selection is available only for GUI.')
    value = piece.lower()
    if value == 'theme':
        value = 'themes'
    if value not in GUI_PIECES:
        raise ComponentError('Choose a GUI piece: home, aihub, fabric, usb or themes.')
    return value


def list_gui_pieces(root: Path = ROOT) -> dict:
    gui = _load(root)['parts']['gui']
    return {'schemaVersion': 1, 'part': 'gui', 'status': 'planned', 'executed': False,
            'pieces': [{'id': name, **gui['pieces'][name]} for name in GUI_PIECES],
            'testScope': 'The shared native build compiles every GUI view; pieces select edit scope only.'}


def _steps(name: str) -> list[dict]:
    return [{'name': step.name, 'argv': list(step.argv), 'platform': step.platform,
             'timeoutSeconds': step.timeout, 'evidence': step.result} for step in PROFILES[name]]


def list_parts(root: Path = ROOT) -> dict:
    data = _load(root)
    return {'schemaVersion': 1, 'repository': data['repository'], 'sourcePolicy': 'single-repository',
            'status': 'planned', 'executed': False,
            'parts': [{'id': name, **data['parts'][name]} for name in PARTS]}


def plan_part(name: str, root: Path = ROOT, piece: str | None = None) -> dict:
    name = _name(name)
    piece = _piece(name, piece)
    data = _load(root)
    part = data['parts'][name]
    selected = {'id': piece, **part['pieces'][piece]} if piece else None
    edit_paths = selected['paths'] if selected else part['paths']
    missing = sorted({path for path in [*part['paths'], *edit_paths, *part['artifacts'], *part['workflows']]
                      if not (root / path).exists()})
    deployment = {'executed': False, 'automaticApply': False, 'boundary': part['releaseBoundary']}
    if name in ('cloud', 'fleet'):
        deployment.update(workflow='.github/workflows/helios-deploy.yml', environment='azure-dev',
                          ref='refs/heads/main', event='workflow_dispatch',
                          inputs={'what_if': True, 'deploy_confirmed': False},
                          authority='Protected environment approval and current repository instructions; this helper never dispatches.')
    return {'schemaVersion': 1, 'repository': data['repository'], 'part': name,
            'status': 'incomplete' if missing else 'planned', 'executed': False,
            'details': part, 'selectedPiece': selected, 'editPaths': edit_paths,
            'linkedParts': selected['linkedParts'] if selected else part['dependsOn'],
            'testScope': ('The shared native build compiles every GUI view; piece selection limits edit scope only.'
                          if name == 'gui' else 'Fixed focused checks for this part; shared dependencies may also compile.'),
            'missingPaths': missing, 'tests': _steps(name), 'deployment': deployment,
            'note': 'A targeted check does not replace required repository CI, prove live service access or authorize a release.'}


def _executable(name: str) -> str | None:
    candidate = sys.executable if name == 'python' else shutil.which(name)
    # Executing a Windows .cmd/.bat wrapper invokes shell parsing implicitly.
    if candidate and Path(candidate).suffix.lower() in ('.cmd', '.bat'):
        candidate = shutil.which(name + '.exe')
    return candidate


def _stop(child: subprocess.Popen) -> bool:
    stopped = False
    try:
        if os.name == 'nt':
            taskkill = _executable('taskkill.exe')
            if taskkill:
                stopped = subprocess.run([taskkill, '/PID', str(child.pid), '/T', '/F'],
                    shell=False, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL, timeout=15, check=False).returncode == 0
        else:
            os.killpg(child.pid, signal.SIGKILL)
            stopped = True
    except ProcessLookupError:
        stopped = True
    except (OSError, subprocess.TimeoutExpired):
        pass
    finally:
        try:
            child.kill()
            child.wait(timeout=5)
        except (OSError, subprocess.TimeoutExpired):
            stopped = False
    return stopped


def _trx_passed(path: Path) -> bool:
    try:
        if not path.is_file() or path.stat().st_size > 32 * 1024 * 1024:
            return False
        counters = ET.parse(path).find('.//{*}Counters')
        return counters is not None and int(counters.attrib['total']) > 0 and int(counters.attrib['executed']) > 0 \
            and int(counters.attrib['failed']) == 0 and int(counters.attrib['passed']) == int(counters.attrib['executed']) == int(counters.attrib['total'])
    except (OSError, ET.ParseError, ValueError, KeyError):
        return False


def _junit_passed(path: Path) -> bool:
    try:
        if not path.is_file() or path.stat().st_size > 32 * 1024 * 1024:
            return False
        document = ET.parse(path).getroot()
        suites = list(document.iter('testsuite'))
        return bool(suites) and sum(int(item.attrib['tests']) for item in suites) > 0 and all(
            int(item.attrib.get(key, '0')) == 0 for item in suites for key in ('failures', 'errors', 'skipped'))
    except (OSError, ET.ParseError, ValueError, KeyError):
        return False


def _execute(step: Step, root: Path, result_dir: Path) -> dict:
    executable = _executable(step.argv[0])
    if not executable:
        return {'name': step.name, 'status': 'unavailable', 'executed': False, 'reason': 'Missing tool: ' + step.argv[0]}
    argv = [executable, *step.argv[1:]]
    if step.result == 'trx':
        argv += ['--logger', 'trx;LogFileName=component.trx', '--results-directory', str(result_dir)]
    elif step.result == 'junit':
        argv += ['--junitxml', str(result_dir / 'component.xml')]
    elif step.result == 'bicep':
        argv += ['--outfile', str(result_dir / 'compiled.json')]
    env = {**os.environ, 'CI': 'true', 'GIT_TERMINAL_PROMPT': '0', 'GH_PROMPT_DISABLED': '1',
           'DOTNET_CLI_TELEMETRY_OPTOUT': '1', 'DOTNET_SKIP_FIRST_TIME_EXPERIENCE': '1',
           'NUGET_EXE_NO_PROMPT': 'true', 'NUGET_CREDENTIALPROVIDER_NONINTERACTIVE': 'true',
           'POWERSHELL_TELEMETRY_OPTOUT': '1', 'POWERSHELL_UPDATECHECK': 'Off',
           'PYTHONPATH': str(root / 'src/ai/python')}
    options = {'cwd': root, 'env': env, 'shell': False, 'stdin': subprocess.DEVNULL,
               'stdout': sys.stderr, 'stderr': sys.stderr}
    if os.name == 'nt':
        options['creationflags'] = subprocess.CREATE_NEW_PROCESS_GROUP
    else:
        options['start_new_session'] = True
    try:
        child = subprocess.Popen(argv, **options)
        try:
            code = child.wait(timeout=step.timeout)
        except subprocess.TimeoutExpired:
            status = 'timeout' if _stop(child) else 'cleanup-failed'
            return {'name': step.name, 'status': status, 'executed': True}
        except KeyboardInterrupt:
            _stop(child)
            raise
    except OSError:
        return {'name': step.name, 'status': 'unavailable', 'executed': False, 'reason': 'Test process could not start.'}
    passed = code == 0 and (step.result != 'trx' or _trx_passed(result_dir / 'component.trx')) \
        and (step.result != 'junit' or _junit_passed(result_dir / 'component.xml'))
    return {'name': step.name, 'status': 'passed' if passed else 'failed', 'executed': True,
            'exitCode': code, 'evidence': step.result,
            **({'reason': 'No successful nonempty test receipt.'} if code == 0 and not passed else {})}


def test_part(name: str, root: Path = ROOT, piece: str | None = None) -> dict:
    # API callers may inspect another source snapshot; execution is confined to
    # this helper's reviewed repository. There is intentionally no --repo CLI.
    if root.resolve() != ROOT:
        raise ComponentError('Tests run only from this helper\'s reviewed repository.')
    plan = plan_part(name, root, piece=piece)
    name = plan['part']
    if plan['missingPaths']:
        return {**plan, 'status': 'unavailable', 'results': [], 'reason': 'Required component files are missing.'}
    if any(step.platform == 'windows' for step in PROFILES[name]) and os.name != 'nt':
        return {**plan, 'status': 'unavailable', 'results': [], 'reason': 'Native Desktop/GUI validation requires Windows and Visual Studio MSBuild.'}
    results = []
    for step in PROFILES[name]:
        with tempfile.TemporaryDirectory(prefix='helios-component-') as temporary:
            result = _execute(step, root, Path(temporary))
        results.append(result)
        if result['status'] != 'passed':
            break
    return {**plan, 'status': results[-1]['status'] if results else 'unavailable',
            'executed': any(item['executed'] for item in results), 'results': results}


UNITTEST_MODULES = {
    'identity-plan': 'scripts.bootstrap.tests.test_identity_plan',
    'oidc-targets': 'scripts.bootstrap.tests.test_azure_oidc_target',
}


def _run_unittest(profile: str) -> int:
    # A fixed leaf process for unittest, whose default exit code otherwise allows
    # zero collected tests. Module selection never comes from the manifest.
    import unittest
    if profile not in UNITTEST_MODULES:
        return 2
    sys.path.insert(0, str(ROOT))
    suite = unittest.defaultTestLoader.loadTestsFromName(UNITTEST_MODULES[profile])
    if suite.countTestCases() == 0:
        print('No tests collected for the component.', file=sys.stderr)
        return 1
    result = unittest.TextTestRunner(stream=sys.stderr, verbosity=2).run(suite)
    return 0 if result.testsRun > 0 and result.wasSuccessful() and not result.skipped else 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action')
    sub.add_parser('list')
    for action in ('plan', 'test'):
        command = sub.add_parser(action)
        command.add_argument('name', choices=PARTS, type=str.lower)
        command.add_argument('--piece', choices=(*GUI_PIECES, 'theme'), type=str.lower)
    sub.add_parser('_unittest', help=argparse.SUPPRESS).add_argument('profile', choices=tuple(UNITTEST_MODULES))
    args = parser.parse_args(argv)
    if args.action == '_unittest':
        return _run_unittest(args.profile)
    try:
        result = list_parts() if args.action in (None, 'list') else \
            plan_part(args.name, piece=args.piece) if args.action == 'plan' else test_part(args.name, piece=args.piece)
        print(json.dumps(result, indent=2))
        return 0 if result['status'] in ('planned', 'passed') else 2
    except ComponentError as error:
        print(json.dumps({'status': 'invalid', 'executed': False, 'error': str(error)}))
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
