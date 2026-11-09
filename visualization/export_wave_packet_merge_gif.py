from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


WIDTH = 1400
HEIGHT = 780
SCALE = 2

BG = "#F4F8FB"
PANEL = "#FFFFFF"
MUTED_PANEL = "#EAF1F5"
TEXT = "#132238"
MUTED = "#64748B"
LINE = "#CBD8E2"
GREEN = "#079455"
GREEN_SOFT = "#DDF8E9"
BLUE = "#3B82F6"
GRAY = "#94A3B8"


def load_font(size, bold=False):
    candidates = [
        "/System/Library/Fonts/PingFang.ttc",
        "/System/Library/Fonts/Hiragino Sans GB.ttc",
        "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
    ]
    for path in candidates:
        if Path(path).is_file():
            index = 1 if bold and path.endswith(".ttc") else 0
            return ImageFont.truetype(path, size=size, index=index)
    return ImageFont.load_default()


FONT_TITLE = load_font(36, bold=True)
FONT_HEADING = load_font(25, bold=True)
FONT_BODY = load_font(21)
FONT_SMALL = load_font(17)
FONT_CODE = load_font(20, bold=True)


def rounded(draw, box, fill=PANEL, outline=LINE, width=2, radius=16):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def centered_text(draw, xy, text, font, fill=TEXT):
    box = draw.textbbox((0, 0), text, font=font)
    draw.text((xy[0] - (box[2] - box[0]) / 2,
               xy[1] - (box[3] - box[1]) / 2),
              text, font=font, fill=fill)


def draw_arrow(draw, start, end, fill=MUTED, width=3):
    draw.line([start, end], fill=fill, width=width)
    x, y = end
    draw.polygon([(x, y), (x - 14, y - 7), (x - 14, y + 7)], fill=fill)


def draw_crest(draw, x, label, active=False, dim=False):
    color = GREEN if active else GRAY
    if dim:
        color = "#CBD5E1"
    points = [
        (x, 212),
        (x + 7, 250),
        (x + 12, 290),
        (x + 7, 330),
        (x, 370),
        (x + 4, 412),
        (x - 2, 454),
    ]
    draw.line(points, fill=color, width=8, joint="curve")
    centered_text(draw, (x + 2, 490), label, FONT_CODE, color)


def draw_edge(draw, x1, x2, y, label, state):
    if state == "hidden":
        return
    color = GREEN if state == "current" else BLUE
    width = 6 if state == "current" else 4
    draw.line([(x1, y), (x2, y)], fill=color, width=width)
    centered_text(draw, ((x1 + x2) / 2, y - 21), label, FONT_SMALL, color)


def draw_group_bracket(draw, left, right, y, label):
    draw.line([(left, y - 18), (left, y), (right, y), (right, y - 18)],
              fill=GREEN, width=6)
    centered_text(draw, ((left + right) / 2, y + 26), label, FONT_CODE, GREEN)


def draw_queue_row(draw, y, text, state):
    outline = GREEN if state in {"current", "done"} else LINE
    fill = GREEN_SOFT if state == "done" else PANEL
    width = 4 if state == "current" else 2
    rounded(draw, (1015, y, 1320, y + 68), fill=fill, outline=outline, width=width)
    draw.text((1040, y + 20), text, font=FONT_CODE, fill=TEXT)


