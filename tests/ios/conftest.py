"""iOS App UI 測試的 fixture：模擬器、Appium（XCUITest）、測試代理伺服器、失敗時留下證據。

    pip install -r requirements-app.txt
    xcodebuild -project ios/Wallet.xcodeproj -scheme Wallet -configuration Debug \\
        -destination 'generic/platform=iOS Simulator' -derivedDataPath ios/build build
    xcrun simctl boot "iPhone 17"                      # 任何一台 iPhone 模擬器
    appium --address 127.0.0.1 --port 4723             # 另一個終端機；需要 xcuitest driver
    pytest tests/ios --ios

要模擬器，所以加了 --ios 才收集（tests/conftest.py）。加了 --ios 卻少了東西（模擬器、Appium 伺服器、
App），每個測試都會失敗並說缺什麼：不能讓「什麼都沒跑」看起來像「全過」。

API 和資料庫沿用上一層 conftest 的 server、api、db：App 測完一樣直接查資料庫。App 不直接連
API，而是連測試代理伺服器（framework/app/proxy.py，和 Android 的測試共用），由它轉給 API，需要時
製造網路狀況。模擬器和 Mac 共用網路，App 直接連 127.0.0.1，不需要 Android 的 adb reverse。
"""
from __future__ import annotations

import re
import time
from pathlib import Path

import pytest
import requests

try:
    from appium import webdriver
    from appium.options.ios import XCUITestOptions
except ImportError as e:
    # 會收集到這裡就表示要跑 iOS 測試：缺客戶端要講清楚，不能悄悄跳過
    raise ImportError(f"{e}. The iOS app tests need: pip install -r requirements-app.txt") from e

from framework.app.proxy import TestProxy
from framework.ios.simulator import BUNDLE_ID, Simulator, booted
from framework.ios.start_screen import StartScreen

ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = ROOT / "reports" / "ios"
RUNNING_IN_FOREGROUND = 4            # Appium 的 app state：App 開著、在最上層
SUSPENDED_IN_BACKGROUND = 2          # 在背景、暫停了

# 畫面時間依裝置時區顯示（D-03），固定下來結果才穩定；和網頁、Android 的測試相同。模擬器的時區跟著
# Mac，所以用 App 啟動時的 TZ 環境變數固定（Foundation 的 TimeZone.current 會讀它）
TIMEZONE = "Asia/Taipei"


def pytest_collection_modifyitems(config, items):
    """直接指定 pytest tests/ios 時，pytest 不套用 tests/conftest.py 的忽略規則：沒加 --ios 一樣跳過，並說原因。"""
    if config.getoption("--ios"):
        return
    skip = pytest.mark.skip(reason="the iOS app tests need a simulator: run with --ios")
    for item in items:
        if Path(item.path).is_relative_to(Path(__file__).parent):
            item.add_marker(skip)


@pytest.fixture(scope="session")
def simulator(request) -> Simulator:
    running = booted()
    udid = request.config.getoption("--ios-udid")
    if udid:
        match = [d for d in running if d["udid"] == udid]
        if not match:
            pytest.fail(f"simulator {udid} is not booted. Boot it: xcrun simctl boot {udid}", pytrace=False)
    else:
        match = running
        if len(match) != 1:
            pytest.fail(f"--ios needs one booted simulator; found {[d['name'] for d in running] or 'none'}. "
                        'Boot one (xcrun simctl boot "iPhone 17") or choose with --ios-udid or IOS_UDID',
                        pytrace=False)
    d = match[0]
    return Simulator(d["udid"], d["name"], d["os"])


@pytest.fixture(scope="session")
def installed(request, simulator) -> None:
    """測試開始前安裝一次要測的 App。"""
    app = Path(request.config.getoption("--ios-app"))
    if not (app / "Info.plist").is_file():
        pytest.fail(f"{app} does not exist. Build it first (see ios/README.md)", pytrace=False)
    simulator.install(str(app))


@pytest.fixture(scope="session")
def proxy(server):
    """App 和 API 之間的測試代理伺服器，聽 Mac 的 127.0.0.1：模擬器直接連得到。"""
    p = TestProxy(server["base_url"]).start()
    yield p
    p.stop()


