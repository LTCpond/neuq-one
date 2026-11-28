import hashlib
from http.client import HTTPException
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from tempfile import TemporaryDirectory
from time import sleep
from urllib.error import HTTPError, URLError
from urllib.request import HTTPRedirectHandler, Request, build_opener


REPOSITORY = "LTCpond/neuq-one"
PUBLIC_ORIGIN = "https://download.neuq.one"
ABIS = ("arm64-v8a", "armeabi-v7a", "x86_64")
METADATA = "apk-downloads.json"
APK_TYPE = "application/vnd.android.package-archive"
MAX_ASSET_SIZE = 2 * 1024**3 - 1


class ReleaseError(Exception):
    pass


def fingerprint(stream, limit=MAX_ASSET_SIZE):
    size = 0
    digest = hashlib.sha256()
    while chunk := stream.read(1024 * 1024):
        size += len(chunk)
        if size > limit:
            raise ReleaseError("文件超过预期大小")
        digest.update(chunk)
    return size, digest.hexdigest()


def release_metadata(tag, directory):
    if len(tag) > 129 or not re.fullmatch(r"v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", tag):
        raise ReleaseError("发布标签无效")
    downloads = []
    for abi in ABIS:
        filename = f"neuq-one-{tag}-{abi}.apk"
        with (directory / filename).open("rb") as apk:
            size, sha256 = fingerprint(apk)
        if size == 0:
            raise ReleaseError(f"APK 为空：{filename}")
        downloads.append({
            "abi": abi,
            "filename": filename,
            "url": f"{PUBLIC_ORIGIN}/releases/{tag}/{filename}",
            "fallbackUrl": f"https://github.com/{REPOSITORY}/releases/download/{tag}/{filename}",
            "size": size,
            "sha256": sha256,
        })
    return {"schemaVersion": 1, "version": tag[1:], "downloads": downloads}


def metadata_bytes(metadata):
    return (json.dumps(metadata, indent=2) + "\n").encode("utf-8")


def command(*args):
    return subprocess.run(args, capture_output=True, encoding="utf-8", check=False)


class RejectRedirect(HTTPRedirectHandler):
    def redirect_request(self, request, *args):
        return None


def verify_public_download(download, request=build_opener(RejectRedirect()).open):
    filename = download["filename"]
    public_request = Request(
        download["url"], headers={"User-Agent": "NEUQ-One-Release/1.0 (+https://neuq.one)"},
    )
    for attempt in range(4):
        try:
            with request(public_request, timeout=45) as response:
                if (response.status != 200 or response.headers.get_content_type() != APK_TYPE
                        or response.headers.get_content_disposition() != "attachment"
                        or response.headers.get_filename() != filename
                        or response.headers.get("Content-Length") != str(download["size"])):
                    raise ReleaseError(f"R2 公开下载响应头无效：{filename}")
                if fingerprint(response, download["size"]) != (download["size"], download["sha256"]):
                    raise ReleaseError(f"R2 公开下载完整性校验失败：{filename}")
                return
        except HTTPError as error:
            status = error.code
            error.close()
            if status not in (404, 408, 429) and not 500 <= status < 600:
                raise ReleaseError(f"R2 公开下载失败（HTTP {status}）：{filename}") from None
        except (URLError, OSError, HTTPException):
            pass
        if attempt < 3:
            sleep(2 ** attempt)
    raise ReleaseError(f"R2 公开下载失败或超时：{filename}")


