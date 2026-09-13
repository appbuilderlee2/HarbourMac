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
    def test_normal_exit_stops_background_descendant(self):
        result = subprocess.run([str(self.worker), '/bin/bash', '-c',
            'sleep 30 & echo $!; exit 0'], capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0)
        child = int(result.stdout.strip())
        check = subprocess.run(['ps', '-o', 'stat=', '-p', str(child)], capture_output=True, text=True)
        self.assertTrue(check.returncode != 0 or not check.stdout.strip() or check.stdout.strip().startswith('Z'))
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
