(*
         DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE 
                    Version 2, December 2004 

 Copyright (C) 2004 Sam Hocevar <sam@hocevar.net> 

 Everyone is permitted to copy and distribute verbatim or modified 
 copies of this license document, and changing it is allowed as long 
 as the name is changed. 

            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE 
   TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION 

  0. You just DO WHAT THE FUCK YOU WANT TO.
*)
open Spoc

open Kirc

let gpu_to_gray = kern v ->
  let open Std in
  let tid = thread_idx_x + block_dim_x * block_idx_x in
  let tab = make_local 32 in
  let tab2 = make_shared 32 in
  tab2.(0) <- tab.(0) +  v.[<0>];
  if tid <= (512*512) then (
    let i = (tid*4) in
    let res = int_of_float ((0.21 *. (float (v.[<i>]))) +.
                            (0.71 *. (float (v.[<i+1>]))) +.
                            (0.07 *. (float (v.[<i+2>]))) ) in
    v.[<i>] <- res;
    v.[<i+1>] <- res;
    v.[<i+2>] <- res )

let append_text e s = Dom.appendChild e (document##createTextNode (Js.string s))

let button name action = 
  let b = createInput ~_type:(Js.string "button")  document in
  b##value <- (Js.string name);
  b##onclick <- handler action;
  b##style##margin <- Js.string "10px";
  b
;;  

let measure_time s f =
  let t0 = Unix.gettimeofday () in
  let a = f () in
  let t1 = Unix.gettimeofday () in
  Printf.printf "Time %s : %Fs\n%!" s (t1 -. t0);
  a;;


let compute devid devs data imageData c tf = 
  let dev = devs.(devid) in
  Printf.printf "Will use device : %s!"
    (dev).Spoc.Devices.general_info.Spoc.Devices.name;
  let gpu_vect = Spoc.Vector.create Vector.int32 (512*512*4)
  in
  let s = Printf.sprintf "%s" (Js.to_string tf##value) in
  (fst gpu_to_gray)#set_opencl_sources s;
  Random.self_init ();
  for i = 0 to Vector.length gpu_vect - 1 do
    gpu_vect.[<i>] <- Int32.of_int (pixel_get data i);
  done;

  let threadsPerBlock = match dev.Devices.specific_info with
    | Devices.OpenCLInfo clI -> 
      (match clI.Devices.device_type with
       | Devices.CL_DEVICE_TYPE_CPU -> 1
       | _  ->   256)
    | _  -> 256 in


  let blocksPerGrid =
    ((512*512) + threadsPerBlock -1) / threadsPerBlock
  in
  let block0 = {Spoc.Kernel.blockX = threadsPerBlock;
                Spoc.Kernel.blockY = 1; Spoc.Kernel.blockZ = 1}
  and grid0= {Spoc.Kernel.gridX = blocksPerGrid;
              Spoc.Kernel.gridY = 1; Spoc.Kernel.gridZ = 1} in
  measure_time "" 
    (fun () -> Kirc.run gpu_to_gray (gpu_vect) (block0,grid0) 0 dev);

  for i = 0 to Vector.length gpu_vect - 1 do
    let t = Int32.to_int gpu_vect.[<i>] in 
    pixel_set data i t
  done;
  c##putImageData (imageData, 0., 0.);
;;


let f select_devices devs data imageData c tf = 
  (fun _ ->
     let select = select_devices##selectedIndex + 0 in
     compute select devs data imageData c tf;
     Js._false)
;;

let newLine _ = Dom_html.createBr document


let nodeJsText t =
  let sp = Dom_html.createSpan document in
  Dom.appendChild sp (document##createTextNode (t)) ;
  sp

let nodeText t =
  nodeJsText (Js.string t)

open Spoc

let go _ =


  let body =
    Js.Opt.get (document##getElementById (Js.string "section1"))
      (fun () -> assert false) in

  Dom.appendChild body (newLine ());
  let select_devices = createSelect document in
  Dom.appendChild body (nodeText "Choose a computing device : ");



  Dom.appendChild body select_devices;
  Dom.appendChild body (newLine ());


  let canvas = createCanvas document in
  canvas##width <- 512;
  canvas##height <- 512;
  canvas##style##margin <- Js.string "10px";

  let image : imageElement Js.t = createImg document in
  image##src <- Js.string "lena.png";


  let c = canvas##getContext (Dom_html._2d_) in
  image##onload <- 
    handler (fun _ -> 
        c##drawImage (image, 0., 0.); 
        Dom.appendChild body (newLine ());
        Dom.appendChild body canvas;
        let devs =
          Devices.init ~only:Devices.OpenCL () in	     
        let imageData = c##getImageData (0., 0., 512., 512.) in
        let data = imageData##data in
        ignore(Kirc.gen ~only:Devices.OpenCL
                 gpu_to_gray);
        let tf =  createTextarea document in
        Dom.appendChild body tf;

        tf##value <- Js.string 
            (List.hd 
               ((fst gpu_to_gray)#get_opencl_sources ()));
        Dom.appendChild body (newLine ());
        tf##rows <- 33;
        tf##cols <- 80;

        Array.iter
          (fun n ->
             let option = createOption document in
             append_text option n.Devices.general_info.Devices.name;
             Dom.appendChild select_devices  option)
          devs;


        Dom.appendChild body (button "GO" (f select_devices devs data 
                                        imageData c tf ));


        Dom.appendChild body (button "Reset picture" (fun _ -> c##drawImage (image, 0., 0.); Js._false) );
        Js._false);

  Js._false


let _ = 
  window##onload <- handler go

