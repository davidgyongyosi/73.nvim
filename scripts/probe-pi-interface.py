"""Optional Pi RPC startup probe. No prompt, provider call, or user config.

Usage: python3 scripts/probe-pi-interface.py [path-to-pi]
This is separate from the smoke suite, which needs only Neovim.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

FLAGS = [
    '--mode', 'rpc', '--no-session', '--no-tools', '--no-extensions',
    '--no-mcp', '--no-skills', '--no-prompt-templates', '--no-themes',
    '--no-context-files', '--no-approve', '--offline',
]


def main():
    executable = shutil.which(sys.argv[1] if len(sys.argv) > 1 else 'pi')
    if not executable:
        raise RuntimeError('Pi executable not found')
    with tempfile.TemporaryDirectory(prefix='73-pi-probe-') as temporary:
        root = Path(temporary)
        agent, workspace = root / 'agent', root / 'workspace'
        agent.mkdir()
        workspace.mkdir()
        sentinel = workspace / 'extension-executed'
        # If discovery were enabled, this extension would leave observable evidence.
        extension = "import { writeFileSync } from 'node:fs';\nwriteFileSync(" + json.dumps(str(sentinel)) + ", 'loaded');\nexport default function () {}\n"
        for config in (agent, workspace / '.pi'):
            (config / 'extensions').mkdir(parents=True)
            (config / 'extensions' / 'probe.ts').write_text(extension)
        (workspace / 'unsaved-target.txt').write_text('original\n')
        before = {str(p.relative_to(workspace)): p.read_bytes() for p in workspace.rglob('*') if p.is_file()}
        # Do not inherit provider credentials, session overrides, or Node preload hooks.
        env = {key: os.environ[key] for key in ('PATH', 'HOME', 'TMPDIR', 'SYSTEMROOT') if key in os.environ}
        env.update(PI_CODING_AGENT_DIR=str(agent), PI_OFFLINE='1', PI_TELEMETRY='false')
        version = subprocess.run([executable, '--version'], env=env, cwd=workspace,
                                 capture_output=True, text=True, check=True, timeout=15).stdout.strip()
        commands = [{'id': kind, 'type': kind} for kind in ('get_state', 'get_commands', 'abort')]
        result = subprocess.run([executable, *FLAGS], input=''.join(json.dumps(c) + '\n' for c in commands),
                                cwd=workspace, env=env, capture_output=True, text=True, timeout=30)
        if result.returncode:
            raise RuntimeError('Pi startup failed: ' + result.stderr[-2000:])
        records = [json.loads(line) for line in result.stdout.split('\n') if line.strip()]
        responses = {record.get('id'): record for record in records if record.get('type') == 'response'}
        for command in commands:
            response = responses.get(command['id'])
            assert response and response.get('success') is True, 'Missing/failed response: ' + command['id']
        state = responses['get_state']['data']
        assert state['messageCount'] == 0 and state['isStreaming'] is False
        assert not state.get('sessionFile'), 'Ephemeral session unexpectedly has a session file'
        assert responses['get_commands']['data']['commands'] == [], 'Unexpected discovered commands'
        after = {str(p.relative_to(workspace)): p.read_bytes() for p in workspace.rglob('*') if p.is_file()}
        assert before == after, 'Workspace changed during startup probe'
        assert not sentinel.exists(), 'Extension executed despite disabled discovery'
        print('Pi ' + version + ': RPC state, empty commands, abort, EOF exit, disabled extension discovery, and unchanged workspace verified.')
        print('No prompt was sent. Model output and active-tool enforcement remain untested at runtime.')


if __name__ == '__main__':
    main()
