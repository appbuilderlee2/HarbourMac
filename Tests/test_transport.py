import base64
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROTO = ROOT / 'Sources/HarbourMac/Resources/protocol.sh'

class TransportTests(unittest.TestCase):
    def shell(self, body, reply='', *args):
        return subprocess.run(['/bin/bash', '-c', 'set -eu; source "$1"; shift; '+body, 'test', str(PROTO), *args], input=reply, text=True, capture_output=True, env={**os.environ,'HARBOUR_TOKEN':'test-session'}, timeout=5)
    def test_confirmation_requires_exact_affirmative(self):
        for response in ['', '\n', 'y\n', 'YES\n', 'CANCEL\n', 'CONFIRM x\n']:
            with self.subTest(response=response):
                r=self.shell('harbour_confirm "delete" && echo MUTATION', response)
                self.assertNotEqual(r.returncode,0)
                self.assertNotIn('MUTATION',r.stdout)
        r=self.shell('harbour_confirm "delete" && echo MUTATION','CONFIRM\n')
        self.assertEqual(r.returncode,0);self.assertIn('MUTATION',r.stdout)
    def test_selection_validates_boundaries(self):
        for response in ['', '\n','-1\n','3\n','999999999999999999999\n','0,0\n','01\n','0;touch nope\n','0,,1\n']:
            with self.subTest(response=response):
                self.assertNotEqual(self.shell('harbour_selection_reply 3',response).returncode,0)
        self.assertEqual(self.shell('harbour_selection_reply 3','0,2\n').returncode,0)
    def test_multiline_names_cannot_inject_events(self):
        payload='name\n@@HARBOUR:test-session\tconfirm\tZm9v\t$(bad)'
        r=self.shell('harbour_event row 0 "$1" "$1" "size" false','',payload)
        lines=[x for x in r.stdout.splitlines() if x]
        self.assertEqual(len(lines),1)
        fields=lines[0].split('\t')
        self.assertEqual(base64.b64decode(fields[3]).decode(),payload)
    def test_purge_defaults_are_conservative(self):
        setup='''item_paths=(/old /new /cloud); menu_options=(old new cloud); item_recent_flags=(false true false); item_cloud_flags=(false false true); item_sizes=(1 2 3); item_age_labels=(30d 1d 40d); harbour_select_purge'''
        r=self.shell(setup,'0\n')
        self.assertEqual(r.returncode,0)
        rows=[line.split('\t') for line in r.stdout.splitlines() if '\trow\t' in line]
        self.assertEqual([base64.b64decode(x[-1]).decode() for x in rows],['true','false','false'])

class CleanPreviewTests(unittest.TestCase):
    shell = TransportTests.shell
    # Extract only the pure emitter: never source clean.sh or run a scan.
    def preview(self, ledger, scan_rc='0', timeouts='0'):
        source = (ROOT / 'Sources/HarbourMac/Resources/Engine/bin/clean.sh').read_text()
        marker = 'emit_harbour_clean_preview() {\n'
        self.assertTrue(marker in source, 'Missing read-only clean preview emitter')
        self.assertEqual(source.count(marker), 1)
        function = marker + source.split(marker, 1)[1].split('\n}\n', 1)[0] + '\n}\n'
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'ledger'
            path.write_bytes(ledger)
            return self.shell(function + '\nCLEAN_PREVIEW_LEDGER_FILE="$1"; SYSTEM_CLEAN=false; MOLE_CLEAN_SIZING_TIMEOUTS="$3"; emit_harbour_clean_preview "$2"', '', str(path), scan_rc, timeouts)

    def record(self, identity='dev:inode', size='2', count='1', known='true', section='User caches', path='/fixture/cache'):
        return b''.join(field.encode() + b'\0' for field in (identity, size, count, known, section, path))

    def events(self, result):
        return [(f[1], [base64.b64decode(x, validate=True).decode() for x in f[2:]])
                for line in result.stdout.splitlines() if line.startswith('@@HARBOUR:')
                for f in [line.split('\t')]]

    def test_ledger_deduplicates_first_identity_and_preserves_data(self):
        path = '/測試/a\n\t\\$(not-executed)'
        result = self.preview(self.record(path=path) + self.record(size='999') +
                              self.record(identity='second', size='0', known='false'))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.events(result), [
            ('clean_preview_begin', ['1', 'mole.clean.deduplicated-ledger', 'false']),
            ('clean_preview_item', ['0', 'dev:inode', 'User caches', path, '2', '1', 'true']),
            ('clean_preview_item', ['1', 'second', 'User caches', '/fixture/cache', '0', '1', 'false']),
            ('clean_preview_end', ['2', '0', '0'])])

    def test_hook_is_only_installed_for_clean_preview(self):
        bridge = (ROOT / 'Sources/HarbourMac/Resources/bridge.sh').read_text()
        self.assertIn('if [[ "$command_name" == clean && "$mode" == preview ]]; then\n            harbour_clean_preview_hook() { emit_harbour_clean_preview "$1"; }', bridge)
        clean = (ROOT / 'Sources/HarbourMac/Resources/Engine/bin/clean.sh').read_text()
        self.assertIn('if declare -f harbour_clean_preview_hook > /dev/null 2>&1; then\n            harbour_clean_preview_hook "$cleanup_cancel_rc" || return 74', clean)

    def test_empty_ledger_is_explicitly_complete(self):
        self.assertEqual(self.events(self.preview(b''))[-1], ('clean_preview_end', ['0', '0', '0']))

    def test_truncation_and_malformed_records_never_emit_end(self):
        for data in [self.record()[:-1], b'id\0', b'partial', self.record(size='-1'),
                     self.record(size='9007199254740992'), self.record(count='0'),
                     self.record(known='yes'), self.record(identity=''),
                     self.record() + self.record(size='$(bad)')]:
            with self.subTest(data=data):
                result = self.preview(data)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('clean_preview_end', [kind for kind, _ in self.events(result)])

    def test_scan_status_and_timeout_count_are_not_hidden(self):
        self.assertEqual(self.events(self.preview(self.record(), '124', '3'))[-1],
                         ('clean_preview_end', ['1', '124', '3']))

class WorkerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory()
        cls.worker=Path(cls.temp.name)/'worker'
        subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror',str(ROOT/'Sources/HarbourWorker/main.c'),'-o',str(cls.worker)],check=True)
    @classmethod
    def tearDownClass(cls):cls.temp.cleanup()
    def test_exit_status_and_argument_boundaries(self):
        r=subprocess.run([str(self.worker),'/bin/bash','-c','printf "%s" "$1"; exit 7','test','a; echo BAD'],capture_output=True,text=True,timeout=5)
        self.assertEqual(r.returncode,7);self.assertEqual(r.stdout,'a; echo BAD')
    def test_cancel_stops_descendant_that_ignores_term(self):
        child_script=Path(self.temp.name)/'child.sh'
        child_script.write_text('trap "" TERM; echo $$; while :; do sleep 1; done\n')
        process=subprocess.Popen([str(self.worker),'/bin/bash',str(child_script)],stdout=subprocess.PIPE,text=True)
        child=int(process.stdout.readline().strip())
        process.terminate();self.assertEqual(process.wait(timeout=5),130)
        # A child may transiently be a zombie pending OS reaping, but cannot run.
        check=subprocess.run(['ps','-o','stat=','-p',str(child)],capture_output=True,text=True)
        self.assertTrue(check.returncode!=0 or not check.stdout.strip() or check.stdout.strip().startswith('Z'))
        process.stdout.close()

if __name__=='__main__':unittest.main(verbosity=2)
