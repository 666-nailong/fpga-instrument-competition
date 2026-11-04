"""Parametric FSR402B foot pressure pad; all dimensions are millimetres.

Run with Python and CadQuery 2.8. Each exported STEP/STL contains one solid.
The soft actuator pad and metal fasteners are separate purchased parts.
"""

from pathlib import Path

import cadquery as cq


OUT = Path(__file__).resolve().parent
BASE_W, BASE_D, BASE_T = 96.0, 76.0, 6.0
TREAD_W, TREAD_D, TREAD_T = 90.0, 70.0, 6.0
CORNER_R = 6.0
POCKET_D, POCKET_FLOOR = 20.2, 5.2
TAIL_W = 9.8
GUIDES = [(x, y) for x in (-39.0, 39.0) for y in (-27.0, 27.0)]
STOPS = [(x, y) for x in (-26.0, 26.0) for y in (-18.0, 18.0)]
GUIDE_D, GUIDE_TOP = 6.2, 17.5
TREAD_GUIDE_HOLE_D = 6.8
STOP_TOP = 13.0
BOSS_D, BOSS_H = 10.0, 2.5
# At rest, tread underside is z=15; it meets the stops after 2 mm travel.
RELEASE_UNDERSIDE = 15.0


def cylinder(x: float, y: float, z: float, radius: float, height: float) -> cq.Workplane:
    return cq.Workplane("XY").workplane(offset=z).center(x, y).circle(radius).extrude(height)


def plate(width: float, depth: float, height: float) -> cq.Workplane:
    return cq.Workplane("XY").rect(width, depth).extrude(height).edges("|Z").fillet(CORNER_R)


def make_base() -> cq.Workplane:
    base = plate(BASE_W, BASE_D, BASE_T)
    for x, y in GUIDES:
        base = base.union(cylinder(x, y, BASE_T, GUIDE_D / 2, GUIDE_TOP - BASE_T))
    for x, y in STOPS:
        base = base.union(cylinder(x, y, BASE_T, 5.0, STOP_TOP - BASE_T))

    base = base.cut(cylinder(0, 0, POCKET_FLOOR, POCKET_D / 2, BASE_T - POCKET_FLOOR + 0.5))
    # The groove reaches the outside edge; its floor stays level with the sensor.
    tail = cq.Workplane("XY").workplane(offset=POCKET_FLOOR).center(0, -23.5).rect(TAIL_W, 30.0).extrude(1.3)
    base = base.cut(tail)
    # Two tie holes retain the wire, well behind the fragile sensor tail.
    for x in (-8.0, 8.0):
        base = base.cut(cylinder(x, -29.0, -0.5, 1.5, BASE_T + 1))
    for x, y in GUIDES:
        base = base.cut(cylinder(x, y, -0.5, 1.7, GUIDE_TOP + 1))
        nut = cq.Workplane("XY").workplane(offset=-0.5).center(x, y).polygon(6, 6.8).extrude(3.2)
        base = base.cut(nut)
    return base


def make_tread() -> cq.Workplane:
    # Exported with the shoe-facing face on the print bed (z=0).
    tread = plate(TREAD_W, TREAD_D, TREAD_T)
    tread = tread.union(cylinder(0, 0, TREAD_T, BOSS_D / 2, BOSS_H))
    for x, y in GUIDES:
        tread = tread.cut(cylinder(x, y, -0.5, TREAD_GUIDE_HOLE_D / 2, TREAD_T + 1))
    return tread


def export_part(part: cq.Workplane, stem: str) -> None:
    solid = part.val()
    if len(part.solids().vals()) != 1 or not solid.isValid():
        raise ValueError(f"{stem}: invalid or multiple solids")
    cq.exporters.export(part, str(OUT / f"{stem}.step"))
    cq.exporters.export(part, str(OUT / f"{stem}.stl"), tolerance=0.08, angularTolerance=0.12)
    box = solid.BoundingBox()
    print(f"{stem}: {box.xlen:.2f} x {box.ylen:.2f} x {box.zlen:.2f} mm; {solid.Volume():.1f} mm3")


if __name__ == "__main__":
    export_part(make_base(), "base_FSR402B")
    export_part(make_tread(), "tread_FSR402B")
