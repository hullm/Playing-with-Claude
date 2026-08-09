; =============================================================================
;  WORKED EXAMPLE  -  Face + Turn a Step (Shoulder)   [GRBL hobby lathe]
; -----------------------------------------------------------------------------
;  WHAT IT MAKES:
;     Starts from 25 mm dia round aluminium stock.
;     1) Faces the end flat at Z0.
;     2) Turns a 20 mm dia section, 15 mm long -> leaves a shoulder.
;
;  MACHINE ASSUMPTIONS (change to match YOUR lathe!):
;     * Controller : GRBL 1.1 (works on most GRBL router/lathe boards)
;     * Units      : millimetres (G21)
;     * X axis     : RADIUS from spindle centreline  (X0 = centreline)
;                    >>> NOT diameter.  20 mm dia part = X10.0 <<<
;     * Z axis     : along the bed.  Z0 = finished end face.
;                    Z-  = toward the chuck (into the part).
;     * Spindle    : M3 Sxxxx  (S = RPM if $30 is set to your max RPM)
;     * One tool   : a right-hand turning/facing insert, tip zeroed by hand.
;
;  SAFETY: dry-run with the spindle OFF and the tool backed WELL clear first.
;          Single-block / feed-hold ready on your first real cut.
; =============================================================================

; ---- KEY NUMBERS (edit these to re-use the program) -------------------------
;   Stock radius        = 12.5   (25 mm dia)
;   Finish radius       = 10.0   (20 mm dia)
;   Shoulder length     = 15 mm  -> cut to Z-15
;   Depth of cut (rad)  = 0.5 mm per roughing pass
;   Clearance radius    = 14.0   (safe X to rapid around at)
; -----------------------------------------------------------------------------

; ===== SAFETY / STARTUP BLOCK ================================================
G21             ; set units to millimetres
G90             ; absolute positioning (coordinates are destinations, not steps)
G94             ; feed is per MINUTE (mm/min) - GRBL has no per-rev feed (G95)
G54             ; use work coordinate system 1 (where you set your zero)
G0 X14.0 Z2.0   ; RAPID to a safe start point: clear of the OD and off the face
M3 S1200        ; spindle ON, clockwise, 1200 rpm  (tune for your material)
; (a real dwell for spindle spin-up:)
G4 P1.5         ; dwell 1.5 s so the spindle reaches speed before cutting

; ===== 1) FACING PASS  (clean the end to Z0) =================================
; Assumes < ~0.5 mm of stock stands proud of Z0. Repeat block if more remains.
G0 Z0.0         ; move to the finished-face plane (rapid, still clear at X14)
G1 X-0.3 F60    ; FEED across the face, just past centre so no nub is left
G0 X14.0        ; rapid the tool straight out, clear of the part
G0 Z2.0         ; rapid back to the start-of-cut side in Z

; ===== 2) ROUGHING PASSES (turn 12.5 -> 10.2 radius) ========================
; Each pass: rapid to depth off the face -> feed along Z -> peel out -> return.
; Left 0.2 mm of radius on for a clean finishing pass.

; --- pass 1 : radius 12.0 ---
G0 X12.0 Z2.0
G1 Z-15.0 F80   ; turn along the length to the shoulder
G1 X12.7 F150   ; feed OUT a touch to break contact (no rubbing on retract)
G0 Z2.0         ; rapid back for the next pass

; --- pass 2 : radius 11.5 ---
G0 X11.5 Z2.0
G1 Z-15.0 F80
G1 X12.2 F150
G0 Z2.0

; --- pass 3 : radius 11.0 ---
G0 X11.0 Z2.0
G1 Z-15.0 F80
G1 X11.7 F150
G0 Z2.0

; --- pass 4 : radius 10.5 ---
G0 X10.5 Z2.0
G1 Z-15.0 F80
G1 X11.2 F150
G0 Z2.0

; --- pass 5 : radius 10.2 (leave 0.2 for finish) ---
G0 X10.2 Z2.0
G1 Z-15.0 F80
G1 X10.9 F150
G0 Z2.0

; ===== 3) FINISHING PASS (to final 10.0 radius = 20.0 mm dia) ================
; Lighter cut + slower feed for a better surface finish; face the shoulder too.
G0 X10.0 Z2.0
G1 Z-15.0 F50   ; finish along the diameter
G1 X12.7 F50    ; feed OUT along the shoulder face to clean it (square corner)
G0 Z2.0

; ===== SHUTDOWN BLOCK ========================================================
G0 X14.0        ; retract to clearance radius
G0 Z25.0        ; rapid well clear in Z for part removal
M5              ; spindle OFF
M30             ; program end + rewind