def check_r2_object(download, attachment, options, run, *, allow_missing=False):
    filename = download["filename"]
    # Read the origin even if the CDN already has the expected bytes cached.
    with TemporaryDirectory() as temp:
        stored = Path(temp) / filename
        get = run("aws", "s3api", "get-object", *options, str(stored))
        if get.returncode:
            if allow_missing and re.search(r"\((NoSuchKey|404)\).*GetObject", get.stderr):
                return False
            raise ReleaseError(f"无法读取 R2 对象：{filename}")
        if stored.stat().st_size != download["size"]:
            raise ReleaseError(f"同版本 R2 APK 大小冲突：{filename}")
        with stored.open("rb") as apk:
            if fingerprint(apk, download["size"])[1] != download["sha256"]:
                raise ReleaseError(f"同版本 R2 APK SHA-256 冲突：{filename}")
        headers = json.loads(get.stdout)
        if (headers.get("ContentLength") != download["size"] or headers.get("ContentType") != APK_TYPE
                or headers.get("ContentDisposition") != attachment):
            raise ReleaseError(f"R2 源站下载响应头无效：{filename}")
    return True


def upload_r2(tag, directory, metadata, bucket, run=command, verify=verify_public_download):
    for download in metadata["downloads"]:
        filename = download["filename"]
        key = f"releases/{tag}/{filename}"
        attachment = f'attachment; filename="{filename}"'
        options = ("--bucket", bucket, "--key", key, "--output", "json", "--no-cli-pager")
        if not check_r2_object(download, attachment, options, run, allow_missing=True):
            put = run(
                "aws", "s3api", "put-object", *options, "--body", str(directory / filename),
                "--if-none-match", "*", "--content-type", APK_TYPE, "--content-disposition", attachment,
                "--cache-control", "public, max-age=31536000, immutable, no-transform",
            )
            if put.returncode and not re.search(r"\((PreconditionFailed|412)\).*PutObject", put.stderr):
                raise ReleaseError(f"R2 上传失败：{filename}")
            check_r2_object(download, attachment, options, run)
        verify(download)
        print(f"已校验 R2 APK：{filename}")


class GitHubRelease:
    def __init__(self, tag, channel, metadata, run=command):
        if channel not in ("beta", "stable"):
            raise ReleaseError("发布渠道无效")
        self.tag = tag
        self.beta = channel == "beta"
        self.run = run
        self.api = f"repos/{REPOSITORY}/releases"
        self.expected = {
            download["filename"]: (download["size"], download["sha256"])
            for download in metadata["downloads"]
        }
        manifest = metadata_bytes(metadata)
        self.expected[METADATA] = (len(manifest), hashlib.sha256(manifest).hexdigest())

    def gh(self, *args):
        result = self.run("gh", *args)
        if result.returncode:
            status = re.search(r"\bHTTP ([45][0-9]{2})\b", result.stderr)
            detail = f"（HTTP {status[1]}）" if status else ""
            raise ReleaseError(f"GitHub {args[0]} 操作失败{detail}：{self.tag}")
        return result.stdout

    def list(self, endpoint):
        pages = json.loads(self.gh("api", "--paginate", "--slurp", f"{endpoint}?per_page=100"))
        return [item for page in pages for item in page]

    def find(self):
        releases = [release for release in self.list(self.api) if release["tag_name"] == self.tag]
        if len(releases) > 1:
            raise ReleaseError(f"找到多个同标签 GitHub Release：{self.tag}")
        if releases:
            release = releases[0]
        else:
            owner, name = REPOSITORY.split("/")
            query = """
                query($owner: String!, $name: String!, $tag: String!) {
                  repository(owner: $owner, name: $name) {
                    release(tagName: $tag) {
                      id: databaseId
                      draft: isDraft
                      prerelease: isPrerelease
                    }
                  }
                }
            """
            response = json.loads(self.gh(
                "api", "graphql", "-f", f"query={query}",
                "-f", f"owner={owner}", "-f", f"name={name}", "-f", f"tag={self.tag}",
            ))
            release = response["data"]["repository"]["release"]
        if release and release["prerelease"] != self.beta:
            raise ReleaseError(f"现有 GitHub Release 渠道冲突：{self.tag}")
        return release

    def pending(self, release):
        assets = self.list(f"{self.api}/{release['id']}/assets")
        pending = {}
        for name, (size, sha256) in self.expected.items():
            matches = [asset for asset in assets if asset["name"] == name]
            if not matches and release["draft"]:
                pending[name] = None
                continue
            if len(matches) == 1:
                asset = matches[0]
                if asset["state"] == "uploaded" and asset["size"] == size and asset.get("digest") == f"sha256:{sha256}":
                    continue
                if release["draft"] and asset["state"] == "starter" and asset["size"] == 0:
                    pending[name] = asset["id"]
                    continue
            raise ReleaseError(f"现有 GitHub Release 附件缺失或内容冲突：{name}")
        return pending

    def check(self):
        if release := self.find():
            self.pending(release)

    def publish(self, directory):
        release = self.find()
        if release is None:
            flags = ["--prerelease", "--latest=false", "--title", f"{self.tag} 公测版"] if self.beta else []
            notes = Path(".github/release-notes") / f"{self.tag}.md"
            if notes.is_file():
                flags += ["--notes-file", str(notes)]
            self.gh("release", "create", self.tag, "--repo", REPOSITORY,
                    "--draft", "--verify-tag", "--generate-notes", *flags)
            for delay in (1, 2, 4):
                release = self.find()
                if release is not None:
                    break
                sleep(delay)
            else:
                release = self.find()
            if release is None:
                raise ReleaseError(f"暂时无法读取 GitHub Release 草稿：{self.tag}")

        pending = self.pending(release)
        if not release["draft"]:
            print(f"已校验现有 GitHub Release：{self.tag}")
            return
        for name, starter in pending.items():
            if starter is not None:
                self.gh("api", "--method", "DELETE", f"{self.api}/assets/{starter}")
            self.gh("release", "upload", self.tag, str(directory / name), "--repo", REPOSITORY)
        if self.pending(release):
            raise ReleaseError(f"GitHub Release 仍有附件未就绪：{self.tag}")
        published = json.loads(self.gh(
            "api", "--method", "PATCH", f"{self.api}/{release['id']}",
            "-F", "draft=false", "-f", f"make_latest={'false' if self.beta else 'true'}",
        ))
        if published["draft"] is not False or published["prerelease"] != self.beta or published["tag_name"] != self.tag:
            raise ReleaseError(f"GitHub Release 发布状态未确认：{self.tag}")
        print(f"已发布 GitHub Release：{self.tag}")


