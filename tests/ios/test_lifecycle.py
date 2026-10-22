"""IOS-015、017：App 在背景被系統結束（SPEC.md K-08、N-01），和 Android 的 APP-015、017 是同一組行為。

網頁沒有對應的案例：重新整理網頁就是從頭開始（SPEC.md §10）。App 放到背景之後，系統可能為了記憶體
直接結束它，使用者回來時 iOS 用進背景時保存的狀態（@SceneStorage）重建畫面。這時錢的狀態不能錯：
結果未知的付款要能用同一把 key 重試，已經完成的付款不能再被確認一次。

iOS 沒有系統返回鍵，APP-017 裡按返回鍵的部分在這裡不適用；改用收據唯一的出口 Done 回首頁。
"""
import pytest

from framework.ios.pay_screen import ConfirmScreen
from framework.ios.receipt_screen import ReceiptScreen
from testdata.factories import funded_wallet

pytestmark = [pytest.mark.ios, pytest.mark.idempotency]


def payments_of(db, wallet) -> list[int]:
    return [r["amount"] for r in db.all("SELECT amount FROM payments WHERE wallet_id = ?", wallet)]


@pytest.mark.case_id("IOS-015")
def test_process_death_with_the_outcome_unknown(app, api, db, proxy, kill_and_reopen):
    """付款結果未知時 App 被結束：回來還是確認頁、還是「沒有回應」，重試用的是存起來的同一把 key。"""
    wallet = funded_wallet(api, "100.00")
    confirm = app.open_wallet(wallet).go_pay().continue_with("30")
    with proxy.lose_response("/payments"):
        confirm.confirm()
        confirm.expect_shown("no-answer")

    kill_and_reopen()

    confirm = ConfirmScreen(app.driver).wait()
    confirm.expect_shown("no-answer")
    confirm.expect_text("confirm-amount", "30.00")
    confirm.retry()
    confirm.wait_for_receipt().expect_shown("replayed")
    keys = proxy.keys("/payments")
    assert len(keys) == 2 and keys[0] == keys[1], f"the retry after process death must resend the saved key: {keys}"
    assert payments_of(db, wallet) == [3000]


@pytest.mark.case_id("IOS-017")
def test_process_death_on_the_receipt(app, api, db, kill_and_reopen):
    """收據頁時 App 被結束：回來還是同一張收據，沒有「Confirm payment」。

    Android 在 2.3 之前會回到確認頁，再按一次就是第二筆付款（SPEC.md §11）。
    """
    wallet = funded_wallet(api, "100.00")
    receipt = app.open_wallet(wallet).go_pay().pay("30")
    payment_id = receipt.payment_id()

    kill_and_reopen()

    receipt = ReceiptScreen(app.driver).wait()
    receipt.expect_text("result-payment-id", payment_id)
    receipt.expect_text("result-balance", "70.00")
    receipt.expect_absent("confirm-pay")
    receipt.done().expect_text("balance", "70.00")
    assert payments_of(db, wallet) == [3000]


@pytest.mark.case_id("IOS-017")
def test_process_death_on_a_replayed_receipt(app, api, db, proxy, kill_and_reopen):
    """重試後的收據（「這筆付款之前已經完成」）在 App 被結束之後也照實顯示。"""
    wallet = funded_wallet(api, "100.00")
    confirm = app.open_wallet(wallet).go_pay().continue_with("30")
    with proxy.lose_response("/payments"):
        confirm.confirm()
        confirm.expect_shown("no-answer")
    confirm.retry()
    confirm.wait_for_receipt().expect_shown("replayed")

    kill_and_reopen()

    receipt = ReceiptScreen(app.driver).wait()
    receipt.expect_shown("replayed")
    receipt.expect_absent("confirm-pay")
    assert payments_of(db, wallet) == [3000]