@pytest.fixture(scope="session")
def driver(request, simulator, installed):
    url = request.config.getoption("--appium-url")
    try:
        requests.get(url + "/status", timeout=5).raise_for_status()
    except requests.RequestException as e:
        pytest.fail(f"no Appium server at {url} ({e}). Start one: appium --address 127.0.0.1 --port 4723",
                    pytrace=False)
    options = XCUITestOptions()
    options.udid = simulator.udid
    options.no_reset = True                       # 每個測試自己重新啟動 App（app fixture）
    options.new_command_timeout = 300
    options.wda_launch_timeout = 600_000          # 第一次要編譯 WebDriverAgent，最多等 10 分鐘
    d = webdriver.Remote(url, options=options)
    yield d
    d.quit()


def launch(simulator, proxy) -> None:
    # 和 Android 的啟動參數 apiBaseUrl 同名；只有 Debug 版會讀（ApiConfig.swift）
    simulator.launch(["-apiBaseUrl", proxy.url], {"TZ": TIMEZONE})
    # 沒帶到代理伺服器的位址，App 連的是預設位址，之後每一步都是「沒有回應」：在這裡就說清楚
    arguments = simulator.arguments()
    assert arguments is not None and proxy.url in arguments, \
        f"the app runs with {arguments}, not with the test proxy's address"


@pytest.fixture
def app(request, driver, proxy, simulator):
    """每個測試一個全新啟動的 App，停在開始畫面，API 位址指向測試代理伺服器。

    結束時檢查 App 還開著：畫面看起來對，程式也可能已經掛了（Android 版檢查崩潰紀錄，這裡檢查
    App 是否還在前景執行）。失敗時留下截圖、畫面結構（XCUITest 看到的樹）和代理伺服器看到的請求。
    """
    proxy.reset()
    driver.terminate_app(BUNDLE_ID)
    # 上一個測試若讓 App 進過背景（IOS-015、017），iOS 會還原那時的畫面：先丟掉，每個測試都從開始畫面起
    simulator.clear_saved_state()
    launch(simulator, proxy)
    yield StartScreen(driver).wait()

    failed = getattr(request.node, "rep_call", None) is not None and request.node.rep_call.failed
    if failed:
        out = ARTIFACTS / re.sub(r"[^\w.-]+", "_", request.node.nodeid)
        out.mkdir(parents=True, exist_ok=True)
        driver.get_screenshot_as_file(str(out / "screen.png"))
        (out / "screen.xml").write_text(driver.page_source, encoding="utf-8")
        # App 送了哪些請求、各自有沒有回應：畫面停在某一步時，分得出是沒送出去，還是送了沒回應
        (out / "proxy.txt").write_text("".join(f"{e.method} {e.path} key={e.key} status={e.status}\n"
                                               for e in proxy.exchanges()), encoding="utf-8")
    state = driver.query_app_state(BUNDLE_ID)
    assert state == RUNNING_IN_FOREGROUND, f"the app is no longer running in the foreground (state {state}): did it crash?"


@pytest.fixture
def kill_and_reopen(request, driver, proxy, simulator):
    """放到背景、像系統那樣殺掉程序、再打開（K-08）。Android 的 send_to_background、kill_background_process、
    reopen_from_launcher。

    等 App 在背景暫停了才殺：系統回收記憶體時殺的就是暫停的 App，而 iOS 在暫停之前已經存好畫面狀態。
    不能靠「狀態檔更新了」來等：內容沒變時 iOS 不一定重寫，沒有保存狀態的 App 也永遠等不到。
    重新打開時帶一樣的啟動參數，App 才會連回測試代理伺服器；啟動參數和還原畫面無關。
    """
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    def run(timeout: float = 10) -> None:
        driver.execute_script("mobile: pressButton", {"name": "home"})
        deadline = time.monotonic() + timeout
        while driver.query_app_state(BUNDLE_ID) != SUSPENDED_IN_BACKGROUND:
            if time.monotonic() > deadline:
                raise AssertionError(f"the app was not suspended in the background within {timeout:.0f} s")
            time.sleep(0.2)
        simulator.kill()
        # 重開之前 App 是不是已經在跑（不是我們啟動的）：記下來，CI 上才看得出系統會不會自己把它叫起來
        before = simulator.arguments()
        with (ARTIFACTS / "relaunches.txt").open("a", encoding="utf-8") as log:
            log.write(f"{request.node.nodeid}: before the relaunch, "
                      f"{'no process' if before is None else f'a process was running with {before}'}\n")
        launch(simulator, proxy)
    return run


@pytest.hookimpl(wrapper=True)
def pytest_runtest_makereport(item, call):
    """把每個階段的結果掛在 item 上，app fixture 收尾時才知道測試有沒有失敗。"""
    rep = yield
    setattr(item, f"rep_{rep.when}", rep)
    return rep
