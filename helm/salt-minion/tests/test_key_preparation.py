"""Run as non-root: python3 -m unittest discover -s helm/salt-minion/tests -p 'test_*.py'.

Requires Helm and PyYAML. Exercises the rendered shell script with temporary
paths; Kubernetes Secret projection and fsGroup behavior require cluster tests.
"""

import base64
import os
from pathlib import Path
import secrets
import shlex
import stat
import subprocess
import tempfile
import unittest

import yaml


class KeyPreparationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if os.geteuid() == 0:
            raise RuntimeError("Run these tests as a non-root user")
        chart = Path(__file__).resolve().parents[1]
        rendered = subprocess.run(
            ["helm", "template", "test", str(chart), "--show-only",
             "templates/deployment.yaml", "--set", "agent.minion.keySecretName=test-keys"],
            check=True, capture_output=True, text=True,
        )
        deployment = yaml.safe_load(rendered.stdout)
        init = next(container for container in
                    deployment["spec"]["template"]["spec"]["initContainers"]
                    if container["name"] == "prepare-minion-keys")
        cls.command = init["command"]

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        self.source = root / "source"
        self.source.mkdir()
        self.pki = root / "pki"
        self.pki.mkdir()
        self.destination = self.pki / "minion"
        self.keys = {"minion.pem": secrets.token_bytes(64),
                     "minion.pub": secrets.token_bytes(64)}

    def write_source(self, encoded):
        for name, content in self.keys.items():
            if encoded:
                name = {"minion.pem": "private-key-b64",
                        "minion.pub": "public-key-b64"}[name]
                content = base64.b64encode(content)
            path = self.source / name
            path.write_bytes(content)
            path.chmod(0o440)

    def prepare(self):
        script = self.command[-1].replace(
            "/var/run/salt-minion-keys", shlex.quote(str(self.source))
        ).replace("/pki", shlex.quote(str(self.pki)))
        return subprocess.run(
            [*self.command[:-1], script], capture_output=True, text=True,
        )

    def assert_prepared(self):
        self.assertEqual(stat.S_IMODE(self.destination.stat().st_mode), 0o700)
        for name, content in self.keys.items():
            path = self.destination / name
            self.assertEqual(path.read_bytes(), content)
            self.assertEqual(path.stat().st_uid, os.geteuid())
            self.assertEqual(stat.S_IMODE(path.stat().st_mode),
                             0o400 if name == "minion.pem" else 0o644)
        self.assertEqual(list(self.destination.glob(".keys.*")), [])

    def test_raw_keys(self):
        self.write_source(encoded=False)
        result = self.prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_prepared()

    def test_encoded_keys(self):
        self.write_source(encoded=True)
        result = self.prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_prepared()

    def test_retry_replaces_read_only_keys_from_secret(self):
        for encoded in (False, True):
            with self.subTest(encoded=encoded):
                for _ in range(2):
                    for path in self.source.iterdir():
                        path.unlink()
                    self.keys = {name: secrets.token_bytes(64) for name in self.keys}
                    self.write_source(encoded)
                    result = self.prepare()
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assert_prepared()

    def test_incomplete_input_preserves_existing_pair(self):
        self.write_source(encoded=False)
        result = self.prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        for encoded in (False, True):
            for missing in ("minion.pem", "minion.pub"):
                with self.subTest(encoded=encoded, missing=missing):
                    for path in self.source.iterdir():
                        path.unlink()
                    self.write_source(encoded)
                    name = ({"minion.pem": "private-key-b64",
                             "minion.pub": "public-key-b64"}[missing]
                            if encoded else missing)
                    (self.source / name).unlink()
                    self.assertNotEqual(self.prepare().returncode, 0)
                    self.assert_prepared()


if __name__ == "__main__":
    unittest.main()
