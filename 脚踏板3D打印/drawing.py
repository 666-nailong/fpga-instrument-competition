"""Generate dimensioned assembly drawing and exploded preview from model.py."""

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Circle, FancyBboxPatch, Rectangle
import vtk

from model import (
    BASE_D, BASE_W, BOSS_D, BOSS_H, GUIDE_D, GUIDES, POCKET_D,
    POCKET_FLOOR, RELEASE_UNDERSIDE, STOPS, STOP_TOP, TAIL_W,
    TREAD_D, TREAD_T, TREAD_W,
)


OUT = Path(__file__).resolve().parent


def dimension(ax, start, end, label, color="#344054"):
    ax.annotate("", xy=end, xytext=start, arrowprops={"arrowstyle": "<->", "color": color, "lw": 1})
    ax.text((start[0] + end[0]) / 2, (start[1] + end[1]) / 2, label,
            ha="center", va="center", color=color, fontsize=9,
            bbox={"facecolor": "white", "edgecolor": "none", "pad": 1})


def diagram():
    fig, (plan, section) = plt.subplots(1, 2, figsize=(13, 5.5), constrained_layout=True)
    plan.add_patch(FancyBboxPatch((-BASE_W / 2, -BASE_D / 2), BASE_W, BASE_D,
        boxstyle="round,pad=0,rounding_size=6", fc="#d7dee8", ec="#344054", lw=1.5))
    plan.add_patch(FancyBboxPatch((-TREAD_W / 2, -TREAD_D / 2), TREAD_W, TREAD_D,
        boxstyle="round,pad=0,rounding_size=6", fill=False, ec="#3875af", lw=1.2, ls="--"))
    plan.add_patch(Circle((0, 0), POCKET_D / 2, fc="#202d3d", ec="black"))
    plan.add_patch(Circle((0, 0), BOSS_D / 2, fill=False, ec="#f0a51d", lw=2))
    plan.add_patch(Rectangle((-TAIL_W / 2, -38), TAIL_W, 29.5, fc="#d09c6d", ec="none"))
    for x, y in GUIDES:
        plan.add_patch(Circle((x, y), GUIDE_D / 2, fc="#69b8a4", ec="#267460"))
        plan.add_patch(Circle((x, y), 1.7, fc="white", ec="#267460"))
    for x, y in STOPS:
        plan.add_patch(Circle((x, y), 5, fc="#a7b0bf", ec="#667085"))
    for x in (-8, 8):
        plan.add_patch(Circle((x, -29), 1.5, fc="white", ec="#a45f30"))
    dimension(plan, (-48, 45), (48, 45), "96 mm")
    dimension(plan, (56, -38), (56, 38), "76 mm")
    plan.annotate("sensor pocket Ø20.2", xy=(6, 7), xytext=(12, 17), arrowprops={"arrowstyle": "->"}, fontsize=9)
    plan.annotate("tail channel 9.8", xy=(0, -25), xytext=(9, -46), arrowprops={"arrowstyle": "->"}, fontsize=9)
    plan.set(xlim=(-63, 66), ylim=(-50, 51), aspect="equal", title="Plan: base; dashed outline = moving tread")
    plan.axis("off")

    section.add_patch(Rectangle((-48, 0), 96, 6, fc="#d7dee8", ec="#344054"))
    section.add_patch(Rectangle((-10.1, POCKET_FLOOR), 20.2, 0.375, fc="#202d3d"))
    section.add_patch(Rectangle((-5, 5.575), 10, 6.925, fc="#e9b85e", alpha=0.8, ec="#ad701e"))
    section.add_patch(Rectangle((-5, 12.5), 10, BOSS_H, fc="#77a9dc", ec="#235b97"))
    section.add_patch(Rectangle((-45, RELEASE_UNDERSIDE), 90, TREAD_T, fc="#77a9dc", ec="#235b97", alpha=0.7))
    for x in (-26, 26):
        section.add_patch(Rectangle((x - 5, 6), 10, STOP_TOP - 6, fc="#a7b0bf", ec="#667085"))
    for x in (-39, 39):
        section.add_patch(Rectangle((x - GUIDE_D / 2, 6), GUIDE_D, 11.5,
                                    fc="#69b8a4", ec="#267460", alpha=0.8))
    dimension(section, (49, STOP_TOP), (49, RELEASE_UNDERSIDE), "2 mm stroke")
    section.annotate("Ø10 × 7 soft foam", xy=(0, 9), xytext=(-28, 24), arrowprops={"arrowstyle": "->"}, fontsize=9)
    section.set(xlim=(-55, 61), ylim=(-2, 27), aspect="equal", title="Section: released position; foam shown nominally")
    section.set_xlabel("millimetres")
    section.set_ylabel("z / mm")
    section.grid(alpha=0.15)
    fig.suptitle("FSR402B foot pressure pad — all dimensions in mm")
    for suffix in ("png", "svg"):
        fig.savefig(OUT / f"assembly_diagram.{suffix}", dpi=180)
    plt.close(fig)


def preview():
    renderer = vtk.vtkRenderer()
    renderer.SetBackground(1, 1, 1)
    for stem, color, lid in (("base_FSR402B", (0.67, 0.76, 0.86), False),
                             ("tread_FSR402B", (0.16, 0.46, 0.76), True)):
        reader = vtk.vtkSTLReader()
        reader.SetFileName(str(OUT / f"{stem}.stl"))
        reader.Update()
        mapper = vtk.vtkPolyDataMapper()
        mapper.SetInputConnection(reader.GetOutputPort())
        actor = vtk.vtkActor()
        actor.SetMapper(mapper)
        actor.GetProperty().SetColor(*color)
        actor.GetProperty().SetSpecular(0.12)
        if lid:
            transform = vtk.vtkTransform()
            transform.PostMultiply()
            transform.RotateX(180)
            transform.Translate(0, 0, 29)
            actor.SetUserTransform(transform)
        renderer.AddActor(actor)
    camera = renderer.GetActiveCamera()
    camera.SetPosition(135, -145, 105)
    camera.SetFocalPoint(0, 0, 14)
    camera.SetViewUp(0, 0, 1)
    renderer.ResetCamera()
    renderer.GetActiveCamera().Zoom(1.3)
    window = vtk.vtkRenderWindow()
    window.SetOffScreenRendering(1)
    window.SetSize(1200, 800)
    window.AddRenderer(renderer)
    window.Render()
    snapshot = vtk.vtkWindowToImageFilter()
    snapshot.SetInput(window)
    snapshot.Update()
    writer = vtk.vtkPNGWriter()
    writer.SetFileName(str(OUT / "exploded_preview.png"))
    writer.SetInputConnection(snapshot.GetOutputPort())
    writer.Write()


if __name__ == "__main__":
    diagram()
    preview()