def frame_for(state):
    image = Image.new("RGB", (WIDTH, HEIGHT), BG)
    draw = ImageDraw.Draw(image)

    draw.text((70, 42), "波包空间归并过程", font=FONT_TITLE, fill=TEXT)
    draw.text((70, 94), "从最小 gap 的合法波锋对开始，不预设头波",
              font=FONT_BODY, fill=MUTED)

    rounded(draw, (70, 145, 940, 585))
    rounded(draw, (980, 145, 1350, 585))
    draw.text((100, 170), "同一景中的波锋", font=FONT_HEADING, fill=TEXT)
    draw.text((1010, 170), "候选边队列", font=FONT_HEADING, fill=TEXT)
    draw.text((1010, 207), "按 [gap, a, b] 排序", font=FONT_SMALL, fill=MUTED)

    draw_arrow(draw, (135, 235), (865, 235))
    draw.text((700, 197), "传播前方", font=FONT_SMALL, fill=MUTED)

    xs = {"D": 190, "C": 470, "B": 680, "A": 820}
    active = set()
    if state >= 2:
        active.update(["A", "B"])
    if state >= 3:
        active.add("C")

    for label in ["D", "C", "B", "A"]:
        draw_crest(
            draw,
            xs[label],
            label,
            active=label in active,
            dim=state >= 2 and label not in active,
        )

    edge_visible = state >= 1
    draw_edge(draw, xs["B"] + 12, xs["A"] - 8, 315, "AB = 4 km",
              "current" if state == 2 else "visible" if edge_visible else "hidden")
    draw_edge(draw, xs["C"] + 12, xs["B"] - 8, 405, "BC = 6 km",
              "current" if state == 3 else "visible" if edge_visible else "hidden")

    row_ab = "done" if state >= 3 else "current" if state == 2 else "normal"
    row_bc = "done" if state >= 4 else "current" if state == 3 else "normal"
    draw_queue_row(draw, 255, "1. AB    4 km", row_ab)
    draw_queue_row(draw, 340, "2. BC    6 km", row_bc)
    rounded(draw, (1015, 425, 1320, 515))
    draw.text((1040, 445), "D：无候选边", font=FONT_CODE, fill=TEXT)
    draw.text((1040, 480), "最近 gap > 8 km", font=FONT_SMALL, fill=MUTED)

    if state == 2:
        draw_group_bracket(draw, 650, 850, 540, "{A,B}")
    elif state == 3:
        draw_group_bracket(draw, 440, 850, 540, "检查 {A,B,C}")
    elif state >= 4:
        draw_group_bracket(draw, 440, 850, 540, "packet {A,B,C}")

    rounded(draw, (70, 620, 1350, 730), fill=MUTED_PANEL)
    messages = [
        ("初始化：labels = [A,B,C,D]",
         "每条波锋先独立成组。"),
        ("计算所有合法波锋对并排序",
         "只有 gap ≤ 8 km 的合法波锋对进入候选队列。"),
        ("处理 AB = 4 km",
         "AB 的 gap 最小；联合组只有 A、B，完整性检查通过。"),
        ("处理 BC = 6 km",
         "B 已属于 {A,B}，所以实际尝试合并 {A,B} + {C}。"),
        ("归并结束：labels = [A,A,A,D]",
         "AB、BC、AC 均 ≤ 40 km，且 A 在 B 前、B 在 C 前；D 保持未归包。"),
    ]
    title, detail = messages[state]
    draw.text((100, 642), title, font=FONT_HEADING, fill=TEXT)
    draw.text((100, 690), detail, font=FONT_BODY, fill=MUTED)

    for index in range(5):
        color = GREEN if index == state else LINE
        draw.ellipse((610 + index * 35, 750, 622 + index * 35, 762), fill=color)

    return image


def main():
    output_dir = Path(__file__).resolve().parent
    frames = [frame_for(i) for i in range(5)]
    gif_path = output_dir / "wave_packet_merge_animation.gif"
    png_path = output_dir / "wave_packet_merge_final.png"

    palette_frames = [
        frame.convert("P", palette=Image.Palette.ADAPTIVE, colors=128)
        for frame in frames
    ]
    palette_frames[0].save(
        gif_path,
        save_all=True,
        append_images=palette_frames[1:],
        duration=[1100, 1400, 1600, 1800, 2800],
        loop=0,
        optimize=True,
        disposal=2,
    )
    frames[-1].save(png_path, optimize=True)
    print(gif_path)
    print(png_path)


if __name__ == "__main__":
    main()
