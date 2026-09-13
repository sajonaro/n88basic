(* The display list as SVG: a second renderer over the same input.
 
   WHY A SECOND ONE. png.ml flattens the list to 640x400 pixels, which is what
   the machine did and what a fixture should compare. But the list itself is
   VECTOR -- lines, boxes, circles, arcs -- and a browser can draw vectors
   crisply at any size, select them, and load them in a fraction of the bytes.
   So this renders the geometry as geometry, and the page shows a drawing that
   stays sharp when you zoom it.

   WHAT IT CANNOT DO, AND WHY IT SAYS SO RATHER THAN GUESSING. PAINT is a
   FLOOD FILL: it starts at a point and spreads until it meets a border
   colour, so what it covers is a function of every pixel already drawn. That
   has no vector form short of tracing the filled region's contour, which is a
   different program. A list containing PAINT is therefore rendered by
   embedding the rasterised frame instead -- correct, just not vector -- and
   [kind] tells the caller which it got. Silently dropping the fill would
   produce a picture that is wrong in exactly the way nobody checks. *)

type kind = Vector | Raster

let width = Framebuffer.width
let height = Framebuffer.height

let rgb (mapping : int array) (code : int) : string =
  let r, g, b = Palette.to_rgb mapping.(Palette.wrap code) in
  Printf.sprintf "#%02x%02x%02x" r g b

let buf_add = Buffer.add_string

(* LINE's 16-bit style mask as a dash pattern. Bit 15 is the first dot and bit
   0 the sixteenth, a set bit drawing and a clear one leaving background, the
   whole pattern repeating every sixteen dots. SVG's stroke-dasharray is
   alternating on/off run lengths, so the mask becomes the runs it describes --
   an exact translation, not an approximation, as long as the list starts with
   an "on" run. A mask beginning with a clear bit gets a leading zero-length
   dash, which is what SVG expects for the same thing. *)
let dasharray (mask : int) : string =
  let bit i = (mask lsr (15 - i)) land 1 = 1 in
  let runs = ref [] and n = ref 0 and on = ref true in
  for i = 0 to 15 do
    if bit i = !on then incr n
    else begin
      runs := !n :: !runs;
      on := not !on;
      n := 1
    end
  done;
  runs := !n :: !runs;
  String.concat " " (List.rev_map string_of_int !runs)