def main(action):
    tag = os.environ["GITHUB_REF_NAME"]
    directory = Path("release-apks")
    metadata = release_metadata(tag, directory)
    if action == "upload-r2":
        bucket = os.environ["R2_BUCKET"]
        endpoint = os.environ["AWS_ENDPOINT_URL_S3"]
        if (not re.fullmatch(r"[a-z0-9][a-z0-9-]{1,61}[a-z0-9]", bucket)
                or os.environ["R2_PUBLIC_URL"].removesuffix("/") != PUBLIC_ORIGIN
                or not re.fullmatch(r"https://[a-f0-9]{32}(?:\.(?:eu|fedramp))?\.r2\.cloudflarestorage\.com/?", endpoint)
                or not os.environ["AWS_ACCESS_KEY_ID"] or not os.environ["AWS_SECRET_ACCESS_KEY"]):
            raise ReleaseError("R2 发布配置缺失或无效")
        upload_r2(tag, directory, metadata, bucket)
        (directory / METADATA).write_bytes(metadata_bytes(metadata))
        return

    release = GitHubRelease(tag, os.environ["UPDATE_CHANNEL"], metadata)
    if action == "check-github":
        release.check()
    elif action == "publish-github":
        if (directory / METADATA).read_bytes() != metadata_bytes(metadata):
            raise ReleaseError("APK 与通过 R2 校验的元数据不符")
        release.publish(directory)
    else:
        raise ReleaseError("未知的 APK 发布操作")


if __name__ == "__main__":
    try:
        main(sys.argv[1])
    except ReleaseError as error:
        sys.exit(str(error))
    except (KeyError, OSError, ValueError):
        sys.exit("APK 发布配置、文件或服务响应无效")
