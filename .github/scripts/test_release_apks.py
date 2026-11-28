from email.message import Message
import hashlib
from importlib.util import module_from_spec, spec_from_file_location
from io import BytesIO
import json
import os
from pathlib import Path
from subprocess import CompletedProcess
from tempfile import TemporaryDirectory
from unittest import TestCase
from unittest.mock import patch


spec = spec_from_file_location("release_apks", Path(__file__).with_name("release-apks.py"))
release_apks = module_from_spec(spec)
spec.loader.exec_module(release_apks)


def result(args, data=None, error=""):
    return CompletedProcess(args, bool(error), json.dumps(data), error)


class R2:
    def __init__(self):
        self.objects = {}
        self.fail_key = None
        self.concurrent_key = None
        self.verifications = []
        self.writes = []

    def run(self, *args):
        key = args[args.index("--key") + 1]
        if args[:3] == ("aws", "s3api", "put-object"):
            assert args[args.index("--if-none-match") + 1] == "*"
            body = Path(args[args.index("--body") + 1]).read_bytes()
            mime = args[args.index("--content-type") + 1]
            disposition = args[args.index("--content-disposition") + 1]
            if key == self.concurrent_key:
                self.objects[key] = body, mime, disposition
            if key in self.objects:
                return result(args, error="An error occurred (PreconditionFailed) when calling the PutObject operation")
            self.objects[key] = body, mime, disposition
            self.writes.append(key)
            if key == self.fail_key:
                return result(args, error="connection lost after the commit")
        else:
            assert args[:3] == ("aws", "s3api", "get-object")
            if key not in self.objects:
                return result(args, error="An error occurred (NoSuchKey) when calling the GetObject operation")
            body, mime, disposition = self.objects[key]
            Path(args[-1]).write_bytes(body)
            return result(args, {"ContentLength": len(body), "ContentType": mime, "ContentDisposition": disposition})
        return result(args)

    def verify(self, download):
        def request(url, *, timeout):
            key = url.removeprefix("https://download.neuq.one/")
            body, mime, disposition = self.objects[key]
            response = BytesIO(body)
            response.status = 200
            response.headers = Message()
            response.headers["Content-Type"] = mime
            response.headers["Content-Disposition"] = disposition
            response.headers["Content-Length"] = str(len(body))
            return response

        release_apks.verify_public_download(download, request)
        self.verifications.append(download["filename"])


class GitHub:
    def __init__(self, tag):
        self.tag = tag
        self.release = None
        self.assets = {}
        self.fail_upload = False
        self.fail_publish = False
        self.uploads = []
        self.deletions = []
        self.make_latest = None
        self.creations = 0

    def run(self, *args):
        if args[:4] == ("gh", "api", "--paginate", "--slurp"):
            if args[-1].endswith("/assets?per_page=100"):
                return result(args, [list(self.assets.values())])
            return result(args, [[self.release] if self.release else []])
        if args[:3] == ("gh", "release", "create"):
            assert {"--draft", "--verify-tag", "--generate-notes"}.issubset(args)
            self.creations += 1
            self.release = {"id": 1, "tag_name": self.tag, "draft": True, "prerelease": "--prerelease" in args}
        elif args[:3] == ("gh", "release", "upload"):
            path = Path(args[4])
            assert self.release["draft"] and path.name not in self.assets
            data = path.read_bytes()
            asset = {"id": len(self.assets) + 2, "name": path.name, "size": len(data), "state": "uploaded",
                     "digest": "sha256:" + hashlib.sha256(data).hexdigest()}
            if self.fail_upload and len(self.assets) == 1:
                self.assets[path.name] = {**asset, "size": 0, "state": "starter", "digest": None}
                return result(args, error="HTTP 502")
            self.assets[path.name] = asset
            self.uploads.append(path.name)
        elif args[:4] == ("gh", "api", "--method", "DELETE"):
            name, = [name for name, asset in self.assets.items() if str(asset["id"]) == args[-1].rsplit("/", 1)[-1]]
            assert self.release["draft"] and self.assets[name]["state"] == "starter"
            self.deletions.append(name)
            del self.assets[name]
        else:
            assert args[:4] == ("gh", "api", "--method", "PATCH") and len(self.assets) == 4
            self.release["draft"] = False
            self.make_latest = args[-1]
            if self.fail_publish:
                return result(args, error="HTTP 502")
            return result(args, self.release)
        return result(args)


