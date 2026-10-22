"""IOS-018：文字樣式保有 Figma 的行高（SPEC.md §3、§5）。IOS-020：圖示佔滿 24 x 24 的框（§7.7）。

SwiftUI 沒有「行高」可設：App 在行與行之間補行距，再在文字上下各補一半（Theme.swift），和 CSS、
Compose 一樣。原本只補了行距，單行文字只有字型本身的高度（15 pt 的字 18 pt 高，不是 Body 的 22），
每一列都比網頁和 Android 矮，整個畫面擠在一起：2.11 版三端並排量測時發現。

量的是相鄰兩列的距離，不是元素的外框：SwiftUI 回報的容器外框只包住裡面的文字、不含 padding，
兩列之間的距離才是一列真正的高度。交易紀錄量的是每一列標題的位置，不是列本身：可以點開的付款列是
按鈕，按鈕的外框含 padding，一般的列不含，兩種列混在一起時，列的外框之間的距離不等於列高（2.14）。
期望值由設計的數字算出來，網頁和 Android 量起來也是這兩個數。

IOS-020 量的是圖示旁邊那段文字從哪裡開始：圖示本身沒有 hook。SF Symbol 沒有指定框時，寬度是符號自己的
寬度，比網頁和 Android 的 24 窄，文字就往左靠（2.16 三端量測時發現，訊息文字差 5 pt）。
"""
import pytest

from testdata.factories import funded_wallet

pytestmark = pytest.mark.ios

HAIRLINE = 1
# 交易紀錄的一列：上下 spacing/md 12、Body/Strong 22、間距 2、Caption 18，再加列與列之間的細線
TRANSACTION_ROW = 12 + 22 + 2 + 18 + 12 + HAIRLINE          # 67
# 收據的一列：上下 spacing/md 12、Body/Regular 22，加細線
RECEIPT_ROW = 12 + 22 + 12 + HAIRLINE                       # 47
TOLERANCE = 1                                               # pt：外框會四捨五入
# 訊息：內容左右 20、訊息左右 spacing/lg 16、圖示 24、間距 spacing/md 12，文字從 72 開始
MESSAGE_TEXT_X = 20 + 16 + 24 + 12
# 收據標題：內容左右 20、圖示 24、間距 spacing/sm 8
HEADING_TEXT_X = 20 + 24 + 8


def pitches(frames) -> list[float]:
    return [round(b[1] - a[1], 1) for a, b in zip(frames, frames[1:])]


@pytest.mark.case_id("IOS-018")
def test_text_styles_keep_their_line_heights(app, api):
    wallet = funded_wallet(api, "100.00")
    api.pay(wallet, "10.00")
    api.pay(wallet, "20.00")

    home = app.open_wallet(wallet)
    home.recent_rows()                                       # 等最近三筆載入：兩筆付款（按鈕）、一筆儲值
    rows = home.frames("item-title")
    assert len(rows) == 3, rows
    home_pitches = pitches(rows)

    receipt = home.go_pay().pay("5")
    rows = receipt.frames("receipt-row")
    assert len(rows) == 4, rows                               # Status、Time、Payment ID、Balance after
    receipt_pitches = pitches(rows)

    assert all(abs(p - TRANSACTION_ROW) <= TOLERANCE for p in home_pitches) and \
        all(abs(p - RECEIPT_ROW) <= TOLERANCE for p in receipt_pitches), \
        f"transaction rows {home_pitches} pt apart, expected {TRANSACTION_ROW}; " \
        f"receipt rows {receipt_pitches} pt apart, expected {RECEIPT_ROW}"



@pytest.mark.case_id("IOS-018")
def test_rows_add_up_without_drift(app, api):
    """每一列單獨看都在 1 pt 以內，累積起來卻可能不是：每行文字多 1/3 pt 時，一列 67.67 pt，
    History 的第六列比網頁和 Android 低 3.3 pt（2.16 三端量測時發現）。第一列到最後一列要剛好 5 x 67。"""
    wallet = funded_wallet(api, "100.00")
    for amount in ("1.00", "2.00", "3.00", "4.00", "5.00"):
        api.pay(wallet, amount)

    history = app.open_wallet(wallet).tab_history()
    rows = history.frames("item-title")
    assert len(rows) == 6, rows                              # 一筆儲值、五筆付款，同一天
    span = rows[-1][1] - rows[0][1]
    assert abs(span - 5 * TRANSACTION_ROW) <= TOLERANCE, \
        f"the first to the last of six rows is {span} pt, expected {5 * TRANSACTION_ROW}"

@pytest.mark.case_id("IOS-020")
def test_icons_take_their_24_pt_box(app, api):
    wallet = funded_wallet(api, "100.00")
    confirm = app.open_wallet(wallet).go_pay().continue_with("500")
    confirm.confirm()
    confirm.expect_shown("error-message")                    # 超過餘額，被拒絕（E-02）
    message_x = confirm.frames("error-message")[0][0]

    receipt = confirm.change_amount().continue_with("30").confirm_and_wait()
    heading_x = receipt.frames("Payment completed")[0][0]   # 標題沒有 hook：用文字找

    assert abs(message_x - MESSAGE_TEXT_X) <= TOLERANCE and abs(heading_x - HEADING_TEXT_X) <= TOLERANCE, \
        f"a message's text starts at {message_x} pt, expected {MESSAGE_TEXT_X}; " \
        f"the receipt heading at {heading_x} pt, expected {HEADING_TEXT_X}"
