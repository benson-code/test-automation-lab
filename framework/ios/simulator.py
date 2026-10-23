"""用 xcrun simctl 操作 iOS 模擬器：Appium 管不到、或用 simctl 比較直接的事（Android 的 device.py）。

模擬器和 Mac 共用網路：App 裡的 127.0.0.1 就是這台 Mac，不需要 Android 的 adb reverse。
"""
from __future__ import annotations

import json
import os
import shutil
import signal
import subprocess
import time
from pathlib import Path

BUNDLE_ID = "lab.wallet"


class SimctlError(RuntimeError):
    pass


def simctl(*args: str, timeout: float = 120) -> str:
    r = subprocess.run(["xcrun", "simctl", *args], capture_output=True, text=True, timeout=timeout)
    if r.returncode != 0:
        raise SimctlError(f"simctl {' '.join(args)}: {r.stderr.strip() or r.stdout.strip()}")
    return r.stdout


def booted() -> list[dict]:
    """開著的模擬器：每台是 simctl 的一筆資料（udid、name、state …），另外加上它的 iOS 版本 os。"""
    devices = json.loads(simctl("list", "devices", "booted", "--json"))["devices"]
    # runtime 的名字像 com.apple.CoreSimulator.SimRuntime.iOS-26-0
    return [{**d, "os": runtime.rsplit(".", 1)[-1].replace("-", " ", 1).replace("-", ".")}
            for runtime, ds in devices.items() for d in ds if d["state"] == "Booted"]


class Simulator:
    def __init__(self, udid: str, name: str = "", os: str = "") -> None:
        self.udid, self.name, self.os = udid, name, os

    def install(self, app_path: str) -> None:
        """先移除再安裝：上一輪留下的資料一起清掉。"""
        try:
            simctl("uninstall", self.udid, BUNDLE_ID)
        except SimctlError:
            pass                                       # 本來就沒裝
        simctl("install", self.udid, app_path)

    def saved_state(self) -> Path:
        """App 的畫面狀態（@SceneStorage）：進背景時 iOS 寫到這裡，App 在背景被結束、再打開時用它還原。"""
        data = simctl("get_app_container", self.udid, BUNDLE_ID, "data").strip()
        return Path(data) / "Library" / "Saved Application State" / f"{BUNDLE_ID}.savedState"

    def clear_saved_state(self) -> None:
        """丟掉保存的畫面狀態，下次打開從頭開始（Android 的 force-stop）。

        只結束 App 不夠：在前景被結束，iOS 還是會還原上一次進背景時存的狀態（2.15 實測）。
        """
        shutil.rmtree(self.saved_state(), ignore_errors=True)

    def launch(self, arguments: list[str], environment: dict[str, str]) -> None:
        """帶啟動參數和環境變數啟動 App；App 若已經在跑，先把它結束，參數才一定生效。

        不用 Appium 的 mobile: launchApp：App 已經在跑時，它只把 App 叫到前景，帶的參數不會生效
        （本機實測：pid 不變，參數還是舊的）。CI 上 App 被殺掉之後重開，有兩次連不到測試代理伺服器，
        請求一個都沒到：最可能是重開之前程序已經在了，App 沒帶參數、連到預設位址。重開前有沒有程序，
        kill_and_reopen 會記在 reports/ios/relaunches.txt。
        """
        env = {**os.environ, **{f"SIMCTL_CHILD_{k}": v for k, v in environment.items()}}
        r = subprocess.run(["xcrun", "simctl", "launch", "--terminate-running-process", self.udid, BUNDLE_ID,
                            *arguments], capture_output=True, text=True, timeout=120, env=env)
        if r.returncode != 0:
            raise SimctlError(f"simctl launch: {r.stderr.strip() or r.stdout.strip()}")

    def arguments(self) -> list[str] | None:
        """App 程序的命令列參數，不含執行檔本身；App 沒在跑是 None（有程序、沒帶參數是空的清單）。"""
        pid = self._pid()
        if pid is None:
            return None
        out = subprocess.run(["ps", "-o", "args=", "-p", str(pid)], capture_output=True, text=True).stdout.split()
        return out[1:]

    def _pid(self) -> int | None:
        """App 的程序；模擬器裡的程序就是 Mac 上的程序，PID 從模擬器的 launchctl 查。"""
        label = f"UIKitApplication:{BUNDLE_ID}["
        for line in simctl("spawn", self.udid, "launchctl", "list").splitlines():
            pid, _, name = line.split("\t")
            if name.startswith(label) and pid.isdigit():
                return int(pid)
        return None

    def kill(self, timeout: float = 10) -> None:
        """像系統在背景回收記憶體那樣直接殺掉 App 的程序（SIGKILL），App 沒有機會做任何事。

        等到程序真的消失才回來：還沒消失就叫 App 起來，iOS 會當成它還在，結果什麼都沒打開。
        """
        pid = self._pid()
        if pid is None:
            raise SimctlError(f"{BUNDLE_ID} is not running")
        os.kill(pid, signal.SIGKILL)
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if self._pid() is None:
                return
            time.sleep(0.2)
        raise SimctlError(f"{BUNDLE_ID} was still running {timeout:.0f} s after SIGKILL")
