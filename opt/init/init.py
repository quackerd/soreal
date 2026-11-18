import json
import os
import shutil
import subprocess
import urllib.parse
from pathlib import Path
from typing import Any

import jinja2

RENDER_ROOTS = [Path("/opt/caddy"), Path("/opt/xray")]
USERS_DIR = Path("/opt/soreal/data/users")


class xray_args:
    host: str
    port: int
    self_sign: bool
    log_level: str
    caddy_log_level: str
    site_url: str
    upstream_url: str
    users: list[str]
    userlinks: dict[str, str]

    def __init__(self) -> None:
        self._from_env()

    @staticmethod
    def _str_to_bool(s: str) -> bool:
        return s.lower() == "true".lower()

    @staticmethod
    def _get_env(name: str, default: str, required: bool = False) -> str:
        env = os.getenv(name)
        if env is None:
            if required:
                raise RuntimeError(f'Missing environment variable "{name}".')
            else:
                return default
        return env

    def _populate_shareable_links(self) -> None:
        self.userlinks = {}
        for user in self.users:
            params = {
                "security": "tls",
                "encryption": "none",
                "headerType": "none",
                "type": "tcp",
                "flow": "xtls-rprx-vision",
                "sni": self.host,
                "fp": "chrome",
            }
            if self.self_sign:
                params["insecure"] = "1"
            query: str = urllib.parse.urlencode(params)
            link: str = (
                f"vless://{user}@{self.host}:{self.port}?{query}"
                f"#{urllib.parse.quote(self.host)}"
            )
            self.userlinks[user] = link

    def _from_env(self) -> None:
        self.host = self._get_env("HOST", "", required=True)
        self.port = int(self._get_env("PORT", "443"))
        self.log_level = self._get_env("LOG_LEVEL", default="warning")
        self.caddy_log_level = self._get_env("CADDY_LOG_LEVEL", default="warn")
        self.site_url = self._get_env("SITE_URL", "")
        self.upstream_url = self._get_env("UPSTREAM_URL", "")
        self.self_sign = self._str_to_bool(self._get_env("SELF_SIGN", "false"))
        self.users = []
        i = 0
        while True:
            user_val = self._get_env(f"USER{i}", "").strip()
            if len(user_val) == 0:
                if i == 0:
                    raise RuntimeError("Must define at least one user.")
                break

            if "@" in user_val:
                raise RuntimeError(f'USER{i} must not contain "@".')
            if not len(user_val.encode()) < 30:
                raise RuntimeError(f'USER{i} must be under 30 bytes.')

            self.users.append(user_val)
            i += 1

        self._populate_shareable_links()

    def __str__(self) -> str:
        ret = (
            f"HOST: {self.host}\n"
            f"PORT: {self.port}\n"
            f"SITE_URL: {self.site_url}\n"
            f"UPSTREAM_URL: {self.upstream_url}\n"
            f"LOG_LEVEL: {self.log_level}\n"
            f"CADDY_LOG_LEVEL: {self.caddy_log_level}\n"
            f"SELF_SIGN: {self.self_sign}\n"
            f"USERS: {self.users}"
        )
        return ret


def process_directory(
    path: Path, vars: dict[str, str], delete_template: bool = True
) -> None:
    for f in os.listdir(path):
        full_path = path / f
        if os.path.isdir(full_path):
            process_directory(full_path, vars, delete_template)
        elif f.endswith(".in"):
            with open(full_path, "r") as sf, open(str(full_path)[:-3], "w") as df:
                template: jinja2.Template = jinja2.Template(sf.read())
                expanded: str = template.render(**vars)
                df.write(expanded)
            if delete_template:
                subprocess.check_call(f"rm {full_path}", shell=True)


def build_xray_clients(args: xray_args) -> str:
    clients = [
        {"id": user, "flow": "xtls-rprx-vision"}
        for user in args.users
    ]
    return json.dumps(clients, indent=4)


def build_jinja_dict(args: xray_args) -> dict[str, Any]:
    jinja_dict: dict[str, Any] = {}
    jinja_dict["HOST"] = args.host
    jinja_dict["PORT"] = args.port
    jinja_dict["SELF_SIGN"] = args.self_sign
    jinja_dict["SITE_URL"] = args.site_url
    jinja_dict["LOG_LEVEL"] = args.log_level
    jinja_dict["CADDY_LOG_LEVEL"] = args.caddy_log_level
    jinja_dict["USERS"] = build_xray_clients(args)
    jinja_dict["UPSTREAM_URL"] = args.upstream_url
    jinja_dict["CERT_FILE"] = os.environ["CERT_FILE"]
    jinja_dict["KEY_FILE"] = os.environ["KEY_FILE"]

    return jinja_dict


def gen_shareable_links(path: Path, args: xray_args) -> None:
    if os.path.isdir(path):
        shutil.rmtree(path)  # directory must reflect the current USERx env only

    for user, link in args.userlinks.items():
        print(f'\n===== User "{user}" =====')
        print(link)
        user_dir: Path = path / user
        os.makedirs(str(user_dir), exist_ok=True)
        file = user_dir / "link.txt"
        with open(str(file), "w") as f:
            f.write(link + "\n")
        subprocess.check_output(
            f"qrencode -o {user_dir / 'qrcode.png'!s} < {file}", shell=True)
        print(subprocess.check_output(f"qrencode -t ansiutf8 < {file}\n", shell=True).decode())


def main():
    print("Initializing soreal...")
    args: xray_args = xray_args()

    print(f"\nConfiguration:\n{args!s}\n")

    template = build_jinja_dict(args)

    print("Generating shareable links...")
    gen_shareable_links(USERS_DIR, args)

    print("Processing config files...")
    for root in RENDER_ROOTS:
        process_directory(root, template)

    print("Initialization completed.")


main()