class ReleaseTests(TestCase):
    def setUp(self):
        temp = TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.directory = Path(temp.name)
        self.tag = "v1.2.3"
        for abi in release_apks.ABIS:
            (self.directory / f"neuq-one-{self.tag}-{abi}.apk").write_bytes(abi.encode())
        self.metadata = release_apks.release_metadata(self.tag, self.directory)

    def upload_r2(self, r2):
        release_apks.upload_r2(self.tag, self.directory, self.metadata, "test-bucket", r2.run, r2.verify)

    def github(self, channel):
        (self.directory / release_apks.METADATA).write_bytes(release_apks.metadata_bytes(self.metadata))
        github = GitHub(self.tag)
        return github, release_apks.GitHubRelease(self.tag, channel, self.metadata, github.run)

    def test_all_abis_and_safe_rerun(self):
        r2 = R2()
        self.upload_r2(r2)
        names = [download["filename"] for download in self.metadata["downloads"]]
        self.assertEqual(r2.verifications, names)
        self.assertEqual(r2.writes, [f"releases/{self.tag}/{name}" for name in names])
        self.upload_r2(r2)
        self.assertEqual(r2.verifications, names * 2)
        self.assertEqual(len(r2.writes), 3)

    def test_upload_failure_after_commit_can_retry(self):
        r2 = R2()
        r2.fail_key = f"releases/{self.tag}/neuq-one-{self.tag}-armeabi-v7a.apk"
        with self.assertRaisesRegex(release_apks.ReleaseError, "R2 上传失败"):
            self.upload_r2(r2)
        self.assertEqual(len(r2.writes), 2)
        self.upload_r2(r2)
        self.assertEqual(len(r2.writes), 3)

    def test_r2_failure_never_creates_the_metadata_required_for_publication(self):
        env = {
            "GITHUB_REF_NAME": self.tag,
            "UPDATE_CHANNEL": "beta",
            "R2_BUCKET": "test-bucket",
            "R2_PUBLIC_URL": release_apks.PUBLIC_ORIGIN,
            "AWS_ENDPOINT_URL_S3": "https://" + "0" * 32 + ".r2.cloudflarestorage.com",
            "AWS_ACCESS_KEY_ID": "test-key",
            "AWS_SECRET_ACCESS_KEY": "test-secret",
        }
        with (patch.dict(os.environ, env), patch.object(release_apks, "Path", return_value=self.directory),
              patch.object(release_apks, "upload_r2", side_effect=release_apks.ReleaseError("R2 上传失败"))):
            with self.assertRaisesRegex(release_apks.ReleaseError, "R2 上传失败"):
                release_apks.main("upload-r2")
            self.assertFalse((self.directory / release_apks.METADATA).exists())
            with self.assertRaises(FileNotFoundError):
                release_apks.main("publish-github")

    def test_checks_bytes_after_a_concurrent_conditional_write(self):
        r2 = R2()
        r2.concurrent_key = f"releases/{self.tag}/neuq-one-{self.tag}-arm64-v8a.apk"
        self.upload_r2(r2)
        self.assertNotIn(r2.concurrent_key, r2.writes)
        self.assertEqual(len(r2.verifications), 3)

    def test_different_bytes_at_same_r2_key_are_never_replaced(self):
        r2 = R2()
        name = f"neuq-one-{self.tag}-arm64-v8a.apk"
        key = f"releases/{self.tag}/{name}"
        r2.objects[key] = (b"tampered!", release_apks.APK_TYPE, f'attachment; filename="{name}"')
        with self.assertRaisesRegex(release_apks.ReleaseError, "SHA-256 冲突"):
            self.upload_r2(r2)
        self.assertEqual(r2.objects[key][0], b"tampered!")
        self.assertEqual(r2.writes, [])

    def test_public_download_headers_and_checksum_are_verified(self):
        r2 = R2()
        self.upload_r2(r2)
        download = self.metadata["downloads"][0]
        key = download["url"].removeprefix("https://download.neuq.one/")
        body, mime, disposition = r2.objects[key]
        for changes, message in [((body, "text/html", disposition), "响应头无效"),
                                 ((b"tampered!", mime, disposition), "完整性校验失败")]:
            r2.objects[key] = changes
            with self.assertRaisesRegex(release_apks.ReleaseError, message):
                r2.verify(download)

    def test_github_partial_draft_and_lost_publish_response_are_recoverable(self):
        github, release = self.github("beta")
        github.fail_upload = True
        with self.assertRaisesRegex(release_apks.ReleaseError, "HTTP 502"):
            release.publish(self.directory)
        self.assertTrue(github.release["draft"])
        github.fail_upload = False
        github.fail_publish = True
        with self.assertRaisesRegex(release_apks.ReleaseError, "HTTP 502"):
            release.publish(self.directory)
        self.assertFalse(github.release["draft"])
        release.check()
        release.publish(self.directory)
        self.assertEqual(github.creations, 1)
        self.assertEqual(len(github.deletions), 1)
        self.assertEqual(len(github.uploads), 4)
        self.assertEqual(github.make_latest, "make_latest=false")

    def test_stable_and_github_published_conflicts(self):
        github, release = self.github("stable")
        release.publish(self.directory)
        self.assertEqual(github.make_latest, "make_latest=true")
        self.assertFalse(github.release["prerelease"])
        beta = release_apks.GitHubRelease(self.tag, "beta", self.metadata, github.run)
        with self.assertRaisesRegex(release_apks.ReleaseError, "渠道冲突"):
            beta.check()
        first = github.uploads[0]
        github.assets[first]["digest"] = "sha256:" + "0" * 64
        with self.assertRaisesRegex(release_apks.ReleaseError, "内容冲突"):
            release.check()
        self.assertEqual(len(github.uploads), 4)
        self.assertEqual(github.deletions, [])
