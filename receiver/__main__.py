import argparse
import os
from pathlib import Path
import queue
import threading
import tkinter as tk
from tkinter import messagebox, ttk

from .core import Receiver, Server, identity
from .discovery import Advertisement


def main():
    parser = argparse.ArgumentParser(description="DropMP4 Windows LAN receiver")
    parser.add_argument("--port", type=int, default=47321)
    parser.add_argument("--ip", action="append", help="Advertised LAN IPv4; repeat for multiple NICs")
    parser.add_argument("--destination", type=Path, default=Path.home() / "Downloads" / "DropMP4")
    parser.add_argument("--state", type=Path, default=Path(os.getenv("LOCALAPPDATA", Path.home())) / "DropMP4")
    args = parser.parse_args()
    root = tk.Tk()
    root.title("DropMP4 — 接收影片")
    root.geometry("620x430")
    root.minsize(580, 400)
    panel = ttk.Frame(root, padding=24)
    panel.pack(fill="both", expand=True)
    ttk.Label(panel, text="DropMP4", font=("Segoe UI", 26, "bold")).pack(anchor="w")
    ttk.Label(panel, text="同一個 Wi-Fi，影片就能抵達。每次接收都需要你確認。", wraplength=550).pack(anchor="w", pady=(4, 16))
    status = tk.StringVar(value="正在啟動…")
    ttk.Label(panel, textvariable=status, wraplength=550).pack(anchor="w", pady=10)
    progress = ttk.Progressbar(panel, maximum=100)
    progress.pack(fill="x", pady=10)
    events = queue.Queue()
    cert, key, fp = identity(args.state)
    code = "-".join(fp[i:i+4].upper() for i in range(0, 12, 4))
    ttk.Label(panel, text=f"核對碼  {code}", font=("Consolas", 20, "bold")).pack(anchor="w", pady=10)
    ttk.Label(panel, text="iPhone 顯示的核對碼必須與這裡完全相同。", wraplength=550).pack(anchor="w")
    ttk.Label(panel, text=f"儲存位置：{args.destination}", wraplength=550).pack(anchor="w", pady=10)
    receiver = Receiver(args.destination, lambda offer: events.put(("approve", offer)),
                        lambda kind, data: events.put((kind, data)))
    server = Server(("0.0.0.0", args.port), receiver, cert, key)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    advertisement = None
    try:
        advertisement = Advertisement(server.server_port, fp, args.ip)
        status.set(f"等待 iPhone · {', '.join(advertisement.addresses)}:{server.server_port}")
    except Exception as error:
        status.set(f"自動搜尋啟動失敗：{error}。請重新啟動並指定 --ip。")

    def poll():
        try:
            for _ in range(30):
                kind, data = events.get_nowait()
                if kind == "approve":
                    with receiver.lock:
                        current = receiver.active is data and not data.answer.is_set()
                    if current:
                        accepted = messagebox.askyesno("接收影片？",
                            f"{data.sender} 想傳送\n{data.name}\n{data.size / 1024**2:.1f} MB\n\n核對碼：{code}\n請先確認 iPhone 上的核對碼相同。\n是否接收？", parent=root)
                        with receiver.lock:
                            if receiver.active is data:
                                data.accepted = accepted
                                data.answer.set()
                        status.set("等待開始傳輸…" if accepted else "已拒絕接收")
                        progress["value"] = 0
                elif kind == "progress":
                    progress["value"] = 100 * data["received"] / data["size"]
                    status.set(f"接收 {data['name']} · {progress['value']:.0f}%")
                elif kind == "complete":
                    status.set(f"已接收並通過 SHA-256 校驗：{data['name']}")
                elif kind == "error":
                    status.set("傳輸失敗：" + data["message"])
        except queue.Empty:
            pass
        root.after(100, poll)

    def close():
        with receiver.lock:
            if receiver.active:
                receiver.active.accepted = False
                receiver.active.answer.set()
        root.destroy()

    root.protocol("WM_DELETE_WINDOW", close)
    poll()
    try:
        root.mainloop()
    finally:
        if advertisement:
            advertisement.close()
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    main()
