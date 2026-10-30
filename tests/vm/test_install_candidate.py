"""Real APT same-version archive selection, inside an explicit test container."""
import hashlib
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


@unittest.skipUnless(os.environ.get('NORVI_TEST_PACKAGE_INSTALL') == '1'
                     and os.geteuid() == 0 and Path('/.dockerenv').exists(),
                     'requires an explicitly selected disposable root container')
class CandidateInstallTest(unittest.TestCase):
    def setUp(self):
        current = subprocess.run(['dpkg-query', '-W', '-f=${db:Status-Status}', 'norvi-os'],
                                 capture_output=True, text=True)
        self.assertNotEqual(current.stdout, 'installed', 'fixture requires a container without NorviOS')
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.work.chmod(0o755)
        self.repo = self.work / 'repo'
        self.repo.mkdir()
        sources = self.work / 'sources'
        sources.mkdir()
        (sources / 'fixture.list').write_text(f'deb [trusted=yes] file:{self.repo} ./\n')
        config = self.work / 'apt.conf'
        config.write_text(f'Dir::Etc::sourcelist "/dev/null";\nDir::Etc::sourceparts "{sources}";\n'
                          f'Dir::State::lists "{self.work}/lists";\nDir::Cache::archives "{self.work}/archives";\n')
        (self.work / 'lists').mkdir()
        (self.work / 'archives').mkdir()
        self.env = {**os.environ, 'APT_CONFIG': str(config), 'DEBIAN_FRONTEND': 'noninteractive'}
        self.addCleanup(self.purge)
        archive = self.make_deb('1.4.1', 'archive', self.repo / 'archive.deb')
        fields = self.command('dpkg-deb', '-f', str(archive)).stdout
        data = archive.read_bytes()
        (self.repo / 'Packages').write_text(fields + f'Filename: archive.deb\nSize: {len(data)}\n'
                                            f'SHA256: {hashlib.sha256(data).hexdigest()}\n\n')
        (self.repo / 'Release').write_text('Origin: Synthetic\nLabel: Synthetic\nSuite: fixture-candidate\n'
                                         'Codename: fixture-candidate\nNotAutomatic: yes\nButAutomaticUpgrades: yes\n')
        self.command('apt-get', 'update')
        self.command('apt-get', 'install', '-y', '-t', 'fixture-candidate', 'norvi-os')

    def command(self, *args, check=True):
        result = subprocess.run(args, env=self.env, capture_output=True, text=True, timeout=30)
        if check:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def purge(self):
        self.command('dpkg', '--purge', 'norvi-os')

    def make_deb(self, version, payload, destination):
        package = self.work / ('package-' + version)
        (package / 'DEBIAN').mkdir(parents=True, exist_ok=True)
        (package / 'DEBIAN/control').write_text(f'Package: norvi-os\nVersion: {version}\nArchitecture: all\n'
                                               'Maintainer: Example <example@example.invalid>\n'
                                               'Description: Synthetic candidate selection control\n')
        relative = 'usr/share/norvi-candidate-selection/data'
        target = package / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(payload)
        digest = hashlib.md5(target.read_bytes(), usedforsecurity=False).hexdigest()
        (package / 'DEBIAN/md5sums').write_text(f'{digest}  {relative}\n')
        self.command('dpkg-deb', '--build', str(package), str(destination))
        return destination

    def install(self, version):
        candidate = self.make_deb(version, 'producer', self.work / 'candidate.deb')
        return self.command('bash', str(Path(__file__).with_name('install-candidate.sh')),
                            str(candidate), check=False)

    def test_same_version_from_archive_installs_producer_bytes(self):
        result = self.install('1.4.1')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(Path('/usr/share/norvi-candidate-selection/data').read_text(), 'producer')

    def test_newer_version_is_accepted(self):
        result = self.install('1.4.2')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.command('dpkg-query', '-W', '-f=${Version}', 'norvi-os').stdout, '1.4.2')

    def test_reinstall_after_purge_uses_producer_bytes(self):
        self.command('dpkg', '--purge', 'norvi-os')
        result = self.install('1.4.1')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(Path('/usr/share/norvi-candidate-selection/data').read_text(), 'producer')

    def test_older_version_is_rejected_without_changing_installed_bytes(self):
        result = self.install('1.4.0')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Refusing older candidate', result.stderr)
        self.assertEqual(self.command('dpkg-query', '-W', '-f=${Version}', 'norvi-os').stdout, '1.4.1')
        self.assertEqual(Path('/usr/share/norvi-candidate-selection/data').read_text(), 'archive')
