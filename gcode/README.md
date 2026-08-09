# G-code — CNC Lathe (GRBL) worked example

`lathe_face_and_step_grbl.nc` — a fully commented turning program that **faces**
the end of round stock and **turns a step/shoulder** down to a smaller diameter.

## What it makes
From 25 mm dia aluminium round stock:
1. Faces the end flat at `Z0`.
2. Turns a **20 mm dia × 15 mm long** section, leaving a shoulder.

## Read this before you run it

| Assumption | Value | Change if… |
|---|---|---|
| Controller | GRBL 1.1 | you're on Fanuc/Haas/LinuxCNC (dialect differs — ask me) |
| Units | mm (`G21`) | you work in inches → use `G20` and rescale numbers |
| **X axis** | **RADIUS from centreline** | your GRBL is set for diameter (rare) |
| Z axis | `Z0` = finished face, `Z-` = toward chuck | your zero is elsewhere |
| Spindle | `M3 S1200` (RPM via `$30`) | your `$30` max-RPM / material differ |
| Tooling | one RH turning insert, zeroed by hand | you have a turret / more tools |

> ⚠️ **X is radius, not diameter.** The single most common way to scrap a part
> on a GRBL lathe: a 20 mm-diameter feature is programmed as `X10.0`.

## What GRBL can't do (so this program avoids it)
- No `G96` constant surface speed — RPM is fixed via `S`.
- No canned cycles (`G71`/`G70` roughing/finish, `G76` threading) — every pass
  is written out by hand. That's expected.
- No tool offsets / turret indexing.
- No per-rev feed (`G95`) — feeds are mm/min (`G94`).

## Before the first real cut
1. **Dry run with the spindle OFF**, tool backed well clear — watch the moves.
2. Set your work zero (`G54`): X0 on centreline, Z0 on the finished face.
3. Keep a hand on feed-hold; run the first pass in single-block if you can.
4. Tune `S` (RPM) and `F` (feed) for your material, insert, and rigidity.

Want a different operation (parting, boring, a taper/chamfer, or a full
diameter-programmed Fanuc version)? Tell me the part and I'll write it.
