"""Exercise source/ABI receipts and artifact confinement without a native load."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'scripts/build-native.sh'
ABI = 'fixture_aq_0.15_hu_0.14_hg_0.5_hc_0.1_hlg_0.6'

class OrbitNativeBuildTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='orbit-native-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.drive = self.base / 'drive'
        (self.drive / 'Artifacts').mkdir(parents=True)
        self.bin = self.base / 'bin'; self.bin.mkdir()
        self.env = dict(os.environ, PATH=str(self.bin)+os.pathsep+os.environ['PATH'],
                        ORBIT_ARTIFACT_DRIVE=str(self.drive), CXX=str(self.bin/'compiler'),
                        MOCK_DRIVE=str(self.drive), MOCK_ABI=ABI)
        self.env.pop('ORBIT_ARTIFACT_ROOT', None)
        self.write('hyprctl', '''#!/bin/sh
printf '{"abiHash":"%s"}\\n' "$MOCK_ABI"
''')
        self.write('pkg-config', '#!/bin/sh\nexit 0\n')
        self.write('findmnt', '''#!/bin/sh
printf '%s %s %s\\n' "${MOCK_MOUNT:-$MOCK_DRIVE}" "${MOCK_FS:-ext4}" "${MOCK_OPTIONS:-rw,relatime}"
''')
        self.write('compiler', """#!/usr/bin/python3
import sys
from pathlib import Path
if '-E' in sys.argv:
 for name,value in [('GIT_COMMIT_HASH','fixture'),('AQUAMARINE_VERSION','0.15.0'),('HYPRUTILS_VERSION','0.14.1'),('HYPRGRAPHICS_VERSION','0.5.1'),('HYPRCURSOR_VERSION','0.1.13'),('HYPRLANG_VERSION','0.6.8')]:
  print('#define',name,'"'+value+'"')
else:
 Path(sys.argv[sys.argv.index('-o')+1]).write_bytes(b'fixture binary')
""")
    def write(self, name, text):
        p=self.bin/name; p.write_text(text); p.chmod(0o755)
    def run_build(self, *args):
        return subprocess.run(['bash',str(BUILD),*args],env=self.env,text=True,capture_output=True)
    def test_reuse_verified_build_and_reject_corruption(self):
        self.assertNotEqual(self.run_build('--locate').returncode,0)
        built=self.run_build(); self.assertEqual(built.returncode,0,built.stderr)
        binary=Path(built.stdout.strip())
        self.assertTrue(binary.is_relative_to(self.drive/'Artifacts/orbit-native/build'))
        receipt=json.loads(binary.with_name('build.json').read_text())
        self.assertEqual(receipt['abi'],ABI)
        self.assertEqual(self.run_build('--locate').stdout,built.stdout)
        binary.write_bytes(b'corrupt')
        self.assertNotEqual(self.run_build('--locate').returncode,0)
        repaired=self.run_build(); self.assertEqual(repaired.returncode,0,repaired.stderr)
        self.assertEqual(binary.read_bytes(),b'fixture binary')
        self.assertFalse(list(binary.parent.glob('tmp.*')))
    def test_missing_readonly_autofs_and_wrong_mount_refuse(self):
        for field,value in [('MOCK_OPTIONS','ro'),('MOCK_FS','autofs'),('MOCK_MOUNT','/')]:
            with self.subTest(field=field):
                self.env[field]=value
                self.assertNotEqual(self.run_build().returncode,0)
                self.assertFalse((self.drive/'Artifacts/orbit-native').exists())
                del self.env[field]
        self.env['ORBIT_ARTIFACT_DRIVE']=str(self.base/'missing')
        self.assertNotEqual(self.run_build().returncode,0)
    def test_escaped_artifact_root_and_symlink_build_refuse(self):
        self.env['ORBIT_ARTIFACT_ROOT']=str(self.base/'escape')
        self.assertNotEqual(self.run_build().returncode,0)
        self.assertFalse((self.base/'escape').exists())
        del self.env['ORBIT_ARTIFACT_ROOT']
        root=self.drive/'Artifacts/orbit-native'; root.mkdir()
        outside=self.base/'outside'; outside.mkdir()
        (root/'build').symlink_to(outside,target_is_directory=True)
        self.assertNotEqual(self.run_build().returncode,0)
        self.assertFalse(list(outside.iterdir()))
    def test_header_abi_mismatch_refuses_before_build(self):
        self.env['MOCK_ABI']='wrong'
        result=self.run_build()
        self.assertNotEqual(result.returncode,0)
        self.assertIn('ABI verification failed',result.stderr)
        self.assertFalse((self.drive/'Artifacts/orbit-native').exists())
    def test_output_symlinks_and_low_space_refuse(self):
        built=self.run_build(); self.assertEqual(built.returncode,0,built.stderr)
        binary=Path(built.stdout.strip())
        binary.unlink()
        outside=self.base/'outside'; outside.write_bytes(b'preserve')
        binary.symlink_to(outside)
        self.assertNotEqual(self.run_build().returncode,0)
        self.assertEqual(outside.read_bytes(),b'preserve')
        binary.unlink()
        self.write('df', '#!/bin/sh\nprintf "Avail\\n1000\\n"\n')
        result=self.run_build()
        self.assertNotEqual(result.returncode,0)
        self.assertIn('256 MB',result.stderr)
        self.assertFalse(binary.exists())

if __name__ == '__main__': unittest.main()