let encode (ops : N88basic.Display.op list) : string * kind =
  (* PAINT is a flood fill and a TILE is an 8-dot bit pattern: neither has a
     vector form, so a list containing either takes the raster path. *)
  let has_paint =
    List.exists
      (function
        | N88basic.Display.Paint _ -> true
        | N88basic.Display.Line { fill = Some (N88basic.Display.Tiled _); _ } -> true
        | N88basic.Display.Circle { fill = Some (N88basic.Display.Fill_tile _); _ } -> true
        | _ -> false)
      ops
  in
  if has_paint then begin
    (* One <image> holding the frame png.ml produced, so the caller gets an
       SVG either way and the picture is never wrong. *)
    let png = Png.encode (Rasterize.to_framebuffer ops) in
    let b64 = Base64.encode png in
    ( Printf.sprintf
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" \
         viewBox=\"0 0 %d %d\" shape-rendering=\"crispEdges\">\n\
         <image width=\"%d\" height=\"%d\" image-rendering=\"pixelated\" \
         href=\"data:image/png;base64,%s\"/>\n</svg>\n"
        width height width height width height b64,
      Raster )
  end
  else begin
    let b = Buffer.create 4096 in
    Printf.bprintf b
      "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" \
       viewBox=\"0 0 %d %d\" shape-rendering=\"crispEdges\">\n"
      width height width height;
    let mapping = ref (Palette.initial_mapping ()) in
    let current = ref (0.0, 0.0) in
    let fg = ref Palette.default_foreground_index in
    let bg = ref Palette.default_background_index in
    (* The ground the machine starts on, and what CLS restores. *)
    Printf.bprintf b "<rect width=\"%d\" height=\"%d\" fill=\"%s\"/>\n" width height
      (rgb !mapping !bg);
    let dot x y colour =
      Printf.bprintf b "<rect x=\"%g\" y=\"%g\" width=\"1\" height=\"1\" fill=\"%s\"/>\n"
        (Float.round x) (Float.round y) (rgb !mapping colour)
    in
    List.iter
      (fun (op : N88basic.Display.op) ->
        match op with
        | N88basic.Display.Cls code when code = 2 || code = 3 ->
            Printf.bprintf b "<rect width=\"%d\" height=\"%d\" fill=\"%s\"/>\n" width height
              (rgb !mapping !bg)
        | N88basic.Display.Color { foreground; background; _ } ->
            Option.iter (fun c -> fg := c) foreground;
            Option.iter (fun c -> bg := c) background
        | N88basic.Display.Color_palette { palette; code } ->
            !mapping.(Palette.wrap palette) <- Palette.wrap code
        | N88basic.Display.Color_palette_init -> mapping := Palette.initial_mapping ()
        | N88basic.Display.Point_lp { point } ->
            current := Rasterize.resolve_point !current point
        | N88basic.Display.Pset { point; colour } ->
            let x, y = Rasterize.resolve_point !current point in
            current := (x, y);
            dot x y (Rasterize.colour_of ~default:!fg colour)
        | N88basic.Display.Preset { point; colour } ->
            let x, y = Rasterize.resolve_point !current point in
            current := (x, y);
            dot x y (Rasterize.colour_of ~default:!bg colour)
        | N88basic.Display.Line { from_point; to_point; colour; box; style; fill } ->
            let start =
              match from_point with
              | None -> !current
              | Some p -> Rasterize.resolve_point !current p
            in
            let x1, y1 = start in
            let x2, y2 = Rasterize.resolve_point start to_point in
            current := (x2, y2);
            let c = rgb !mapping (Rasterize.colour_of ~default:!fg colour) in
            let dash =
              match style with
              | None -> ""
              | Some m -> Printf.sprintf " stroke-dasharray=\"%s\"" (dasharray m)
            in
            let rx = Float.min x1 x2 and ry = Float.min y1 y2 in
            let rw = Float.abs (x2 -. x1) and rh = Float.abs (y2 -. y1) in
            (match box with
             | `None ->
                 Printf.bprintf b
                   "<line x1=\"%g\" y1=\"%g\" x2=\"%g\" y2=\"%g\" stroke=\"%s\" \
                    stroke-width=\"1\"%s/>\n"
                   (x1 +. 0.5) (y1 +. 0.5) (x2 +. 0.5) (y2 +. 0.5) c dash
             | `Frame ->
                 Printf.bprintf b
                   "<rect x=\"%g\" y=\"%g\" width=\"%g\" height=\"%g\" fill=\"none\" \
                    stroke=\"%s\" stroke-width=\"1\"%s/>\n"
                   (rx +. 0.5) (ry +. 0.5) rw rh c dash
             | `Filled ->
                 let f =
                   match fill with
                   | Some (N88basic.Display.Solid n) -> rgb !mapping n
                   (* A tile is an 8-dot bit pattern, which is a raster thing.
                      Falls back to the line colour here, and encode's caller
                      is told the list held a tile so it can choose the
                      raster path instead. *)
                   | Some (N88basic.Display.Tiled _) | None -> c
                 in
                 Printf.bprintf b
                   "<rect x=\"%g\" y=\"%g\" width=\"%g\" height=\"%g\" fill=\"%s\"/>\n"
                   rx ry (rw +. 1.) (rh +. 1.) f)
        | N88basic.Display.Circle
            { center; radius; colour; start_angle; end_angle; aspect; fill } ->
            let cx, cy = Rasterize.resolve_point !current center in
            current := (cx, cy);
            (* A machine pixel (x,y) covers the square [x,x+1), so its centre
               is at x+0.5 in SVG's continuous space. Strokes are centred on
               the path, which is why lines above carry the same half. Omitting
               it here put every circle half a pixel up and to the left --
               invisible by eye and measurable in the bounding box. *)
            let cx = cx +. 0.5 and cy = cy +. 0.5 in
            let c = rgb !mapping (Rasterize.colour_of ~default:!fg colour) in
            let ry = radius *. Option.value aspect ~default:1.0 in
            let filled = fill <> None in
            let fill_colour =
              match fill with
              | Some (N88basic.Display.Fill_palette n) -> rgb !mapping n
              | _ -> c
            in
            let paint_attr =
              if filled then Printf.sprintf "fill=\"%s\"" fill_colour
              else Printf.sprintf "fill=\"none\" stroke=\"%s\" stroke-width=\"1\"" c
            in
            (match (start_angle, end_angle) with
             | None, None ->
                 Printf.bprintf b "<ellipse cx=\"%g\" cy=\"%g\" rx=\"%g\" ry=\"%g\" %s/>\n"
                   cx cy radius ry paint_attr
             | _ ->
                 (* An arc. The machine measures angles anticlockwise from the
                    positive X axis; SVG's Y grows downward, so the sign of the
                    sine flips and nothing else does. *)
                 let a0 = Option.value start_angle ~default:0.0 in
                 let a1 = Option.value end_angle ~default:(2.0 *. Float.pi) in
                 let px a = cx +. (radius *. Float.cos a) in
                 let py a = cy -. (ry *. Float.sin a) in
                 let large = if Float.abs (a1 -. a0) > Float.pi then 1 else 0 in
                 Printf.bprintf b
                   "<path d=\"M %g %g A %g %g 0 %d 0 %g %g%s\" %s/>\n"
                   (px a0) (py a0) radius ry large (px a1) (py a1)
                   (if filled then Printf.sprintf " L %g %g Z" cx cy else "")
                   paint_attr)
        | _ -> ())
      ops;
    buf_add b "</svg>\n";
    (Buffer.contents b, Vector)
  end
