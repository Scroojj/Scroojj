"""Бэктест EMA 15/30 системы (те же правила, что в rts_ema_trend_strategy.pine) на 5м свечах.

Запуск:
  python backtest.py --csv BTC.csv ETH.csv ...      # CSV: time(ms или ISO),open,high,low,close
  python backtest.py --fetch binance:BTCUSDT binance:ETHUSDT binance:ETCUSDT hl:HYPE --days 365

Стоп в крипте задаётся множителем ATR (500 пунктов РТС к крипте не переносятся).
Вход: сигнал на закрытии свечи i, сделка по open свечи i+1. Если в свече достигнуты и стоп,
и разворот, считается стоп. Комиссия берётся с каждой стороны (--fee, доля от цены).
"""
import argparse
import json
import time
import urllib.request

import numpy as np
import pandas as pd

BARS_PER_DAY = 288


def load_csv(path):
    df = pd.read_csv(path)
    df.columns = [c.lower() for c in df.columns]
    t = df["time"]
    df.index = pd.to_datetime(t, unit="ms") if np.issubdtype(t.dtype, np.number) else pd.to_datetime(t)
    return df[["open", "high", "low", "close"]].astype(float).sort_index()


def _get(url, body=None):
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body else None,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def fetch_binance(symbol, days):
    end = int(time.time() * 1000)
    start = end - days * 86_400_000
    rows = []
    while start < end:
        chunk = _get(f"https://api.binance.com/api/v3/klines?symbol={symbol}&interval=5m&startTime={start}&limit=1000")
        if not chunk:
            break
        rows += chunk
        start = chunk[-1][0] + 300_000
    df = pd.DataFrame(rows).iloc[:, :5]
    df.columns = ["time", "open", "high", "low", "close"]
    df.index = pd.to_datetime(df["time"], unit="ms")
    return df[["open", "high", "low", "close"]].astype(float)


def fetch_hl(coin, days):
    end = int(time.time() * 1000)
    body = {"type": "candleSnapshot",
            "req": {"coin": coin, "interval": "5m", "startTime": end - days * 86_400_000, "endTime": end}}
    rows = _get("https://api.hyperliquid.xyz/info", body)
    df = pd.DataFrame(rows).rename(columns={"t": "time", "o": "open", "h": "high", "l": "low", "c": "close"})
    df.index = pd.to_datetime(df["time"], unit="ms")
    return df[["open", "high", "low", "close"]].astype(float)


def signals(df, fast=15, slow=30, atr_len=BARS_PER_DAY * 7, k=0.5, use_htf=True, pullback=True, regime=True):
    c = df["close"]
    ef, es = c.ewm(span=fast, adjust=False).mean(), c.ewm(span=slow, adjust=False).mean()
    tr = pd.concat([df.high - df.low, (df.high - c.shift()).abs(), (df.low - c.shift()).abs()], axis=1).max(axis=1)
    atr = tr.ewm(alpha=1 / atr_len, adjust=False).mean()
    up = ef > es
    dn = ef < es
    ok = (ef - es).abs() > k * atr if regime else pd.Series(True, index=df.index)
    if use_htf:  # часовик: берём последнюю ЗАКРЫТУЮ часовую свечу
        h = c.resample("1h").last().dropna()
        hup = (h.ewm(span=fast, adjust=False).mean() > h.ewm(span=slow, adjust=False).mean()).shift(1)
        hup = hup.reindex(df.index, method="ffill").astype("boolean").fillna(False).astype(bool)
        lg_ok, sh_ok = hup, ~hup
    else:
        lg_ok = sh_ok = pd.Series(True, index=df.index)
    pl = (df.low <= es) & (c > es) if pullback else True
    ps = (df.high >= es) & (c < es) if pullback else True
    return up & lg_ok & ok & pl, dn & sh_ok & ok & ps, ef, es, atr


def run(df, stop_atr=3.0, fee=0.0005, **kw):
    lg, sh, ef, es, atr = signals(df, **kw)
    o, h, l, c = (df[x].to_numpy() for x in ("open", "high", "low", "close"))
    lg, sh, ef, es, atr = (x.to_numpy() for x in (lg, sh, ef, es, atr))
    pos, entry, stop, trades = 0, 0.0, 0.0, []
    for i in range(1, len(df)):
        if pos:
            hit_stop = (l[i] <= stop) if pos > 0 else (h[i] >= stop)
            rev = (ef[i] < es[i]) if pos > 0 else (ef[i] > es[i])
            if hit_stop or rev:
                px = min(stop, o[i]) if (hit_stop and pos > 0) else max(stop, o[i]) if hit_stop else c[i]
                trades.append(pos * (px - entry) / entry - 2 * fee)
                pos = 0
        if not pos and (lg[i - 1] or sh[i - 1]) and np.isfinite(atr[i - 1]):
            pos = 1 if lg[i - 1] else -1
            entry = o[i]
            stop = entry - pos * stop_atr * atr[i - 1]
    return np.array(trades)


def report(name, tr, days):
    if len(tr) == 0:
        return f"{name}: сделок нет"
    eq = np.cumsum(tr)
    dd = (np.maximum.accumulate(eq) - eq).max()
    return (f"{name}: сделок={len(tr)} winrate={np.mean(tr > 0):.1%} avg={tr.mean():.3%} "
            f"сумма(простая)={tr.sum():.1%} макс.просадка(простая)={dd:.1%} дней={days:.0f}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", nargs="*", default=[])
    ap.add_argument("--fetch", nargs="*", default=[])
    ap.add_argument("--days", type=int, default=365)
    ap.add_argument("--stop-atr", type=float, default=3.0)
    ap.add_argument("--fee", type=float, default=0.0005)
    a = ap.parse_args()
    data = {p: load_csv(p) for p in a.csv}
    for s in a.fetch:
        src, sym = s.split(":")
        data[s] = (fetch_binance if src == "binance" else fetch_hl)(sym, a.days)
    for name, df in data.items():
        days = (df.index[-1] - df.index[0]).days
        print(report(name, run(df, stop_atr=a.stop_atr, fee=a.fee), days))
